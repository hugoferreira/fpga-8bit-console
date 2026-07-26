; ------------------------------------------------------------------------------
; Celeste - target constants and physical aliases
;
; Stable storage shapes and addresses live in layout.inlay.asm. The aliases
; retained here are consumed by raw target operations whose semantics cannot
; yet be expressed by a typed Inlay operand.
; ------------------------------------------------------------------------------

; PPU aliases needed by mov/cmp or non-A register transfers.
    SPR_CTRL = $4005   ; bit0 tilemap en, bit1 overlay en
    SPR_OVLCOL = $4006
    SPR_INDEX = $4008
    SPR_Y = $400A
    SPR_FRAME = $400D   ; +1 per vsync
    SPR_DPAL = $4010   ; draw palette, 16 entries: remaps the
                                       ;   post-base colour of tiles + sprites
    SPR_REP = $4037   ; staged repeat, in cells: one committed
                                       ;   entry blits its row that many times
    SPR_CLIPX1 = $4032
    SPR_CLIPY1 = $4033

; PSG aliases needed by mov, logic, or non-A register transfers.
    PSG_ADDR_LO = $4100
    PSG_ADDR_HI = $4101
    PSG_MUSMASK = $4121
    PSG_FADE = $4122

; Wide and pointer-addressed regions whose current target forms cannot consume
; a typed fixed-overlay path directly.
    OVL = $E000   ; 160x120 1bpp, byte = y*20 + x/8,
                                       ; bit 0 = LEFTMOST pixel
    MAP_LO = $F000   ; tile pattern base, 32x16 cells
    MAP_HI = $F200   ; tile attributes
    MAP_STRIDE = 32

; Buttons. The cart's k_* constants in the console's bit order.
    BTN_L = $01
    BTN_R = $02
    BTN_U = $04
    BTN_D = $08
    BTN_JUMP = $10     ; O
    BTN_DASH = $20     ; X

; ------------------------------------------------------------------------------
; Geometry
;
; A Celeste room is 16x16 tiles = 128x128 px; the display is 160x120. The room
; sits at world x 0 (bank 0) or 128 (bank 1) in the 256x128 tile world, so both
; the current and the next room are resident and a load never tears. The clip
; rectangle keeps tiles and sprites inside the 128-wide playfield, which is what
; stops the neighbouring bank showing through on the right; the overlay is
; composited above the clip and carries the HUD there.
;
; Vertically the room is 8 lines taller than the display, so camera Y follows
; the player through exactly that band. Sprites are staged in SCREEN space, so
; every sprite's Y has the camera subtracted at draw time.
; ------------------------------------------------------------------------------
    ROOM_W = 16      ; tiles
    ROOM_H = 16
    PLAYFIELD_W = 128
    CAM_Y_MAX = 8       ; 128 - 120

; ------------------------------------------------------------------------------
; Object records. 64 bytes each, 16 slots, page-aligned pool: the base address
; of slot i is {OBJPOOL_HI + (i>>2), (i&3)<<6}, which is two shifts and a mask.
;
; Every field the cart puts on an object stays on the object, including the
; player's dash vectors and hair - the point of this corpus is to measure what
; that costs, so hoisting the player's state into globals because there is only
; ever one player would defeat it. The tail of the record is a per-type area:
; the player uses all of it, smoke uses none.
; ------------------------------------------------------------------------------

    OBJ_MAX = 16
    HAIR_NODES = 5

    F_COLLIDEABLE = $01
    F_SOLIDS = $02

; The cart's marker tiles. Only player_spawn is a stage-1 type; the rest are
; recognised so load_room can skip them without warning, and are stage 2.
    TILE_SPAWN = 1
; Spike tiles, by the direction the spikes point.
    TILE_SPIKE_D = 17
    TILE_SPIKE_U = 27
    TILE_SPIKE_R = 43
    TILE_SPIKE_L = 59

; Music, as the cart calls it. Every music() in the program is here.
;
;   title_screen   music(40,0,7)     the theme
;   begin_game     music(0,0,7)      the climb
;   start_game     music(-1)         cut, the moment the flash starts
;   next_room      music(30,500,7)   leaving rooms 10, 20 and 29
;                  music(20,500,7)   leaving room 11 ("old site")
;   music_timer    music(10,0,7)     after the orb, in stage 2
;   big_chest      music(-1,500,7)   stage 2
;
; The PSG's fade register is in 16 ms units, so the cart's 500 ms is 31.
    MUS_TITLE = 40
    MUS_CLIMB = 0
    MUS_ORB = 10
    MUS_STOP = $80
    FADE_500MS = 31
    TITLE_LEVEL = 31

; The cart's tile flags, as the cart numbers them.
    FLAG_SOLID = $01
    FLAG_ICE = $10

; ------------------------------------------------------------------------------
; Zero page
; ------------------------------------------------------------------------------
; scratch - callee-clobbered, never live across a jsr
    t0 = $00
    t1 = $01
    t2 = $02
    t3 = $03
    t4 = $04
    t5 = $05
    t6 = $06
    t7 = $07

