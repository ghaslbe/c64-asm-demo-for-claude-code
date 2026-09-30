; ============================================================================
;  DUNGEON BLAST  -  a maze shooter for the Commodore 64
;  (in the spirit of Wizard of Wor)  Guenther Haslbeck + Claude Code, 2026
;
;  Maze    : 20 x 11 tiles of 16x16 pixels, drawn with 2x2 characters per wall tile
;  Actors  : hardware sprites 0 = player, 1 = player bullet, 2..6 = monsters/wizard,
;            7 = enemy bullet. All movement is tile based (2 pixels per step).
;  Control : joystick port 2, or W A S D, fire = SPACE / RETURN
;  Sound   : SID voice 1 = effects, voice 2 = bass, voice 3 = lead arpeggio
;
;  Assemble with 64tass (see build.py). Tables live in dungeonblast_data.inc.
; ============================================================================
        .cpu "6502"

; ---- game states ----
ST_TITLE = 0
ST_READY = 1
ST_PLAY  = 2
ST_DEAD  = 3
ST_CLEAR = 4
ST_OVER  = 5
ST_PAUSE = 6

; ---- zero page ----
fflag   = $02
frame   = $03
state   = $04
lives   = $05
level   = $06
lvlidx  = $07
mazeidx = $08
wallc   = $09
score   = $0a           ; 3 bytes BCD, low first
hisc    = $0d           ; 3 bytes BCD
inp     = $10           ; input by direction: 0 right, 1 left, 2 down, 3 up
inf     = $14           ; fire
finh    = $15
keyp    = $16
keym    = $17
pprev   = $18
mprev   = $19
timer   = $1a
rnd     = $1b
pface   = $1c           ; direction the player faces
pinv    = $1d           ; invulnerability frames
nalive  = $1e           ; monsters alive
wizmode = $1f           ; 0 no wizard yet, 1 wizard active, 2 wizard beaten
wizt    = $20           ; frames until the wizard teleports
bul     = $21           ; bullet 0 (player) at +0..+4, bullet 1 (enemy) at +5..+9:
                        ; on, xlo, xhi, y, dir
cxl     = $2b           ; centre of an entity
cxh     = $2c
cy      = $2d
qxl     = $2e           ; point to test against
qxh     = $2f
qy      = $30
hrad     = $31
tmp     = $32
tmp2    = $33
tmp3    = $34
tmpx    = $35
tmpy    = $36
col     = $37
scol    = $38
strp    = $39           ; word
dst     = $3b           ; word
ptr     = $3d           ; word
cptr    = $3f           ; word
sxl     = $41
sxh     = $42
sy      = $43
msbacc  = $44
enacc   = $45
mstep   = $46
mfr     = $47
muson   = $48
sfxn    = $49
sfxf    = $4a
sfxs    = $4b
sfxw    = $4c
sfxst   = $4d
anim    = $4e
ei      = $4f
cmd     = $50
cmd2    = $51
cdx     = $52
cdy     = $53
kk      = $54
rr      = $55
wizflash = $56
lp      = $57           ; word
sp      = $59           ; word (spawn table pointer)

; ---- entity arrays (0 = player, 1..5 = monsters / wizard) ----
etx     = $c000         ; tile
ety     = $c008
eox     = $c010         ; pixel offset inside the movement
eoy     = $c018
edir    = $c020         ; 0 right 1 left 2 down 3 up, $ff = standing
etype   = $c028         ; 0 none, 1..3 monsters, 4 wizard
maze    = $c100         ; 20 x 11 tiles, 1 = wall

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
        ldx #31
_g2     lda glyph_walls,x
        sta CHARSET + $60*8,x
        dex
        bpl _g2

        ; ---- sprite shapes (13 blocks = 832 bytes) ----
        ldx #0
_sd     lda sprites,x
        sta SPRDATA,x
        lda sprites + 256,x
        sta SPRDATA + 256,x
        lda sprites + 512,x
        sta SPRDATA + 512,x
        inx
        bne _sd
        ldx #63
_sd2    lda sprites + 768,x
        sta SPRDATA + 768,x
        dex
        bpl _sd2

        ; ---- VIC ----
        lda #$1c
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
        sta $d017
        sta $d01d
        lda #7
        sta $d027               ; player
        lda #1
        sta $d028               ; player bullet
        lda #10
        sta $d02e               ; enemy bullet

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
        sta wizflash
        sta bul
        sta bul+5
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
jump    .word st_title-1, st_ready-1, st_play-1, st_dead-1, st_clear-1, st_over-1, st_pause-1

