; ------------------------------------------------------------------------------
; Celeste - memory map, console registers, object record layout
; ------------------------------------------------------------------------------

; PPU registers
    .define SPR_SHADDR_LO      $4000
    .define SPR_SHADDR_HI      $4001
    .define SPR_SHDATA         $4002   ; auto-incrementing sheet upload port
    .define SPR_CAMX           $4003
    .define SPR_CAMY           $4004   ; 7 bits: the 8 lines of vertical travel
    .define SPR_CTRL           $4005   ; bit0 tilemap en, bit1 overlay en
    .define SPR_OVLCOL         $4006
    .define SPR_BTN            $4007   ; 0 left 1 right 2 up 3 down 4 O 5 X
    .define SPR_INDEX          $4008
    .define SPR_X              $4009
    .define SPR_Y              $400A
    .define SPR_FLAGS          $400B   ; write commits the staged entry
    .define SPR_COUNT          $400C
    .define SPR_FRAME          $400D   ; +1 per vsync
    .define SPR_BASE           $400E
    .define SPR_RND            $400F
    .define SPR_DPAL           $4010   ; draw palette, 16 entries: remaps the
                                       ;   post-base colour of tiles + sprites
    .define SPR_SPAL           $4020   ; screen palette, 16 entries
    .define SPR_SPLIT          $4036   ; entries below this composite BEFORE
                                       ;   the tile layer (background sprites)
    .define SPR_REP            $4037   ; staged repeat, in cells: one committed
                                       ;   entry blits its row that many times
    .define SPR_CLIPX0         $4030
    .define SPR_CLIPY0         $4031
    .define SPR_CLIPX1         $4032
    .define SPR_CLIPY1         $4033

; PSG
    .define PSG_ADDR_LO        $4100
    .define PSG_ADDR_HI        $4101
    .define PSG_DATA           $4102
    .define PSG_STATUS         $4103   ; read: bits 0-3 channel playing
    .define PSG_CH             $4110   ; +ch: SFX # to play, $80 stop
    .define PSG_MUSIC          $4120
    .define PSG_MUSMASK        $4121
    .define PSG_FADE           $4122

    .define OVL                $E000   ; 160x120 1bpp, byte = y*20 + x/8,
                                       ; bit 0 = LEFTMOST pixel
    .define MAP_LO             $F000   ; tile pattern base, 32x16 cells
    .define MAP_HI             $F200   ; tile attributes
    .define MAP_STRIDE         32

; Buttons. The cart's k_* constants in the console's bit order.
    .define BTN_L              $01
    .define BTN_R              $02
    .define BTN_U              $04
    .define BTN_D              $08
    .define BTN_JUMP           $10     ; O
    .define BTN_DASH           $20     ; X

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
    .define ROOM_W             16      ; tiles
    .define ROOM_H             16
    .define PLAYFIELD_W        128
    .define CAM_Y_MAX          8       ; 128 - 120
    .define HUD_X              128

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
    .define O_TYPE             0       ; 0 = free slot
    .define O_SPR              1       ; the cart's sprite number
    .define O_X                2       ; signed integer pixels
    .define O_Y                3
    .define O_SPDX             4       ; 8.8 signed, lo then hi
    .define O_SPDY             6
    .define O_REMX             8       ; 8.8 sub-pixel remainder
    .define O_REMY             10
    .define O_HBX              12      ; hitbox
    .define O_HBY              13
    .define O_HBW              14
    .define O_HBH              15
    .define O_FLIP             16      ; bit0 x, bit1 y
    .define O_FLAGS            17      ; bit0 collideable, bit1 solids
    .define O_STATE            18
    .define O_DELAY            19
    .define O_DJUMP            20
    .define O_GRACE            21
    .define O_JBUF             22
    .define O_DASHT            23      ; dash_time
    .define O_DASHE            24      ; dash_effect_time
    .define O_PBITS            25      ; bit0 p_jump, bit1 p_dash, bit2 was_on_ground
    .define O_SPROFF           26      ; animation, in quarter-frames
    .define O_DTX              27      ; dash_target x, 8.8
    .define O_DTY              29
    .define O_DAX              31      ; dash_accel x, 8.8
    .define O_DAY              33
    .define O_TGTX             35      ; player_spawn's landing target
    .define O_TGTY             36
    .define O_HAIR             37      ; 5 nodes x {x lo,hi, y lo,hi} = 20 bytes
    .define O_SIZE             64
    .define OBJ_MAX            16
    .define HAIR_NODES         5

    .define F_COLLIDEABLE      $01
    .define F_SOLIDS           $02

