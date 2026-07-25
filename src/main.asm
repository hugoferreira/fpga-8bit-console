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
    .define PSG_STATUS         $4103  ; read: bits 0-3 channel playing, bit7 music
    .define PSG_CH             $4110  ; +ch: write cart SFX # to play, $80 stops,
                                      ; $81 releases from looping
    .define PSG_CHROW          $4114  ; +ch: write start row; read {playing, sfx #}
    .define PSG_CHLEN          $4118  ; +ch: write rows to play (0 = all)
    .define PSG_MUSIC          $4120  ; write pattern # to start music, $80 stops
    .define PSG_MUSMASK        $4121  ; channels reserved for music
    .define PSG_FADE           $4122  ; music fade length, 16 ms units
    .define MUS_FADE_2S        125    ; the cart's music(-1, 2000)

    ; sound ids (the cart's own SFX slot numbers; brick = 2 + chain)
    .define SND_WALL           0
    .define SND_PADDLE         1
    .define SND_LOSE           2
    .define SND_SERVE          12
    .define SND_SHATTER        13
    .define SND_CHAIN          44

    ; music (the cart's own pattern numbers)
    .define MUS_TITLE          1
    .define MUS_CLEAR          6
    .define MUS_OVER           7
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
    .define ST_WIN             3

    .define MUS_WIN            8
    .define SND_INVINC         10
    .define SND_PILL           11
    .define SND_EXPLODE        14
    .define SND_SD             29

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

    ; power-ups / pills (two falling pills max)
    .define pill_t  $38    ; and $39: type 1-7, 0 = inactive
    .define pill_x  $3A    ; and $3B
    .define pill_y  $3C    ; and $3D
    .define pill_yf $3E    ; and $3F: y fraction (falls 0.7/frame)
    .define t_slow  $40    ; 16-bit frame timers
    .define t_expand $42
    .define t_reduce $44
    .define t_megaw $46    ; megaball warmup (armed until first brick)
    .define t_mega  $48    ; megaball active (8-bit, 120)
    .define stickyf $49    ; sticky-paddle armed
    .define stuckf  $4A    ; ball riding the paddle mid-play
    .define stuckoff $4B   ; ballx - padx while stuck
    .define padw    $4C    ; 0 = 24px, 1 = 32px (expand), 2 = 16px (reduce)
    .define b2on    $4D    ; second ball (multiball) active
    .define b2x     $4E    ; and $4F: 8.8 frac,int
    .define b2y     $50    ; and $51
    .define b2vx    $52    ; and $53
    .define b2vy    $54    ; and $55
    .define sd_on   $56    ; sudden death armed
    .define sd_t    $57    ; and $58: 450-frame fuse
    .define sd_blink $59   ; frames to next beep/flash
    .define sd_idx  $5A    ; shadow index of the doomed brick
    .define curball $5B    ; 0 = primary, 1 = ball2 (inside ball_step)
    .define msgt    $5C    ; pill sash message timer
    .define ncmb    $5D    ; brick_hit: 1 = no score/chain (explosions)
    .define hittype $5E    ; brick_hit: type code seen at entry
    .define expn    $5F    ; explosion queue depth
    .define nextch  $60    ; sfx_play round-robin steal cursor

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
    .define EXPQ    $2180  ; explosion queue: shadow indices (8)

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

    ; Upload the cart's audio RAM image (music + SFX, 4608 bytes) to the
    ; PSG at PICO-8 address $3100 - verbatim cart bytes, no conversion
    lda #$00
    sta PSG_ADDR_LO
    lda #$31
    sta PSG_ADDR_HI
    lda #<audio_data
    sta ptr
    lda #>audio_data
    sta ptr+1
    ldx #18                ; 18 pages = 4608 bytes
    ldy #0
@sfxup:
    lda (ptr),y
    sta PSG_DATA
    iny
    bne @sfxup
    inc ptr+1
    dex
    bne @sfxup

    ; title music while waiting to serve
    lda #MUS_TITLE
    sta PSG_MUSIC

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
    lda #MUS_FADE_2S       ; title music fades out over 2 s, as music(-1,2000)
    sta PSG_FADE
    lda #$80
    sta PSG_MUSIC
    ldx #SND_SERVE
    ldy #2
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
    lda #MUS_TITLE         ; back to the title loop while serving
    sta PSG_MUSIC
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

    ; power-up timers, falling pills, sudden-death fuse, explosions
    jsr powerup_timers
    jsr update_pills
    jsr update_sd
    jsr update_explosions

    ; pill sash message expiry
    lda msgt
    beq @nomsg
    dec msgt
    bne @nomsg
    jsr msg_clear
@nomsg:

    ; a stuck ball rides the paddle; X releases it
    lda stuckf
    beq @notstuck
    lda padx
    clc
    adc stuckoff
    sta ballx+1
    lda #PAD_Y-5
    sta bally+1
    lda btn
    and #BTN_X
    beq @after1
    lda btnprev
    and #BTN_X
    bne @after1
    lda #0
    sta stuckf
    jsr pad_zone
    bcc @after1
    jsr set_vec
    lda bvy+1
    bmi @after1
    jsr negy
    jmp @after1
@notstuck:
    lda #0
    sta curball
    jsr ball_step
    bcc @after1
    ; primary ball lost: promote ball2 if one is out, else lose a life
    lda b2on
    beq @lifelost
    ldx #7
@promote:
    lda b2x,x
    sta ballx,x
    dex
    bpl @promote
    lda #0
    sta b2on
    beq @after1
@lifelost:
    ldx #SND_LOSE
    ldy #2
    jsr sfx_play
    lda #8
    sta shaket
    dec lives
    jsr draw_hud
    jsr serve_reset
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
    lda #MUS_OVER          ; the cart's game-over jingle
    sta PSG_MUSIC
    jsr msg_over
    lda #124
    sta bally+1            ; park the dead ball off-screen
    jmp frame_end
@after1:

    ; second ball (multiball)
    lda b2on
    beq @noball2
    jsr swap_ball2
    lda #1
    sta curball
    jsr ball_step
    jsr swap_ball2
    bcc @noball2
    lda #0
    sta b2on
    ldx #SND_LOSE
    ldy #2
    jsr sfx_play
@noball2:

    ; level cleared?
    lda bricksn
    bne @go
    ldx level
    inx
    cpx #15
    bcc @lv
    ; all 15 levels cleared: winner screen (X restarts via do_over)
    lda #ST_WIN
    sta state
    lda #MUS_WIN
    sta PSG_MUSIC
    jsr serve_reset
    jsr msg_win
    lda #124
    sta bally+1
    jmp frame_end
@lv:
    stx level
    jsr build_level
    jsr draw_hud
    jsr serve_reset
    lda #MUS_CLEAR         ; the cart's level-clear jingle
    sta PSG_MUSIC
    lda #6
    sta flasht
    lda #ST_SERVE
    sta state
@go:
    jmp frame_end

; ------------------------------------------------------------------------------
; ball_step: move/bounce/collide the ball in ballx..bvy (curball says which
; ball that is). Returns C=1 if the ball fell off the bottom.
ball_step:
    ; position += velocity (halved while a slowdown pill is active)
    lda t_slow
    ora t_slow+1
    beq @full
    lda bvx+1              ; arithmetic halves into tmp2:tmp
    cmp #$80
    ror
    sta tmp2
    lda bvx
    ror
    sta tmp
    lda ballx
    clc
    adc tmp
    sta ballx
    lda ballx+1
    adc tmp2
    sta ballx+1
    lda bvy+1
    cmp #$80
    ror
    sta tmp2
    lda bvy
    ror
    sta tmp
    lda bally
    clc
    adc tmp
    sta bally
    lda bally+1
    adc tmp2
    sta bally+1
    jmp @moved
@full:
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
@moved:

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
    sec
    rts
@alive:

    ; paddle bounce (moving down, box bottom in paddle band, x overlap)
    lda bvy+1
    bmi @nopad
    lda bally+1
    cmp #PAD_Y-4
    bcc @nopad
    cmp #PAD_Y+2
    bcs @nopad
    jsr pad_zone
    bcc @nopad
    ; sticky paddle catches the primary ball instead of bouncing
    lda stickyf
    beq @bounce
    lda stuckf
    bne @bounce
    lda curball
    bne @bounce
    lda #1
    sta stuckf
    lda ballx+1
    sec
    sbc padx
    sta stuckoff
    lda #0
    sta bvx
    sta bvx+1
    sta bvy
    sta bvy+1
    lda #1
    sta chain
    ldx #SND_PADDLE
    ldy #1
    jsr sfx_play
    jmp @nopad
@bounce:
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
    ldy #1
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
    jsr mega_pass          ; C=1: megaball smashes through, no bounce
    bcs @noh
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
    jsr mega_pass
    bcs @nov
    jsr negy
@nov:
    clc
    rts

; pad_zone: Y = bounce angle index for the ball's paddle position
; (width-aware). C=1 when the ball overlaps the paddle, C=0 otherwise.
pad_zone:
    ldx padw
    lda ballx+1
    sec
    sbc padx
    sec
    sbc pleft_adj,x        ; overlap vs the true left edge
    clc
    adc #6
    cmp ovr_max,x
    bcs @miss
    ldy #0
    cmp zthr1,x
    bcc @zok
    iny
    cmp zthr2,x
    bcc @zok
    iny
    cmp zthr3,x
    bcc @zok
    iny
    cmp zthr4,x
    bcc @zok
    iny
@zok:
    lda zone_ang,y
    tay
    sec
    rts
@miss:
    clc
    rts

; mega_pass: C=1 when an active/armed megaball should pass through the
; brick just hit (never through invincible bricks)
mega_pass:
    lda hittype
    cmp #4
    beq @solid
    lda t_mega
    bne @pass
    lda t_megaw
    ora t_megaw+1
    bne @pass
@solid:
    clc
    rts
@pass:
    sec
    rts

; swap_ball2: exchange the working ball state with ball2's
swap_ball2:
    ldx #7
@sw:
    lda ballx,x
    pha
    lda b2x,x
    sta ballx,x
    pla
    sta b2x,x
    dex
    bpl @sw
    rts

; powerup_timers: tick the four 16-bit timers and t_mega; the paddle
; width follows whichever of expand/reduce is running
powerup_timers:
    lda t_mega
    beq @m0
    dec t_mega
@m0:
    ldx #0                 ; t_slow/t_expand/t_reduce/t_megaw are contiguous
@tl:
    lda t_slow,x
    ora t_slow+1,x
    beq @tn
    lda t_slow,x
    bne @dl
    dec t_slow+1,x
@dl:
    dec t_slow,x
@tn:
    inx
    inx
    cpx #8
    bne @tl
    lda t_expand
    ora t_expand+1
    beq @notw
    lda #1
    sta padw
    rts
@notw:
    lda t_reduce
    ora t_reduce+1
    beq @notn
    lda #2
    sta padw
    rts
@notn:
    lda #0
    sta padw
    rts

; spawn_pill: drop a random pill (type 1-7) from the brick at hitr/hitc
spawn_pill:
    ldx #0
    lda pill_t
    beq @slot
    ldx #1
    lda pill_t+1
    bne @full
@slot:
    lda SPR_RND
    and #7
    bne @t
    lda #7
@t:
    sta pill_t,x
    lda hitc
    asl
    asl
    asl
    clc
    adc #15                ; brick centre - half a pill
    sta pill_x,x
    lda hitr
    asl
    asl
    asl
    clc
    adc #15
    sta pill_y,x
    lda #0
    sta pill_yf,x
@full:
    rts

; update_pills: pills fall 0.7px/frame; the paddle catches them
update_pills:
    ldx #1
@pl:
    lda pill_t,x
    bne @act
    jmp @pnext
@act:
    lda pill_yf,x
    clc
    adc #$B3
    sta pill_yf,x
    lda pill_y,x
    adc #0
    sta pill_y,x
    cmp #118
    bcc @on
    lda #0
    sta pill_t,x
    jmp @pnext
@on:
    cmp #PAD_Y-5
    bcc @pnext
    cmp #PAD_Y+6
    bcs @pnext
    ldy padw
    lda padx
    clc
    adc pleft_adj,y
    sta tmp                ; paddle left edge
    clc
    adc padwid,y
    sta tmp2               ; paddle right edge
    lda pill_x,x
    clc
    adc #8
    cmp tmp
    bcc @pnext
    lda pill_x,x
    cmp tmp2
    bcs @pnext
    ; caught
    lda pill_t,x
    sta mulk
    lda #0
    sta pill_t,x
    txa
    pha
    ldx #SND_PILL
    ldy #2
    jsr sfx_play
    lda mulk
    jsr apply_pill
    pla
    tax
@pnext:
    dex
    bpl @pl
    rts

; apply_pill: A = pill type 1-7
apply_pill:
    cmp #1
    bne @n1
    lda #$90               ; slowdown: 400 frames at half ball speed
    sta t_slow
    lda #$01
    sta t_slow+1
    lda #0
    jmp msg_show
@n1:
    cmp #2
    bne @n2
    lda lives              ; extra life (display is one digit)
    cmp #9
    bcs @lmax
    inc lives
    jsr draw_hud
@lmax:
    lda #1
    jmp msg_show
@n2:
    cmp #3
    bne @n3
    lda #1                 ; sticky paddle until the next serve
    sta stickyf
    lda #2
    jmp msg_show
@n3:
    cmp #4
    bne @n4
    lda #$58               ; expand: 600 frames of 32px paddle
    sta t_expand
    lda #$02
    sta t_expand+1
    lda #0
    sta t_reduce
    sta t_reduce+1
    lda #1
    sta padw
    lda #3
    jmp msg_show
@n4:
    cmp #5
    bne @n5
    lda #$58               ; reduce: 600 frames of 16px paddle
    sta t_reduce
    lda #$02
    sta t_reduce+1
    lda #0
    sta t_expand
    sta t_expand+1
    lda #2
    sta padw
    lda #4
    jmp msg_show
@n5:
    cmp #6
    bne @n6
    lda #$58               ; megaball: armed until the next brick contact
    sta t_megaw
    lda #$02
    sta t_megaw+1
    lda #0
    sta t_mega
    lda #5
    jmp msg_show
@n6:
    ; multiball: clone the ball, diverging horizontally
    lda b2on
    bne @have
    ldx #7
@cp:
    lda ballx,x
    sta b2x,x
    dex
    bpl @cp
    lda #1
    sta b2on
    ; a clone of a riding ball launches upward instead
    lda stuckf
    beq @negvx
    lda #0
    sta b2vx
    sta b2vy
    lda #1
    sta b2vx+1
    lda #$FF
    sta b2vy+1
    jmp @have
@negvx:
    sec
    lda #0
    sbc b2vx
    sta b2vx
    lda #0
    sbc b2vx+1
    sta b2vx+1
@have:
    lda #6
    jmp msg_show

; check_sd: arm sudden death when 3 or fewer destructible bricks remain
; (called from brick_hit - preserves hitr for the caller)
check_sd:
    lda sd_on
    bne @done
    lda bricksn
    beq @done
    cmp #4
    bcs @done
    ldy #0
@scan:
    lda shadow,y
    beq @next
    cmp #4
    beq @next
    sty sd_idx
    lda #1
    sta sd_on
    lda #$C2               ; 450-frame fuse
    sta sd_t
    lda #$01
    sta sd_t+1
    lda #8
    sta sd_blink
    ldx #SND_SD
    ldy #3
    jsr sfx_play
    lda hitr
    pha
    lda #7
    jsr msg_show
    pla
    sta hitr
@done:
    rts
@next:
    iny
    cpy #110
    bne @scan
    rts

; sd_attr: write A to the doomed brick's tile attribute (flash/restore)
sd_attr:
    pha
    lda sd_idx
    ldx #0
@dv:
    cmp #11
    bcc @f
    sbc #11
    inx
    bne @dv
@f:
    clc
    adc #2
    tay
    lda rowmap2_lo,x
    sta ptr2
    lda rowmap2_hi,x
    clc
    adc #2
    sta ptr2+1
    pla
    sta (ptr2),y
    rts
sd_attr_norm:
    lda #$0C
    jmp sd_attr

; update_sd: tick the fuse; flash and beep faster as it runs out; on
; expiry the brick detonates like an explosive brick
update_sd:
    lda sd_on
    beq @done
    lda sd_t
    bne @d1
    dec sd_t+1
@d1:
    dec sd_t
    lda sd_t
    ora sd_t+1
    beq @boom
    lda sd_blink
    cmp #4
    bcs @dark
    lda #$2C
    jsr sd_attr
    jmp @tick
@dark:
    lda #$0C
    jsr sd_attr
@tick:
    dec sd_blink
    bne @done
    ldx #SND_SD
    ldy #3
    jsr sfx_play
    lda sd_t+1             ; reload: fuse/8 + 2 frames (accelerates)
    sta tmp
    lda sd_t
    lsr tmp
    ror
    lsr tmp
    ror
    lsr tmp
    ror
    clc
    adc #2
    sta sd_blink
@done:
    rts
@boom:
    lda #0
    sta sd_on
    lda sd_idx
    ldx #0
@dv2:
    cmp #11
    bcc @f2
    sbc #11
    inx
    bne @dv2
@f2:
    sta hitc
    stx hitr
    ldy sd_idx
    lda #3                 ; detonate as an explosive brick
    sta shadow,y
    lda #1
    sta ncmb
    jsr brick_hit
    lda #0
    sta ncmb
    rts

; update_explosions: one queued detonation per frame hits all 8 neighbours
update_explosions:
    lda expn
    beq @done
    dec expn
    ldx expn
    lda EXPQ,x
    sta tmp3
    ldx #SND_EXPLODE
    ldy #2
    jsr sfx_play
    lda #6
    sta shaket
    lda tmp3
    ldx #0
@dv:
    cmp #11
    bcc @f
    sbc #11
    inx
    bne @dv
@f:
    sta colv
    stx rowv
    ldy #0
@nb:
    lda rowv
    clc
    adc nb_dr,y
    cmp #10
    bcs @skip
    sta hitr
    lda colv
    clc
    adc nb_dc,y
    cmp #11
    bcs @skip
    sta hitc
    ldx hitr
    lda times11,x
    clc
    adc hitc
    tax
    lda shadow,x
    beq @skip
    tya
    pha
    lda rowv
    pha
    lda colv
    pha
    lda #1
    sta ncmb
    jsr brick_hit
    lda #0
    sta ncmb
    pla
    sta colv
    pla
    sta rowv
    pla
    tay
@skip:
    iny
    cpy #8
    bne @nb
@done:
    rts

; serve_reset: clear everything a new serve resets (pills, timers,
; sticky, multiball, sudden death, explosions, sash)
serve_reset:
    lda sd_on
    beq @nosd
    jsr sd_attr_norm
@nosd:
    lda #0
    sta pill_t
    sta pill_t+1
    sta t_slow
    sta t_slow+1
    sta t_expand
    sta t_expand+1
    sta t_reduce
    sta t_reduce+1
    sta t_megaw
    sta t_megaw+1
    sta t_mega
    sta stickyf
    sta stuckf
    sta padw
    sta b2on
    sta sd_on
    sta expn
    sta msgt
    rts

; msg_show: A = message index; print it centred in the sash row
msg_show:
    tax
    lda msg_pairs,x
    sta tmp3
    lda #12
    sec
    sbc tmp3
    clc
    adc #<(OVL+70*20)
    sta ptr
    lda #>(OVL+70*20)
    adc #0
    sta ptr+1
    lda msg_txt_hi,x
    tay
    lda msg_txt_lo,x
    tax
    lda tmp3
    jsr ovl_print
    lda #120
    sta msgt
    rts

msg_win:
    lda #8
    jmp msg_show


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
    stx hittype
    ; smashing the sudden-death brick disarms it with a bonus
    lda sd_on
    beq @nosdhit
    lda sidx
    cmp sd_idx
    bne @nosdhit
    lda #0
    sta sd_on
    jsr sd_attr_norm
    sed
    lda score0
    clc
    adc #$10
    sta score0
    lda score1
    adc #0
    sta score1
    lda score2
    adc #0
    sta score2
    cld
    ldx #1                 ; force-destroy as a plain brick
    stx hittype
@nosdhit:
    ; megaball: first brick contact converts the warmup to active
    cpx #4
    beq @nomega
    lda t_megaw
    ora t_megaw+1
    beq @mchk
    lda #0
    sta t_megaw
    sta t_megaw+1
    lda #120
    sta t_mega
@mchk:
    lda t_mega             ; active megaball smashes hard bricks outright
    beq @nomega
    cpx #2
    beq @msmash
    cpx #6
    bne @nomega
@msmash:
    ldx #1
@nomega:
    ; explosion side-hits score no points and do not boost the chain
    lda ncmb
    bne @nopts
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
    ; refresh the chain window; the chain boost and its rising-pitch smash
    ; and fanfare happen at the destroy site below, matching the original
    ; (sfx(2+chain) fires with the pre-boost chain, then boostchain)
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
    ; a destroyed powerup brick drops a pill
    lda hittype
    cmp #5
    bne @nopill
    jsr spawn_pill
@nopill:
    ; a destroyed explosive brick detonates next frame
    lda hittype
    cmp #3
    bne @noexp
    ldy expn
    cpy #8
    bcs @noexp
    lda sidx
    sta EXPQ,y
    inc expn
@noexp:
    jsr check_sd
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
    ; sound (matching the original): a destroyed brick plays the rising
    ; smash sfx(2+chain) AND the shatter sfx(13), layered on auto-picked
    ; channels; a surviving brick (invincible or a hardened first hit) just
    ; clinks sfx(10). Combo destroys then boost the chain, with the
    ; max-chain fanfare sfx(44) on the 6->7 step.
    txa
    pha                    ; save the NEW type across the sound calls
    bne @clink             ; new type != 0 -> brick survived
    lda chain              ; smash pitch rises with the chain (sfx 3..9)
    clc
    adc #2
    tax
    jsr sfx_play
    ldx #SND_SHATTER       ; layered shatter (sfx 13)
    jsr sfx_play
    lda ncmb               ; explosion side-hits do not boost the chain
    bne @snddone
    lda chain
    cmp #6
    bne @chinc
    ldx #SND_CHAIN         ; max-chain fanfare on the 6->7 step (sfx 44)
    jsr sfx_play
@chinc:
    lda chain
    cmp #7
    bcs @snddone           ; already maxed, clamp
    inc chain
    jmp @snddone
@clink:
    ldx #SND_INVINC        ; invincible / hardened clink (sfx 10)
    jsr sfx_play
@snddone:
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
    ldy #1
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
    ldy padw               ; clamps follow the current paddle width
    cmp pmin_tbl,y
    bcs @okmin
    lda pmin_tbl,y
    sta padx
    lda #0
    sta padvx
    sta padvx+1
    sta padxf
@okmin:
    lda padx
    cmp pmax_tbl,y
    bcc @done
    lda pmax_tbl,y
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
    ; paddle: up to 4 segments depending on width (unused slots park)
    ldy padw
    lda padx
    clc
    adc pleft_adj,y
    sta tmp                ; true left edge
    tya
    asl
    asl
    sta tmp2               ; psegs row base = padw*4
    ldx #0
@pseg:
    txa
    clc
    adc tmp2
    tay
    lda psegs,y
    cmp #$FF
    beq @ppark
    pha
    txa
    asl
    asl
    asl                    ; segment*8
    clc
    adc tmp
    adc shx
    sta SPR_X
    lda #PAD_Y
    sta SPR_Y
    pla
    sta SPR_BASE
    lda #$0C
    sta SPR_FLAGS
    jmp @pnexts
@ppark:
    lda #0
    sta SPR_X
    lda #124
    sta SPR_Y
    lda #44
    sta SPR_BASE
    lda #0
    sta SPR_FLAGS
@pnexts:
    inx
    cpx #4
    bne @pseg
    ; second ball (multiball)
    lda b2on
    beq @b2park
    lda b2x+1
    clc
    adc shx
    sta SPR_X
    lda b2y+1
    sta SPR_Y
    lda #0
    sta SPR_BASE
    lda #$0C
    sta SPR_FLAGS
    jmp @b2done
@b2park:
    lda #0
    sta SPR_X
    lda #124
    sta SPR_Y
    lda #44
    sta SPR_BASE
    lda #0
    sta SPR_FLAGS
@b2done:
    ; falling pills: an 8px circle tinted per type
    ldx #1
@pillspr:
    lda pill_t,x
    beq @pillpark
    tay
    lda pill_x,x
    clc
    adc shx
    sta SPR_X
    lda pill_y,x
    sta SPR_Y
    lda #45
    sta SPR_BASE
    lda pill_flags-1,y
    sta SPR_FLAGS
    jmp @pillnext
@pillpark:
    lda #0
    sta SPR_X
    lda #124
    sta SPR_Y
    lda #44
    sta SPR_BASE
    lda #0
    sta SPR_FLAGS
@pillnext:
    dex
    bpl @pillspr
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
    lda #32                ; dust 8 + ball + paddle 4 + ball2 + pills 2 + 16
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
    jsr serve_reset
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

; sfx_play: X = cart SFX number. Auto-picks a channel the way PICO-8's
; sfx(n) (default channel -1) does - the lowest channel that is neither
; playing nor reserved for music, so sounds layer instead of cutting each
; other off; if all four are busy it steals round-robin. Y is ignored
; (kept for old call sites).
sfx_play:
    lda PSG_STATUS         ; bits 0-3 = channel playing flags
    ora PSG_MUSMASK        ; channels music() reserved are off limits
    ldy #0
    lsr                    ; ch0 -> carry
    bcc @go
    iny
    lsr                    ; ch1
    bcc @go
    iny
    lsr                    ; ch2
    bcc @go
    iny
    lsr                    ; ch3
    bcc @go
    lda nextch             ; all busy: round-robin steal
    clc
    adc #1
    and #3
    sta nextch
    tay
@go:
    txa
    sta PSG_CH,y
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
    .byte $03,$05,$03,$05,$03,$00   ; 66 B
    .byte $07,$01,$01,$01,$07,$00   ; 72 C
    .byte $03,$05,$05,$05,$03,$00   ; 78 D
    .byte $07,$01,$03,$01,$01,$00   ; 84 F
    .byte $05,$05,$07,$05,$05,$00   ; 90 H
    .byte $07,$02,$02,$02,$07,$00   ; 96 I
    .byte $05,$05,$03,$05,$05,$00   ; 102 K
    .byte $01,$01,$01,$01,$07,$00   ; 108 L
    .byte $03,$05,$05,$05,$05,$00   ; 114 N
    .byte $07,$02,$02,$02,$02,$00   ; 120 T
    .byte $05,$05,$05,$05,$07,$00   ; 126 U
    .byte $05,$05,$07,$07,$05,$00   ; 132 W
    .byte $05,$05,$02,$02,$02,$00   ; 138 Y

msg_press_t:
    .byte 30, 36, 6, 42, 42, 60, 54, 60          ; PRESS X
msg_over_t:
    .byte 12, 0, 18, 6, 60, 24, 48, 6, 36, 60    ; GAME OVER

; pill sash / event messages (glyph-offset pairs)
msg_slow_t:  .byte 42, 108, 24, 132, 78, 24, 132, 114              ; SLOWDOWN
msg_life_t:  .byte 108, 96, 84, 6, 60, 126, 30, 60                 ; LIFE UP
msg_stick_t: .byte 42, 120, 96, 72, 102, 138                       ; STICKY
msg_exp_t:   .byte 6, 54, 30, 0, 114, 78                           ; EXPAND
msg_red_t:   .byte 36, 6, 78, 126, 72, 6                           ; REDUCE
msg_mega_t:  .byte 18, 6, 12, 0, 66, 0, 108, 108                   ; MEGABALL
msg_multi_t: .byte 18, 126, 108, 120, 96, 66, 0, 108, 108, 60      ; MULTIBALL
msg_sd_t:    .byte 42, 126, 78, 78, 6, 114, 60, 78, 6, 0, 120, 90  ; SUDDEN DEATH
msg_win_t:   .byte 138, 24, 126, 60, 132, 96, 114, 60              ; YOU WIN
msg_txt_lo:
    .byte <msg_slow_t, <msg_life_t, <msg_stick_t, <msg_exp_t, <msg_red_t
    .byte <msg_mega_t, <msg_multi_t, <msg_sd_t, <msg_win_t
msg_txt_hi:
    .byte >msg_slow_t, >msg_life_t, >msg_stick_t, >msg_exp_t, >msg_red_t
    .byte >msg_mega_t, >msg_multi_t, >msg_sd_t, >msg_win_t
msg_pairs:
    .byte 4, 4, 3, 3, 3, 4, 5, 6, 4

; paddle-width tables (indexed by padw: 0=24px, 1=32px expand, 2=16px reduce)
pleft_adj: .byte 0, $FC, 4
padwid:    .byte 24, 32, 16
ovr_max:   .byte 30, 38, 22
zthr1:     .byte 6, 8, 4
zthr2:     .byte 12, 16, 9
zthr3:     .byte 18, 23, 13
zthr4:     .byte 24, 30, 18
pmin_tbl:  .byte 16, 20, 12
pmax_tbl:  .byte 80, 76, 84
; paddle sprite segments per width ($FF = park the slot)
psegs:
    .byte 4, 8, 12, $FF
    .byte 4, 8, 8, 12
    .byte 4, 12, $FF, $FF
; pill sprite tints (1bpp circle palette bases), types 1-7
pill_flags: .byte $80, $60, $A0, $B0, $70, $D0, $90
; explosion neighbour offsets
nb_dr: .byte $FF, $FF, $FF, 0, 0, 1, 1, 1
nb_dc: .byte $FF, 0, 1, $FF, 1, $FF, 0, 1

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
