.segment "CODE"
    ; ------------------------------------------------------------------------------
    ; BREAKOUT HERO - port of Krystman's PICO-8 cart to this console
    ; ------------------------------------------------------------------------------
    ; Original game (c) Krystman / Lazy Devs Academy (PICO-8 BBS cart 53976).
    ; Level layouts and paddle/ball art come from the cart; this 6502 game
    ; code is an original implementation written for this hardware.
    ;
    ; Arena: tile cols 1 and 13 are walls, bricks in an 11-wide grid at tile
    ; cols 2-12, rows 2-11. Interior pixels x 16..103, top y 16, open bottom.
    ; Right side (cols 14+) is the HUD. Ball and paddle are sprites; bricks
    ; are tilemap cells; messages use the 4x6 overlay font.

    ; PPU registers
    .define SPR_SHADDR_LO      $4000
    .define SPR_SHADDR_HI      $4001
    .define SPR_SHDATA         $4002
    .define SPR_CTRL           $4005
    .define SPR_OVLCOL         $4006
    .define SPR_CAMX           $4003
    .define SPR_BTN            $4007
    .define SPR_INDEX          $4008
    .define SPR_X              $4009
    .define SPR_Y              $400A
    .define SPR_FLAGS          $400B
    .define SPR_COUNT          $400C
    .define SPR_FRAME          $400D
    .define SPR_BASE           $400E
    .define SPR_RND            $400F  ; hardware LFSR, read-only
    .define SPR_BSPLIT         $4036  ; list entries below this draw behind tiles

    ; PSG
    .define PSG_ADDR_LO        $4100
    .define PSG_ADDR_HI        $4101
    .define PSG_DATA           $4102
    .define PSG_CH             $4110  ; +ch*4: start, len, speed, ctrl

    ; sound ids (indices into the sfx_* tables)
    .define SND_WALL           0
    .define SND_PADDLE         1
    .define SND_LOSE           2
    .define SND_BRICK          3
    .define SND_SERVE          4
    .define SND_SHATTER        5
    .define SND_CHAIN          6
    .define SPR_SPAL           $4020

    .define MAP_LO             $F000
    .define MAP_HI             $F200
    .define OVL                $E000

    ; Buttons
    .define BTN_L              $01
    .define BTN_R              $02
    .define BTN_X              $20

    ; Geometry
    .define ARENA_L            16     ; interior left edge
    .define ARENA_R            104    ; interior right edge (exclusive)
    .define ARENA_T            16     ; interior top edge
    .define PAD_Y              106    ; paddle sprite y
    .define PAD_MIN            16
    .define PAD_MAX            80     ; 24px paddle in the 88px interior
    .define BALL_DEATH         118

    ; Game states
    .define ST_SERVE           0
    .define ST_PLAY            1
    .define ST_OVER            2

    ; Zero page
    .define ballx   $04    ; 8.8: frac, int
    .define bally   $06
    .define bvx     $08    ; signed 8.8
    .define bvy     $0A
    .define padx    $0C
    .define state   $0D
    .define lives   $0E
    .define level   $0F    ; 0-based
    .define score0  $10    ; BCD, low digits first
    .define score1  $11
    .define score2  $12
    .define bricksn $13
    .define tmp     $14
    .define tmp2    $15
    .define btn     $16
    .define btnprev $17
    .define blink   $18
    .define ptr     $19    ; and $1A
    .define rowv    $1B
    .define colv    $1C
    .define hitr    $1D
    .define hitc    $1E
    .define tmp3    $1F
    .define servedx $20
    .define ptr2    $22    ; and $23
    .define shaket  $24
    .define shx     $25
    .define pnext   $26
    .define spx     $27
    .define spy     $28
    .define spvx    $29
    .define spvy    $2A
    .define spcol   $2B
    .define padvx   $2C    ; and $2D (signed 8.8)
    .define padxf   $2E    ; paddle x fraction
    .define ballspd $2F    ; wind-up speed level 0-2
    .define windt   $30    ; and $31
    .define chain   $32    ; score multiplier 1-7
    .define chaint  $33    ; chain window frames
    .define flasht  $34    ; screen flash frames
    .define spkind  $35    ; particle kind for spawn
    .define mulk    $36    ; scratch (brick_hit)
    .define sidx    $37    ; scratch (brick_hit)

    ; Particle pool (12), one page
    .define PPX     $2100
    .define PPY     $2110
    .define PVX     $2120
    .define PVY     $2130
    .define PLIFE   $2140
    .define PCOL    $2150
    .define PKIND   $2160  ; 0 = burst spark, 1 = ball trail, 2 = shard
    .define DUSTX   $2170  ; ambient dust (8), behind the bricks
    .define DUSTY   $2178

    ; Brick shadow map: 10 rows x 11 cols (well above the program image,
    ; which now extends past $1200 - the original $0C00 scratch overlapped
    ; the level data and got wiped by the shadow clear)
    .define shadow  $2000