getrnd                          ; 8 bit LFSR, returns A, keeps X/Y
        lda rnd
        asl a
        bcc _r1
        eor #$1d
_r1     sta rnd
        rts

; ---- title ----
to_title
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
        lda #<(SCREEN + 24*40 + HI_DIGITS_COL)
        sta dst
        lda #>(SCREEN + 24*40 + HI_DIGITS_COL)
        sta dst+1
        ldx #hisc
        jsr bcd3out
        rts

st_title
        lda #0                  ; rainbow logo, one row per step
        sta rr
_tr     ldx rr
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
        inc rr
        lda rr
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
        lda frame               ; a little entropy for the getrnd numbers
        eor rnd
        ora #1
        sta rnd
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
        lda level               ; lvlidx = min(level-1, NLEVELS-1), mazeidx = (level-1) mod 4
        sec
        sbc #1
        pha
        and #3
        sta mazeidx
        pla
        cmp #NLEVELS
        bcc _li
        lda #NLEVELS-1
_li     sta lvlidx
        ldx mazeidx
        lda mazecol,x
        sta wallc
        lda mazelo,x
        sta lp
        lda mazehi,x
        sta lp+1
        ldy #0
_mc     lda (lp),y              ; copy the 220 maze tiles into RAM
        sta maze,y
        iny
        cpy #220
        bne _mc
        jsr clearscreen
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
        jsr drawmaze

        ; actors
        lda lvlidx              ; enemy row = lvlidx * 5
        asl a
        asl a
        clc
        adc lvlidx
        sta tmp
        ldx mazeidx
        lda spawnlo,x
        sta sp
        lda spawnhi,x
        sta sp+1
        lda #0
        sta nalive
        sta wizmode
        sta wizflash
        sta bul
        sta bul+5
        ldx #1
_sp     stx ei
        lda tmp
        clc
        adc ei
        tay
        dey                     ; entity 1 -> first entry
        ldx ei
        lda lvlenemy,y
        sta etype,x
        beq _spn
        inc nalive
        txa
        asl a
        tay
        dey
        dey                     ; (entity-1)*2
        lda (sp),y
        sta etx,x
        iny
        lda (sp),y
        sta ety,x
        lda #0
        sta eox,x
        sta eoy,x
        lda #$ff
        sta edir,x
_spn    inx
        cpx #6
        bne _sp
        jsr placeplayer
        lda #90
        sta timer
        lda #ST_READY
        sta state
        ldx #<str_ready
        ldy #>str_ready
        jsr drawstr
        ldx #SFX_START
        jmp sfx_start

placeplayer
        lda #STARTX
        sta etx
        lda #STARTY
        sta ety
        lda #0
        sta eox
        sta eoy
        sta pface
        sta bul
        sta bul+5
        lda #$ff
        sta edir
        rts

; ---- draw the maze: each wall tile is 2x2 characters ----
drawmaze
        lda #0
        sta rr
_dr     lda rr
        asl a
        clc
        adc #2
        tax
        lda rlo,x
        sta ptr
        sta cptr
        lda rhi,x
        sta ptr+1
        lda rchi,x
        sta cptr+1
        lda rlo+1,x
        sta dst
        sta strp
        lda rhi+1,x
        sta dst+1
        lda rchi+1,x
        sta strp+1
        ldx rr
        lda row20,x
        sta tmp3
        lda #0
        sta kk
_dt     lda tmp3
        clc
        adc kk
        tax
        lda maze,x
        beq _dn
        lda kk
        asl a
        tay
        lda #$60
        sta (ptr),y
        lda #$62
        sta (dst),y
        lda wallc
        sta (cptr),y
        sta (strp),y
        iny
        lda #$61
        sta (ptr),y
        lda #$63
        sta (dst),y
        lda wallc
        sta (cptr),y
        sta (strp),y
_dn     inc kk
        lda kk
        cmp #20
        bne _dt
        inc rr
        lda rr
        cmp #11
        bne _dr
        rts

; ---- ready ----
st_ready
        jsr updsprites
        jsr drawhud
        dec timer
        bne _rx
        jsr clrmsg
        lda #ST_PLAY
        sta state
