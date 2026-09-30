; ============================================================================
;  BRICKSTORM  -  a Breakout game for the Commodore 64
;  Guenther Haslbeck + Claude Code, 2026
;
;  Sprites : paddle (sprite 0, x-expanded), ball (sprite 1)
;  Bricks  : characters in screen RAM, colour from colour RAM
;  Control : joystick port 2, or keys A/D (Z/X-style alternatives , .), fire = SPACE/RETURN
;  Sound   : SID voice 1 = effects, voice 2 = bass, voice 3 = lead arpeggio
;
;  Assemble with 64tass (see build.py). Tables live in brickstorm_data.inc.
; ============================================================================
        .cpu "6502"

; ---- game states ----
ST_TITLE = 0
ST_SERVE = 1
ST_PLAY  = 2
ST_LOST  = 3
ST_CLEAR = 4
ST_OVER  = 5
ST_PAUSE = 6

; ---- zero page ----
fflag   = $02           ; set by the raster IRQ once per frame
frame   = $03
state   = $04
lives   = $05
level   = $06
spd     = $07           ; ball speed index 0..5
hits    = $08           ; paddle hits since last speed-up
bricks  = $09           ; bricks left
score   = $0a           ; 3 bytes BCD, low first
hisc    = $0d           ; 3 bytes BCD
pxl     = $10           ; paddle x in pixels (16 bit)
pxh     = $11
bxl     = $12           ; ball position in 1/16 pixel
bxh     = $13
byl     = $14
byh     = $15
vxl     = $16           ; ball velocity in 1/16 pixel per frame (signed 16 bit)
vxh     = $17
vyl     = $18
vyh     = $19
xpl     = $1a           ; ball x in pixels (16 bit)
xph     = $1b
ypx     = $1c           ; ball y in pixels
qxl     = $1d           ; brick probe point
qxh     = $1e
qy      = $1f
col     = $20
row     = $21
bcode    = $22
bcol    = $23
ptr     = $24           ; word
cptr    = $26           ; word
strp    = $28           ; word
dst     = $2a           ; word
lp      = $2c           ; word, level data pointer
tmp     = $2e
tmp2    = $2f
scol    = $30
inl     = $31           ; input: left / right / fire
inr     = $32
inf     = $33
finh    = $34           ; fire was held last frame
timer   = $35
curlvl  = $36
bcolor  = $37
kk      = $38
rr      = $39
lvlc    = $3a           ; 6 brick row colours of the current level
outf    = $42           ; ball left the playfield
keyp    = $43
keym    = $44
pprev   = $45
mprev   = $46
mstep   = $47
mfr     = $48
muson   = $49
sfxn    = $4a
sfxf    = $4b
sfxs    = $4c
sfxw    = $4d
sfxst   = $4e

; ---- memory ----
SCREEN  = $0400
COLRAM  = $d800
CHARSET = $3000
SPRDATA = $3800

; ============================================================================
        * = $0801
        .word _next
        .word 10
        .byte $9e, $32, $30, $36, $34, 0        ; 10 SYS 2064
_next   .word 0
        .fill $0810 - *, 0

start
        sei
        lda #$7f
        sta $dc0d
        sta $dd0d
        lda $dc0d
        lda $dd0d
        lda #0
        sta $d01a
        sta $d015
        lda #$ff
        sta $d019
        sta $dc02               ; CIA1 port A: outputs (keyboard columns)
        lda #0
        sta $dc03               ; port B: inputs (keyboard rows)

        ; ---- font: ROM -> RAM, then our own glyphs ----
        lda #$33
        sta $01
        ldx #0
_cp
        .for pg = 0, pg < 8, pg += 1
        lda $d000 + pg*256,x
        sta CHARSET + pg*256,x
        .next
        inx
        bne _cp
        lda #$35
        sta $01
        ldx #7
_g1     lda glyph_block,x
        sta CHARSET + $40*8,x
        dex
        bpl _g1
        ldx #39
_g2     lda glyph_set,x
        sta CHARSET + $60*8,x
        dex
        bpl _g2

        ; ---- sprite shapes ----
        ldx #127