; ------------------------------------------------------------------------------
start:
    ; Upload game patterns to sheet slots 0-39 (font at 128+ is preloaded)
    lda #0
    sta SPR_SHADDR_LO
    sta SPR_SHADDR_HI
    ldx #0
@gfx1:
    lda gfx_data,x
    sta SPR_SHDATA
    inx
    bne @gfx1
    ldx #0
@gfx2:
    lda gfx_data+256,x
    sta SPR_SHDATA
    inx
    cpx #144
    bne @gfx2

    ; Clear the whole tilemap and overlay
    ldx #0
    lda #0
@clrmap:
    sta MAP_LO,x
    sta MAP_LO+256,x
    sta MAP_HI,x
    sta MAP_HI+256,x
    inx
    bne @clrmap
    ldx #0
    lda #0
@clrovl:
    sta OVL,x
    sta OVL+$100,x
    sta OVL+$200,x
    sta OVL+$300,x
    sta OVL+$400,x
    sta OVL+$500,x
    sta OVL+$600,x
    sta OVL+$700,x
    sta OVL+$800,x
    sta OVL+$900,x
    inx
    bne @clrovl

    ; Walls: top row 1 (cols 1-13), sides cols 1 and 13 (rows 1-14)
    ldx #1
@topwall:
    lda #40            ; wall pattern base
    sta MAP_LO+32,x    ; row 1 starts at cell 32
    lda #$0C           ; 4bpp, pal 0
    sta MAP_HI+32,x
    inx
    cpx #14
    bne @topwall
    ldx #1
@sidewall:
    lda rowmap_lo,x
    sta ptr
    lda rowmap_hi,x
    sta ptr+1
    ldy #1
    lda #40
    sta (ptr),y
    ldy #13
    sta (ptr),y
    lda ptr+1
    clc
    adc #2             ; MAP_HI page = MAP_LO page + $200
    sta ptr+1
    ldy #1
    lda #$0C
    sta (ptr),y
    ldy #13
    sta (ptr),y
    inx
    cpx #15
    bne @sidewall

    ; HUD labels (font tiles, white): SCORE / BALLS / LEVEL in col 14+
    ldx #0
@hud1:
    lda txt_score,x
    ora #$80
    sta MAP_LO+32+14,x     ; row 1
    lda #$60
    sta MAP_HI+32+14,x
    inx
    cpx #5
    bne @hud1
    ldx #0
@hud2:
    lda txt_balls,x
    ora #$80
    sta MAP_LO+128+14,x    ; row 4
    lda #$60
    sta MAP_HI+128+14,x
    inx
    cpx #5
    bne @hud2
    ldx #0
@hud3:
    lda txt_level,x
    ora #$80
    sta MAP_LO+224+14,x    ; row 7
    lda #$60
    sta MAP_HI+224+14,x
    inx
    cpx #5
    bne @hud3

    ; Original look: navy background, value 3 renders black (mortar)
    lda #1
    sta SPR_SPAL+0
    lda #0
    sta SPR_SPAL+3

    ; Upload the cart's sound effects to the PSG
    lda #0
    sta PSG_ADDR_LO
    sta PSG_ADDR_HI
    ldx #0
@sfxup:
    lda sfx_data,x
    sta PSG_DATA
    inx
    cpx #SFX_BYTES
    bne @sfxup

    ; First 8 list entries (ambient dust) composite behind the tile layer
    lda #8
    sta SPR_BSPLIT
    ; seed the dust from the hardware LFSR
    ldx #0
@dust0:
    lda SPR_RND
    and #63
    clc
    adc #20
    sta DUSTX,x
    lda SPR_RND
    and #63
    clc
    adc #24
    sta DUSTY,x
    inx
    cpx #8
    bne @dust0

    ; PPU on: tilemap + overlay, white overlay text
    lda #7
    sta SPR_OVLCOL
    lda #3
    sta SPR_CTRL

    jsr new_game

; ------------------------------------------------------------------------------
main_loop:
    lda SPR_FRAME
@wf: cmp SPR_FRAME
    beq @wf

    lda btn
    sta btnprev
    lda SPR_BTN
    sta btn
    inc blink

    lda state
    cmp #ST_PLAY
    bne @notplay
    jmp do_play
@notplay:
    cmp #ST_SERVE
    beq do_serve
    jmp do_over

; --- serve: ball rides the paddle, X launches ---------------------------------
do_serve:
    jsr move_paddle
    lda padx
    clc
    adc #9
    sta ballx+1
    lda #0
    sta ballx
    sta bally
    lda #98
    sta bally+1
    ; blink PRESS X
    lda blink
    and #$0F
    bne @noblk
    jsr msg_clear
    lda blink
    and #$10
    bne @noblk
    jsr msg_press