_rx     rts

; ---- play ----
st_play
        jsr playerupdate
        jsr playerfire
        lda #4
        ldx #0
        jsr bulletmove
        bcc _nb
        jsr playerbullethit
_nb     jsr enemies
        lda #3
        ldx #5
        jsr bulletmove
        bcc _nb2
        jsr enemybullethit
_nb2    jsr touch
        lda pinv
        beq _iv
        dec pinv
_iv     lda wizflash
        beq _wf
        dec wizflash
_wf     jsr wavecheck
        jsr updsprites
        jsr drawhud
        rts

; the level is over when all monsters and the wizard are gone
wavecheck
        lda state
        cmp #ST_PLAY
        bne _wx
        lda nalive
        bne _wx
        lda wizmode
        bne _w1
        lda #1                  ; monsters gone: the wizard appears
        sta wizmode
        jsr clrmsg
        ldx #1
        lda #4
        sta etype,x
        jsr teleport
        ldx #<str_wizard
        ldy #>str_wizard
        jsr drawstr
        ldx #SFX_WIZ
        jmp sfx_start
_w1     cmp #2
        bne _wx
        jsr clrmsg
        ldx #<str_cleared
        ldy #>str_cleared
        jsr drawstr
        ldx #SFX_LEVEL
        jsr sfx_start
        lda #100
        sta timer
        lda #ST_CLEAR
        sta state
_wx     rts

st_clear
        jsr updsprites
        jsr drawhud
        dec timer
        bne _cx
        inc level
        jmp newlevel
_cx     rts

st_dead
        jsr updsprites
        jsr drawhud
        dec timer
        bne _dx
        lda lives
        beq _over
        jsr placeplayer
        lda #150
        sta pinv
        lda #ST_PLAY
        sta state
        jsr clrmsg
        rts
_over   jsr hiscore
        jsr drawhud
        ldx #<str_gameover
        ldy #>str_gameover
        jsr drawstr
        lda #180
        sta timer
        lda #ST_OVER
        sta state
_dx     rts

st_over
        jsr updsprites
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
        jsr clrmsg
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
        lda $dc00               ; joystick port 2, 0 = pressed
        sta tmp
        lda #0
        sta inp
        sta inp+1
        sta inp+2
        sta inp+3
        sta inf
        sta keyp
        sta keym
        lda tmp
        and #$01
        bne _j1
        inc inp+3               ; up
_j1     lda tmp
        and #$02
        bne _j2
        inc inp+2               ; down
_j2     lda tmp
        and #$04
        bne _j3
        inc inp+1               ; left
_j3     lda tmp
        and #$08
        bne _j4
        inc inp                 ; right
_j4     lda tmp
        and #$10
        bne _j5
        inc inf
_j5     lda #$fd                ; column 1: W A S
        sta $dc00
        lda $dc01
        sta tmp
        and #$02
        bne _k1
        inc inp+3
_k1     lda tmp
        and #$04
        bne _k2
        inc inp+1
_k2     lda tmp
        and #$20
        bne _k3
        inc inp+2
_k3     lda #$fb                ; column 2: D
        sta $dc00
        lda $dc01
        and #$04
        bne _k4
        inc inp
_k4     lda #$df                ; column 5: P
        sta $dc00
        lda $dc01
        and #$02
        bne _k5
        inc keyp
_k5     lda #$ef                ; column 4: M
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
        jsr bot
        .endif
        rts

        .if AUTOPLAY != 0
; test bot: hunts the first living monster and shoots all the time
bot
        lda #0
        sta inp
        sta inp+1
        sta inp+2
        sta inp+3
        lda frame
        lsr a
        and #1
        sta inf
        lda state
        cmp #ST_PLAY
        bne _bx
        ldx #1
_bf     lda etype,x
        bne _bg
        inx
        cpx #6
        bne _bf
        rts
_bg     lda etx,x               ; dx, dy in tiles
        sec
        sbc etx
        sta tmpx
        lda ety,x
        sec
        sbc ety
        sta tmpy
        lda frame
        and #16
        beq _bh
        lda tmpx                ; horizontal preferred
        beq _bv
        bmi _bl
        inc inp
        rts
_bl     inc inp+1
        rts
_bh     lda tmpy                ; vertical preferred
        beq _bhz
        bmi _bu
        inc inp+2
        rts
