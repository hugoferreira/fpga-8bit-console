; ------------------------------------------------------------------------------
; NEMO - memory map and console registers
; ------------------------------------------------------------------------------

; PPU registers
    .define SPR_CTRL           $4005   ; bit0 tilemap en, bit1 overlay en
    .define SPR_OVLCOL         $4006   ; overlay colour
    .define SPR_BTN            $4007   ; 0 left 1 right 2 up 3 down 4 O 5 X
    .define SPR_COUNT          $400C   ; active sprite count
    .define SPR_FRAME          $400D   ; frame counter, +1 per vsync
    .define SPR_RND            $400F   ; LFSR
; PSG registers
    .define PSG_ADDR_LO        $4100
    .define PSG_ADDR_HI        $4101
    .define PSG_DATA           $4102
    .define PSG_STATUS         $4103   ; read: bits 0-3 channel playing, bit7 music
    .define PSG_CH             $4110   ; +ch: SFX # to play, $80 stop, $81 release
    .define PSG_MUSIC          $4120   ; pattern # to start, $80 stops
    .define PSG_MUSMASK        $4121   ; channels reserved for music
    .define PSG_FADE           $4122   ; fade length, 16 ms units

; Sprite sheet / list
    .define SPR_SHADDR_LO      $4000
    .define SPR_SHADDR_HI      $4001
    .define SPR_SHDATA         $4002
    .define SPR_INDEX          $4008
    .define SPR_X              $4009
    .define SPR_Y              $400A
    .define SPR_FLAGS          $400B
    .define SPR_BASE           $400E

    .define OVL                $E000   ; 160x120 1bpp, byte = y*20 + x/8,
                                       ; bit 0 = LEFTMOST pixel

; Button masks
    .define BTN_L              $01
    .define BTN_R              $02
    .define BTN_U              $04
    .define BTN_D              $08
    .define BTN_O              $10
    .define BTN_X              $20

; ------------------------------------------------------------------------------
; Geometry. Cells are 6x6 like the original cart; the grid is anchored so its
; bottom-right corner is fixed, which is what makes smaller puzzles sit down
; and to the right. Row clues run horizontally to the right of the grid,
; column clues run vertically below it - the cart's layout, not the usual one.
;
;   (0,0)                                        (159,0)
;     +---------------------------+----------------+
;     |  GRID  <=90x90            |  ROW CLUES     |
;     |  bottom-right at (91,91)  |  x 94..159     |
;     +---------------------------+----------------+ y=92
;     |  COLUMN CLUES  y 94..119  |  HUD           |
;     +---------------------------+----------------+ (159,119)
; ------------------------------------------------------------------------------
    .define CELL_PX            6
    .define MAX_DIM            15
    .define GRID_R             91      ; grid right edge  (fixed)
    .define GRID_B             91      ; grid bottom edge (fixed)
    .define CLUE_H_X           94      ; row clues start here
    .define CLUE_V_Y           94      ; column clues start here
    .define OVL_STRIDE         20      ; bytes per overlay scanline
    .define OVL_BYTES          2400    ; 20 * 120

; Cell values. Deliberately a small set of distinct bytes rather than a packed
; bitfield: the board is read far more often than it is written (every clue
; match check walks it) so a byte per cell keeps the inner loops branch-free.
    .define CELL_EMPTY         0
    .define CELL_FILL          1
    .define CELL_MARK          2

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
    .define t8                 $1B     ; block/rect corner, outlives t1..t6
    .define t9                 $1C

; pointer pairs (lo,hi) for (zp),y addressing
    .define pSrc               $08     ; +$09
    .define pDst               $0A     ; +$0B
    .define pRow               $0C     ; +$0D   row base into a cell array
    .define pCls               $0E     ; +$0F   class descriptor being walked
    .define pFn                $10     ; +$11   method address for the jmp
    .define pObj               $12     ; +$13   object record base
    .define pClue              $14     ; +$15

; multiply / divide workspace
    .define mulA               $16
    .define mulB               $17
    .define mulR               $18     ; +$19  16-bit product
    .define mulH               $1A     ; high half of the shifted multiplicand

; puzzle state
    .define pz_idx             $20     ; selected puzzle 0..49
    .define pz_w               $21     ; width  in cells
    .define pz_h               $22     ; height in cells
    .define pz_cells           $23     ; +$24  w*h, 16-bit
    .define grid_x             $25     ; grid left edge in pixels
    .define grid_y             $26     ; grid top edge in pixels

; cursor
    .define cur_x              $28
    .define cur_y              $29
    .define cur_blink          $2A

; input
    .define btn                $2C
    .define btnprev            $2D
    .define btnedge            $2E

