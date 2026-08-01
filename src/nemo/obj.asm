; ------------------------------------------------------------------------------
; NEMO - class chain, scene graph and event bus
;
; The cart is object-oriented: class(base) builds a metatable chain, `new`
; walks that chain collecting every ancestor's init, sprite holds a child list
; that render() descends, and event holds {handler, context} lists that emit()
; fans out to (cart lines 97-190). Eight classes, three levels deep.
;
; This is the part of the corpus that measures pointer cost, so it is ported as
; structure rather than flattened away. Concretely:
;
;   * method dispatch is an indirect jump through a class descriptor, with a
;     miss falling back to the base class - a pointer walk with a loop;
;   * the scene graph is a first-child / next-sibling tree walked recursively;
;   * the event bus is an array of {event, handler, context} triples.
;
; A flatter design would be faster. It would also delete the thing being
; measured, so it is not the design used here.
; ------------------------------------------------------------------------------

    .define OBJ_MAX            16
    .define OBJ_SIZE           16
; object record layout
    .define O_CLASS            0       ; +1: class descriptor pointer
    .define O_X                2
    .define O_Y                3
    .define O_FLAGS            4       ; bit0 visible
    .define O_CHILD            5       ; first child index, $FF none
    .define O_SIBLING          6       ; next sibling index, $FF none
    .define O_STATE            7       ; +7..15 per-class

    .define OF_VISIBLE         $01
    .define NIL                $FF

; class descriptor layout: base pointer then one slot per method
    .define C_BASE             0       ; +1: base class descriptor, $0000 none
    .define C_INIT             2       ; +3
    .define C_DRAW             4       ; +5
    .define C_UPDATE           6       ; +7

    .define EV_MAX             16
    .define EV_SIZE            4
    .define E_EVENT            0
    .define E_FN               1       ; +2
    .define E_CTX              3

; event ids live in memmap.asm - they are used by main.asm before this
; file is included.

; ------------------------------------------------------------------------------
; obj_init: empty the pool, the tree and the bus.
; Clobbers A, X.
; ------------------------------------------------------------------------------
obj_init:
    lda #0
    sta obj_count
    sta ev_count
    lda #NIL
    sta obj_root
    rts

; ------------------------------------------------------------------------------
; obj_ptr: pObj = OBJPOOL + A * OBJ_SIZE. OBJ_SIZE is 16 and OBJ_MAX is 16, so
; the pool is one page and the offset never leaves a byte.
; Clobbers A.
; ------------------------------------------------------------------------------
obj_ptr:
    asl
    asl
    asl
    asl
    clc
    adc #<OBJPOOL
    sta pObj
    lda #>OBJPOOL
    adc #0
    sta pObj+1
    rts

; ------------------------------------------------------------------------------
; obj_new: allocate an object of the class in t4/t5. Returns its index in A.
;
; Constructor chaining is the cart's `new`: walk to the root of the class chain
; collecting descriptors, then call each init from the base down, so a subclass
; sees its parent's fields already set up.
; Clobbers everything.
; ------------------------------------------------------------------------------
obj_new:
    ldx obj_count
    cpx #OBJ_MAX
    bcc @ok
    lda #NIL                    ; pool exhausted; callers treat NIL as fatal
    rts
@ok:
    inc obj_count
    stx t6                      ; new object's index

    txa
    jsr obj_ptr
    ldy #O_CLASS
    lda t4
    sta (pObj),y
    iny
    lda t5
    sta (pObj),y
    ldy #O_X
    lda #0
    sta (pObj),y
    iny
    sta (pObj),y
    ldy #O_FLAGS
    lda #OF_VISIBLE
    sta (pObj),y
    ldy #O_CHILD
    lda #NIL
    sta (pObj),y
    ldy #O_SIBLING
    sta (pObj),y

    ; collect the class chain onto the stack, base last pushed
    lda t4
    sta pCls
    lda t5
    sta pCls+1
    lda #0
    sta t7                      ; depth
@walk:
    lda pCls
    pha
    lda pCls+1
    pha
    inc t7
    ldy #C_BASE
    lda (pCls),y
    tax
    iny
    lda (pCls),y
    beq @haveall                ; a zero high byte terminates the chain
    sta pCls+1
    stx pCls
    jmp @walk
@haveall:
    ; unwind: the last pushed is the base, so init runs base-first
@callinit:
    pla
    sta pCls+1
    pla
    sta pCls
    ldy #C_INIT
    lda (pCls),y
    sta pFn
    iny
    lda (pCls),y
    sta pFn+1
    beq @noinit                 ; slot empty -> this level has no init
    ; An init is arbitrary code and will clobber the zero page, so the depth
    ; counter and the new object's index have to be spilled across the call.
    ; Two pha/pla pairs per constructor level, purely to survive a jsr - the
    ; spill traffic add-isa-frame-pointer exists to remove.
    lda t7
    pha
    lda t6
    pha
    sta obj_cur
    jsr call_pFn
    pla
    sta t6
    pla
    sta t7