_bu     inc inp+3
        rts
_bhz    lda tmpx
        bmi _bl
        inc inp
        rts
_bv     lda tmpy
        bmi _bu
        inc inp+2
_bx     rts
        .endif

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
;  movement primitives (X = entity)
; ============================================================================
; C=1 if the tile next to entity X in direction Y is free. Keeps X and Y.
canmove
        sty cmd
        lda etx,x
        clc
        adc dxt,y
        bpl _p
        lda #19                 ; left tunnel -> right side
        bne _nx
_p      cmp #20
        bcc _nx
        lda #0                  ; right tunnel -> left side
_nx     sta tmpx
        lda ety,x
        clc
        adc dyt,y
        bmi _blk
        cmp #11
        bcs _blk
        tay
        lda row20,y
        clc
        adc tmpx
        tay
        lda maze,y
        bne _blk
        ldy cmd
        sec
        rts
_blk    ldy cmd
        clc
        rts

; move entity X by A pixels (2) in its direction, keeping tile + offset consistent
stepent
        sta tmp3
        ldy edir,x
        bmi _sx
        cpy #2
        bcs _vert
        cpy #1
        beq _left
        lda eox,x               ; right
        clc
        adc tmp3
        cmp #16
        bcc _rok
        sbc #16
        sta eox,x
        inc etx,x
        lda etx,x
        cmp #20
        bcc _sx
        lda #0
        sta etx,x
        rts
_rok    sta eox,x
        rts
_left   lda eox,x
        sec
        sbc tmp3
        bpl _lok
        clc
        adc #16
        sta eox,x
        dec etx,x
        bpl _sx
        lda #19
        sta etx,x
        rts
_lok    sta eox,x
        rts
_vert   cpy #3
        beq _up
        lda eoy,x               ; down
        clc
        adc tmp3
        cmp #16
        bcc _dok
        sbc #16
        sta eoy,x
        inc ety,x
        rts
_dok    sta eoy,x
        rts
_up     lda eoy,x
        sec
        sbc tmp3
        bpl _uok
        clc
        adc #16
        sta eoy,x
        dec ety,x
        rts
_uok    sta eoy,x
_sx     rts

; centre pixel of entity X -> cxl/cxh/cy. Keeps X.
entcenter
        ldy etx,x
        clc
        lda t16lo,y
        adc eox,x
        sta cxl
        lda t16hi,y
        adc #0
        sta cxh
        clc
        lda cxl
        adc #8
        sta cxl
        bcc _e1
        inc cxh
_e1     ldy ety,x
        clc
        lda y16,y
        adc eoy,x
        adc #8
        sta cy
        rts

; top-left of entity X as sprite register values -> sxl/sxh (+24), sy (+66)
entpos
        ldy etx,x
        clc
        lda t16lo,y
        adc eox,x
        sta sxl
        lda t16hi,y
        adc #0
        sta sxh
        clc
        lda sxl
        adc #24
        sta sxl
        bcc _p1
        inc sxh
_p1     ldy ety,x
        clc
        lda y16,y
        adc eoy,x
        adc #66
        sta sy
        rts

; C=1 if the point (qx,qy) is closer than hrad to the centre (cx,cy) on both axes
hitcheck
        lda cxl
        sec
        sbc qxl
        sta tmp
        lda cxh
        sbc qxh
        sta tmp2
        bcs _h1
        sec
        lda #0
        sbc tmp
        sta tmp
        lda #0
        sbc tmp2
        sta tmp2
_h1     lda tmp2
        bne _far
        lda tmp
        cmp hrad
        bcs _far
        lda cy
        sec
        sbc qy
        bcs _h2
        eor #$ff
        adc #1
_h2     cmp hrad
        bcs _far
        sec
        rts
_far    clc
        rts

; ============================================================================
;  player
; ============================================================================
playerupdate
        ldx #0
        lda eox
        ora eoy
        bne _mid
        jsr choosedir
_mid    lda edir
        bmi _px
        tay
        lda inp,y               ; still pushing the current direction?
        bne _go
        tya
        eor #1
        tay
        lda inp,y               ; pushing the opposite one: turn around
        beq _go
        sty edir
        sty pface
_go     ldx #0
        lda #2
        jsr stepent
_px     rts

; at a tile centre: pick the pushed direction (turning has priority)
choosedir
        ldy #0