_sd     lda sprites,x
        sta SPRDATA,x
        dex
        bpl _sd

        ; ---- VIC ----
        lda #$1c                ; screen $0400, charset $3000
        sta $d018
        lda #$1b
        sta $d011
        lda #$c8
        sta $d016
        lda #0
        sta $d020
        sta $d021
        sta $d010
        sta $d01b
        sta $d01c
        lda #$e0
        sta $07f8               ; paddle
        lda #$e1
        sta $07f9               ; ball
        lda #14
        sta $d027
        lda #1
        sta $d028
        lda #1
        sta $d01d               ; paddle x-expanded

        ; ---- SID ----
        ldx #$18
        lda #0
_sid    sta $d400,x
        dex
        bpl _sid
        lda #8
        sta $d403               ; pulse width voice 1 = $0800
        sta $d40a               ; voice 2
        sta $d411               ; voice 3
        lda #$08
        sta $d40c
        lda #$84
        sta $d40d
        lda #$06
        sta $d413
        lda #$44
        sta $d414
        lda #$0f
        sta $d418

        ; ---- variables ----
        lda #0
        sta score
        sta score+1
        sta score+2
        sta hisc
        sta hisc+1
        sta hisc+2
        sta frame
        sta mstep
        sta mfr
        sta sfxn
        sta sfxst
        sta finh
        sta pprev
        sta mprev
        sta outf
        lda #1
        sta muson
        lda #136
        sta pxl
        lda #0
        sta pxh

        ; ---- interrupts ----
        lda #<irq
        sta $fffe
        lda #>irq
        sta $ffff
        lda #<nmi
        sta $fffa
        lda #>nmi
        sta $fffb
        lda #250
        sta $d012
        lda #$1b
        sta $d011
        lda #1
        sta $d01a
        lda #$ff
        sta $d019

        jsr to_title
        cli

main    lda fflag
        beq main
        lda #0
        sta fflag
        inc frame
        jsr tick
        jmp main

nmi     rti

; one raster interrupt per frame (line 250): sound + frame flag
irq
        cld
        pha
        txa
        pha
        tya
        pha
        lda #$01
        sta $d019
        jsr snd
        lda #1
        sta fflag
        pla
        tay
        pla
        tax
        pla
        rti

; ============================================================================
;  state machine
; ============================================================================
tick
        jsr readinput
        jsr keys
        lda state
        asl a
        tax
        lda jump+1,x
        pha
        lda jump,x
        pha
        rts
jump    .word st_title-1, st_serve-1, st_play-1, st_lost-1, st_clear-1, st_over-1, st_pause-1

; ---- title ----
to_title
        lda #0
        sta $d015
        lda #ST_TITLE
        sta state
        jsr clearscreen
        ldx #0
_t1     lda tlogo,x
        sta SCREEN + 3*40,x
        inx
        cpx #200
        bne _t1
        ldx #<str_t_sub
        ldy #>str_t_sub
        jsr drawstr
        ldx #<str_t_by
        ldy #>str_t_by
        jsr drawstr
        ldx #<str_t_year
        ldy #>str_t_year
        jsr drawstr
        ldx #<str_t_ctl1
        ldy #>str_t_ctl1
        jsr drawstr
        ldx #<str_t_ctl2
        ldy #>str_t_ctl2
        jsr drawstr
        ldx #<str_t_ctl3
        ldy #>str_t_ctl3
        jsr drawstr
        ldx #<str_t_hi
        ldy #>str_t_hi
        jsr drawstr
        lda #<(SCREEN + 23*40 + HI_DIGITS_COL)
        sta dst
        lda #>(SCREEN + 23*40 + HI_DIGITS_COL)
        sta dst+1
        ldx #hisc
        jsr bcd3out
        rts

st_title
        ldx #0                  ; rainbow logo rows
_tr     stx rr
        txa
        asl a
        sta tmp
        lda frame
        lsr a
        lsr a
        clc
        adc tmp
        and #15
        tay
        lda ctab,y
        sta tmp2
        ldx rr
        lda tcolo,x
        sta ptr
        lda tcohi,x
        sta ptr+1
        lda tmp2
        ldy #39
_tc     sta (ptr),y
        dey
        bpl _tc
        ldx rr
        inx
        cpx #5
        bne _tr
        lda frame
        and #32
        bne _toff
        ldx #<str_press
        ldy #>str_press
        jmp _tdraw
_toff   ldx #<str_blank
        ldy #>str_blank
_tdraw  jsr drawstr
        jsr firepress
        bcc _tx
        jsr newgame