; Type ids. 0 means "free slot", so the first real type is 1.
    .define T_PLAYER           1
    .define T_SPAWN            2
    .define T_SMOKE            3
    .define T_TITLE            4
    .define T_COUNT            4

; The cart's marker tiles. Only player_spawn is a stage-1 type; the rest are
; recognised so load_room can skip them without warning, and are stage 2.
    .define TILE_SPAWN         1
    .define TILE_SPRING        18
    .define TILE_BALLOON       22
    .define TILE_FALL_FLOOR    23
    .define TILE_FRUIT         26
    .define TILE_FLY_FRUIT     28
    .define TILE_FAKE_WALL     64

; Spike tiles, by the direction the spikes point.
    .define TILE_SPIKE_D       17
    .define TILE_SPIKE_U       27
    .define TILE_SPIKE_R       43
    .define TILE_SPIKE_L       59

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
    .define MUS_TITLE          40
    .define MUS_CLIMB          0
    .define MUS_ORB            10
    .define MUS_STOP           $80
    .define FADE_500MS         31
    .define TITLE_LEVEL        31

; The cart's tile flags, as the cart numbers them.
    .define FLAG_SOLID         $01
    .define FLAG_ICE           $10

; ------------------------------------------------------------------------------
; Zero page
; ------------------------------------------------------------------------------
; scratch - callee-clobbered, never live across a jsr
    .define t0                 $00
    .define t1                 $01
    .define t2                 $02
    .define t3                 $03
    .define t4                 $04
    .define t5                 $05
    .define t6                 $06
    .define t7                 $07

; 16-bit working registers for the 8.8 fixed-point routines
    .define w0                 $08     ; +$09
    .define w1                 $0A     ; +$0B
    .define w2                 $0C     ; +$0D

; pointers
    .define pObj               $10     ; +$11  object being updated or drawn
    .define pOth               $12     ; +$13  the other object, in collide
    .define pFn                $14     ; +$15  method address for jmp (pFn)
    .define pOvl               $16     ; +$17  overlay shadow row
    .define pSrc               $18     ; +$19
    .define pDst               $1A     ; +$1B

; the object list
    .define obj_slot           $1C     ; slot index being dispatched
    .define obj_free           $1D     ; scratch: slot found by init_object
    .define spawn_type         $1E     ; init_object arguments
    .define spawn_x            $1F
    .define spawn_y            $20
    .define spawn_slot         $21     ; slot init_object used, for the caller

; collision arguments and results
    .define c_x                $22     ; box being tested
    .define c_y                $23
    .define c_w                $24
    .define c_h                $25
    .define c_mask             $26     ; tile flag under test
    .define c_ox               $27     ; is_solid's offsets, signed
    .define c_oy               $28
    .define c_type             $29     ; collide's target type
    .define c_hit              $2A     ; slot hit, or $FF
    .define c_i                $2B     ; box walk: tile columns
    .define c_j                $2C     ; box walk: tile rows
    .define c_i1               $2D
    .define c_j1               $2E

