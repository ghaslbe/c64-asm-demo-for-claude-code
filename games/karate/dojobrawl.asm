; ============================================================================
;  DOJO BRAWL  -  a three fighter karate game for the Commodore 64
;  (inspired by the gameplay of IK+)   Guenther Haslbeck + Claude Code, 2026
;
;  Fighters : 3 x two stacked multicolor sprites (24 x 42 pixels), 14 poses, mirrored in
;             the sprite data for the facing direction (sprite data lives at $2800)
;  Combat   : punch, front kick, sweep, flying kick, back kick, jump, crouch; hits are
;             checked per attack against position, reach and the victim's stance
;  Rounds   : first to 6 points or 45 seconds; the last of the three is out; every second
;             round a bonus round (block the balls)
;  Sky      : a raster loop writes one background colour per line (sunset gradient)
;  Control  : joystick port 2, or W A S D, fire = SPACE / RETURN
;
;  Assemble with 64tass (see build.py). Tables live in dojobrawl_data.inc,
;  sprite shapes in dojobrawl_sprites.inc.
; ============================================================================
        .cpu "6502"

; ---- fighter states ----
S_IDLE   = 0
S_WALK   = 1
S_CROUCH = 2
S_JUMP   = 3
S_PUNCH  = 4
S_KICK   = 5
S_SWEEP  = 6
S_FLY    = 7
S_BACK   = 8
S_HIT    = 9
S_FALL   = 10
S_GETUP  = 11
S_WIN    = 12

; ---- game states ----
ST_TITLE  = 0
ST_INTRO  = 1
ST_FIGHT  = 2
ST_END    = 3
ST_RESULT = 4
ST_BONUS  = 5
ST_BONEND = 6
ST_OVER   = 7
ST_PAUSE  = 8

; ---- control bits ----
CL = 1
CR = 2
CU = 4
CD = 8
CF = 16

GROUNDY  = 194          ; sprite Y register of the upper half when standing

; ---- zero page ----
fflag   = $02
frame   = $03
state   = $04
rnum   = $05
stage   = $06
rtime   = $07           ; seconds left
rsub    = $08
timer   = $09
fi      = $0a
score   = $0b           ; 3 bytes BCD
hisc    = $0e
inl     = $11
inr     = $12
inu     = $13
ind     = $14
inf     = $15
finh    = $16
keyp    = $17
keym    = $18
pprev   = $19
mprev   = $1a
rnd     = $1b
tmp     = $1c
tmp2    = $1d
tmp3    = $1e
tmpx    = $1f
tmpy    = $20
col     = $21
scol    = $22
strp    = $23
dst     = $25
ptr     = $27
sxl     = $29
sxh     = $2a
sy      = $2b
msbacc  = $2c
enacc   = $2d
mstep   = $2e
mfr     = $2f
muson   = $30
sfxn    = $31
sfxf    = $32
sfxs    = $33
sfxw    = $34
sfxst   = $35
vv      = $36
atype   = $37
dsgn    = $38
nrst    = $39
nrdist  = $3a
nrside  = $3b
n2      = $3c
n2dist  = $3d
n2side  = $3e
sparkt  = $3f
sparkxl = $40
sparkxh = $41
sparky  = $42
tw      = $43
mvd     = $44
nballs  = $45
bon     = $46
bside   = $47
bhgt    = $48
bxl     = $49
bxh     = $4a
blocked = $4b
missed  = $4c
bwait   = $4d
msgt    = $4e
winner  = $4f
stagevec = $50
rk      = $52           ; ranking: fighter index per place (3 bytes)
bhurt   = $55
kk      = $56
cptr    = $57
shside  = $59           ; bonus round: shield side (0 none, 1 left, 2 right)
shhgt   = $5a           ; bonus round: shield height (0 high, 1 middle, 2 low)
skyp    = $5b           ; pointer to the current sky colour table (word)

; ---- fighter arrays (3 entries, stride 4) ----
fxl     = $c000         ; centre x (16 bit)
fxh     = $c004
fy      = $c008         ; height above the ground
fst     = $c00c
ftm     = $c010
ffc     = $c014         ; facing: 0 right, 1 left
fsc     = $c018         ; score in half points
fhit    = $c01c         ; victims already hit by the running attack
fjt     = $c020         ; jump timer
fai     = $c024         ; ai action
fait    = $c028         ; ai timer
fctl    = $c02c         ; control bits
fkb     = $c030         ; knock back pixels left
fkd     = $c034         ; knock back direction

SCREEN  = $0400
COLRAM  = $d800
CHARSET = $3800

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
        sta $dc02
        lda #0
        sta $dc03

        ; ---- font and glyphs ----
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
        ldx #15
_g2     lda glyph_planks,x
        sta CHARSET + $60*8,x
        dex
        bpl _g2
        ldx #79
_g3     lda glyph_caps,x
        sta CHARSET + $70*8,x
        dex
        bpl _g3

        ; ---- VIC ----
        lda #$1e                ; screen $0400, charset $3800
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
        sta $d017
        sta $d01d
        lda #$3f                ; fighters are multicolor sprites
        sta $d01c
        lda #SKIN
        sta $d025
        lda #DARK
        sta $d026

        ; ---- SID ----
        ldx #$18
        lda #0
_sid    sta $d400,x
        dex
        bpl _sid
        lda #8
        sta $d403
        sta $d40a
        sta $d411
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
        sta sparkt
        sta msgt
        lda #1
        sta muson
        lda #$a5
        sta rnd

        ; ---- interrupts ----
        lda #<irq
        sta $fffe
        lda #>irq
        sta $ffff
        lda #<nmi
        sta $fffa
        lda #>nmi
        sta $fffb
        lda #<stageA
        sta stagevec
        lda #>stageA
        sta stagevec+1
        jsr skytit
        lda #50
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

irq
        cld
        pha
        txa
        pha
        tya
        pha
        lda #$01
        sta $d019
        jmp (stagevec)