_c1     cpy pface
        beq _c1n
        lda inp,y
        beq _c1n
        jsr canmove
        bcs _cset
_c1n    iny
        cpy #4
        bne _c1
        ldy pface
        lda inp,y
        beq _cnone
        jsr canmove
        bcs _cset
_cnone  lda #$ff
        sta edir
        rts
_cset   sty edir
        sty pface
        rts

playerfire
        lda state
        cmp #ST_PLAY
        bne _pf
        jsr firepress
        bcc _pf
        lda bul
        bne _pf
        ldx #0
        jsr entcenter
        lda cxl
        sta bul+1
        lda cxh
        sta bul+2
        lda cy
        sta bul+3
        lda pface
        sta bul+4
        lda #1
        sta bul
        ldx #SFX_SHOT
        jmp sfx_start
_pf     rts

; move bullet X (0 = player, 5 = enemy) by A pixels; C=1 if it is still flying
bulletmove
        sta tmp3
        lda bul,x
        beq _bx0
        ldy bul+4,x
        cpy #2
        bcs _bv
        cpy #1
        beq _bl
        clc
        lda bul+1,x
        adc tmp3
        sta bul+1,x
        lda bul+2,x
        adc #0
        sta bul+2,x
        jmp _bt
_bl     sec
        lda bul+1,x
        sbc tmp3
        sta bul+1,x
        lda bul+2,x
        sbc #0
        sta bul+2,x
        bmi _boff
        jmp _bt
_bv     cpy #3
        beq _bup
        clc
        lda bul+3,x
        adc tmp3
        sta bul+3,x
        jmp _bt
_bup    sec
        lda bul+3,x
        sbc tmp3
        sta bul+3,x
        bcc _boff
_bt     lda bul+1,x             ; wall check on the tile under the bullet
        lsr a
        lsr a
        lsr a
        lsr a
        sta tmp
        lda bul+2,x
        asl a
        asl a
        asl a
        asl a
        ora tmp
        cmp #20
        bcs _boff
        sta tmpx
        lda bul+3,x
        lsr a
        lsr a
        lsr a
        lsr a
        cmp #11
        bcs _boff
        tay
        lda row20,y
        clc
        adc tmpx
        tay
        lda maze,y
        bne _boff
        sec
        rts
_boff   lda #0
        sta bul,x
_bx0    clc
        rts

playerbullethit
        lda bul+1
        sta qxl
        lda bul+2
        sta qxh
        lda bul+3
        sta qy
        lda #8
        sta hrad
        ldx #1
_pe     lda etype,x
        beq _pen
        jsr entcenter
        jsr hitcheck
        bcc _pen
        jsr killenemy
        lda #0
        sta bul
        rts
_pen    inx
        cpx #6
        bne _pe
        rts

killenemy                       ; X = monster
        lda etype,x
        tay
        lda scorehund,y
        jsr addhund
        cpy #4
        bne _km1
        lda #2                  ; the wizard is beaten
        sta wizmode
        jmp _km2
_km1    dec nalive
_km2    lda #0
        sta etype,x
        txa
        pha
        ldx #SFX_KILL
        jsr sfx_start
        pla
        tax
        rts

enemybullethit
        ldx #0
        jsr entcenter
        lda cxl
        sta qxl
        lda cxh
        sta qxh
        lda cy
        sta qy
        lda bul+6
        sta cxl
        lda bul+7
        sta cxh
        lda bul+8
        sta cy
        lda #7
        sta hrad
        jsr hitcheck
        bcc _ebx
        lda #0
        sta bul+5
        jmp playerhit
_ebx    rts

; monsters touching the player
touch
        lda state
        cmp #ST_PLAY
        bne _tx
        ldx #0
        jsr entcenter
        lda cxl
        sta qxl
        lda cxh
        sta qxh
        lda cy
        sta qy
        lda #10
        sta hrad
        ldx #1
_tl     lda etype,x
        beq _tn
        jsr entcenter
        jsr hitcheck
        bcc _tn
        jmp playerhit
_tn     inx
        cpx #6
        bne _tl
_tx     rts

playerhit
        .if AUTOPLAY == 2
        rts                     ; test mode: the bot cannot die
        .endif
        lda pinv
        bne _phx
        lda state
        cmp #ST_PLAY
        bne _phx
        dec lives
        lda #ST_DEAD
        sta state
        lda #90
        sta timer
        lda #0
        sta bul
        sta bul+5
        ldx #SFX_DIE
        jmp sfx_start