; game state, all the cart's globals
    .define frames             $30     ; 0..29, as the cart keeps it
    .define seconds            $31
    .define minutes            $32
    .define deaths             $33
    .define max_djump          $34
    .define freeze             $35
    .define shake              $36
    .define shake_x            $37     ; this frame's shake offset, applied to
    .define shake_y            $38     ;   sprites (the camera moves tiles only)
    .define will_restart       $39
    .define delay_restart      $3A
    .define room_slot          $3B     ; index into the resident room table
    .define room_bank          $3C     ; 0 or 1: which half of the tile world
    .define level              $3D     ; the cart's level_index
    .define camera_y           $3E
    .define btn                $40
    .define btnprev            $41
    .define btnedge            $42
    .define sfx_timer          $43
    .define music_timer        $44
    .define has_dashed         $45
    .define pause_player       $46
    .define nspr               $47     ; sprites staged this frame
    .define ovl_dirty          $48     ; the overlay shadow needs rebuilding
    .define hud_secs           $49     ; the clock value the HUD last drew
    .define nextch             $4A     ; round-robin channel for sfx stealing
    .define ld_i               $4B     ; load_room's spawn scan, which calls out
    .define start_game         $4C     ; the title screen's hand-off to the game
    .define start_game_flash   $4D     ; counts 50 down to -30, signed

; player update locals. The cart declares these with `local` inside update();
; here they are seven bytes of file scope, which is the frame-pointer slice's
; evidence and is deliberately not hidden.
    .define p_input            $50     ; -1, 0 or 1
    .define p_onground         $51
    .define p_onice            $52
    .define p_jump             $53     ; edge, not level
    .define p_dash             $54
    .define p_maxrun           $55
    .define p_accel            $56     ; +$57  8.8
    .define p_deccel           $58     ; +$59
    .define p_maxfall          $5A     ; +$5B
    .define p_gravity          $5C     ; +$5D
    .define p_vinput           $5E
    .define p_walldir          $5F

; drawing pen, which cannot live in t0..t7 because the glyph blitter calls the
; row blitter and both want scratch
    .define d_x                $60
    .define d_y                $61
    .define d_ch               $62
    .define d_bits             $63
    .define d_row              $64
    .define d_n                $65
    .define d_i                $66
    .define hair_i             $67
    .define hair_col           $68
    .define hair_lx            $6A     ; +$6B  the node this one chases, 8.8
    .define hair_ly            $6C     ; +$6D
    .define hair_hx            $6E     ; +$6F  the node being moved
    .define hair_hy            $70     ; +$71

; ------------------------------------------------------------------------------
; Working RAM, above the $4000-$41FF MMIO windows.
; ------------------------------------------------------------------------------
    .define OBJPOOL            $5000   ; OBJ_MAX * O_SIZE = 1024
    .define ROOMTILES          $5400   ; 256 tile ids: mget for the live room.
                                       ; Page-aligned, so mget(x,y) is one
                                       ; indexed load with y<<4|x in Y.
    .define OVLROW_LO          $5500   ; 120 overlay row addresses
    .define OVLROW_HI          $5580
; Background effects, structure-of-arrays because every loop over them touches
; one field at a time and X is the index.
; 32 bytes apart, not 16: the cart's counts are 17 clouds and 25 particles.
    .define CL_XL              $5600   ; cloud x, 8.8
    .define CL_XH              $5620
    .define CL_Y               $5640
    .define CL_W               $5660   ; width in 8-pixel cells
    .define CL_SL              $5680   ; cloud speed, 8.8
    .define CL_SH              $56A0
    .define PA_XL              $56C0   ; particle x, 8.8
    .define PA_XH              $56E0
    .define PA_YL              $5700
    .define PA_YH              $5720
    .define PA_SL              $5740
    .define PA_SH              $5760
    .define PA_ATTR            $5780   ; sprite attribute = its colour
    .define PA_OFF             $57A0   ; bob phase

    .define OVLSHADOW          $6000   ; 2400 bytes; the overlay is write-only
    .define OVL_STRIDE         20
    .define OVL_BYTES          2400