irqx
        pla
        tay
        pla
        tax
        pla
        rti

; ---- stage A (line 50): sunset gradient, one background colour per line ----
stageA
        ldx #50
        ldy #0
        lda (skyp),y
_a1     cpx $d012
        beq _a1
        sta $d021
        inx
        iny
        lda (skyp),y
        cpy #144
        bne _a1
_a2     cpx $d012
        beq _a2
        lda #0                  ; the dojo floor is dark
        sta $d021
        lda #<stageB
        sta stagevec
        lda #>stageB
        sta stagevec+1
        lda #250
        sta $d012
        jmp irqx

; ---- stage B (line 250): sound and frame flag ----
stageB
        jsr snd
        lda #1
        sta fflag
        lda #<stageA
        sta stagevec
        lda #>stageA
        sta stagevec+1
        lda #50
        sta $d012
        jmp irqx

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
jump    .word st_title-1, st_intro-1, st_fight-1, st_end-1, st_result-1, st_bonus-1
        .word st_bonend-1, st_over-1, st_pause-1

skygame                         ; sunset for the fights
        lda #<sky
        sta skyp
        lda #>sky
        sta skyp+1
        rts

skytit                          ; dark sky for the title
        lda #<skytitle
        sta skyp
        lda #>skytitle
        sta skyp+1
        rts

getrnd                          ; 8 bit LFSR, keeps X/Y
        lda rnd
        asl a
        bcc _r1
        eor #$1d
_r1     sta rnd
        rts

; ---- title ----
to_title
        jsr skytit
        lda #0
        sta $d015
        lda #ST_TITLE
        sta state
        jsr clearscreen
        ldx #0
_t1     lda tlogo,x
        sta SCREEN + 2*40,x
        lda tlogo + 200,x
        sta SCREEN + 8*40,x
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
        ldx #<str_t_c1
        ldy #>str_t_c1
        jsr drawstr
        ldx #<str_t_c2
        ldy #>str_t_c2
        jsr drawstr
        ldx #<str_t_c3
        ldy #>str_t_c3
        jsr drawstr
        ldx #<str_t_c4
        ldy #>str_t_c4
        jsr drawstr
        ldx #<str_t_c5
        ldy #>str_t_c5
        jsr drawstr
        rts

st_title
        lda #0
        sta tmp3
_tr     ldx tmp3
        lda logorows,x
        tay
        txa
        asl a
        sta tmp
        lda frame
        lsr a
        lsr a
        clc
        adc tmp
        and #15
        tax
        lda ctab,x
        sta tmp2
        lda rlo,y
        sta ptr
        lda rchi,y
        sta ptr+1
        lda tmp2
        ldy #39
_tc     sta (ptr),y
        dey
        bpl _tc
        inc tmp3
        lda tmp3
        cmp #LOGO_ROWS
        bne _tr
        lda frame
        and #32
        bne _toff
        ldx #<str_press
        ldy #>str_press
        jmp _tdraw
_toff   ldx #<str_blankp
        ldy #>str_blankp
_tdraw  jsr drawstr
        jsr firepress
        bcc _tx
        lda frame
        eor rnd
        ora #1
        sta rnd
        lda #0
        sta score
        sta score+1
        sta score+2
        lda #1
        sta rnum
        jmp newround
_tx     rts

; ---- round set-up ----
newround
        jsr skygame
        lda rnum
        sec
        sbc #1
        cmp #7
        bcc _ns
        lda #6
_ns     sta stage
        jsr clearscreen
        jsr drawbg
        jsr drawhudstatic
        lda #45
        sta rtime
        lda #50
        sta rsub
        ldx #2                  ; player in the middle, opponents to the sides
_nf     lda #0
        sta fy,x
        sta fst,x
        sta ftm,x
        sta fsc,x
        sta fhit,x
        sta fjt,x
        sta fai,x
        sta fait,x
        sta fctl,x
        sta fkb,x
        sta fkd,x
        sta fxh,x
        lda fstartx,x
        sta fxl,x
        lda fstartf,x
        sta ffc,x
        txa
        asl a
        tay
        lda fcolor,x
        sta $d027,y
        sta $d028,y
        dex
        bpl _nf
        lda #7
        sta $d02d               ; spark colour (sprite 6)
        lda #$3f
        sta $d015
        lda #ST_INTRO
        sta state
        lda #80
        sta timer
        lda #0
        sta sparkt
        sta msgt
        ldx #<str_roundtxt
        ldy #>str_roundtxt
        jsr drawstr
        lda rnum
        jsr dec2
        sta SCREEN + 2*40 + 21
        stx SCREEN + 2*40 + 20
        ldx #SFX_START
        jmp sfx_start

fstartx .byte 160, 70, 250
fstartf .byte 0, 0, 1

; A (< 100) -> X = tens digit (screen code), A = ones digit (screen code)
dec2
        ldx #0
        sec
_d2     cmp #10
        bcc _d2x
        sbc #10
        inx
        bne _d2
_d2x    ora #$30
        pha
        txa
        ora #$30
        tax
        pla
        rts

st_intro
        jsr updsprites
        jsr drawhud
        dec timer
        bne _ix
        ldx #<str_clear4
        ldy #>str_clear4
        jsr drawstr
        ldx #<str_fight
        ldy #>str_fight
        jsr drawstr
        lda #40
        sta msgt
        lda #ST_FIGHT
        sta state
_ix     rts

; ---- the fight ----
st_fight
        lda msgt
        beq _nm
        dec msgt
        bne _nm
        ldx #<str_clear
        ldy #>str_clear
        jsr drawstr
_nm
        .if AUTOPLAY == 1
        ldx #0
        jsr ai                  ; the bot plays the human fighter
        .elsif AUTOPLAY == 2
        lda #0                  ; test mode: the human fighter does nothing
        sta fctl
        .else
        jsr playerctl
        .endif
        ldx #1
        jsr ai
        ldx #2
        jsr ai
        ldx #0