@noblk:
    lda btn
    and #BTN_X
    beq @done
    lda btnprev
    and #BTN_X
    bne @done
    jsr msg_clear
    lda #ST_PLAY
    sta state
    ; serve at a near-vertical angle with per-serve variation
    lda #0
    sta ballspd
    sta windt
    sta windt+1
    ldx #SND_SERVE
    ldy #8
    jsr sfx_play
    lda SPR_RND
    and #3
    clc
    adc #5                 ; angle index 5..8
    tay
    jsr set_vec
@done:
    jmp frame_end

; --- game over -----------------------------------------------------------------
do_over:
    lda btn
    and #BTN_X
    beq @done
    lda btnprev
    and #BTN_X
    bne @done
    jsr msg_clear
    jsr new_game
@done:
    jmp frame_end

; --- play ----------------------------------------------------------------------
do_play:
    jsr move_paddle

    ; speed wind-up: every 600 frames raise the speed level (applies at
    ; the next paddle bounce), max level 2
    inc windt
    bne @wnb
    inc windt+1
@wnb:
    lda windt+1
    cmp #2
    bcc @wdone
    lda windt
    cmp #$58
    bcc @wdone
    lda #0
    sta windt
    sta windt+1
    lda ballspd
    cmp #2
    bcs @wdone
    inc ballspd
@wdone:
    ; chain multiplier window
    lda chaint
    beq @chz
    dec chaint
    bne @chz
    lda #1
    sta chain
@chz:

    ; ball position += velocity (16-bit signed adds)
    lda ballx
    clc
    adc bvx
    sta ballx
    lda ballx+1
    adc bvx+1
    sta ballx+1
    lda bally
    clc
    adc bvy
    sta bally
    lda bally+1
    adc bvy+1
    sta bally+1

    ; walls (ball box is sprite+2 .. sprite+5)
    lda ballx+1
    cmp #ARENA_L-1
    bcs @notleft
    lda #ARENA_L-1
    sta ballx+1
    jsr negx
    jsr snd_wall
@notleft:
    lda ballx+1
    cmp #ARENA_R-7
    bcc @notright
    lda #ARENA_R-7
    sta ballx+1
    jsr negx
    jsr snd_wall
@notright:
    lda bally+1
    cmp #ARENA_T-1
    bcs @nottop
    lda #ARENA_T-1
    sta bally+1
    jsr negy
    jsr snd_wall
@nottop:

    ; death?
    lda bally+1
    cmp #BALL_DEATH
    bcc @alive
    ldx #SND_LOSE
    ldy #8
    jsr sfx_play
    lda #8
    sta shaket
    dec lives
    jsr draw_hud
    lda lives
    beq @gameover
    lda #ST_SERVE
    sta state
    lda #0
    sta blink
    jmp frame_end
@gameover:
    lda #ST_OVER
    sta state
    jsr msg_over
    lda #124
    sta bally+1            ; park the dead ball off-screen
    jmp frame_end
@alive:

    ; paddle bounce (moving down, box bottom in paddle band, x overlap)
    lda bvy+1
    bmi @nopad
    lda bally+1
    cmp #PAD_Y-4
    bcc @nopad
    cmp #PAD_Y+2
    bcs @nopad
    lda ballx+1
    sec
    sbc padx
    clc
    adc #6                 ; 0..29 when overlapping
    cmp #30
    bcs @nopad
    ldy #0
    cmp #6
    bcc @zok
    iny
    cmp #12
    bcc @zok
    iny
    cmp #18
    bcc @zok
    iny
    cmp #24
    bcc @zok
    iny
@zok:
    lda zone_ang,y
    tay
    ; paddle velocity biases the bounce one angle step
    lda padvx+1
    bmi @bleft
    bne @bright
    lda padvx
    cmp #$60
    bcc @nobias
@bright:
    cpy #12
    bcs @nobias
    iny
    bne @nobias
@bleft:
    cpy #0
    beq @nobias
    dey
@nobias:
    jsr set_vec
    lda #1                 ; returning to the paddle resets the chain
    sta chain
    ldx #SND_PADDLE
    ldy #4
    jsr sfx_play
@nopad:

    ; ball trail: a shrinking circle every frame (white -> yellow -> orange)
    lda ballx+1
    sta spx
    lda bally+1
    sta spy
    lda #0
    sta spvx
    sta spvy
    lda #1
    sta spkind
    lda #12
    jsr spawn_particle

    ; --- brick collisions: probe ahead of the ball center on each axis ---
    lda ballx+1
    clc
    adc #3
    sta tmp                ; cx
    lda bally+1
    clc
    adc #3
    sta tmp2               ; cy
    ; horizontal probe (cx +/- 3, cy)
    lda tmp
    ldy bvx+1
    bmi @hneg
    clc
    adc #3
    jmp @hgo