_tx     rts

newgame
        lda #0
        sta score
        sta score+1
        sta score+2
        lda #3
        sta lives
        lda #1
        sta level
        jmp newlevel

; ---- level set-up ----
newlevel
        lda level
        sec
        sbc #1
_m5     cmp #5
        bcc _m5d
        sbc #5
        bcs _m5
_m5d    sta curlvl
        asl a
        asl a
        asl a
        tax
        ldy #0
_pl     lda lvlpal,x
        sta lvlc,y
        inx
        iny
        cpy #6
        bne _pl
        ldx curlvl
        lda lvlplo,x
        sta lp
        lda lvlphi,x
        sta lp+1
        jsr drawfield
        lda level               ; speed = min(level-1, 3)
        sec
        sbc #1
        cmp #4
        bcc _sp
        lda #3
_sp     sta spd
        jmp resetserve

resetserve
        lda #0
        sta hits
        sta outf
        lda #3
        sta $d015
        lda #ST_SERVE
        sta state
        ldx #SFX_START
        jmp sfx_start

; ---- draw the playfield ----
drawfield
        jsr clearscreen
        ldx #39                 ; top wall
_w1     lda #$64
        sta SCREEN + 40,x
        lda #12
        sta COLRAM + 40,x
        dex
        bpl _w1
        ldx #2                  ; side walls
_sw     lda rlo,x
        sta ptr
        sta cptr
        lda rhi,x
        sta ptr+1
        lda rchi,x
        sta cptr+1
        lda #$64
        ldy #0
        sta (ptr),y
        ldy #39
        sta (ptr),y
        lda #11
        ldy #0
        sta (cptr),y
        ldy #39
        sta (cptr),y
        inx
        cpx #25
        bne _sw
        ldx #<str_score
        ldy #>str_score
        jsr drawstr
        ldx #<str_hi
        ldy #>str_hi
        jsr drawstr
        ldx #<str_level
        ldy #>str_level
        jsr drawstr
        lda #2                  ; hearts are red
        sta COLRAM + 36
        sta COLRAM + 37
        sta COLRAM + 38

        lda #0                  ; bricks
        sta bricks
        sta rr
_br     lda rr
        clc
        adc #3
        tax
        lda rlo,x
        sta ptr
        sta cptr
        lda rhi,x
        sta ptr+1
        lda rchi,x
        sta cptr+1
        ldx rr
        lda lvlc,x
        sta bcolor
        lda #0
        sta kk
_bk     ldy #0
        lda (lp),y
        beq _bs
        sta tmp
        inc bricks
        ldx kk
        ldy bcolk,x
        lda tmp
        cmp #1
        bne _ar
        lda #$60
        sta (ptr),y
        iny
        sta (ptr),y
        iny
        lda #$61
        sta (ptr),y
        lda bcolor
        sta (cptr),y
        dey
        sta (cptr),y
        dey
        sta (cptr),y
        jmp _bs
_ar     lda #$62
        sta (ptr),y
        iny
        sta (ptr),y
        iny
        lda #$63
        sta (ptr),y
        lda #15
        sta (cptr),y
        dey
        sta (cptr),y
        dey
        sta (cptr),y
_bs     inc lp
        bne _b2
        inc lp+1
_b2     inc kk
        lda kk
        cmp #12
        bne _bk
        inc rr
        lda rr
        cmp #6
        bne _br
        rts

; ---- serve: ball rides on the paddle ----
st_serve
        jsr movepaddle
        clc
        lda pxl
        adc #21
        sta bxl
        lda pxh
        adc #0
        sta bxh
        .for i = 0, i < 4, i += 1
        asl bxl
        rol bxh
        .next
        lda #<(170*16)
        sta byl
        lda #>(170*16)
        sta byh
        jsr ballpx
        jsr updspr
        jsr drawhud
        ldx #<str_launch
        ldy #>str_launch
        jsr drawstr
        jsr firepress
        bcc _sx
        jsr clrmsg
        lda frame               ; slightly random launch angle
        and #1
        clc
        adc #3
        jsr setvel
        lda #ST_PLAY
        sta state
_sx     rts

; ---- play ----
st_play
        jsr movepaddle
        jsr moveball
        jsr updspr
        jsr drawhud
        lda outf
        bne _lost
        lda bricks
        beq _clear
        rts