_fl     stx fi
        jsr fupdate
        ldx fi
        inx
        cpx #3
        bne _fl
        jsr sparkupd
        jsr timing
        jsr updsprites
        jsr drawhud
        jsr checkend
        rts

timing
        dec rsub
        bne _tx
        lda #50
        sta rsub
        lda rtime
        beq _tx
        dec rtime
_tx     rts

checkend
        lda state
        cmp #ST_FIGHT
        bne _ce
        ldx #2
_c1     lda fsc,x
        cmp #12
        bcs _end
        dex
        bpl _c1
        lda rtime
        bne _ce
_end    jmp endround
_ce     rts

endround
        jsr ranking
        ldx rk                  ; winner = first place
        stx winner
        ldx #2
_er     lda fst,x
        cmp #S_FALL
        bcs _ek                 ; lying fighters stay down
        lda #S_IDLE
        sta fst,x
        lda #0
        sta ftm,x
        sta fy,x
        sta fjt,x
_ek     dex
        bpl _er
        ldx winner
        lda fst,x
        cmp #S_FALL
        bcs _ew
        lda #S_WIN
        sta fst,x
_ew     lda #100
        sta timer
        lda #ST_END
        sta state
        ldx #SFX_WIN
        jmp sfx_start

st_end
        jsr updsprites
        jsr drawhud
        dec timer
        bne _sx
        jmp showresult
_sx     rts

; ranking: rk[0..2] = fighter indices by score, highest first (ties: lower index first)
ranking
        lda #0
        sta rk
        lda #1
        sta rk+1
        lda #2
        sta rk+2
        lda #0
        sta tmp3
_rp     ldx #0
_rc     ldy rk,x
        lda fsc,y
        sta tmp
        ldy rk+1,x
        lda fsc,y
        cmp tmp
        bcc _rn                 ; next one is smaller: fine
        beq _rn
        lda rk,x                ; swap
        pha
        lda rk+1,x
        sta rk,x
        pla
        sta rk+1,x
_rn     inx
        cpx #2
        bne _rc
        inc tmp3
        lda tmp3
        cmp #3
        bne _rp
        rts

showresult
        jsr skytit              ; black sky: the text needs a dark background
        jsr clearscreen
        jsr drawbg
        jsr drawhudstatic
        jsr panel
        lda #0
        sta $d015
        ldx #<str_over
        ldy #>str_over
        jsr drawstr
        lda #0
        sta tmp3
_sr     jsr resline
        inc tmp3
        lda tmp3
        cmp #3
        bne _sr
        lda rk+2                ; did the human survive (not last)?
        beq _out
        lda fsc                 ; round score: 50 per half point, 1000 for the win
        sta kk
_sa     lda kk
        beq _sb
        lda #$50
        jsr addscore
        dec kk
        jmp _sa
_sb     lda rk
        bne _adv
        lda #$10
        jsr addhund
_adv    ldx #<str_advance
        ldy #>str_advance
        jsr drawstr
        lda #1
        sta winner              ; marker: advance
        jmp _rd
_out    ldx #<str_out
        ldy #>str_out
        jsr drawstr
        lda #0
        sta winner              ; marker: out
_rd     lda #ST_RESULT
        sta state
        lda #70
        sta timer
        rts

; black panel behind the ranking text (rows 3..12, columns 4..35)
panel
        ldx #3
_pl     lda rlo,x
        sta ptr
        sta cptr
        lda rhi,x
        sta ptr+1
        lda rchi,x
        sta cptr+1
        ldy #4
_pc     lda #$40
        sta (ptr),y
        lda #0
        sta (cptr),y
        iny
        cpy #36
        bne _pc
        inx
        cpx #13
        bne _pl
        rts

; one line of the ranking: place tmp3 (0..2)
resline
        lda tmp3
        asl a
        clc
        adc #6
        tay
        lda rlo,y
        clc
        adc #12
        sta dst
        lda rhi,y
        adc #0
        sta dst+1
        lda dst
        sta cptr
        lda dst+1
        clc
        adc #$d4
        sta cptr+1
        ldy #10                 ; clear the line (the panel blocks) first
        lda #$20
_cl     sta (dst),y
        dey
        bpl _cl
        ldx tmp3
        ldy rk,x
        sty tmp                 ; fighter
        txa
        clc
        adc #$31                ; '1'..'3'
        ldy #0
        sta (dst),y
        lda #46
        iny
        sta (dst),y
        lda tmp
        asl a
        clc
        adc tmp
        tax
        lda nametab,x
        ldy #3
        sta (dst),y
        lda nametab+1,x
        iny
        sta (dst),y
        lda nametab+2,x
        iny
        sta (dst),y
        ldx tmp
        lda fsc,x
        lsr a
        ora #$30
        ldy #8
        sta (dst),y
        lda #46
        iny
        sta (dst),y
        lda fsc,x
        and #1
        beq _z
        lda #$35
        bne _y
_z      lda #$30
_y      iny
        sta (dst),y
        lda fcolor,x
        ldy #10
_c      sta (cptr),y
        dey
        bpl _c
        rts

st_result
        jsr drawhud
        lda timer
        beq _rw
        dec timer
        rts
_rw     jsr firepress
        bcc _rx
        lda winner
        beq _gameover
        inc rnum
        lda rnum
        and #1
        bne _bonus              ; after rounds 2, 4, 6 ...: bonus round
        jmp newround
_bonus  jmp newbonus
_gameover
        jsr hiscore
        jsr drawhud
        ldx #<str_gameover
        ldy #>str_gameover
        jsr drawstr
        lda #ST_OVER
        sta state
        lda #150
        sta timer
_rx     rts

st_over
        dec timer
        beq _go
        lda timer
        cmp #90
        bcs _ox
        jsr firepress
        bcs _go
