; Console register constants (PPU/PSG/gamepad MMIO) and the game's zero-page
; variable layout. Extracted from the top of main.asm during the ca65 ->
; customasm migration; content is unchanged (`.define NAME v` -> `NAME = v`).

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
    SPR_SHADDR_LO = $4000
    SPR_SHADDR_HI = $4001
    SPR_SHDATA = $4002
    SPR_CTRL = $4005
    SPR_OVLCOL = $4006
    SPR_CAMX = $4003
    SPR_BTN = $4007
    SPR_INDEX = $4008
    SPR_X = $4009
    SPR_Y = $400A
    SPR_FLAGS = $400B
    SPR_COUNT = $400C
    SPR_FRAME = $400D
    SPR_BASE = $400E
    SPR_RND = $400F  ; hardware LFSR, read-only
    SPR_BSPLIT = $4036  ; list entries below this draw behind tiles

    ; PSG
    PSG_ADDR_LO = $4100
    PSG_ADDR_HI = $4101
    PSG_DATA = $4102
    PSG_STATUS = $4103  ; read: bits 0-3 channel playing, bit7 music
    PSG_CH = $4110  ; +ch: write cart SFX # to play, $80 stops,
                                      ; $81 releases from looping
    PSG_CHROW = $4114  ; +ch: write start row; read {playing, sfx #}
    PSG_CHLEN = $4118  ; +ch: write rows to play (0 = all)
    PSG_MUSIC = $4120  ; write pattern # to start music, $80 stops
    PSG_MUSMASK = $4121  ; channels reserved for music
    PSG_FADE = $4122  ; music fade length, 16 ms units
    MUS_FADE_2S = 125    ; the cart's music(-1, 2000)

    ; sound ids (the cart's own SFX slot numbers; brick = 2 + chain)
    SND_WALL = 0
    SND_PADDLE = 1
    SND_LOSE = 2
    SND_SERVE = 12
    SND_SHATTER = 13
    SND_CHAIN = 44

    ; music (the cart's own pattern numbers)
    MUS_TITLE = 1
    MUS_CLEAR = 6
    MUS_OVER = 7
    SPR_SPAL = $4020

    MAP_LO = $F000
    MAP_HI = $F200
    OVL = $E000

    ; Buttons
    BTN_L = $01
    BTN_R = $02
    BTN_X = $20

    ; Geometry
    ARENA_L = 16     ; interior left edge
    ARENA_R = 104    ; interior right edge (exclusive)
    ARENA_T = 16     ; interior top edge
    PAD_Y = 106    ; paddle sprite y
    PAD_MIN = 16
    PAD_MAX = 80     ; 24px paddle in the 88px interior
    BALL_DEATH = 118

    ; Game states
    ST_SERVE = 0
    ST_PLAY = 1
    ST_OVER = 2
    ST_WIN = 3

    MUS_WIN = 8
    SND_INVINC = 10
    SND_PILL = 11
    SND_EXPLODE = 14
    SND_SD = 29

    ; Zero page
    ballx = $04    ; 8.8: frac, int
    bally = $06
    bvx = $08    ; signed 8.8
    bvy = $0A
    padx = $0C
    state = $0D
    lives = $0E
    level = $0F    ; 0-based
    score0 = $10    ; BCD, low digits first
    score1 = $11
    score2 = $12
    bricksn = $13
    tmp = $14
    tmp2 = $15
    btn = $16
    btnprev = $17
    blink = $18
    ptr = $19    ; and $1A
    rowv = $1B
    colv = $1C
    hitr = $1D
    hitc = $1E
    tmp3 = $1F
    servedx = $20
    ptr2 = $22    ; and $23
    shaket = $24
    shx = $25
    pnext = $26
    spx = $27
    spy = $28
    spvx = $29
    spvy = $2A
    spcol = $2B
    padvx = $2C    ; and $2D (signed 8.8)
    padxf = $2E    ; paddle x fraction
    ballspd = $2F    ; wind-up speed level 0-2
    windt = $30    ; and $31
    chain = $32    ; score multiplier 1-7
    chaint = $33    ; chain window frames
    flasht = $34    ; screen flash frames
    spkind = $35    ; particle kind for spawn
    mulk = $36    ; scratch (brick_hit)
    sidx = $37    ; scratch (brick_hit)

    ; power-ups / pills (two falling pills max)
    pill_t = $38    ; and $39: type 1-7, 0 = inactive
    pill_x = $3A    ; and $3B
    pill_y = $3C    ; and $3D
    pill_yf = $3E    ; and $3F: y fraction (falls 0.7/frame)
    t_slow = $40    ; 16-bit frame timers
    t_expand = $42
    t_reduce = $44
    t_megaw = $46    ; megaball warmup (armed until first brick)
    t_mega = $48    ; megaball active (8-bit, 120)
    stickyf = $49    ; sticky-paddle armed
    stuckf = $4A    ; ball riding the paddle mid-play
    stuckoff = $4B   ; ballx - padx while stuck
    padw = $4C    ; 0 = 24px, 1 = 32px (expand), 2 = 16px (reduce)
    b2on = $4D    ; second ball (multiball) active
    b2x = $4E    ; and $4F: 8.8 frac,int
    b2y = $50    ; and $51
    b2vx = $52    ; and $53
    b2vy = $54    ; and $55
    sd_on = $56    ; sudden death armed
    sd_t = $57    ; and $58: 450-frame fuse
    sd_blink = $59   ; frames to next beep/flash
    sd_idx = $5A    ; shadow index of the doomed brick
    curball = $5B    ; 0 = primary, 1 = ball2 (inside ball_step)
    msgt = $5C    ; pill sash message timer
    ncmb = $5D    ; brick_hit: 1 = no score/chain (explosions)
    hittype = $5E    ; brick_hit: type code seen at entry
    expn = $5F    ; explosion queue depth
    nextch = $60    ; sfx_play round-robin steal cursor

    ; Scratch, at $8000: far above the program image and below the $E000
    ; peripheral window, so it cannot collide with either however much the
    ; code grows. It has been placed too low twice now - first at $0C00, on
    ; top of the level data, and then at $2000, on top of `audio_data`, which
    ; ends at $2E11: the shadow clear was overwriting sfx 14-16 and the
    ; particle pool sfx 18-20 every frame, and the pool read its initial
    ; "live" flags out of whatever sfx bytes happened to sit at $2140. Do not
    ; move this back down to chase a smaller image.
    ;
    ; This needs the full 64 KB RAM (RAM_ADDR_BITS=16: the simulator and
    ; top_tangnano20k). On a target with a shrunken RAM $8000 aliases down -
    ; but so does $2000, and breakout's image is ~11 KB, so it never fitted
    ; the 8 KB tops anyway.
    scratch = $8000

    ; Brick shadow map: 10 rows x 11 cols
    shadow = scratch

    ; Particle pool (12), one page
    PPX = scratch + $100
    PPY = scratch + $110
    PVX = scratch + $120
    PVY = scratch + $130
    PLIFE = scratch + $140
    PCOL = scratch + $150
    PKIND = scratch + $160  ; 0 = burst spark, 1 = ball trail, 2 = shard
    DUSTX = scratch + $170  ; ambient dust (8), behind the bricks
    DUSTY = scratch + $178
    EXPQ = scratch + $180  ; explosion queue: shadow indices (8)

