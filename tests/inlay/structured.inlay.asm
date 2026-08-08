struct Fixed8_8 packed
    fraction : u8
    integer : u8
end

struct HairNode packed
    x : Fixed8_8
    y : Fixed8_8
end

struct TestObject packed
    bytes : u8[4]
    hair : HairNode[5]
end

struct WordObject packed
    value : Fixed8_8
    timer : u8
end

struct RegisterBank packed
    channels : u8[4]
end

location pObj : ptr TestObject
location pOther : ptr TestObject
pool objects : TestObject[4] at OBJPOOL table obj_lo, obj_hi
overlay registers : RegisterBank at REGS volatile

static_assert objects.count == 4
static_assert objects.stride == 24
static_assert objects.size == 96

#include "../../src/isa/nmos6502.asm"
#include "../../src/isa/ext_core.asm"

#bankdef conformance { #addr 0x0300, #size 0x0200, #outp 0 }
#bank conformance

pObj = 0x10

proc indexed_load naked
    self : ptr TestObject in pObj
begin
    lda [self + TestObject.hair[x].y.integer]
    ret
end

proc indexed_store naked
    self : ptr TestObject in pObj
begin
    sta [self + TestObject.bytes[x]]
    ret
end

proc typed_operations naked
    self : ptr WordObject in pWord
    word : u16 in w0
begin
    ldw word, [self + WordObject.value]
    stw [self + WordObject.value], word
    addw ab, word
    subw ab, word
    cmpw ab, word
    inc [self + WordObject.timer]
    dec [self + WordObject.timer]
    and [self + WordObject.timer], #$fe
    ora [self + WordObject.timer], #1
    lda [registers + RegisterBank.channels[y]]
    sta [registers + RegisterBank.channels[y]]
    ret
end

proc object_at
    self : ptr TestObject in pObj
    slot : u8 in a
begin
    address self, objects[a]
    ret
end

proc framed
    saved : u8 in frame
begin
    sta [saved]
    lda [saved]
    ret
end

proc convention using console6502 naked
    first : u8
    second : u8
    third : u8
    result : u8 return
begin
    ret
end

proc pointer_frame
    self : ptr TestObject in pObj
    saved : ptr TestObject in frame
begin
    mov [saved], self
    mov self, [saved]
    ret
end

proc aggregate_frame
    temporary : HairNode in frame
begin
    lda [temporary + HairNode.y.integer]
    ret
end

proc callee using console6502 naked
    left : u8
    right : u8
    result : u8 return
begin
    ret
end

proc invoke_swap naked
begin
    invoke callee, left=x, right=a
    ret
end

proc invoke_continued naked
begin
    invoke callee,
        left=5,
        right=y
    ret
end

proc callee3 using console6502 naked
    left : u8
    middle : u8
    right : u8
begin
    ret
end

proc invoke_cycle naked
begin
    invoke callee3, left=x, middle=y, right=a
    ret
end

proc pointer_callee naked
    target : ptr TestObject in pObj
begin
    ret
end

proc invoke_pointer naked
    source : ptr TestObject in pOther
begin
    invoke pointer_callee, target=source
    ret
end

proc mixed_callee naked
    target : ptr TestObject in pObj
    value : u8 in x
begin
    ret
end

proc invoke_mixed naked
    source : ptr TestObject in pOther
begin
    invoke mixed_callee, target=source, value=a
    ret
end

proc observation_operations naked
    self : ptr WordObject in pWord
    word : u16 in w0
begin
    decz [self + WordObject.timer], .idle
.idle:
    tstw [self + WordObject.value]
    tstw word
    ret
end

proc word_moves naked
    self : ptr WordObject in pWord
    word : u16 in w0
    other : u16 in w1
begin
    movw word, #$1234
    movw word, #-2
    movw other, word
    stw [self + WordObject.value], #$8001
    ret
end

proc bump_timer inline
    self : ptr WordObject in pWord
begin
    decz [self + WordObject.timer], .out
.out:
end

proc inline_caller naked
    self : ptr WordObject in pWord
begin
    invoke bump_timer, self=self
    invoke bump_timer, self=self
    ret
end

obj_lo:
    #d8 $00, $18, $30, $48
obj_hi:
    #d8 (OBJPOOL)[15:8], (OBJPOOL)[15:8], (OBJPOOL)[15:8], (OBJPOOL)[15:8]

OBJPOOL = $8000
pOther = $12
pWord = $14
w0 = $16
w1 = $18
REGS = $4100
t0 = $20
t1 = $21
t2 = $22