_ox     rts
_go     jmp to_title

st_pause
        ldx #<str_paused
        ldy #>str_paused
        jmp drawstr

keys
        lda keyp
        beq _kp0
        lda pprev
        bne _km
        lda #1
        sta pprev
        lda state
        cmp #ST_FIGHT
        beq _topause
        cmp #ST_PAUSE
        bne _km
        ldx #<str_clear
        ldy #>str_clear
        jsr drawstr
        lda #ST_FIGHT
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
        lda $dc00
        sta tmp
        lda #0
        sta inl
        sta inr
        sta inu
        sta ind
        sta inf
        sta keyp
        sta keym
        lda tmp
        and #$01
        bne _j1
        inc inu
_j1     lda tmp
        and #$02
        bne _j2
        inc ind
_j2     lda tmp
        and #$04
        bne _j3
        inc inl
_j3     lda tmp
        and #$08
        bne _j4
        inc inr
_j4     lda tmp
        and #$10
        bne _j5
        inc inf
_j5     lda #$fd                ; W A S
        sta $dc00
        lda $dc01
        sta tmp
        and #$02
        bne _k1
        inc inu
_k1     lda tmp
        and #$04
        bne _k2
        inc inl
_k2     lda tmp
        and #$20
        bne _k3
        inc ind
_k3     lda #$fb                ; D
        sta $dc00
        lda $dc01
        and #$04
        bne _k4
        inc inr
_k4     lda #$df                ; P
        sta $dc00
        lda $dc01
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
        lda frame               ; test mode: press fire on all menu screens
        lsr a
        and #1
        sta inf
        lda state
        cmp #ST_BONUS
        bne _bx
        lda bon                 ; bonus round: hold the shield where the ball comes in
        beq _bx
        lda bside
        bne _br
        inc inl
        jmp _bh
_br     inc inr
_bh     lda bhgt
        bne _bm
        inc inu
        jmp _bx
_bm     cmp #2
        bne _bx
        inc ind
_bx
        .endif
        rts

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

; translate the human input into control bits of fighter 0
playerctl
        lda #0
        ldx inl
        beq _p1
        ora #CL
_p1     ldx inr
        beq _p2
        ora #CR
_p2     ldx inu
        beq _p3
        ora #CU
_p3     ldx ind
        beq _p4
        ora #CD
_p4     ldx inf
        beq _p5
        ora #CF
_p5     sta fctl
        rts

; ============================================================================
;  fighter helpers
; ============================================================================
; X = a, Y = b: A = |xb - xa| (max 255), dsgn = 0 if b is to the right of a
fdist
        sec
        lda fxl,y
        sbc fxl,x
        sta tmp
        lda fxh,y
        sbc fxh,x
        sta tmp2
        bcs _fp
        lda #1
        sta dsgn
        sec
        lda #0
        sbc tmp
        sta tmp
        lda #0
        sbc tmp2
        sta tmp2
        jmp _fc
_fp     lda #0
        sta dsgn
_fc     lda tmp2
        beq _fo
        lda #255
        rts
_fo     lda tmp
        rts

; nearest and second nearest opponent of fighter X -> nrst/nrdist/nrside, n2/n2dist/n2side
nearest
        txa
        clc
        adc #1
        cmp #3
        bcc _n1
        sbc #3
_n1     tay
        jsr fdist
        sta nrdist
        lda dsgn
        sta nrside
        sty nrst
        txa
        clc
        adc #2
        cmp #3
        bcc _n2
        sbc #3
_n2     tay
        jsr fdist
        sta n2dist
        lda dsgn
        sta n2side
        sty n2
        lda n2dist
        cmp nrdist
        bcs _nd
        lda nrdist              ; the second one is closer: swap
        ldy n2dist
        sty nrdist
        sta n2dist
        lda nrside
        ldy n2side
        sty nrside
        sta n2side
        lda nrst
        ldy n2
        sty nrst
        sta n2
_nd     rts

; move fighter X by tmp3 pixels, mvd = 0 right / 1 left. Keeps to the arena, no overlapping.
movex
        stx fi
        lda fxl,x
        sta tmpx
        lda fxh,x
        sta tmpy
        lda mvd
        bne _ml
        clc
        lda tmpx
        adc tmp3
        sta tmpx
        lda tmpy
        adc #0
        sta tmpy
        jmp _mb
_ml     sec
        lda tmpx
        sbc tmp3
        sta tmpx
        lda tmpy
        sbc #0
        sta tmpy
_mb     lda tmpy                ; arena 24 .. 296
        bmi _mno
        bne _mhi
        lda tmpx
        cmp #24
        bcc _mno
        jmp _mcol
_mhi    lda tmpx
        cmp #$29
        bcs _mno
_mcol   lda fy,x
        bne _mok                ; airborne fighters pass through
        ldy #0
_mc1    cpy fi
        beq _mnx
        lda fy,y
        bne _mnx
        sec                     ; distance from the new position
        lda tmpx
        sbc fxl,y
        sta tmp
        lda tmpy
        sbc fxh,y
        sta tmp2
        bcs _mp
        sec
        lda #0
        sbc tmp
        sta tmp
        lda #0
        sbc tmp2
        sta tmp2
_mp     lda tmp2
        bne _mnx
        lda tmp
        cmp #16
        bcs _mnx
        ldx fi                  ; too close: only a problem when walking towards him
        jsr fdist
        ldx fi
        lda dsgn
        cmp mvd
        beq _mno
_mnx    iny
        cpy #3
        bne _mc1
_mok    ldx fi
        lda tmpx
        sta fxl,x
        lda tmpy
        sta fxh,x
_mno    ldx fi
        rts

; face the nearest opponent
facenearest
        jsr nearest
        lda nrside
        sta ffc,x
        rts