_phx    rts

; ============================================================================
;  monsters
; ============================================================================
enemies
        ldx #1
_el     stx ei
        lda etype,x
        bne _ea
        jmp _en
_ea     cmp #4
        bne _nw
        dec wizt                ; the wizard teleports every now and then
        bne _nw
        jsr teleport
        ldx ei
_nw     lda eox,x
        ora eoy,x
        bne _mv
        jsr ai
        ldx ei
        jsr eshoot
        ldx ei
_mv     lda etype,x
        asl a
        asl a
        sta tmp
        lda frame
        clc
        adc ei
        and #3
        ora tmp
        tay
        lda gate,y
        beq _en
        lda edir,x
        bmi _en
        lda #2
        jsr stepent
_en     ldx ei
        inx
        cpx #6
        bne _el
        rts

; wizard: jump to a getrnd floor tile at least 5 tiles away from the player
teleport
        lda #40
        sta tmp2
_tl     jsr getrnd
        and #31
        cmp #20
        bcs _tr
        sta tmpx
        jsr getrnd
        and #15
        cmp #11
        bcs _tr
        sta tmpy
        tay
        lda row20,y
        clc
        adc tmpx
        tay
        lda maze,y
        bne _tr
        lda tmpx                ; |dx| + |dy| >= 5
        sec
        sbc etx
        bcs _t1
        eor #$ff
        adc #1
_t1     sta tmp
        lda tmpy
        sec
        sbc ety
        bcs _t2
        eor #$ff
        adc #1
_t2     clc
        adc tmp
        cmp #5
        bcs _tok
_tr     dec tmp2
        bne _tl
        rts                     ; no luck: stay where we are
_tok    ldx #1
        lda tmpx
        sta etx,x
        lda tmpy
        sta ety,x
        lda #0
        sta eox,x
        sta eoy,x
        lda #$ff
        sta edir,x
        lda #100
        sta wizt
        lda #8
        sta wizflash
        ldx #SFX_TELE
        jmp sfx_start

; try direction Y for entity X (never straight back). C=1 and edir set on success
trydir
        cpy #$ff
        beq _no
        lda edir,x
        bmi _ok1
        eor #1
        sta cmd2
        cpy cmd2
        beq _no
_ok1    jsr canmove
        bcc _no
        tya
        sta edir,x
        sec
        rts
_no     clc
        rts

; choose the next direction at a tile centre
ai
        jsr getrnd
        sta tmp
        ldy lvlidx
        lda chase,y
        sta tmp3
        lda etype,x
        cmp #4
        bne _a1
        lda #210
        sta tmp3
_a1     lda tmp
        cmp tmp3
        bcs _rnd
        lda etx                 ; direction towards the player
        sec
        sbc etx,x
        sta tmpx
        lda ety
        sec
        sbc ety,x
        sta tmpy
        lda #$ff
        sta cdx
        sta cdy
        lda tmpx
        beq _a2
        ldy #0
        bpl _a3
        ldy #1
_a3     sty cdx
_a2     lda tmpy
        beq _a4
        ldy #2
        bpl _a5
        ldy #3
_a5     sty cdy
_a4     lda tmpx                ; |dx| >= |dy| ? horizontal first
        bpl _a6
        eor #$ff
        clc
        adc #1
_a6     sta tmp
        lda tmpy
        bpl _a7
        eor #$ff
        clc
        adc #1
_a7     cmp tmp
        beq _hf
        bcs _vf
_hf     ldy cdx
        jsr trydir
        bcs _done
        ldy cdy
        jsr trydir
        bcs _done
        jmp _rnd
_vf     ldy cdy
        jsr trydir
        bcs _done
        ldy cdx
        jsr trydir
        bcs _done
_rnd    lda #8
        sta tmp2
_rl     jsr getrnd
        and #3
        tay
        jsr trydir
        bcs _done
        dec tmp2
        bne _rl
        ldy #0                  ; dead end: any direction, even back
_fl     jsr canmove
        bcs _fset
        iny
        cpy #4
        bne _fl
        lda #$ff
        sta edir,x
        rts
_fset   tya
        sta edir,x
_done   rts