_lost   lda #0
        sta outf
        dec lives
        ldx #SFX_LOSE
        jsr sfx_start
        lda #1
        sta $d015               ; ball disappears
        lda lives
        beq _over
        lda #60
        sta timer
        lda #ST_LOST
        sta state
        rts
_over   jsr hiscore
        jsr drawhud
        ldx #<str_gameover
        ldy #>str_gameover
        jsr drawstr
        ldx #<str_again
        ldy #>str_again
        jsr drawstr
        lda #180
        sta timer
        lda #ST_OVER
        sta state
        rts
_clear  ldx #SFX_LEVELUP
        jsr sfx_start
        ldx #<str_cleared
        ldy #>str_cleared
        jsr drawstr
        lda #100
        sta timer
        lda #ST_CLEAR
        sta state
        lda #1
        sta $d015
        rts

st_lost
        jsr movepaddle
        jsr updspr
        jsr drawhud
        dec timer
        bne _lx
        jsr resetserve
_lx     rts

st_clear
        jsr drawhud
        dec timer
        bne _cx
        inc level
        jmp newlevel
_cx     rts

st_over
        dec timer
        beq _go
        lda timer
        cmp #120
        bcs _ox
        jsr firepress
        bcs _go
_ox     rts
_go     jmp to_title

st_pause
        ldx #<str_paused
        ldy #>str_paused
        jmp drawstr

; ---- pause and music keys ----
keys
        lda keyp
        beq _kp0
        lda pprev
        bne _km
        lda #1
        sta pprev
        lda state
        cmp #ST_PLAY
        beq _topause
        cmp #ST_PAUSE
        bne _km
        jsr clrmsg              ; resume
        lda #ST_PLAY
        sta state
        jmp _km
_topause
        lda #ST_PAUSE
        sta state
        jmp _km
_kp0    lda #0
        sta pprev
_km     lda keym
        beq _km0
        lda mprev
        bne _kx
        lda #1
        sta mprev
        lda muson
        eor #1
        sta muson
        rts
_km0    lda #0
        sta mprev
_kx     rts

; ============================================================================
;  input
; ============================================================================
readinput
        lda #$ff
        sta $dc00
        lda $dc00               ; joystick port 2 (0 = pressed)
        sta tmp
        lda #0
        sta inl
        sta inr
        sta inf
        sta keyp
        sta keym
        lda tmp
        and #$04
        bne _j1
        inc inl
_j1     lda tmp
        and #$08
        bne _j2
        inc inr
_j2     lda tmp
        and #$10
        bne _j3
        inc inf
_j3     lda #$fd                ; A
        sta $dc00
        lda $dc01
        and #$04
        bne _k1
        inc inl
_k1     lda #$fb                ; D
        sta $dc00
        lda $dc01
        and #$04
        bne _k2
        inc inr
_k2     lda #$df                ; , . P
        sta $dc00
        lda $dc01
        sta tmp
        and #$80
        bne _k3
        inc inl
_k3     lda tmp
        and #$10
        bne _k4
        inc inr
_k4     lda tmp
        and #$02
        bne _k5
        inc keyp
_k5     lda #$ef                ; M
        sta $dc00
        lda $dc01
        and #$10
        bne _k6
        inc keym
_k6     lda #$7f                ; SPACE
        sta $dc00
        lda $dc01
        and #$10
        bne _k7
        inc inf
_k7     lda #$fe                ; RETURN
        sta $dc00
        lda $dc01
        and #$02
        bne _k8
        inc inf
_k8     lda #$ff
        sta $dc00
        .if AUTOPLAY != 0
        lda #0                  ; test mode: the computer plays
        sta inl
        sta inr
        lda frame
        and #1
        sta inf
        .if AUTOPLAY == 1
        lda state
        cmp #ST_PLAY
        bne _auto_x
        lda frame
        lsr a
        lsr a
        and #31
        sta tmp
        clc
        lda xpl
        adc tmp
        sta pxl
        lda xph
        adc #0
        sta pxh
        sec
        lda pxl
        sbc #37
        sta pxl
        lda pxh
        sbc #0
        sta pxh
        jsr clamppx
_auto_x
        .endif
        .endif
        rts

; returns C=1 if fire was newly pressed
firepress
        lda inf
        beq _fu
        lda finh
        bne _fd
        lda #1
        sta finh
        sec
        rts