; ============================================================================
;  fighter update (X = fighter)
; ============================================================================
fupdate
        lda fst,x
        cmp #S_HIT
        bcc _f0
        jmp _locked
_f0     cmp #S_PUNCH
        bcc _f0b
        jmp _attack
_f0b    cmp #S_JUMP
        bne _free
        jmp _air
_free   jsr facenearest
        lda fctl,x
        and #CF
        beq _nofire
        lda ffc,x               ; tw = control bit of "towards the opponent"
        beq _fr
        lda #CL
        bne _fs
_fr     lda #CR
_fs     sta tw
        lda fctl,x
        and #CD
        beq _f1
        lda #S_SWEEP
        jmp startatk
_f1     lda fctl,x
        and #CU
        beq _f2
        lda #S_FLY
        jsr startatk
        lda #0
        sta fjt,x
        rts
_f2     lda fctl,x
        and tw
        beq _f3
        lda #S_KICK
        jmp startatk
_f3     lda fctl,x
        and #(CL|CR)
        beq _f4
        lda #S_BACK
        jmp startatk
_f4     lda #S_PUNCH
        jmp startatk
_nofire lda fctl,x
        and #CU
        beq _nj
        lda #S_JUMP
        sta fst,x
        lda #0
        sta fjt,x
        rts
_nj     lda fctl,x
        and #CD
        beq _nc
        lda #S_CROUCH
        sta fst,x
        rts
_nc     lda fctl,x
        and #(CL|CR)
        beq _idle
        and #CL
        beq _wr
        lda #1
        bne _wm
_wr     lda #0
_wm     sta mvd
        lda #S_WALK
        sta fst,x
        lda #2
        sta tmp3
        jmp movex
_idle   lda #S_IDLE
        sta fst,x
        rts

_attack                         ; running attack
        cmp #S_FLY
        beq _flyatk
        inc ftm,x
        sec
        sbc #S_PUNCH
        tay
        lda ftm,x
        cmp aact0,y
        bcc _na
        cmp aact1,y
        bcs _na
        sty atype
        jsr hitscan
        ldx fi
        ldy atype
_na     lda ftm,x
        cmp adur,y
        bcc _ax
        lda #S_IDLE
        sta fst,x
        lda #0
        sta ftm,x
_ax     rts
_flyatk jsr airstep
        lda ffc,x               ; fly forward
        sta mvd
        lda #3
        sta tmp3
        jsr movex
        ldx fi
        lda fst,x
        cmp #S_FLY
        bne _fx
        lda ftm,x
        cmp #3
        bcc _fx
        lda #3
        sta atype
        jsr hitscan
        ldx fi
_fx     rts

_air    lda fctl,x              ; jump: fire turns it into a flying kick
        and #CF
        beq _a1
        lda #S_FLY
        sta fst,x
        lda #0
        sta ftm,x
        sta fhit,x
        txa
        pha
        ldx #SFX_PUNCH
        jsr sfx_start
        pla
        tax
        rts
_a1     lda fctl,x              ; air control
        and #CL
        beq _a2
        lda #1
        sta mvd
        lda #2
        sta tmp3
        jsr movex
_a2     ldx fi
        lda fctl,x
        and #CR
        beq _a3
        lda #0
        sta mvd
        lda #2
        sta tmp3
        jsr movex
_a3     ldx fi
        jmp airstep

_locked                         ; hit / fall / get up / win
        lda fkb,x               ; knock back
        beq _lk
        dec fkb,x
        dec fkb,x
        lda fkd,x
        sta mvd
        lda #2
        sta tmp3
        jsr movex
        ldx fi
_lk     lda fst,x
        cmp #S_WIN
        beq _lx
        inc ftm,x
        cmp #S_HIT
        bne _l2
        lda ftm,x
        cmp #12
        bcc _lx
        jmp tofree
_l2     cmp #S_FALL
        bne _l3
        lda ftm,x
        cmp #40
        bcc _lx
        lda #S_GETUP
        sta fst,x
        lda #0
        sta ftm,x
        rts
_l3     lda ftm,x               ; get up
        cmp #20
        bcc _lx
        jmp tofree
_lx     rts

tofree  lda #S_IDLE
        sta fst,x
        lda #0
        sta ftm,x
        rts

; jump arc: height from the table, landing ends the jump / flying kick
airstep
        inc fjt,x
        inc ftm,x
        lda fjt,x
        cmp #JUMP_LEN
        bcc _as1
        lda #0
        sta fy,x
        sta fjt,x
        jmp tofree
_as1    tay
        lda jumptab,y
        sta fy,x
        rts

; A = attack state: start it and play the sound
startatk
        sta fst,x
        lda #0
        sta ftm,x
        sta fhit,x
        txa
        pha
        lda fst,x
        cmp #S_PUNCH
        beq _sp
        ldx #SFX_KICK
        bne _ss
_sp     ldx #SFX_PUNCH
_ss     jsr sfx_start
        pla
        tax
        rts

; ---- hit detection: attacker X, attack type atype ----
hitscan
        stx fi
        ldy #0
_hv     sty vv
        cpy fi
        beq _hn
        ldx vv
        lda fst,x               ; stance of the victim
        tay
        lda stance,y
        ldy atype
        and amask,y
        beq _hn
        ldx fi
        lda fhit,x
        ldy vv
        and bitm,y
        bne _hn                 ; already hit
        ldy vv
        jsr fdist               ; X = attacker, Y = victim
        sta tmp3
        ldx fi
        ldy atype
        lda ffc,x               ; side the attack goes to
        eor aback,y
        cmp dsgn
        bne _hn
        lda tmp3
        cmp #4
        bcc _hn
        ldy atype
        cmp areach,y
        bcs _hn
        jsr applyhit
_hn     ldy vv
        iny
        cpy #3
        bne _hv
        ldx fi
        rts