; game state
    .define state              $30
    .define is_clear           $31
    .define dirty              $32     ; non-zero -> blit the overlay shadow
    .define n_runs             $33     ; scratch: runs produced by run_lengths
    .define sel_scroll         $34
    .define sel_target         $35

; drawing state. Separate from t0..t7 on purpose: ovl_box, ovl_hline and
; glyph_at all clobber t1..t6, so any loop counter that has to survive a draw
; call needs its own byte. This is the globals-as-locals problem the corpus is
; here to measure - eleven bytes of it, in one module.
    .define d_row              $40
    .define d_col              $41
    .define d_val              $42
    .define d_px               $43
    .define d_py               $44
    .define clue_x             $45
    .define clue_y             $46
    .define clue_n             $47
    .define clue_i             $48
    .define txt_i              $49     ; ovl_text's character index
    .define gly_scale          $4A     ; glyph_at pixel size, 1 = normal
    .define box_x              $4B     ; puzzle-box strip pen
    .define box_y              $4C
    .define box_i              $4D
    .define box_n              $4E
    .define blk_x              $4F     ; ovl_blk's own corner, safe across hline
    .define blk_y              $50
    .define blk_n              $51
    ; map_box needs its own four bytes rather than borrowing the strip's: it is
    ; called FROM the strip loop, and sharing box_i/box_n hung the program by
    ; overwriting the caller's loop counter. One collision per shared byte.
    .define mb_x               $52
    .define mb_y               $53
    .define mb_i               $54
    .define mb_n               $55
    ; glyph_at's row counter and row bitmap. They cannot live in t3/t4: ovl_blk
    ; calls ovl_hline, which uses t3 as its length and t4 as its step, so at any
    ; scale above 1 the counter was being zeroed on every pixel plotted.
    .define gly_row            $56
    .define gly_bits           $57
    .define spr_n              $58     ; sprite list entries staged this frame
    ; sfx_play's busy mask. It cannot use t0: ev_emit keeps its loop counter
    ; there, and an event handler calls sfx_play - the fourth time in this port
    ; that a shared zero-page byte was destroyed across a jsr.
    .define sfx_busy           $59

; object system
    .define obj_count          $38
    .define obj_root           $39
    .define obj_cur            $3A     ; index of object being dispatched
    .define ev_count           $3B
    .define m_prevh            $3D     ; row/col match flags before an edit, kept
    .define m_prevv            $3E     ;   out of t0..t7 because match_cursor
                                       ;   clobbers all of them (run_lengths
                                       ;   uses t7 as its span length)

; ------------------------------------------------------------------------------
; Working RAM. Deliberately above the $4000-$41FF MMIO windows.
; ------------------------------------------------------------------------------
    .define SOLUTION           $5000   ; MAX_DIM*MAX_DIM cell bytes
    .define BOARD              $5100   ; MAX_DIM*MAX_DIM cell bytes
    .define ROWOFF             $5200   ; MAX_DIM row offsets (y*w) - see grid.asm
    .define CLUE_H             $5220   ; 15 rows x 16 bytes: count then runs
    .define CLUE_V             $5320   ; 15 cols x 16 bytes
    .define MATCH_H            $5420   ; 15 flags
    .define MATCH_V            $5430   ; 15 flags
    .define DEFINITE_H         $5440   ; 15 flags: row has no slack
    .define DEFINITE_V         $5450
    .define RUNBUF             $5460   ; scratch run list from run_lengths
    .define COLBUF             $5480   ; scratch: one column gathered as a row
    .define PROGRESS           $54A0   ; 7 bytes: 50 completion bits
    .define OBJPOOL            $5500   ; OBJ_MAX * OBJ_SIZE
    .define EVPOOL             $5600   ; EV_MAX * EV_SIZE
    .define OVLROW_LO          $5700   ; 120 overlay row addresses
    .define OVLROW_HI          $5780
    .define OVLSHADOW          $6000   ; OVL_BYTES

; Audio event map. Here rather than in sound.asm for the same reason as the
; event ids: main.asm uses them before that file is included.
    .define SFX_FILL           0
    .define SFX_CLEAR          1
    .define SFX_LINE           2
    .define SFX_MOVE           3
    .define SFX_BLOCKED        4
    .define MUS_MENU           0
    .define MUS_PLAY           13
    .define MUS_CLEAR          6

; Event ids. Here rather than in obj.asm because main.asm registers handlers
; before obj.asm is included, and .define is textual.
    .define EV_CELL_CHANGED    1
    .define EV_PUZZLE_CLEAR    2
    .define EV_CURSOR_MOVED    3

    .define CLUE_STRIDE        16      ; per row/col: [0]=count, [1..] runs