@hneg:
    sec
    sbc #3
@hgo:
    tax
    ldy tmp2
    jsr probe_brick
    bcc @noh
    jsr brick_hit
    jsr negx
@noh:
    ; vertical probe (cx, cy +/- 3)
    lda tmp2
    ldy bvy+1
    bmi @vneg
    clc
    adc #3
    jmp @vgo
@vneg:
    sec
    sbc #3
@vgo:
    tay
    ldx tmp
    jsr probe_brick
    bcc @nov
    jsr brick_hit
    jsr negy
@nov:

    ; level cleared?
    lda bricksn
    bne @go
    ldx level
    inx
    cpx #15
    bcc @lv
    ldx #0
@lv:
    stx level
    jsr build_level
    jsr draw_hud
    lda #6
    sta flasht
    lda #ST_SERVE
    sta state
@go:
    jmp frame_end

; ------------------------------------------------------------------------------
; probe_brick: X = pixel x, Y = pixel y -> C set if a brick cell is there.
; Cell coords left in hitr/hitc.
probe_brick:
    txa
    sec
    sbc #ARENA_L
    bcc @miss
    lsr
    lsr
    lsr
    cmp #11
    bcs @miss
    sta hitc
    tya
    sec
    sbc #ARENA_T
    bcc @miss
    lsr
    lsr
    lsr
    cmp #10
    bcs @miss
    sta hitr
    tax
    lda times11,x
    clc
    adc hitc
    tay
    lda shadow,y
    beq @miss
    sec
    rts
@miss:
    clc
    rts

; ------------------------------------------------------------------------------
; brick_hit: damage the cell at (hitr, hitc)
brick_hit:
    ldx hitr
    lda times11,x
    clc
    adc hitc
    tay
    ldx shadow,y           ; X = type code
    sty sidx
    ; score += points[type] * chain (BCD), then boost the chain
    lda type_pts,x
    beq @nopts
    sta mulk
    ldy chain
    sed
@mul:
    lda score0
    clc
    adc mulk
    sta score0
    lda score1
    adc #0
    sta score1
    lda score2
    adc #0
    sta score2
    dey
    bne @mul
    cld
    lda chain
    cmp #7
    bcs @cmax
    inc chain
    lda chain
    cmp #7
    bne @cmax
    txa
    pha
    ldx #SND_CHAIN
    ldy #12
    jsr sfx_play
    pla
    tax
@cmax:
    lda #44
    sta chaint
@nopts:
    ldy sidx
    lda type_next,x
    sta shadow,y
    pha
    bne @tile              ; still standing (damaged or indestructible)
    cpx #4
    beq @tile
    dec bricksn
@tile:
    ; rewrite the map cell at row hitr+2, col hitc+2
    ldx hitr
    lda rowmap2_lo,x
    sta ptr2
    lda rowmap2_hi,x
    sta ptr2+1
    pla
    tax                    ; X = new type
    ldy hitc
    iny
    iny
    lda type_tile,x
    sta (ptr2),y           ; MAP_LO
    lda ptr2+1
    clc
    adc #2
    sta ptr2+1
    lda type_hi,x
    sta (ptr2),y           ; MAP_HI
    ; sound: shatter when destroyed, blip otherwise (hardware sequencer,
    ; so this is 4 register writes either way)
    txa
    pha
    txa                    ; X here is the NEW type: 0 = destroyed
    bne @sndhit
    ldx #SND_SHATTER
    bne @sndgo
@sndhit:
    ldx #SND_BRICK
@sndgo:
    ldy #0
    jsr sfx_play
    pla
    tax
    ; game feel: shards + shake + 4 sparks from the brick center
    txa                    ; X is the NEW type: shards only on destruction
    bne @noshard
    lda #2
    sta spkind
    lda type_spark,x
    sta spcol
    lda hitc
    asl
    asl
    asl
    clc
    adc #17
    sta spx
    lda hitr
    asl
    asl
    asl
    clc
    adc #17
    sta spy
    lda #$FF
    sta spvx
    lda #$FE
    sta spvy
    lda #16
    jsr spawn_particle
    lda spx
    clc
    adc #4
    sta spx
    lda #1
    sta spvx
    lda #$FE
    sta spvy
    lda #16
    jsr spawn_particle
@noshard:
    lda #4
    sta shaket
    lda type_spark,x
    sta spcol
    lda hitc
    asl
    asl
    asl
    clc
    adc #19                ; brick center x
    sta spx
    lda hitr
    asl
    asl
    asl
    clc
    adc #19                ; brick center y
    sta spy
    lda #0
    sta spkind
    ldy #0
@burst:
    lda burst_vx,y
    sta spvx
    lda burst_vy,y
    sta spvy
    tya
    pha
    lda #10
    jsr spawn_particle
    pla
    tay
    iny
    cpy #4
    bne @burst
    jsr draw_hud
    rts