_fu     lda #0
        sta finh
_fd     clc
        rts

; ============================================================================
;  paddle, ball
; ============================================================================
movepaddle
        lda inl
        beq _mr
        sec
        lda pxl
        sbc #5
        sta pxl
        lda pxh
        sbc #0
        sta pxh
_mr     lda inr
        beq _mx
        clc
        lda pxl
        adc #5
        sta pxl
        lda pxh
        adc #0
        sta pxh
_mx
clamppx                         ; keep 8 <= px <= 264
        lda pxh
        bmi _lo
        bne _hi0
        lda pxl
        cmp #8
        bcs _ok
_lo     lda #8
        sta pxl
        lda #0
        sta pxh
        rts
_hi0    lda pxl
        cmp #9
        bcc _ok
        lda #8
        sta pxl
        lda #1
        sta pxh
_ok     rts

; ball pixel position from the 1/16 pixel position
ballpx
        lda bxl
        sta xpl
        lda bxh
        sta xph
        .for i = 0, i < 4, i += 1
        lsr xph
        ror xpl
        .next
        lda byl
        lsr a
        lsr a
        lsr a
        lsr a
        sta tmp
        lda byh
        asl a
        asl a
        asl a
        asl a
        ora tmp
        sta ypx
        rts

negvx
        sec
        lda #0
        sbc vxl
        sta vxl
        lda #0
        sbc vxh
        sta vxh
        rts

negvy
        sec
        lda #0
        sbc vyl
        sta vyl
        lda #0
        sbc vyh
        sta vyh
        rts

; A = paddle zone 0..7 -> velocity from the table
setvel
        sta tmp
        lda spd
        asl a
        asl a
        asl a
        clc
        adc tmp
        tax
        lda tvxl,x
        sta vxl
        lda tvxh,x
        sta vxh
        lda tvyl,x
        sta vyl
        lda tvyh,x
        sta vyh
        rts

paddlehit
        jsr setvel
        lda #<(170*16)
        sta byl
        lda #>(170*16)
        sta byh
        inc hits
        lda hits
        cmp #12
        bcc _ph
        lda #0
        sta hits
        lda spd
        cmp #5
        bcs _ph
        inc spd
_ph     ldx #SFX_PADDLE
        jmp sfx_start

moveball
        ; ---- horizontal ----
        clc
        lda bxl
        adc vxl
        sta bxl
        lda bxh
        adc vxh
        sta bxh
        jsr ballpx
        lda xph                 ; left wall
        bne _xr
        lda xpl
        cmp #8
        bcs _xr
        lda #<(8*16)
        sta bxl
        lda #>(8*16)
        sta bxh
        jsr negvx
        ldx #SFX_WALL
        jsr sfx_start
        jmp _y
_xr     lda xph                 ; right wall (ball x > 306)
        beq _xb
        lda xpl
        cmp #$33
        bcc _xb
        lda #<(306*16)
        sta bxl
        lda #>(306*16)
        sta bxh
        jsr negvx
        ldx #SFX_WALL
        jsr sfx_start
        jmp _y
_xb     lda vxh                 ; bricks at the leading edge
        bmi _xl
        clc
        lda xpl
        adc #5
        sta qxl
        lda xph
        adc #0
        sta qxh
        jmp _xp
_xl     lda xpl
        sta qxl
        lda xph
        sta qxh
_xp     clc
        lda ypx
        adc #1
        sta qy
        jsr probe
        bcs _xhit
        clc
        lda ypx
        adc #4
        sta qy
        jsr probe
        bcc _y
_xhit   sec
        lda bxl
        sbc vxl
        sta bxl
        lda bxh
        sbc vxh
        sta bxh
        jsr negvx
        jsr ballpx

        ; ---- vertical ----
_y      clc
        lda byl
        adc vyl
        sta byl
        lda byh
        adc vyh
        sta byh
        jsr ballpx
        lda ypx                 ; top wall
        cmp #16
        bcs _yb
        lda #<(16*16)
        sta byl
        lda #>(16*16)
        sta byh
        jsr negvy
        ldx #SFX_WALL
        jsr sfx_start
        jsr ballpx
        rts
_yb     cmp #194                ; ball fell out
        bcc _yc
        lda #1
        sta outf
        rts