; attacker fi hit victim vv with atype
applyhit
        ldx fi
        ldy vv
        lda fhit,x
        ora bitm,y
        sta fhit,x
        ldy atype
        lda admg,y
        clc
        adc fsc,x
        sta fsc,x
        ldx vv                  ; victim reaction
        lda dsgn
        sta fkd,x               ; knock away from the attacker
        ldy atype
        lda admg,y
        cmp #2
        bcs _fall
        lda #S_HIT
        sta fst,x
        lda #6
        sta fkb,x
        ldy #SFX_HIT
        bne _ah
_fall   lda #S_FALL
        sta fst,x
        lda #14
        sta fkb,x
        ldy #SFX_FALL
_ah     lda #0
        sta ftm,x
        sta fjt,x
        sta fy,x
        sty tmp
        lda fxl,x               ; spark where it hits
        sta sparkxl
        lda fxh,x
        sta sparkxh
        lda #GROUNDY + 14
        sta sparky
        lda #8
        sta sparkt
        ldx tmp
        jmp sfx_start

; ============================================================================
;  computer fighters (X = 0..2, controls fctl,x)
; ============================================================================
; actions: 0 wait, 1 approach, 2 retreat, 3 crouch, 4 jump, 5 punch, 6 kick, 7 sweep,
;          8 back kick, 9 flying kick
ai
        stx fi
        lda #0
        sta fctl,x
        lda fst,x
        cmp #S_PUNCH
        bcc _ai0
        rts                     ; busy: attacking or hurt
_ai0    jsr nearest
        ldy nrst                ; react to an incoming attack of the nearest fighter
        lda fst,y
        cmp #S_PUNCH
        bcc _noreact
        cmp #S_HIT
        bcs _noreact
        lda nrdist
        cmp #44
        bcs _noreact
        jsr getrnd
        ldy stage
        cmp react,y
        bcs _noreact
        ldy nrst
        lda fst,y
        cmp #S_SWEEP
        beq _jmp
        lda #3                  ; duck under punches and kicks
        bne _rset
_jmp    lda #4                  ; jump over a sweep
_rset   sta fai,x
        lda #14
        sta fait,x
_noreact
        lda fait,x
        beq _choose
        dec fait,x
        jmp _apply
_choose jsr aichoose
_apply  ldx fi
        lda fai,x
        asl a
        tay
        lda aijt+1,y
        pha
        lda aijt,y
        pha
        rts
aijt    .word a_wait-1, a_appr-1, a_retr-1, a_crouch-1, a_jump-1, a_punch-1, a_kick-1
        .word a_sweep-1, a_back-1, a_fly-1

a_wait  rts
a_appr  ldy nrside              ; towards the nearest fighter
        beq _ar
        lda #CL
        bne _as
_ar     lda #CR
_as     sta fctl,x
        rts
a_retr  ldy nrside
        beq _rl
        lda #CR
        bne _rs
_rl     lda #CL
_rs     sta fctl,x
        rts
a_crouch
        lda #CD
        sta fctl,x
        rts
a_jump  lda #CU
        sta fctl,x
        lda #0                  ; one frame is enough
        sta fai,x
        rts
a_punch lda #CF
        bne a_done
a_kick  lda nrside              ; fire + towards the opponent
        beq _kr
        lda #(CF|CL)
        bne a_done
_kr     lda #(CF|CR)
        bne a_done
a_sweep lda #(CF|CD)
        bne a_done
a_back  lda n2side              ; fire + towards the fighter behind
        beq _br
        lda #(CF|CL)
        bne a_done
_br     lda #(CF|CR)
        bne a_done
a_fly   lda #(CF|CU)
a_done  sta fctl,x
        lda #0
        sta fai,x
        jsr getrnd
        and #15
        clc
        adc #10
        sta fait,x
        rts

aichoose
        jsr getrnd
        sta tmp
        ldy stage
        lda nrdist
        cmp #46
        bcs _far
        lda n2dist              ; someone right behind us?
        cmp #36
        bcs _nb
        lda nrside
        cmp n2side
        beq _nb
        lda tmp
        cmp #80
        bcs _nb
        lda #8
        bne _setf
_nb     lda nrdist
        cmp #28
        bcs _mid
        lda tmp                 ; in range: attack or evade
        cmp aggr,y
        bcs _evade
        jsr getrnd
        and #15
        cmp #6
        bcc _punch
        cmp #10
        bcc _kick
        cmp #13
        bcc _sweep
        lda #9
        bne _setf
_punch  lda #5
        bne _setf
_kick   lda #6
        bne _setf
_sweep  lda #7
        bne _setf
_evade  lda tmp
        and #3
        beq _ev1
        cmp #1
        beq _ev2
        lda #2                  ; step back
        bne _setf
_ev1    lda #3
        bne _setf
_ev2    lda #4
        bne _setf
_mid    lda tmp                 ; a little too far for a punch: kick or close in
        cmp aggr,y
        bcs _wait
        and #1
        beq _appr
        lda #6
        bne _setf
_appr   lda #1
        bne _setf
_far    lda tmp
        cmp #230
        bcs _jumpin
        cmp aggr,y
        bcs _wait
        lda #1
        bne _setf
_jumpin lda #4
        bne _setf
_wait   lda #0
_setf   ldx fi
        sta fai,x
        jsr getrnd
        and #15
        clc
        adc #6
        sta fait,x
        rts

; ============================================================================
;  sprites
; ============================================================================
sparkupd
        lda sparkt
        beq _su
        dec sparkt
_su     rts

; X = sprite number, A = pointer, sxl/sxh/sy = register values
putspr
        pha
        txa
        asl a
        tay
        lda sxl
        sta $d000,y
        lda sy
        sta $d001,y
        lda sxh
        beq _ps1
        lda sprbit,x
        ora msbacc
        sta msbacc
_ps1    lda sprbit,x
        ora enacc
        sta enacc
        pla
        sta $07f8,x
        rts

sprbit  .byte 1, 2, 4, 8, 16, 32, 64, 128