; ------------------------------------------------------------------------------
snd_wall:
    ldx #SND_WALL
    ldy #4
    jmp sfx_play

negx:
    sec
    lda #0
    sbc bvx
    sta bvx
    lda #0
    sbc bvx+1
    sta bvx+1
    rts
negy:
    sec
    lda #0
    sbc bvy
    sta bvy
    lda #0
    sbc bvy+1
    sta bvy+1
    rts

; ------------------------------------------------------------------------------
; Paddle with momentum: accelerate 0.5/frame toward +/-2.5, decay by
; ~x0.75 per frame when no key is held (the original decays by /1.3)
move_paddle:
    lda btn
    and #BTN_L
    beq @notl
    lda padvx
    sec
    sbc #$80
    sta padvx
    lda padvx+1
    sbc #0
    sta padvx+1
    cmp #$FD               ; clamp at -2.5 ($FD80)
    bcs @chkr
    lda #$80
    sta padvx
    lda #$FD
    sta padvx+1
    jmp @apply
@notl:
@chkr:
    lda btn
    and #BTN_R
    beq @friction
    lda padvx
    clc
    adc #$80
    sta padvx
    lda padvx+1
    adc #0
    sta padvx+1
    cmp #3                 ; clamp at +2.5 ($0280)
    bcc @apply
    lda #$80
    sta padvx
    lda #$02
    sta padvx+1
    jmp @apply
@friction:
    lda btn
    and #BTN_L
    bne @apply
    ; v -= v>>2 (arithmetic), toward zero
    lda padvx+1
    cmp #$80
    ror
    sta tmp
    lda padvx
    ror
    sta tmp2
    lda tmp
    cmp #$80
    ror
    sta tmp
    lda tmp2
    ror
    sta tmp2
    lda padvx
    sec
    sbc tmp2
    sta padvx
    lda padvx+1
    sbc tmp
    sta padvx+1
@apply:
    lda padxf
    clc
    adc padvx
    sta padxf
    lda padx
    adc padvx+1
    sta padx
    cmp #PAD_MIN
    bcs @okmin
    lda #PAD_MIN
    sta padx
    lda #0
    sta padvx
    sta padvx+1
    sta padxf
@okmin:
    lda padx
    cmp #PAD_MAX
    bcc @done
    lda #PAD_MAX
    sta padx
    lda #0
    sta padvx
    sta padvx+1
    sta padxf
@done:
    rts

; ------------------------------------------------------------------------------
; spawn_particle: A = life; spx/spy/spvx/spvy/spcol set by caller
spawn_particle:
    ldx pnext
    sta PLIFE,x
    lda spx
    sta PPX,x
    lda spy
    sta PPY,x
    lda spvx
    sta PVX,x
    lda spvy
    sta PVY,x
    lda spcol
    sta PCOL,x
    lda spkind
    sta PKIND,x
    inx
    cpx #16
    bne @w
    ldx #0
@w: stx pnext
    rts

frame_end:
    ; ambient dust drifts up slowly, respawning at the bottom (LFSR x)
    lda blink
    and #3
    bne @dustdone
    ldx #0
@dustup:
    dec DUSTY,x
    lda DUSTY,x
    cmp #18
    bcs @dnext
    lda #110
    sta DUSTY,x
    lda SPR_RND
    and #63
    clc
    adc #20
    sta DUSTX,x
@dnext:
    inx
    cpx #8
    bne @dustup
@dustdone:
    ; powerup chests shimmer: rewrite their tile attribute every 8 frames
    lda blink
    and #7
    bne @noblink
    ldx #0                 ; brick row
@brow:
    lda rowmap2_lo,x
    sta ptr2
    lda rowmap2_hi,x
    clc
    adc #2                 ; attribute page
    sta ptr2+1
    lda #0
    sta colv
@bcol:
    txa
    pha
    lda times11,x
    clc
    adc colv
    tay
    lda shadow,y
    cmp #5
    bne @bnext
    lda colv
    clc
    adc #2
    tay
    lda blink
    and #8
    beq @balt
    lda #$2C               ; alternate chest palette
    bne @bset
@balt:
    lda #$0C
@bset:
    sta (ptr2),y
@bnext:
    pla
    tax
    inc colv
    lda colv
    cmp #11
    bne @bcol
    inx
    cpx #10
    bne @brow
@noblink:
    ; level-clear screen flash via the screen palette
    lda flasht
    beq @noflash
    dec flasht
    lda #7
    bne @setbg
@noflash:
    lda #1
@setbg:
    sta SPR_SPAL+0
    ; screen shake: camera moves the tile layer, sprites get the inverse
    lda shaket
    beq @noshake
    dec shaket
    lda shaket
    clc
    adc blink              ; vary the wobble direction
    and #7
    tax
    lda shake_tbl,x
    sta SPR_CAMX
    eor #$FF
    clc
    adc #1
    sta shx
    jmp @shdone