; 16-bit working registers for the 8.8 fixed-point routines
    w0 = $08     ; +$09
    w1 = $0A     ; +$0B
    w2 = $0C     ; +$0D

; pointers
    pObj = $10     ; +$11  object being updated or drawn
    pOth = $12     ; +$13  the other object, in collide
    pFn = $14     ; +$15  method address for jmp (pFn)
    pOvl = $16     ; +$17  overlay shadow row
    pSrc = $18     ; +$19
    pDst = $1A     ; +$1B

; the object list
    obj_slot = $1C     ; slot index being dispatched
    obj_free = $1D     ; scratch: slot found by init_object
    spawn_type = $1E     ; init_object arguments
    spawn_x = $1F
    spawn_y = $20
    spawn_slot = $21     ; slot init_object used, for the caller

; collision arguments and results
    c_x = $22     ; box being tested
    c_y = $23
    c_w = $24
    c_h = $25
    c_mask = $26     ; tile flag under test
    c_ox = $27     ; is_solid's offsets, signed
    c_oy = $28
    c_type = $29     ; collide's target type
    c_hit = $2A     ; slot hit, or $FF
    c_i = $2B     ; box walk: tile columns
    c_j = $2C     ; box walk: tile rows
    c_i1 = $2D
    c_j1 = $2E

; game state, all the cart's globals
    frames = $30     ; 0..29, as the cart keeps it
    seconds = $31
    minutes = $32
    deaths = $33
    max_djump = $34
    freeze = $35
    shake = $36
    shake_x = $37     ; this frame's shake offset, applied to
    shake_y = $38     ;   sprites (the camera moves tiles only)
    will_restart = $39
    delay_restart = $3A
    room_slot = $3B     ; index into the resident room table
    room_bank = $3C     ; 0 or 1: which half of the tile world
    level = $3D     ; the cart's level_index
    camera_y = $3E
    btn = $40
    btnprev = $41
    btnedge = $42
    sfx_timer = $43
    music_timer = $44
    has_dashed = $45
    pause_player = $46
    nspr = $47     ; sprites staged this frame
    ovl_dirty = $48     ; the overlay shadow needs rebuilding
    hud_secs = $49     ; the clock value the HUD last drew
    nextch = $4A     ; round-robin channel for sfx stealing
    ld_i = $4B     ; load_room's spawn scan, which calls out
    start_game = $4C     ; the title screen's hand-off to the game
    start_game_flash = $4D     ; counts 50 down to -30, signed

; player update locals. The cart declares these with `local` inside update();
; here they are seven bytes of file scope, which is the frame-pointer slice's
; evidence and is deliberately not hidden.
    p_input = $50     ; -1, 0 or 1
    p_onground = $51
    p_onice = $52
    p_jump = $53     ; edge, not level
    p_dash = $54
    p_maxrun = $55
    p_accel = $56     ; +$57  8.8
    p_deccel = $58     ; +$59
    p_maxfall = $5A     ; +$5B
    p_gravity = $5C     ; +$5D
    p_vinput = $5E
    p_walldir = $5F

; drawing pen, which cannot live in t0..t7 because the glyph blitter calls the
; row blitter and both want scratch
    d_x = $60
    d_y = $61
    d_ch = $62
    d_bits = $63
    d_row = $64
    d_n = $65
    d_i = $66
    hair_i = $67
    hair_col = $68
    hair_lx = $6A     ; +$6B  the node this one chases, 8.8
    hair_ly = $6C     ; +$6D
    hair_hx = $6E     ; +$6F  the node being moved
    hair_hy = $70     ; +$71

; ------------------------------------------------------------------------------
; Working RAM, above the $4000-$41FF MMIO windows.
; ------------------------------------------------------------------------------
    OBJPOOL = $5000   ; OBJ_MAX * CelesteObject.size = 1024
    ROOMTILES = $5400   ; 256 tile ids: mget for the live room.
                                       ; Page-aligned, so mget(x,y) is one
                                       ; indexed load with y<<4|x in Y.
    OVLROW_LO = $5500   ; 120 overlay row addresses
    OVLROW_HI = $5580
; Background effects, structure-of-arrays because every loop over them touches
; one field at a time and X is the index.
; 32 bytes apart, not 16: the cart's counts are 17 clouds and 25 particles.
    CL_XL = $5600   ; cloud x, 8.8
    CL_XH = $5620
    CL_Y = $5640
    CL_W = $5660   ; width in 8-pixel cells
    CL_SL = $5680   ; cloud speed, 8.8
    CL_SH = $56A0
    PA_XL = $56C0   ; particle x, 8.8
    PA_XH = $56E0
    PA_YL = $5700
    PA_YH = $5720
    PA_SL = $5740
    PA_SH = $5760
    PA_ATTR = $5780   ; sprite attribute = its colour
    PA_OFF = $57A0   ; bob phase

    OVLSHADOW = $6000   ; 2400 bytes; the overlay is write-only
    OVL_STRIDE = 20
