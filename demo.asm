; ============================================================================
;  IAC MASTERMIND CREW  -  ENGIN DIRI  -  C64 cracktro
;
;  Effects
;    * wobbling 3x5 block logo (per-line $D016 sine)
;    * rainbow raster bars in top/bottom border (scrolling colour ramps)
;    * three sine-driven copper bars behind a 3-layer pixel-smooth starfield
;    * 8-line-high (double height) pixel-smooth scroller on a shaded band
;    * 6-sprite Pulumi snake on a figure-eight path with colour cycling
;    * 3-voice SID tune: PWM arpeggios/lead, bass, kick/snare/hat, filter sweep
;
;  Assemble with 64tass (see build_demo.py). Tables live in demo_data.inc.
; ============================================================================
        .cpu "6502"

; ---- zero page ----
fc      = $02           ; frame counter
fflag   = $03           ; set by the last raster stage, cleared by main loop
cnt     = $04           ; line counter inside raster stages
ph2     = $05           ; rainbow phase
wobph   = $06           ; logo wobble phase (0..63)
scrx    = $07           ; scroller fine scroll 0/2/4/6
scrreg  = $08           ; $d016 value for the scroller lines
tp      = $09           ; scroll text pointer (word)
mph     = $0b           ; music: frame inside step 0..4
mstep   = $0c           ; music: step 0..127
marp    = $0d           ; music: chord offset for arpeggio or $ff
m1on    = $0e
m2on    = $0f
mdt     = $10           ; current drum type
pwc     = $11
bp1     = $12           ; copper bar phases
bp2     = $13
bp3     = $14
pidx    = $15           ; sprite path index
spi      = $16
sn      = $17
msb     = $18
cc      = $19
srcp    = $1a           ; charset generator pointers (words)
topp    = $1c
botp    = $1e
ptr     = $20           ; screen pointer (word)
tmp     = $24
stagevec = $26          ; current raster stage (word)
lrow    = $28

; ---- memory ----
SCREEN  = $0400
COLRAM  = $d800
ROW21   = SCREEN + 21*40
ROW22   = SCREEN + 22*40
CHARSET = $3000
SPRDATA = $3800
BUF     = $c000         ; 80 byte copper bar line buffer

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
        lda #$00
        sta $d01a
        lda #$ff
        sta $d019

        ; ---- copy ROM font to RAM ----
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
        lda #$35                ; I/O + RAM under the ROMs
        sta $01

        ; ---- generate double-height glyphs: $80.. top halves, $c0.. bottom halves ----
        lda #<CHARSET
        sta srcp
        lda #>CHARSET
        sta srcp+1
        lda #<(CHARSET + $80*8)
        sta topp
        lda #>(CHARSET + $80*8)
        sta topp+1
        lda #<(CHARSET + $c0*8)
        sta botp
        lda #>(CHARSET + $c0*8)
        sta botp+1
        ldx #64
_gl
        .for r = 0, r < 4, r += 1
        ldy #r
        lda (srcp),y
        ldy #r*2
        sta (topp),y
        iny
        sta (topp),y
        .next
        .for r = 0, r < 4, r += 1
        ldy #r+4
        lda (srcp),y
        ldy #r*2
        sta (botp),y
        iny
        sta (botp),y
        .next
        clc
        lda srcp
        adc #8
        sta srcp
        bcc _g1
        inc srcp+1
_g1     clc
        lda topp
        adc #8
        sta topp
        bcc _g2
        inc topp+1
_g2     clc
        lda botp
        adc #8
        sta botp
        bcc _g3
        inc botp+1
_g3     dex
        beq _gdone
        jmp _gl
_gdone

        ; ---- special glyphs: solid block, stars, underscore ----
        ldx #7
        lda #$ff
_pb     sta CHARSET + $40*8,x
        dex
        bpl _pb
        ldx #0
_ps     lda stars,x
        sta CHARSET + $60*8,x
        inx
        cpx #192
        bne _ps
        ldx #7
_pu     lda #0
        sta CHARSET + $bf*8,x
        lda uscore,x
        sta CHARSET + $ff*8,x
        dex
        bpl _pu

        ; ---- sprite data ----
        ldx #63
_sd     lda sprite,x
        sta SPRDATA,x
        dex
        bpl _sd

        ; ---- clear screen / colour ram ----
        ldx #0