@noshake:
    lda #0
    sta SPR_CAMX
    sta shx
@shdone:
    ; stream sprites: dust (behind tiles) + ball + paddle + particles
    lda #0
    sta SPR_INDEX
    ldx #0
@dstream:
    lda DUSTX,x
    clc
    adc shx
    sta SPR_X
    lda DUSTY,x
    sta SPR_Y
    lda #44
    sta SPR_BASE
    lda #$40               ; dark grey dot, under the bricks
    sta SPR_FLAGS
    inx
    cpx #8
    bne @dstream
    lda ballx+1
    clc
    adc shx
    sta SPR_X
    lda bally+1
    sta SPR_Y
    lda #0
    sta SPR_BASE
    lda #$0C               ; 4bpp, pal 0
    sta SPR_FLAGS
    lda padx
    clc
    adc shx
    sta SPR_X
    lda #PAD_Y
    sta SPR_Y
    lda #4
    sta SPR_BASE
    lda #$0C
    sta SPR_FLAGS
    lda padx
    clc
    adc #8
    adc shx
    sta SPR_X
    lda #PAD_Y
    sta SPR_Y
    lda #8
    sta SPR_BASE
    lda #$0C
    sta SPR_FLAGS
    lda padx
    clc
    adc #16
    adc shx
    sta SPR_X
    lda #PAD_Y
    sta SPR_Y
    lda #12
    sta SPR_BASE
    lda #$0C
    sta SPR_FLAGS
    ldx #0
@ploop:
    lda PLIFE,x
    bne @palive
    jmp @pdead
@palive:
    dec PLIFE,x
    ; sparks and shards fall: gentle gravity every 4th frame
    lda PKIND,x
    cmp #1
    beq @nograv
    lda blink
    and #3
    bne @nograv
    lda PVY,x
    bmi @grav
    cmp #2
    bcs @nograv
@grav:
    inc PVY,x
@nograv:
    lda PPX,x
    clc
    adc PVX,x
    sta PPX,x
    lda PPY,x
    clc
    adc PVY,x
    sta PPY,x
    clc
    adc shx                ; reuse shx on y for a touch of vertical judder
    sta SPR_Y
    lda PPX,x
    clc
    adc shx
    sta SPR_X
    lda PKIND,x
    beq @bspark
    cmp #2
    bne @ptrail
    ; shard: alternate two silhouettes + xflip as it tumbles
    lda PLIFE,x
    lsr
    lsr
    and #1
    clc
    adc #48
    sta SPR_BASE
    lda PLIFE,x
    and #8
    lsr
    lsr
    lsr
    ora PCOL,x
    sta SPR_FLAGS
    jmp @pnextp
@ptrail:
    ; trail: shrinking circle, white -> yellow -> orange with age
    lda PLIFE,x
    cmp #8
    bcc @t2
    lda #45
    sta SPR_BASE
    lda #$60
    sta SPR_FLAGS
    jmp @pnextp
@t2:
    cmp #4
    bcc @t1
    lda #46
    sta SPR_BASE
    lda #$90
    sta SPR_FLAGS
    jmp @pnextp
@t1:
    lda #47
    sta SPR_BASE
    lda #$80
    sta SPR_FLAGS
    jmp @pnextp
@bspark:
    lda #44
    sta SPR_BASE
    lda PCOL,x
    sta SPR_FLAGS
    jmp @pnextp
@pdead:
    lda #124
    sta SPR_Y
    lda #0
    sta SPR_X
    lda #44
    sta SPR_BASE
    lda #0
    sta SPR_FLAGS
@pnextp:
    inx
    cpx #16
    beq @pfin
    jmp @ploop
@pfin:
    lda #28
    sta SPR_COUNT
    jmp main_loop

; ------------------------------------------------------------------------------
new_game:
    ldx #15
    lda #0
@cp: sta PLIFE,x
    dex
    bpl @cp
    sta shaket
    sta pnext
    sta padvx
    sta padvx+1
    sta padxf
    sta chaint
    sta flasht
    lda #1
    sta chain
    lda #0
    sta score0
    sta score1
    sta score2
    sta level
    sta servedx
    lda #3
    sta lives
    lda #52
    sta padx
    jsr build_level
    jsr draw_hud
    lda #ST_SERVE
    sta state
    rts

; ------------------------------------------------------------------------------
; build_level: unpack level_data[level] into the shadow map and the tilemap
build_level:
    ldy #109
    lda #0
@cs: sta shadow,y
    dey
    bpl @cs
    ; clear brick region rows 2-11, cols 2-12
    ldx #0
@clrrow:
    lda rowmap2_lo,x
    sta ptr2
    lda rowmap2_hi,x
    sta ptr2+1
    lda #0
    ldy #12