; shoot at the player if lined up in a row or column with nothing in between
eshoot
        lda bul+5
        bne _es_x
        lda pinv
        bne _es_x
        lda state
        cmp #ST_PLAY
        bne _es_x
        jsr getrnd
        ldy lvlidx
        cmp shootp,y
        bcs _es_x
        lda ety,x
        cmp ety
        bne _ecol
        lda etx,x               ; same row
        cmp etx
        beq _es_x
        bcc _eright
        lda #1
        bne _echk
_eright lda #0
        beq _echk
_ecol   lda etx,x               ; same column?
        cmp etx
        bne _es_x
        lda ety,x
        cmp ety
        beq _es_x
        bcc _edown
        lda #3
        bne _echk
_edown  lda #2
_echk   sta cdx
        jsr lineclear
        bcc _es_x
        stx ei
        jsr entcenter
        lda cxl
        sta bul+6
        lda cxh
        sta bul+7
        lda cy
        sta bul+8
        lda cdx
        sta bul+9
        lda #1
        sta bul+5
        ldx #SFX_ESHOT
        jsr sfx_start
        ldx ei
_es_x   rts

; C=1 if no wall lies between entity X and the player tile, walking in direction cdx
lineclear
        lda etx,x
        sta tmpx
        lda ety,x
        sta tmpy
_lw     ldy cdx
        lda tmpx
        clc
        adc dxt,y
        sta tmpx
        lda tmpy
        clc
        adc dyt,y
        sta tmpy
        lda tmpx
        cmp etx
        bne _lm
        lda tmpy
        cmp ety
        beq _lc
_lm     ldy tmpy
        lda row20,y
        clc
        adc tmpx
        tay
        lda maze,y
        bne _lb
        jmp _lw
_lc     sec
        rts
_lb     clc
        rts

; ============================================================================
;  sprites
; ============================================================================
; X = sprite number, A = shape pointer; sxl/sxh/sy = register values
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

updsprites
        lda #0
        sta msbacc
        sta enacc
        lda frame
        lsr a
        lsr a
        lsr a
        and #1
        sta anim

        ; player (sprite 0)
        lda state
        cmp #ST_DEAD
        bne _u1
        lda frame
        and #4
        beq _uenemies
        bne _up
_u1     lda pinv
        beq _up
        lda frame
        and #2
        bne _uenemies
_up     ldx #0
        jsr entpos
        ldx #0
        lda #$e0
        clc
        adc pface
        jsr putspr

_uenemies
        ldx #1                  ; monsters (sprites 2..6)
_ue     stx ei
        lda etype,x
        bne _ue1
        jmp _uen
_ue1    cmp #2
        bne _ue2
        lda frame               ; type 2 is only visible now and then
        and #63
        cmp #24
        bcc _ue2
        lda etx,x
        cmp etx
        beq _ue2
        lda ety,x
        cmp ety
        bne _uen
_ue2    lda etype,x
        cmp #4
        bne _ue3
        lda wizflash
        bne _uen
_ue3    jsr entpos
        ldx ei
        lda etype,x
        tay
        lda tcolor,y
        ldx ei
        inx                     ; sprite number = entity + 1
        sta $d027,x
        dey
        tya
        asl a
        clc
        adc #$e4
        adc anim
        jsr putspr
_uen    ldx ei
        inx
        cpx #6
        bne _ue

        lda bul                 ; player bullet (sprite 1)
        beq _ub2
        clc
        lda bul+1
        adc #22
        sta sxl
        lda bul+2
        adc #0
        sta sxh
        clc
        lda bul+3
        adc #64
        sta sy
        ldx #1
        lda #$ec
        jsr putspr
_ub2    lda bul+5               ; enemy bullet (sprite 7)
        beq _ub3
        clc
        lda bul+6
        adc #22
        sta sxl
        lda bul+7
        adc #0
        sta sxh
        clc
        lda bul+8
        adc #64
        sta sy
        ldx #7
        lda #$ec
        jsr putspr
_ub3    lda msbacc
        sta $d010
        lda enacc
        sta $d015
        rts

; ============================================================================
;  score, hud, text (as in BRICKSTORM)
; ============================================================================
addhund                         ; A = BCD hundreds
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

clrmsg
        ldx #<str_blank
        ldy #>str_blank
        jmp drawstr

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
        .include "dungeonblast_data.inc"
        .cerror * > CHARSET, "code + data overlap the charset"