_yc     lda vyh                 ; paddle (only when moving down)
        bmi _ybr
        lda ypx
        cmp #171
        bcc _ybr
        cmp #178
        bcs _ybr
        clc
        lda xpl
        adc #5
        sta tmp
        lda xph
        adc #0
        sta tmp2
        sec
        lda tmp
        sbc pxl
        sta tmp
        lda tmp2
        sbc pxh
        bcc _ybr
        bne _ybr
        lda tmp
        cmp #53
        bcs _ybr
        tax
        lda zone_of,x
        jsr paddlehit
        jsr ballpx
        rts
_ybr    lda vyh                 ; bricks at the leading edge
        bmi _yu
        clc
        lda ypx
        adc #5
        sta qy
        jmp _yq
_yu     lda ypx
        sta qy
_yq     clc
        lda xpl
        adc #1
        sta qxl
        lda xph
        adc #0
        sta qxh
        jsr probe
        bcs _yhit
        clc
        lda xpl
        adc #4
        sta qxl
        lda xph
        adc #0
        sta qxh
        jsr probe
        bcc _yd
_yhit   sec
        lda byl
        sbc vyl
        sta byl
        lda byh
        sbc vyh
        sta byh
        jsr negvy
        jsr ballpx
_yd     rts

; Is there a brick under the pixel (qx,qy)? If so, hit it. C=1 on hit.
probe
        lda qy
        lsr a
        lsr a
        lsr a
        sta row
        cmp #3
        bcc _far0
        cmp #9
        bcc _row_ok
_far0   jmp _no
_row_ok lda qxl
        lsr a
        lsr a
        lsr a
        sta col
        lda qxh
        beq _c1
        lda col
        ora #$20
        sta col
_c1     ldx row
        lda rlo,x
        sta ptr
        sta cptr
        lda rhi,x
        sta ptr+1
        lda rchi,x
        sta cptr+1
        ldy col
        lda (ptr),y
        sta bcode
        cmp #$60
        bcc _far
        cmp #$64
        bcc _hit
_far    jmp _no
_hit    lda bstart,y
        tay
        lda bcode
        cmp #$62
        bcs _arm
        lda #$20                ; normal brick: remove
        sta (ptr),y
        iny
        sta (ptr),y
        iny
        sta (ptr),y
        dec bricks
        lda row
        sec
        sbc #3
        tax
        lda rowscore,x
        jsr addscore
        ldx #SFX_BRICK
        jsr sfx_start
        sec
        rts
_arm    lda #$60                ; armored brick: becomes a normal one
        sta (ptr),y
        iny
        sta (ptr),y
        iny
        lda #$61
        sta (ptr),y
        lda row
        sec
        sbc #3
        tax
        lda lvlc,x
        sta (cptr),y
        dey
        sta (cptr),y
        dey
        sta (cptr),y
        lda #$05
        jsr addscore
        ldx #SFX_ARMOR
        jsr sfx_start
        sec
        rts
_no     clc
        rts

; ---- sprites ----
updspr
        clc
        lda pxl
        adc #24
        sta $d000
        lda pxh
        adc #0
        sta tmp
        lda #226
        sta $d001
        clc
        lda xpl
        adc #24
        sta $d002
        lda xph
        adc #0
        asl a
        ora tmp
        sta $d010
        clc
        lda ypx
        adc #50
        sta $d003
        rts

; ============================================================================
;  score, hud, text
; ============================================================================
addscore                        ; A = BCD points
        sed
        clc
        adc score
        sta score
        lda score+1
        adc #0
        sta score+1
        lda score+2
        adc #0
        sta score+2
        cld
        rts

hiscore
        lda score+2
        cmp hisc+2
        bcc _nh
        bne _nw
        lda score+1
        cmp hisc+1
        bcc _nh
        bne _nw
        lda score
        cmp hisc
        bcc _nh
        beq _nh
_nw     lda score
        sta hisc
        lda score+1
        sta hisc+1
        lda score+2
        sta hisc+2
_nh     rts

drawhud
        lda #<(SCREEN + 7)
        sta dst
        lda #>(SCREEN + 7)
        sta dst+1
        ldx #score
        jsr bcd3out
        lda #<(SCREEN + 18)
        sta dst
        lda #>(SCREEN + 18)
        sta dst+1
        ldx #hisc
        jsr bcd3out
        lda level
        ldx #0