@cc: sta (ptr2),y
    dey
    cpy #1
    bne @cc
    lda ptr2+1
    clc
    adc #2
    sta ptr2+1
    lda #0
    ldy #12
@ch: sta (ptr2),y
    dey
    cpy #1
    bne @ch
    inx
    cpx #10
    bne @clrrow

    lda #0
    sta bricksn
    ldx level
    lda level_ptr_lo,x
    sta ptr
    lda level_ptr_hi,x
    sta ptr+1
    ldy #0
    lda (ptr),y            ; nrows
    sta rowv
    inc ptr
    bne @p0
    inc ptr+1
@p0:
    lda #0
    sta hitr
@rowloop:
    lda hitr
    cmp rowv
    bcs @done
    lda #0
    sta hitc
@colloop:
    ldy hitc
    lda (ptr),y            ; type code
    beq @next
    pha
    ldx hitr
    lda times11,x
    clc
    adc hitc
    tay
    pla
    sta shadow,y
    cmp #4                 ; 'i' is not destructible
    beq @place
    inc bricksn
@place:
    tax
    ldy hitr
    lda rowmap2_lo,y
    sta ptr2
    lda rowmap2_hi,y
    sta ptr2+1
    lda hitc
    clc
    adc #2
    tay
    lda type_tile,x
    sta (ptr2),y
    lda ptr2+1
    clc
    adc #2
    sta ptr2+1
    lda type_hi,x
    sta (ptr2),y
@next:
    inc hitc
    lda hitc
    cmp #11
    bne @colloop
    lda ptr
    clc
    adc #11
    sta ptr
    bcc @p1
    inc ptr+1
@p1:
    inc hitr
    jmp @rowloop
@done:
    rts

; ------------------------------------------------------------------------------
; draw_hud: score (6 digits), lives, level as font tiles
draw_hud:
    lda score2
    jsr bcd_two
    sta MAP_LO+64+14
    stx MAP_LO+64+15
    lda score1
    jsr bcd_two
    sta MAP_LO+64+16
    stx MAP_LO+64+17
    lda score0
    jsr bcd_two
    sta MAP_LO+64+18
    stx MAP_LO+64+19
    ldx #0
@attr:
    lda #$60
    sta MAP_HI+64+14,x
    inx
    cpx #6
    bne @attr
    lda lives
    and #$0F
    ora #$B0               ; font tile for '0' + digit
    sta MAP_LO+160+14
    lda #$60
    sta MAP_HI+160+14
    ldx level
    lda lvl_tens,x
    sta MAP_LO+256+14
    lda lvl_ones,x
    sta MAP_LO+256+15
    lda #$60
    sta MAP_HI+256+14
    sta MAP_HI+256+15
    ; chain multiplier "nX" at row 10
    lda chain
    ora #$B0
    sta MAP_LO+320+14
    lda #$D8               ; 'X' glyph tile
    sta MAP_LO+320+15
    lda #$60
    sta MAP_HI+320+14
    sta MAP_HI+320+15
    rts
bcd_two:                   ; A = BCD byte -> A = tens font tile, X = ones
    pha
    and #$0F
    ora #$B0
    tax
    pla
    lsr
    lsr
    lsr
    lsr
    ora #$B0
    rts

; ------------------------------------------------------------------------------
; Overlay messages (4x6 font, two glyphs per byte, byte-aligned)
msg_press:
    lda #<(OVL+70*20+8)
    sta ptr
    lda #>(OVL+70*20+8)
    sta ptr+1
    ldx #<msg_press_t
    ldy #>msg_press_t
    lda #4
    jmp ovl_print
msg_over:
    lda #<(OVL+70*20+7)
    sta ptr
    lda #>(OVL+70*20+7)
    sta ptr+1
    ldx #<msg_over_t
    ldy #>msg_over_t
    lda #5
; ovl_print: ptr = overlay dest, X/Y = glyph-offset table, A = pair count
ovl_print:
    sta tmp3
    stx tmp
    sty tmp2
    lda #0
    sta rowv
@row:
    lda #0
    sta colv
@pair:
    lda colv
    asl
    tay
    iny
    lda (tmp),y            ; odd glyph offset -> high nibble
    clc
    adc rowv
    tay
    lda font46,y
    asl
    asl
    asl
    asl
    sta hitr
    lda colv
    asl
    tay
    lda (tmp),y            ; even glyph offset -> low nibble
    clc
    adc rowv
    tay
    lda font46,y
    ora hitr
    ldy colv
    sta (ptr),y
    inc colv
    lda colv
    cmp tmp3
    bne @pair
    lda ptr
    clc
    adc #20
    sta ptr
    bcc @nc
    inc ptr+1
@nc:
    inc rowv
    lda rowv
    cmp #6
    bne @row
    rts