_cl     lda #$20
        sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$2e8,x
        lda #1
        sta COLRAM,x
        sta COLRAM+$100,x
        sta COLRAM+$200,x
        sta COLRAM+$2e8,x
        inx
        bne _cl

        ; ---- static text + logo ----
        ldx #0
_t1     lda title1,x
        sta SCREEN + 1*40 + T1POS,x
        lda #3
        sta COLRAM + 1*40 + T1POS,x
        inx
        cpx #T1LEN
        bne _t1
        ldx #0
_t2     lda title2,x
        sta SCREEN + 9*40 + T2POS,x
        lda #7
        sta COLRAM + 9*40 + T2POS,x
        inx
        cpx #T2LEN
        bne _t2
        ldx #0
_lg     lda logo,x
        sta SCREEN + 3*40,x
        inx
        cpx #200
        bne _lg
        ldx #39
_sk     lda #11                 ; far layer
        sta COLRAM + 10*40,x
        sta COLRAM + 11*40,x
        sta COLRAM + 12*40,x
        lda #15                 ; middle layer
        sta COLRAM + 13*40,x
        sta COLRAM + 14*40,x
        sta COLRAM + 15*40,x
        sta COLRAM + 16*40,x
        lda #1                  ; near layer
        sta COLRAM + 17*40,x
        sta COLRAM + 18*40,x
        sta COLRAM + 19*40,x
        dex
        bpl _sk
        ldx #39
_sc     lda #7
        sta COLRAM + 21*40,x
        lda #8
        sta COLRAM + 22*40,x
        dex
        bpl _sc

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
        lda #$e0                ; sprite data $3800
        ldx #5
_sp     sta $07f8,x
        dex
        bpl _sp
        lda #$3f
        sta $d015
        sta $d017
        sta $d01d
        lda #0
        sta $d01b
        sta $d01c
        sta $d010

        ; ---- SID ----
        ldx #$18
        lda #0
_sid    sta $d400,x
        dex
        bpl _sid
        lda #$06
        sta $d405
        lda #$a6
        sta $d406
        lda #$08
        sta $d40c
        lda #$a4
        sta $d40d
        lda #$f1                ; resonance 15, filter voice 1
        sta $d417
        lda #$1f                ; low-pass, volume 15
        sta $d418

        ; ---- state ----
        lda #0
        sta fc
        sta fflag
        sta ph2
        sta wobph
        sta scrx
        sta mph
        sta mstep
        sta pidx
        sta pwc
        sta m1on
        sta m2on
        sta mdt
        lda #$c0
        sta scrreg
        lda #$ff
        sta marp
        lda #0
        sta bp1
        lda #85
        sta bp2
        lda #170
        sta bp3
        lda #<scrtext
        sta tp
        lda #>scrtext
        sta tp+1

        ; ---- interrupts (KERNAL/BASIC off, own vectors) ----
        lda #<irq
        sta $fffe
        lda #>irq
        sta $ffff
        lda #<nmi
        sta $fffa
        lda #>nmi
        sta $fffb
        lda #<stage0
        sta stagevec
        lda #>stage0
        sta stagevec+1
        lda #19
        sta $d012
        lda #$1b
        sta $d011
        lda #1
        sta $d01a
        lda #$ff
        sta $d019
        cli

main    lda fflag
        beq main
        lda #0
        sta fflag
        jsr logic
        jmp main

nmi     rti

; ============================================================================
;  raster interrupt: table driven stages, each one busy-loops over its lines
; ============================================================================
irq
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

; ---- stage 0: rainbow in the top border (lines 20..50) ----
stage0
        lda #31
        sta cnt
        lda ph2
        clc
        adc #20
        tay
        lda pat,y
        ldx #19
_w0     cpx $d012
        beq _w0
        sta $d020
        sta $d021
        inx
        iny
        lda pat,y
        dec cnt
        bne _w0
_w0b    cpx $d012
        beq _w0b
        lda #0
        sta $d020
        sta $d021
        lda #<stage1
        sta stagevec
        lda #>stage1
        sta stagevec+1
        lda #74
        sta $d012
        jmp irqx

; ---- stage 1: wobbling logo (lines 75..114) ----
stage1
        lda #40
        sta cnt
        ldy wobph
        lda wob,y
        ldx #74
_w1     cpx $d012
        beq _w1
        sta $d016
        inx
        iny
        lda wob,y
        dec cnt
        bne _w1