_lt     cmp #10
        bcc _ld
        sbc #10
        inx
        bne _lt
_ld     ora #$30
        sta SCREEN + 33
        txa
        ora #$30
        sta SCREEN + 32
        ldx #0
_hr     lda #$20
        cpx lives
        bcs _hs
        lda #$53
_hs     sta SCREEN + 36,x
        inx
        cpx #3
        bne _hr
        rts

; X = zero page address of the low byte of a 3 byte BCD number, dst = screen
bcd3out
        ldy #0
        lda $02,x
        jsr _two
        lda $01,x
        jsr _two
        lda $00,x
_two    pha
        lsr a
        lsr a
        lsr a
        lsr a
        ora #$30
        sta (dst),y
        iny
        pla
        and #$0f
        ora #$30
        sta (dst),y
        iny
        rts

; X/Y = address of a string record: col, row, colour, text..., $ff
drawstr
        stx strp
        sty strp+1
        ldy #0
        lda (strp),y
        sta col
        iny
        lda (strp),y
        tax
        iny
        lda (strp),y
        sta scol
        lda rlo,x
        clc
        adc col
        sta dst
        sta cptr
        lda rhi,x
        adc #0
        sta dst+1
        clc
        adc #$d4
        sta cptr+1
        clc
        lda strp
        adc #3
        sta strp
        bcc _ds1
        inc strp+1
_ds1    ldy #0
_ds2    lda (strp),y
        cmp #$ff
        beq _dsx
        sta (dst),y
        lda scol
        sta (cptr),y
        iny
        bne _ds2
_dsx    rts

; blank the message area (rows 12..16)
clrmsg
        ldx #12
_cm     lda rlo,x
        sta ptr
        lda rhi,x
        sta ptr+1
        ldy #38
        lda #$20
_cm2    sta (ptr),y
        dey
        bne _cm2
        inx
        cpx #17
        bne _cm
        rts

clearscreen
        ldx #0
_cs     lda #$20
        sta SCREEN,x
        sta SCREEN + $100,x
        sta SCREEN + $200,x
        sta SCREEN + $2e8,x
        lda #1
        sta COLRAM,x
        sta COLRAM + $100,x
        sta COLRAM + $200,x
        sta COLRAM + $2e8,x
        inx
        bne _cs
        rts

; ============================================================================
;  sound: voice 1 = effects, voices 2/3 = music (called from the IRQ)
; ============================================================================
sfx_start                       ; X = effect number (from main code only)
        sei
        lda swave,x
        sta sfxw
        and #$fe
        sta $d404               ; gate off first (hard restart)
        lda shi,x
        sta sfxf
        sta $d401
        lda sstep,x
        sta sfxs
        lda sdur,x
        sta sfxn
        lda sad,x
        sta $d405
        lda ssr,x
        sta $d406
        lda #1
        sta sfxst
        cli
        rts

snd
        lda sfxst
        beq _s1
        lda sfxw
        sta $d404               ; gate on
        lda #0
        sta sfxst
        jmp mus
_s1     lda sfxn
        beq mus
        dec sfxn
        bne _s2
        lda sfxw
        and #$fe
        sta $d404
        jmp mus
_s2     lda sfxf
        clc
        adc sfxs
        sta sfxf
        sta $d401

mus
        lda muson
        bne _mon
        lda #0
        sta $d40b
        sta $d412
        rts
_mon    lda mfr
        bne _m1
        ldx mstep               ; frame 0 of a step: new notes, gates off
        lda bassh,x
        sta $d408
        lda bassl,x
        sta $d407
        lda leadh,x
        sta $d40f
        lda leadl,x
        sta $d40e
        lda #$40
        sta $d412
        lda #$20
        sta $d40b
        jmp _madv
_m1     cmp #1                  ; frame 1: gates on
        bne _madv
        ldx mstep
        lda bassh,x
        beq _m2
        lda #$21
        sta $d40b
_m2     lda leadh,x
        beq _madv
        lda #$41
        sta $d412
_madv   inc mfr
        lda mfr
        cmp #6
        bne _mret
        lda #0
        sta mfr
        lda mstep
        clc
        adc #1
        and #63
        sta mstep
_mret   rts

; ============================================================================
        .include "brickstorm_data.inc"
        .cerror * > CHARSET, "code + data overlap the charset"