msg_clear:
    lda #<(OVL+68*20+5)
    sta ptr
    lda #>(OVL+68*20+5)
    sta ptr+1
    ldx #10
@r: lda #0
    ldy #10
@c: sta (ptr),y
    dey
    bpl @c
    lda ptr
    clc
    adc #20
    sta ptr
    bcc @n
    inc ptr+1
@n: dex
    bne @r
    rts

; ------------------------------------------------------------------------------
; Data
; ------------------------------------------------------------------------------
; brick types:   0    b    h    s    i    p   hdmg
type_tile:
    .byte  0,  16,  20,  28,  32,  36,  24
type_hi:
    .byte  0, $0C, $0C, $0C, $0C, $0C, $0C
type_pts:
    .byte  0, $10, $20, $30, $00, $50, $20
type_next:
    .byte  0,   0,   6,   0,   4,   0,   0

; paddle-english zones: (vx, vy) in signed 8.8
zone_vx_lo: .byte $C0, $40, $40, $C0, $40
zone_vx_hi: .byte $FE, $FF, $00, $00, $01
zone_vy_lo: .byte $40, $C0, $80, $C0, $40
zone_vy_hi: .byte $FF, $FE, $FE, $FE, $FF

; sfx_play: X = sound id, Y = channel*4. Four writes and the hardware
; sequencer does the rest.
sfx_play:
    lda sfx_start,x
    sta PSG_CH,y
    lda sfx_len,x
    sta PSG_CH+1,y
    lda sfx_spd,x
    sta PSG_CH+2,y
    lda #1
    sta PSG_CH+3,y
    rts

; set_vec: Y = angle index 0-12; applies the current wind-up speed level
set_vec:
    tya
    ldx ballspd
    clc
    adc times13,x
    tay
    lda ang_vx_lo,y
    sta bvx
    lda ang_vx_hi,y
    sta bvx+1
    lda ang_vy_lo,y
    sta bvy
    lda ang_vy_hi,y
    sta bvy+1
    rts
times13:  .byte 0, 13, 26
zone_ang: .byte 1, 4, 6, 8, 11

; spark color by brick type (sprite flags: pal<<4, 1bpp)
type_spark:
    .byte $60, $D0, $60, $80, $60, $B0, $60
burst_vx: .byte $01, $FF, $02, $FE
burst_vy: .byte $FF, $FF, $01, $01
shake_tbl:
    .byte 0, 1, $FF, 2, $FE, 1, $FF, 2

times11:
    .byte 0, 11, 22, 33, 44, 55, 66, 77, 88, 99

rowmap_lo:
    .byte $00, $20, $40, $60, $80, $A0, $C0, $E0, $00, $20, $40, $60, $80, $A0, $C0, $E0
rowmap_hi:
    .byte $F0, $F0, $F0, $F0, $F0, $F0, $F0, $F0, $F1, $F1, $F1, $F1, $F1, $F1, $F1, $F1
rowmap2_lo:
    .byte $40, $60, $80, $A0, $C0, $E0, $00, $20, $40, $60
rowmap2_hi:
    .byte $F0, $F0, $F0, $F0, $F0, $F0, $F1, $F1, $F1, $F1

lvl_tens:
    .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B1,$B1,$B1,$B1,$B1,$B1
lvl_ones:
    .byte $B1,$B2,$B3,$B4,$B5,$B6,$B7,$B8,$B9,$B0,$B1,$B2,$B3,$B4,$B5

txt_score: .byte "SCORE"
txt_balls: .byte "BALLS"
txt_level: .byte "LEVEL"

font46:
    .byte $02,$05,$07,$05,$05,$00   ; 0  A
    .byte $07,$01,$03,$01,$07,$00   ; 6  E
    .byte $07,$01,$05,$05,$07,$00   ; 12 G
    .byte $05,$07,$07,$05,$05,$00   ; 18 M
    .byte $07,$05,$05,$05,$07,$00   ; 24 O
    .byte $03,$05,$03,$01,$01,$00   ; 30 P
    .byte $03,$05,$03,$05,$05,$00   ; 36 R
    .byte $07,$01,$07,$04,$07,$00   ; 42 S
    .byte $05,$05,$05,$05,$02,$00   ; 48 V
    .byte $05,$05,$02,$05,$05,$00   ; 54 X
    .byte $00,$00,$00,$00,$00,$00   ; 60 space

msg_press_t:
    .byte 30, 36, 6, 42, 42, 60, 54, 60          ; PRESS X
msg_over_t:
    .byte 12, 0, 18, 6, 60, 24, 48, 6, 36, 60    ; GAME OVER

.include "breakout_data.asm"
.include "breakout_tables.asm"
.include "breakout_sfx.asm"

; ------------------------------------------------------------------------------
nmi_handler:
    rti
irq_handler:
    rti

.segment "VECTORS"
    .word $0000
    .word $0300
    .word $0000