; sprite pointer and x/y registers for fighter X at (xcentre, ground - fy): sets tmp3 = pointer
fighterspr
        ldy fst,x
        lda stpose,y
        cpy #S_IDLE
        bne _u1
        lda frame
        lsr a
        lsr a
        lsr a
        lsr a
        and #1
        jmp _u3
_u1     cpy #S_WALK
        bne _u3
        lda frame
        lsr a
        lsr a
        and #1
        clc
        adc #2
_u3     sta tmp                 ; pose
        lda ffc,x
        cpy #S_BACK
        bne _u4
        eor #1                  ; back kick: the leg goes behind
_u4     sta tmp2                ; drawing facing
        lda tmp                 ; pointer = $a0 + (pose*2 + facing) * 2
        asl a
        clc
        adc tmp2
        asl a
        clc
        adc #$a0
        sta tmp3
        ldy tmp                 ; x = centre - anchor + 24
        lda tmp2
        bne _u5
        lda anchor0,y
        jmp _u6
_u5     lda anchor1,y
_u6     sta tmpx
        sec
        lda fxl,x
        sbc tmpx
        sta sxl
        lda fxh,x
        sbc #0
        sta sxh
        clc
        lda sxl
        adc #24
        sta sxl
        bcc _u7
        inc sxh
_u7     sec                     ; y = ground - height
        lda #GROUNDY
        sbc fy,x
        sta sy
        rts

updsprites
        lda #0
        sta msbacc
        sta enacc
        ldx #0
_uf     stx fi
        jsr fighterspr
        lda fi
        asl a
        tax                     ; sprite number of the upper half
        lda tmp3
        jsr putspr
        ldx fi
        txa
        asl a
        tax
        inx
        clc
        lda sy
        adc #21
        sta sy
        lda tmp3
        clc
        adc #1
        jsr putspr
        ldx fi
        inx
        cpx #3
        beq _ufd
        jmp _uf
_ufd    lda sparkt              ; spark (sprite 6)
        beq _us
        sec
        lda sparkxl
        sbc #8
        sta sxl
        lda sparkxh
        sbc #0
        sta sxh
        clc
        lda sxl
        adc #24
        sta sxl
        bcc _us1
        inc sxh
_us1    lda sparky
        sta sy
        lda sparkt
        and #2
        beq _us2
        lda #BLK_SPARK1
        bne _us3
_us2    lda #BLK_SPARK2
_us3    ldx #6
        jsr putspr
_us     lda msbacc
        sta $d010
        lda enacc
        sta $d015
        rts

; ============================================================================
;  bonus round: block the flying balls
; ============================================================================
newbonus
        jsr skygame
        jsr clearscreen
        jsr drawbg
        jsr drawhudstatic
        ldx #<str_bonus
        ldy #>str_bonus
        jsr drawstr
        lda #0
        sta fst
        sta fy
        sta fxh
        sta ftm
        sta fkb
        sta fsc
        sta fsc+1
        sta fsc+2
        sta bon
        sta blocked
        sta missed
        sta bhurt
        sta sparkt
        lda #160
        sta fxl
        lda #10
        sta nballs
        lda #60
        sta bwait
        lda #0
        sta ffc
        lda fcolor
        sta $d027
        sta $d028
        lda #1
        sta $d02d               ; ball
        lda #14
        sta $d02e               ; shield
        lda #ST_BONUS
        sta state
        ldx #SFX_START
        jmp sfx_start

st_bonus
        lda #0                  ; shield side from the input
        sta shside
        lda inl
        beq _b1
        lda #1
        sta shside
_b1     lda inr
        beq _b2
        lda #2
        sta shside
_b2     lda #1                  ; shield height
        sta shhgt
        lda inu
        beq _b3
        lda #0
        sta shhgt
_b3     lda ind
        beq _b4
        lda #2
        sta shhgt
_b4     lda bon
        bne _fly
        lda bwait
        beq _launch
        dec bwait
        jmp _show
_launch lda nballs
        bne _l1
        jmp bonusdone
_l1     dec nballs
        jsr getrnd
        and #1
        sta bside
        jsr getrnd
        and #3
        cmp #3
        bcc _l2
        lda #1
_l2     sta bhgt
        lda bside
        bne _l3
        lda #12
        sta bxl
        lda #0
        sta bxh
        beq _l4
_l3     lda #<308
        sta bxl
        lda #>308
        sta bxh
_l4     lda #1
        sta bon
        jmp _show
_fly    lda bside               ; move towards the player
        bne _fl
        clc
        lda bxl
        adc #3
        sta bxl
        lda bxh
        adc #0
        sta bxh
        jmp _fc
_fl     sec
        lda bxl
        sbc #3
        sta bxl
        lda bxh
        sbc #0
        sta bxh
_fc     lda bxh                 ; distance to the player at x = 160
        bne _fh
        lda bxl
        cmp #160
        bcs _fa
        sta tmp
        sec
        lda #160
        sbc tmp
        jmp _fd
_fa     sec
        sbc #160
        jmp _fd
_fh     lda bxl
        clc
        adc #96
_fd     sta tmp
        cmp #40
        bcs _show               ; not there yet
        cmp #12
        bcc _miss
        lda bside               ; in the block zone: right side and height?
        clc
        adc #1
        cmp shside
        bne _show
        lda bhgt
        cmp shhgt
        bne _show
        inc blocked
        lda #0
        sta bon
        lda #40
        sta bwait
        lda #$05
        jsr addhund
        ldx #SFX_BLOCK
        jsr sfx_start
        jmp _show
_miss   inc missed
        lda #0
        sta bon
        lda #40
        sta bwait
        lda #14
        sta bhurt
        ldx #SFX_MISS
        jsr sfx_start
_show   lda #S_IDLE             ; the player
        ldx bhurt
        beq _p1
        dec bhurt
        lda #S_HIT