_w1b    cpx $d012
        beq _w1b
        lda #$c8
        sta $d016
        lda #<stage2
        sta stagevec
        lda #>stage2
        sta stagevec+1
        lda #130
        sta $d012
        jmp irqx

; ---- stage 2: copper bars (131..210) + scroller band (211..242) ----
stage2
        lda BUF
        ldx #130
        ldy #0
_b1     cpx $d012
        beq _b1
        sta $d020
        sta $d021
        inx
        iny
        lda BUF,y
        cpy #80
        bne _b1

        ldy #0
        lda band
_b2     cpx $d012
        beq _b2
        sta $d020
        sta $d021
        inx
        iny
        lda band,y
        cpy #8
        bne _b2
        lda scrreg              ; scroller fine scroll for lines 219..234
        sta $d016
        lda band,y
_b3     cpx $d012
        beq _b3
        sta $d020
        sta $d021
        inx
        iny
        lda band,y
        cpy #24
        bne _b3
_b4     cpx $d012
        beq _b4
        sta $d020
        sta $d021
        lda #$c8                ; back to normal from line 235 on
        sta $d016
        inx
        iny
        lda band,y
        cpy #32
        bne _b4

        lda #<stage3
        sta stagevec
        lda #>stage3
        sta stagevec+1
        lda #250
        sta $d012
        jmp irqx

; ---- stage 3: rainbow in the bottom border (lines 251..283) ----
stage3
        lda #33
        sta cnt
        lda ph2
        clc
        adc #100
        tay
        lda pat,y
        ldx #250
_w3     cpx $d012
        beq _w3
        sta $d020
        sta $d021
        inx
        dey
        lda pat,y
        dec cnt
        bne _w3
_w3b    cpx $d012
        beq _w3b
        lda #0
        sta $d020
        sta $d021
        lda #1
        sta fflag
        lda #<stage0
        sta stagevec
        lda #>stage0
        sta stagevec+1
        lda #19
        sta $d012
        jmp irqx

; ============================================================================
;  per-frame logic (runs in the main loop, interrupted by the raster stages)
; ============================================================================
logic
        inc fc
        lda ph2
        clc
        adc #2
        sta ph2
        lda fc
        and #63
        sta wobph
        lda fc
        lsr a
        lsr a
        sta cc
        jsr logocol
        jsr bars
        jsr starsup
        jsr scroller
        jsr sprites
        jsr music
        rts

; ---- logo colour cycling: one row per frame ----
logocol
        lda fc
        and #7
        cmp #5
        bcs _lcx
        sta lrow
        lda fc
        lsr a
        lsr a
        lsr a
        sta tmp
        lda lrow
        asl a
        clc
        adc lrow
        clc
        adc tmp
        and #15
        tax
        lda ctab,x
        sta tmp
        ldx lrow
        lda crlo,x
        sta ptr
        lda crhi,x
        sta ptr+1
        lda tmp
        ldy #39
_lc     sta (ptr),y
        dey
        bpl _lc
_lcx    rts

; ---- copper bar line buffer ----
drawbar .macro
        lda \1
        clc
        adc #\2
        sta \1
        tax
        lda bpos,x
        tax
        ldy #0
-       lda prof+\3,y
        sta BUF,x
        inx
        iny
        cpy #14
        bne -
        .endm

bars
        lda #0
        .for i = 0, i < 80, i += 1
        sta BUF + i
        .next
        #drawbar bp1, 2, 0
        #drawbar bp2, 3, 14
        #drawbar bp3, 5, 28
        rts

; ---- starfield: 3 layers, pixel smooth via 8 shifted glyphs per layer ----
starsup
        ldx #NSTARS-1
_st     lda sadlo,x
        sta ptr
        lda sadhi,x
        sta ptr+1
        ldy #0
        lda #$20
        sta (ptr),y             ; erase
        lda ssub,x
        sec
        sbc sspd,x
        bcs _draw               ; still inside the same cell
        adc #8
        sta ssub,x
        dec scol,x
        bpl _left
        lda #39                 ; wrap to the right edge of the row
        sta scol,x
        lda sadlo,x
        clc
        adc #39
        sta sadlo,x
        bcc _mv
        inc sadhi,x
        jmp _mv
_left   lda sadlo,x
        bne _l2
        dec sadhi,x