@noinit:
    dec t7
    bne @callinit
    lda t6
    rts

; ------------------------------------------------------------------------------
; call_pFn: indirect call through pFn. The 6502 has no "jsr (indirect)", so the
; return address has to come from a jsr to a jmp - the standard trick, and one
; of the reasons dispatch through a pointer costs what it does here.
; ------------------------------------------------------------------------------
call_pFn:
    jmp (pFn)

; ------------------------------------------------------------------------------
; obj_method: find method slot t3 for object A. Returns pFn, and Z set when no
; class in the chain implements it.
;
; This is the prototype-chain lookup: try the object's own class, and on an
; empty slot follow C_BASE and try again.
; Clobbers everything except t3.
; ------------------------------------------------------------------------------
obj_method:
    jsr obj_ptr
    ldy #O_CLASS
    lda (pObj),y
    sta pCls
    iny
    lda (pObj),y
    sta pCls+1
@try:
    lda pCls+1
    beq @none                   ; ran off the end of the chain
    ldy t3
    lda (pCls),y
    sta pFn
    iny
    lda (pCls),y
    sta pFn+1
    beq @up                     ; empty slot -> ask the base class
    lda #1                      ; found: Z clear
    rts
@up:
    ldy #C_BASE
    lda (pCls),y
    tax
    iny
    lda (pCls),y
    sta pCls+1
    stx pCls
    jmp @try
@none:
    lda #0                      ; Z set
    rts

; ------------------------------------------------------------------------------
; obj_send: invoke method slot t3 on object A, if any class implements it.
; Clobbers everything.
; ------------------------------------------------------------------------------
obj_send:
    sta obj_cur
    jsr obj_method
    beq @none
    lda obj_cur
    jmp call_pFn
@none:
    rts

; ------------------------------------------------------------------------------
; obj_add_child: append object A to parent t6's child list.
; Appends at the tail so draw order follows creation order, which is what the
; cart's add_child does.
; Clobbers everything except t6.
; ------------------------------------------------------------------------------
obj_add_child:
    sta t7                      ; child index
    lda t6
    jsr obj_ptr
    ldy #O_CHILD
    lda (pObj),y
    cmp #NIL
    bne @tail
    lda t7                      ; empty list: child becomes the head
    sta (pObj),y
    rts
@tail:
    jsr obj_ptr                 ; walk siblings to the end
    ldy #O_SIBLING
    lda (pObj),y
    cmp #NIL
    bne @tail
    lda t7
    sta (pObj),y
    rts

; ------------------------------------------------------------------------------
; obj_draw_tree: draw object A and, depth-first, its children.
;
; Recursion depth is bounded by the class hierarchy's shape, not by data: the
; deepest the cart nests is a popup inside the root, so two levels. The 6502
; stack is fine with it.
; Clobbers everything.
; ------------------------------------------------------------------------------
obj_draw_tree:
    cmp #NIL
    beq @done
    pha
    jsr obj_ptr
    ldy #O_FLAGS
    lda (pObj),y
    and #OF_VISIBLE
    beq @hidden

    lda #C_DRAW
    sta t3
    pla
    pha
    jsr obj_send

    pla
    pha
    jsr obj_ptr
    ldy #O_CHILD
    lda (pObj),y
    jsr obj_draw_tree           ; descend

@hidden:
    pla
    jsr obj_ptr
    ldy #O_SIBLING
    lda (pObj),y
    jmp obj_draw_tree           ; and along
@done:
    rts

; ------------------------------------------------------------------------------
; ev_on: register handler t4/t5 for event A with context t6.
; Clobbers A, X, Y.
; ------------------------------------------------------------------------------
ev_on:
    ldx ev_count
    cpx #EV_MAX
    bcs @full
    pha
    txa                         ; slot offset = index * 4
    asl
    asl
    tax
    pla
    sta EVPOOL+E_EVENT,x
    lda t4
    sta EVPOOL+E_FN,x
    lda t5
    sta EVPOOL+E_FN+1,x
    lda t6
    sta EVPOOL+E_CTX,x
    inc ev_count
@full:
    rts

; ------------------------------------------------------------------------------
; ev_emit: call every handler registered for event A.
;
; The cart's emit passes varargs; here the payload is whatever the emitter left
; in the shared state, which is the 6502-idiomatic version of the same thing
; and is exactly the kind of implicit coupling the ISA programme is trying to
; make visible.
; Clobbers everything.
; ------------------------------------------------------------------------------
ev_emit:
    sta t7                      ; event id
    lda #0
    sta t0                      ; slot index
@l:
    lda t0
    cmp ev_count
    bcs @done
    asl
    asl
    tax
    lda EVPOOL+E_EVENT,x
    cmp t7
    bne @next
    lda EVPOOL+E_FN,x
    sta pFn
    lda EVPOOL+E_FN+1,x
    sta pFn+1
    lda EVPOOL+E_CTX,x
    sta obj_cur
    jsr call_pFn
@next:
    inc t0
    jmp @l
@done:
    rts