_p1     sta fst
        jsr updbonus
        jsr drawhud
        rts

; sprites for the bonus round: player (0/1), ball (6), shield (7)
updbonus
        lda #0
        sta msbacc
        sta enacc
        ldx #0
        stx fi
        jsr fighterspr
        ldx #0
        lda tmp3
        jsr putspr
        clc
        lda sy
        adc #21
        sta sy
        ldx #1
        lda tmp3
        clc
        adc #1
        jsr putspr
        lda bon
        beq _nb
        clc
        lda bxl
        adc #18                 ; centre - 6 + 24
        sta sxl
        lda bxh
        adc #0
        sta sxh
        ldy bhgt
        lda bally,y
        sta sy
        ldx #6
        lda #BLK_BALL
        jsr putspr
_nb     lda shside              ; shield
        beq _ns
        cmp #1
        bne _sr
        lda #(160-34+24)
        bne _sl
_sr     lda #(160+26+24)
_sl     sta sxl
        lda #0
        sta sxh
        ldy shhgt
        lda bally,y
        sta sy
        ldx #7
        lda #BLK_SHIELD
        jsr putspr
_ns     lda msbacc
        sta $d010
        lda enacc
        sta $d015
        rts
bally   .byte GROUNDY+8, GROUNDY+22, GROUNDY+36

bonusdone
        lda missed
        bne _bd
        ldx #<str_perfect
        ldy #>str_perfect
        jsr drawstr
        lda #$50                ; 5000 bonus
        jsr addhund
        ldx #SFX_WIN
        jsr sfx_start
        jmp _bd2
_bd     ldx #<str_bonusend
        ldy #>str_bonusend
        jsr drawstr
_bd2    lda #ST_BONEND
        sta state
        lda #120
        sta timer
        rts

st_bonend
        jsr drawhud
        dec timer
        bne _be
        jmp newround
_be     rts

; ============================================================================
;  background, hud, text
; ============================================================================
drawbg
        ldx #0                  ; temple scene (rows 2..17, padded to three pages)
_bg     lda bgchar,x
        sta SCREEN + 2*40,x
        lda bgchar + 256,x
        sta SCREEN + 2*40 + 256,x
        lda bgchar + 512,x
        sta SCREEN + 2*40 + 512,x
        lda bgcol,x
        sta COLRAM + 2*40,x
        lda bgcol + 256,x
        sta COLRAM + 2*40 + 256,x
        lda bgcol + 512,x
        sta COLRAM + 2*40 + 512,x
        inx
        bne _bg
        ldy #18                 ; wooden floor: rows 18..24
_fr     lda rlo,y
        sta ptr
        sta cptr
        lda rhi,y
        sta ptr+1
        lda rchi,y
        sta cptr+1
        sty tmp
        ldx #39
_fc2    txa
        clc
        adc tmp
        and #3
        beq _fk
        lda #$60                ; plank
        bne _fs
_fk     lda #$61                ; plank with a knot
_fs     sta tmp2
        txa
        tay
        lda tmp2
        sta (ptr),y
        lda #8
        sta (cptr),y
        dex
        bpl _fc2
        ldy tmp
        iny
        cpy #25
        bne _fr
        rts

drawhudstatic
        ldx #<str_h_you
        ldy #>str_h_you
        jsr drawstr
        ldx #<str_h_red
        ldy #>str_h_red
        jsr drawstr
        ldx #<str_h_blu
        ldy #>str_h_blu
        jsr drawstr
        ldx #<str_h_time
        ldy #>str_h_time
        jsr drawstr
        ldx #<str_h_round
        ldy #>str_h_round
        jsr drawstr
        ldx #<str_h_belt
        ldy #>str_h_belt
        jsr drawstr
        ldx #<str_h_score
        ldy #>str_h_score
        jmp drawstr

drawhud
        ldx #0                  ; points of the three fighters as d.d
_h1     ldy hudcol,x
        lda fsc,x
        lsr a
        ora #$30
        sta SCREEN,y
        lda #46
        sta SCREEN + 1,y
        lda fsc,x
        and #1
        beq _h2
        lda #$35
        bne _h3
_h2     lda #$30
_h3     sta SCREEN + 2,y
        inx
        cpx #3
        bne _h1
        lda rtime               ; time
        jsr dec2
        sta SCREEN + 36
        stx SCREEN + 35
        lda rnum                ; round number
        jsr dec2
        sta SCREEN + 40 + 8
        stx SCREEN + 40 + 7
        lda stage               ; belt name (6 characters)
        asl a
        sta tmp
        asl a
        clc
        adc tmp
        tax
        ldy #0
_hb     lda beltname,x
        sta SCREEN + 40 + 15,y
        inx
        iny
        cpy #6
        bne _hb
        ldx stage
        lda beltcol,x
        ldy #5
_hc     sta COLRAM + 40 + 15,y
        dey
        bpl _hc
        lda #<(SCREEN + 40 + 30)
        sta dst
        lda #>(SCREEN + 40 + 30)
        sta dst+1
        ldx #score
        jmp bcd3out
hudcol  .byte 5, 15, 25

addscore                        ; A = BCD, added to the low byte
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

addhund                         ; A = BCD added to the 100s/1000s byte
        sed
        clc
        adc score+1
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
;  sound (called from the IRQ)
; ============================================================================
sfx_start                       ; X = effect number, from main code only
        sei
        lda swave,x
        sta sfxw
        and #$fe
        sta $d404
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
        sta $d404
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
        ldx mstep
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
_m1     cmp #1
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
        .include "dojobrawl_data.inc"
        .cerror * > $2800, "code + data overlap the sprite data"

        * = $2800
        .include "dojobrawl_sprites.inc"
        .cerror * > CHARSET, "sprite data overlaps the charset"

        * = $4000               ; read by the CPU only, so it may live outside the VIC bank
        .include "dojobrawl_bg.inc"