_l2     dec sadlo,x
_mv     lda sadlo,x
        sta ptr
        lda sadhi,x
        sta ptr+1
        lda ssub,x
_draw   sta ssub,x
        clc
        adc sgb,x
        ldy #0
        sta (ptr),y
        dex
        bpl _st
        rts

; ---- double height scroller, 2 pixels per frame ----
scroller
        lda scrx
        sec
        sbc #2
        bcs _sc_ok
        and #7
        sta scrx
        ldx #0
_sh     lda ROW21+1,x
        sta ROW21,x
        lda ROW22+1,x
        sta ROW22,x
        inx
        cpx #39
        bne _sh
        ldy #0
        lda (tp),y
        cmp #$ff
        bne _nc
        lda #<scrtext
        sta tp
        lda #>scrtext
        sta tp+1
        lda (tp),y
_nc     tax
        ora #$80
        sta ROW21+39
        txa
        ora #$c0
        sta ROW22+39
        inc tp
        bne _sc_set
        inc tp+1
        jmp _sc_set
_sc_ok  sta scrx
_sc_set lda scrx
        ora #$c0                ; CSEL=0 (38 columns) + fine scroll
        sta scrreg
        rts

; ---- sprite snake ----
sprites
        inc pidx
        lda pidx
        sta spi
        lda #0
        sta msb
        sta sn
        tay
_sl     ldx spi
        lda pxlo,x
        sta $d000,y
        lda pyy,x
        sta $d001,y
        lda pxhi,x
        beq _nm
        ldx sn
        lda sprbit,x
        ora msb
        sta msb
_nm     lda cc
        clc
        adc sn
        and #15
        tax
        lda sprcol,x
        ldx sn
        sta $d027,x
        lda spi
        sec
        sbc #9
        sta spi
        iny
        iny
        inc sn
        lda sn
        cmp #6
        bne _sl
        lda msb
        sta $d010
        rts

; ---- music player (5 frames per step) ----
music
        lda mph
        bne _m_not0

        ; ph 0: gates off, load the new step
        ldx mstep
        lda v1hi,x
        cmp #$ff
        beq _m1done
        cmp #$fe
        beq _m1arp
        sta $d401
        sta m1on
        lda v1lo,x
        sta $d400
        lda #$ff
        sta marp
        lda #$40
        sta $d404
        jmp _m1done
_m1arp  lda v1lo,x
        sta marp
        lda #1
        sta m1on
        lda #$40
        sta $d404
_m1done
        lda v2hi,x
        cmp #$ff
        beq _m2done
        sta $d408
        sta m2on
        lda v2lo,x
        sta $d407
        lda #$20
        sta $d40b
_m2done
        ldy drm,x
        sty mdt
        beq _m3done
        lda dwave,y
        sta $d412
        lda dfhi,y
        sta $d40f
        lda #0
        sta $d40e
        lda dad,y
        sta $d413
        lda #0
        sta $d414
_m3done
        jmp _mcommon

_m_not0
        cmp #1
        bne _mmid
        lda m1on                ; ph 1: gates on
        beq _g1
        lda #$41
        sta $d404
_g1     lda m2on
        beq _g2
        lda #$21
        sta $d40b
_g2     ldy mdt
        beq _mmid
        lda dwave,y
        ora #1
        sta $d412
_mmid
        lda marp                ; arpeggio: one chord tone per frame
        cmp #$ff
        beq _noarp
        clc
        adc mph
        tay
        dey
        lda chlo,y
        sta $d400
        lda chhi,y
        sta $d401
_noarp  ldy mdt                 ; kick pitch drop
        cpy #1
        bne _mcommon
        ldx mph
        lda kickhi,x
        sta $d40f

_mcommon
        inc pwc                 ; pulse width modulation, voice 1
        ldx pwc
        lda sintab,x
        sta $d402
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        clc
        adc #4
        sta $d403
        lda fc                  ; filter cutoff sweep
        lsr a
        tax
        lda sintab,x
        lsr a
        clc
        adc #24
        sta $d416
        inc mph
        lda mph
        cmp #5
        bne _mret
        lda #0
        sta mph
        lda mstep
        clc
        adc #1
        and #$7f
        sta mstep
_mret   rts

; ============================================================================
        .include "demo_data.inc"
        .cerror * > CHARSET, "code + data overlap the charset"
