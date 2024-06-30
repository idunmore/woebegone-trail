; title.asm - Title and Intro screen for "The Woebegone Trail"
;
; Copyright (C) 2024, Ian Michael Dunmore
;
; Licensed Under: GNU Public License v3.0
; See: https://github.com/idunmore/woebegone-trail/blob/main/LICENSE

; Include Main Macros and Definitions

        icl '../include/common.asm'
        icl '../include/ANTIC.asm'
        icl '../include/GTIA.asm'
        icl '../include/character_set.asm'
        icl '../include/colors.asm'
        icl '../include/display_list.asm'	
        icl '../include/vertical_blank.asm'

; Local Constants and Equates

MAX_HSCROL_MODE7 = $10 ; Maximum HSCROL value for Mode 7 (16 color clocks)
MAX_HSCROL_MODE4 = $04 ; Maximum HSCROL value for Mode 4 (4 color clocks)

MODE4_HSCROL_LINE_LENGTH = $30 ; Bytes per normal-playfield width HSCROL line in Mode 4

; Variables and Values we want to have in specific memory locations.

; Use Page 0 for Time-Critical Variables
;
; These are faster to access and use shorter instructions (quicker to decode)
; which is important for highly time-sensitive code, like DLIs.

colorTableIdx = $0080 ; Index into color lookup table for color-change DLIs

sceneryBands =  $0081 ; Used to index below HSCROL Pos values as a TABLE (,x)
cloudBandPos =  $0081 ; Cloud (top) band HSCROL smooth-scroll position
hillBandPos =   $0082 ; Hills (middle) band HSCROL smooth-scroll position
shrubBandPos =  $0083 ; Shrubs (bottom) band HSCROL smooth-scroll position
cloudPos =      $0084 ; Cloud PMG horizontal position 

textHSCROLPos = $0085 ; Text scroller HSCROL smooth-scroll position

; Non-Time Critical Variables

; Using Page 6 for now, but these don't necessarily need to be in a specific
; location; they could just be .DEFined and the assembler allowed to place them

; "Color Flow" Variables - "Color Flow" is the scrolling bands of color
;                          (sometimes called the "venetian blind effect),
;                          moving up/down the screen, and in text etc.

colorFlowFirstLine =   $0600 ; Color for the first scan line of the Color Flow
colorFlowCurrentLine = $0601 ; Color fot the current Color Flow scan line

; Title Screen Entry Point

start
        ; Initial Setup

        ; The main character set, and initial playfield and background colors
        ; are set using their shadow registers, so they will be automatically
        ; refreshed at the end of the VBI (*we* don't have to keep doing it).

        SetCharacterSet fntText ; Main text font
        
        lda #COLOR_ULTRAMARINE_BLUE | $04 ; Dark blue background (upper sky)
        sta COLBAK      
        lda #COLOR_GREY | $0C ; Almost white (clouds)     
        sta COLOR0
        lda #COLOR_WHITE      ; Bright white (clouds)
        sta COLOR1
        
        ; Setup PMG (Player Missile Graphics)
        
        lda #>pm_graphics ; Page # (high-byte) of 2K aligned PMG bitmap data
        sta PMBASE
        
        ; Cloud - Player 0
        lda #COLOR_MEDIUM_BLUE | $0F ; Lightest medium blue
        sta PCOLOR0
        lda #PM_SIZE_DOUBLE
        sta SIZEP0
        lda #$00
        sta HPOSP0
        
        ; Sun - Player 1
        lda #COLOR_ORANGE_GREEN | $0F ; Lightest orange green - YELLOW
        sta PCOLOR1
        lda #PM_SIZE_NORMAL
        sta SIZEP1
        lda #$B0
        sta HPOSP1

        ; Enable and Display PMGs - Maintaining necessary settings for SDMCTL
        lda #ENABLE_PLAYERS
        sta GRACTL
        lda #ENABLE_DL_DMA | PM_1LINE_RESOLUTION | ENABLE_PM_DMA | PLAYFIELD_WIDTH_NORMAL        
        sta SDMCTL

        ; Main Screen Setup

        InstallDisplayList dlTitle ; Install our custom display list
        
        lda #MAX_HSCROL_MODE7 ; Text scroller runs right to left, so start at
        sta textHSCROLPos     ; right-most HSCROL position and work back to zero
        
        lda #$00           ; Parallax scrolling bands move from left to right, 
        sta cloudBandPos   ; so start them at the left-most HSCROL position,
        sta hillBandPos    ; and then increment to scroll right.
        sta shrubBandPos

        ; Most of our work occurs in a deferred mode VBI ...
        SetDeferredVBI vbiMain
                                        
        ; Setup is all done; now just loop forever doing "Color Flow":

loopForever	
        inc colorFlowCurrentLine ; Increment color for Color Flow
        lda colorFlowCurrentLine ; Get that color
        sta WSYNC	         ; Wait for horizontal retrace
        sta COLPF2	         ; Set the hardware color register directly 	 
        jmp loopForever

        ; Vertical Blank Interrupt Service Routine

        ; Most of the actual work for the title screen occurs during this VBI,
        ; including text and parallax scrolling.

vbiMain
        
        lda #$00	  ; Reset the DLI color table pointer to its start, 
        sta colorTableIdx ; before we setup the actual DLIs

        ; We are using multiple, chained, DLIs, so we use the VBI to set, and
        ; reset, the correct FIRST DLIs, so they always run in order.

        SetDLI dliSetClouds ; First DLI sets up the cloud band scroll and colors
        
        ; "Color Flow" Update

        inc colorFlowFirstLine   ; Next color for first line, which makes the
        ldx colorFlowFirstLine   ; colors "flow" up the screen
        stx colorFlowCurrentLine ; Current line is also the first line after VBI
                                
        ; Main Text Scroller

        lda textHSCROLPos         ; Get the current text smooth scroll position
        cmp #$0                   ; and see if we need to do a coarse scroll
        bne doNotCoarseScrollText
        
        adw scroll_lms #$02       ; Yes; so coarse scroll (2 bytes for mode 7)                
        sec                       ; Then reset the smooth scroll position
        lda #MAX_HSCROL_MODE7	  ; to it's right-most position.

doNotCoarseScrollText
        sbc #$01                  ; Decrement the smooth scroll location
        sta textHSCROLPos         ; which scrolls to the left
                        
        lda scroll_lms + 1        ; Reached end of text scroller? Reset?
        cmp #>scroll_text_end     ; Check high-byte of LMS address first ...
        bcc doNotResetTextScroll  ; No, don't reset the text scroller yet

        lda scroll_lms            ; High-byte of LMS address is the same, so
        cmp #<scroll_text_end     ; check the low-byte of the LMS address
        bcc doNotResetTextScroll  ; No, don't reset the text scroller yet
                                
        mwa #scroll_text scroll_lms ; Reset the text scroller by pointing its
                                    ; LMS address to start of scroll text

doNotResetTextScroll	

        ; Parallax Scrolling

        ; Each band (see sceneryBands) is scrolled by a single color-clock/pixel
        ; but how often that happens is determined by the delta value in the
        ; hscrol_delta table.  The fraction value in hscrol_fractions is used
        ; to accumulate the fractional part of the scroll, and when it reaches
        ; 256, the CARRY FLAG is set, and the overflow is used to increment
        ; the actual sceneryBand HSCROL position.
        ;
        ; Effectively this is a two-byte fixed-point number, with the high-byte
        ; being the HSCROL value (in the table) and the low-byte being the
        ; fractional part of the two-byte number.

        ; This first loop does the smooth and coarse scrolling of the bands,
        ; and then a subsequent block handles resetting each band when it
        ; reaches the end of its data.

        ; The FINAL block of the parallax band/scrolling is used to update
        ; the PMG cloud (or clouds, in future), and is a special case.  It must
        ; be LAST, and must NOT reset the fraction or it will just sit at Pos 0.

        ldx #$03                ; Last Index into hscrol_fractions + hscrol_delta
move    lda hscrol_fractions, x ; Get the current fraction
        clc
        adc hscrol_delta, x     ; Add the delta
        sta hscrol_fractions, x ; Store the new fraction
        lda sceneryBands, x     ; Get the current HSCROL position
        adc #$00                ; Add the overflow value from the fraction (fraction rolled over)
        sta sceneryBands, x     ; Store the new HSCROL position
        cmp #MAX_HSCROL_MODE4   ; We're in Mode 4, so 4 color-clocks (scroll values)
        bcc nope                ; Done with this band

        cpx #$00                ; Coarse scroll the clouds
        bne ck_hill
        jsr CoarseScrollClouds
        bcc next

ck_hill cpx #$01                ; Coarse scroll the hills
        bne ck_shrb
        jsr CoarseScrollHills
        bcc next
        
ck_shrb cpx #$02
        bne ck_pmg
        jsr CoarseScrollShrubs  ; Coarse scroll the shrubs

ck_pmg  cpx #$03                ; ALWAYS skip the fraction reset for the PMG 
        beq nope                ; cloud, we just want its position to increment

next    lda #$00                ; Reset the fraction after a coarse scroll
        sta sceneryBands, x

nope    dex                     ; Do the next band
        bpl move

        ; Reset the individual bands after the above smooth and coarse scroll?

        ; Reset the scrolling Cloud band?

        lda cbt_lms + 1             ; We reset if the LMS address for the
        cmp #>cloud_band_top        ; top of the cloud band is lower than 
        bcc resetCloudBand          ; the start of the cloud band data ...
        bne doNotResetCloudBand

        lda cbt_lms                 ; ... allowing for one extra character
        cmp #<[cloud_band_top + 1]  ; to account for the HSCROL offset
        bcs doNotResetCloudBand	     
        
resetCloudBand
        ; Reset top and bottom cloud band LMS addresses to one line of data 
        ; before it's end, so the whole line has data to display.
        mwa #[cloud_band_top_end - MODE4_HSCROL_LINE_LENGTH] cbt_lms    
        mwa #[cloud_band_bottom_end - MODE4_HSCROL_LINE_LENGTH ] cbb_lms 
        
doNotResetCloudBand

        ; Reset the scrolling Hill band?

        lda hbt_lms + 1           ; We reset if the LMS address for the
        cmp #>hill_band_top 	  ; top of the hill band is lower than 
        bcc resetHillBand	  ; the start of the hill band data ...
        bne doNotResetHillBand	

        lda hbt_lms               ; ... allowing for one extra character
        cmp #<[hill_band_top + 1] ; to account for the HSCROL offset
        bcs doNotResetHillBand
        
resetHillBand
        ; Reset top and bottom hill band LMS addresses to one line of data 
        ; before it's end, so the whole line has data to display.
        mwa #[hill_band_top_end - MODE4_HSCROL_LINE_LENGTH] hbt_lms
        mwa #[hill_band_bottom_end - MODE4_HSCROL_LINE_LENGTH ] hsb_lms    

doNotResetHillBand   

        ; Reset the scrolling Shrubs band?

        lda shr_lms + 1         ; We reset if the LMS address for the
        cmp #>shrub_band	; top of the shrub band is lower than
        bcc resetShrubBand	; the start of the hill band data ...
        bne doNotResetShrubBand	

        lda shr_lms
        cmp #<[shrub_band + 1]	; ... allowing for one extra character
        bcs doNotResetShrubBand	; to account for the HSCROL offset

resetShrubBand
        ; Reset the shrub band LMS address to one line of data before its end
        mwa #[shrub_band_end - MODE4_HSCROL_LINE_LENGTH] shr_lms

doNotResetShrubBand
        
        ; Updates the PMG Cloud position, from the fraction value computed
        ; during the parallel scrolling of the scenery bands.
        lda cloudPos
        sta HPOSP0        

        ; Done with the VBI, so exit              
exit_vb	        
        ExitDeferredVBI

; Coarse Scrolling Routines for VBI

; These routines are all doing coarse RIGHT scrolling, so they set the LMS
; address to an lower/earlier position in memory, so data appears later on the
; display line, thus resulting in it moving to the RIGHT.

CoarseScrollClouds        
        sbw cbt_lms #$01 ; One byte per coarse scroll in Mode 4
        sbw cbb_lms #$01
        clc              ; Forces branch in our caller
        rts

CoarseScrollHills              
        sbw hbt_lms #$01 ; One byte per coarse scroll in Mode 4
        sbw hsb_lms #$01
        clc              ; Forces branch in our caller
        rts

CoarseScrollShrubs        
        sbw shr_lms #$01 ; One byte per coarse scroll in Mode 4
        clc              ; Forces branch in our caller
        rts

; Display List Interrupt Service Routines
;
; These are broken out into short, simple, routines, to minimize DLI execution
; time for any one scan line or mode line.

; DLI Chain Sequence: dliSetClouds -> dliBackground -> dliHillColors ->
;                     dliHillScroll -> dliBackgroundLower -> dliShrubScroll ->
;                     dliSetText -> dliSetColors	

; dliSetClouds - Switches to the scenery character set, sets the HSCROL position
;                of the cloud parallax band, and chains to the next DLI.
dliSetClouds
        pha
        sta WSYNC                            ; Wait for the next scan line
        SetCharacterSet fntScenery, TRUE     ; Set the character set to the clouds
        lda cloudBandPos	             ; Get the smooth-scroll cloud position	
        sta HSCROL			     ; Update the HSCROL register
        ChainDLI dliBackground, dliSetClouds ; Next do the color-update DLI

; dliBackground - Updates the background color (COLBK) from a table, for several
;                 scan lines, and then chains to the next DLI.

dliBackground
        pha ; Save A and X registers
        txa
        pha      

        ldx colorTableIdx  ; Get the NEXT color ...
        lda color_table, x ; from the table and
        sta WSYNC	   ; wait for the next scan line
        sta COLBK	   ; to update color register	
        inc colorTableIdx  ; then move to NEXT color in table
    
        cpx #$02           ; Chain next DLI if we're 2 colors into the table
        bne doNotChainDLI        
        
        ; Done and move to the next DLI 

        inc colorTableIdx  ; Move to the next color in the table, so the next
                           ; table read is correct for the next DLI        
        pla
        tax
        ChainDLI dliHillColors, dliBackground ; Next to the hill color DLI

; doNotChainDLI - This is just a shared DLI-exit routine, called by multiple
;                 DLIs to restore the A and X registers and RTI.
doNotChainDLI   
              
        pla
        tax
        pla
        rti

; dliHillColors - Updates background and playfield colors for the hill parallax
;                 band and then chains to next DLI.

dliHillColors
        pha
        lda #COLOR_OLIVE_GREEN | $0C ; Very light olive green
        sta WSYNC
        sta COLBK
        lda #COLOR_RED_ORANGE | $08  ; Medimum red orange
        sta COLPF0
        lda #COLOR_RED_ORANGE | $04  ; Dark red orange
        sta COLPF1
        ChainDLI dliHillScroll, dliHillColors ; Next do the hill scrolling DLI

; dliHillScroll - Updates the HSCROL position of the hill parallax band and then
;                 chains to the next DLI.  This happens separately from 
;                 dliHillColors to ensure it finishes in one scane line.

dliHillScroll
        pha        
        lda hillBandPos ; Get the smooth-scroll hill position ...
        sta WSYNC       ; let the scanline finish to avoid flicker ...
        sta HSCROL	; ... and then update the HSCROL register
        ChainDLI dliBackgroundLower, dliHillScroll ; Do lower background color DLI

; dliBackgroundLower - Updates the lower area background color (COLBK) from a
;                      table, for several scan lines, and then chains to the
;                      next DLI.

dliBackgroundLower
        pha
        txa
        pha      
        
        ldx colorTableIdx  ; Get the NEXT color ...
        lda color_table, x ; from the table and
        sta WSYNC	   ; wait for the next scan line
        sta COLBK	   ; to update color register               
        inc colorTableIdx  ; Move to NEXT color in table
        cpx #$06           ; Chain next DLI if we're 6 colors into the table
        bne doNotChainDLI  ; Exit the DLI without chaining
        
         ; Done and chain to the next DLI
        pla
        tax        
        ChainDLI dliShrubScroll, dliBackgroundLower ; Next do the shrub scrolling DLI

; dliShrubScroll - Updates the HSCROL position of the shrub parallax band,
;                  resets the colors for the shrubs and background, and then
;                  chains to the next DLI.

dliShrubScroll
        pha
        lda #COLOR_OLIVE_GREEN | $04  ; Dark olive green - brown
        sta COLPF0
        lda #COLOR_MEDIUM_GREEN | $06 ; Medium green - brown
        sta COLPF1
        lda color_table + 7
        sta WSYNC
        sta COLBK
        lda shrubBandPos	      ; Get the smooth-scroll rock position ...
        sta WSYNC                     ; ... and let the scanline finish ...
        sta HSCROL	              ; ... then update the HSCROL register
        ChainDLI dliSetText, dliShrubScroll ; Chain to text scrolling DLI

; dliSetText - Switches to the text font, resets the backgrond color, and then
;              chains to the next DLI.

dliSetText	
        pha       
        sta WSYNC                         ; Wait for scan line to finish to
                                          ; avoid corrupting shrubs display
        lda color_table + 8               ; Set the background color for the
        sta COLBK                         ; last row of the scrolling area
        SetCharacterSet fntText, TRUE     ; Set character set to the text set
        ChainDLI dliSetColors, dliSetText ; Next do the fixed colors DLI

; dliSetColors - Sets the final fixed colors for the text area of the screen
;              - and sets the HSCROL position for the text scroller.

dliSetColors	
        pha
        lda #COLOR_RED_ORANGE | $06 ; Medium red orange	
        sta COLPF0                  ; Set background color remainder of screen
        lda #COLOR_RED | $06        ; Medium red
        sta COLPF1                  ; Set text color for remainder of screen
        
        lda  textHSCROLPos ; Get the smooth-scroll text position ...
        sta  HSCROL	   ; ... and update the HSCROL register; scrolls
                           ; in the opposite direction of clouds/scenery.
        pla
        rti

END:	
        run start
                                
; Display list for Title Screen

; This is a fairly complex display list, with multiple, chained, DLIs and
; multiple LMS regions, supporting color changes and multiple scrolling regions.

; NOTE: DLIs execute on the LAST scan line of the mode line they're set on, so 
; they affect subsequent mode lines, not the one they're defined/called on.

dlTitle
        DL_TOP_OVERSCAN                                                     ; 24 blank lines
        DL_LMS_MODE_ADDR [DL_TEXT_7 | DL_DLI], first_line                   ; dliSetClouds
        DL_BLANK_LINES	 2
        DL_MODE		 [DL_TEXT_4 | DL_DLI]		                    ; dliBackground
        DL_MODE		 [DL_TEXT_4 | DL_DLI]	                            ; dliBackground
        DL_LMS_MODE	 [DL_TEXT_4 | DL_DLI | DL_HSCROLL]                  ; dliBackground
cbt_lms	DL_LMS_ADDR	 [cloud_band_top_end - MODE4_HSCROL_LINE_LENGTH]    ; Top of cloud band
        DL_LMS_MODE	 [DL_TEXT_4 | DL_DLI | DL_HSCROLL]                  ; dliHillColors
cbb_lms	DL_LMS_ADDR	 [cloud_band_bottom_end - MODE4_HSCROL_LINE_LENGTH] ; Bottom of cloud band
        DL_BLANK         DL_BLANK_2, TRUE                                   ; dliHillScroll (2 blank lines needed to let DLI finish)
        DL_LMS_MODE      [DL_TEXT_4 | DL_DLI | DL_HSCROLL]                  ; dliBackgroundLower
hbt_lms DL_LMS_ADDR	 [hill_band_top_end - MODE4_HSCROL_LINE_LENGTH]	    ; Top of hill band 
        DL_LMS_MODE      [DL_TEXT_4 | DL_DLI | DL_HSCROLL]                  ; dliBackgroundLower
hsb_lms DL_LMS_ADDR	 [hill_band_bottom_end - MODE4_HSCROL_LINE_LENGTH]  ; Bottom of hill band
        DL_LMS_MODE_ADDR [DL_TEXT_4 | DL_DLI], blank_text                   ; dliBackgroundLower
        DL_MODE		 [DL_TEXT_4 | DL_DLI]                               ; dliBackgroundLower
        DL_BLANK         DL_BLANK_1, TRUE                                   ; dliShrubScroll (1 blank line needed to let DLI finish)
        DL_BLANK	 DL_BLANK_2                                         ; Needed for Atari800 emulator to stop HSCROL glitching
        DL_LMS_MODE      [DL_TEXT_4 | DL_DLI | DL_HSCROLL]                  ; dliSetText
shr_lms DL_LMS_ADDR      [shrub_band_end - MODE4_HSCROL_LINE_LENGTH]	    ; Shrub band
        DL_LMS_MODE_ADDR [DL_TEXT_4 | DL_DLI], status_text                  ; dliSetColors
        DL_MODE		 DL_TEXT_6
        DL_MODE		 DL_TEXT_6
        DL_MODE		 DL_TEXT_6
        DL_MODE		 DL_TEXT_7
        DL_BLANK_LINES	 8		
        DL_MODE		 DL_TEXT_2
        DL_BLANK_LINES 	 8
        DL_LMS_MODE	 [DL_TEXT_7 | DL_HSCROLL]                           ; Text Scroller
scroll_lms                                                      
        DL_LMS_ADDR	 scroll_text                                        ; Start of text scroller
        DL_BLANK_LINES	 8
        DL_BLANK_LINES 	 8	
        DL_JVB		 dlTitle                                            ; Back to top of display list

; Data for the Title Screen

        .align BOUNDARY_4K ; Align to a 1KB boundary, so we don't cross a 4K
                           ; boundary and get ANTIC all upset.

; Text for the text lines in the main display.

first_line
        dta d'THE: WOEBEGONE TRAIL'*       	
blank_text       
        dta d'                                        '
        dta d'                                        '
status_text
        dta d'                                        '
        dta d'   CURRENT STATUS   '*
        dta d' EVERYONE IS:alive. '
        dta d'MORALE IS:improving.'
        dta d'location'*
        dta d':'
        dta d'SNAKE RIVER'*
        dta d'   Press [START] to Die of Dysentery.   '*

; Text for the Text Scroller

scroll_text
        dta d'                      WELCOME TO '
        dta d'THE WOEBEGONE TRAIL'*
        dta d' ... A MODERN HOMAGE TO '
        dta d'THE OREGON TRAIL'*
        dta d' FOR '
        dta d'ATARI 8-BIT'*
        dta d' COMPUTERS ... BUILT WITH'
        dta d' MADS'*
        dta d' - THE mad assembler ...'
        dta d' equates/includes & macros inspired by (and some code from)'
        dta d" KEN JENNINGS"*
        dta d' (github.com/kenjennings/atari-mads-includes) ...'
        dta d' font BY "'        
        dta d'DAMIENG'*
        dta d'" (damieng.com/typography)'
        dta d' .......... press ['
        dta d'START'*
        dta d'] to die of dysentery.'        
scroll_text_end
        dta d'                      ' ; Blank buffer to stop spurious data
                                      ; showing at end of text scroller.

; Data (Character/Tile Maps) for the Parallax Scenery Bands

; Each full, normal-width, smooth-scroll-enabled mode line is 48 ($30) bytes
; long.  For seamless wrap-around scrolling the LAST 48 bytes of each line MUST
; be the same as the FIRST 48 bytes of the line (so when an LMS address reset
; occurs, it is showing the same data).
;
; For bands wider than one screen width, the data between the first and last
; blocks of 48 bytes does NOT need to repeat at all.
;
; The data for each band is in two parts: the top and bottom of the band.  They
; are the same length.  Each mode line has an independent LMS address, so the
; bands must be separate or one would scroll up into the prior one.

; Data is the internal character index into the character set, so is effectively
; a character or "tile" map.

; .HE lines are 24 bytes/characters long, so two .HE statements constitute one full
; MODE 4 line.

; Cloud Parallax Band Data

cloud_band_top
        ; These two lines must match the last two lines of the band.
        .HE 00 00 00 00 00 00 00 00 00 00 00 41 00 00 00 42 43 00 00 00 00 47 00 00
        .HE 00 4B 4C 00 00 00 58 59 00 00 4F 00 00 00 00 00 00 00 00 00 00 55 56 57

        ; More data can live here, and does not need to be duplicated.

        ; These two lines must match the first two lines of the band.
        .HE 00 00 00 00 00 00 00 00 00 00 00 41 00 00 00 42 43 00 00 00 00 47 00 00
        .HE 00 4B 4C 00 00 00 58 59 00 00 4F 00 00 00 00 00 00 00 00 00 00 55 56 57
cloud_band_top_end

cloud_band_bottom	
        ; These two lines must match the last two lines of the band.
        .HE 00 00 00 00 00 00 00 00 00 00 60 61 62 63 00 00 00 00 64 65 66 67 68 69
        .HE 6A 6B 6C 6D 00 00 00 00 00 6E 6F 70 71 72 73 74 00 00 00 00 00 75 76 77

        ; More data can live here, and does not need to be duplicated.

        ; These two lines must match the first two lines of the band.
        .HE 00 00 00 00 00 00 00 00 00 00 60 61 62 63 00 00 00 00 64 65 66 67 68 69
        .HE 6A 6B 6C 6D 00 00 00 00 00 6E 6F 70 71 72 73 74 00 00 00 00 00 75 76 77 
cloud_band_bottom_end

; Hill Parallax Band Data

hill_band_top
        ; These two lines must match the last two lines of the band.        
        .HE 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 08 09 0A 0B 00 00 00
        .HE 00 00 00 00 00 0D 0E 0F 08 09 0A 0B 0D 0E 0B 00 00 00 00 00 00 00 00 00

        ; More data can live here, and does not need to be duplicated.

        ; These two lines must match the first two lines of the band.
        .HE 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 08 09 0A 0B 00 00 00
        .HE 00 00 00 00 00 0D 0E 0F 08 09 0A 0B 0D 0E 0B 00 00 00 00 00 00 00 00 00        
hill_band_top_end

hill_band_bottom  
        ; These two lines must match the last two lines of the band.  
        .HE 23 24 25 26 01 02 03 04 05 06 21 22 23 24 25 26 27 28 29 2A 2B 2C 21 01
        .HE 22 23 24 25 06 2D 2E 2F 28 29 2A 2B 2D 2E 2A 21 22 01 23 25 26 03 01 02
        
        ; More data can live here, and does not need to be duplicated.

        ; These two lines must match the first two lines of the band.
        .HE 23 24 25 26 01 02 03 04 05 06 21 22 23 24 25 26 27 28 29 2A 2B 2C 21 01
        .HE 22 23 24 25 06 2D 2E 2F 28 29 2A 2B 2D 2E 2A 21 22 01 02 25 26 03 11 12
hill_band_bottom_end

; Shrubs Parallax Band Data
shrub_band       
        ; These two lines must match the last two lines of the band.  
        .HE 00 00 05 03 04 00 00 00 21 22 23 00 00 00 00 05 02 03 04 00 00 00 00 3F
        .HE 00 00 00 78 00 00 00 00 00 00 08 09 0A 0B 00 00 00 00 00 00 00 00 63 64

        ; More data can live here, and does not need to be duplicated.

        ; These two lines must match the first two lines of the band.
        .HE 00 00 05 03 04 00 00 00 21 22 23 00 00 00 00 05 02 03 04 00 00 00 00 3F
        .HE 00 00 00 78 00 00 00 00 00 00 08 09 0A 0B 00 00 00 00 00 00 00 00 63 64
shrub_band_end

; Colors for the BACKGROUND in main cloud/scenery area		
color_table
        .byte	$75, $87, $9A, $BC, $BA, $B7, $E7, $F5, $F3

; Tables for Parallax Scrolling Fractions and Speeds, in the order:
; Cloud Band, Hills Band, Shrubs Bound, PMG Cloud(s)

; Temporary space for the fractional part of the HSCROL position calculations
hscrol_fractions        
        .byte   $00, $00, $00, $00

; How fast each band scrolls as a fraction of frame Hz/256; Lower is Slower;
hscrol_delta
        .byte   $04, $10, $40, $08

; Character SETs ... first for the text ...

        AlignCharacterSet
fntText
        ins '../fonts/high_noon.fnt'
                
; ... and then for the cloud and scenery graphics ...

        .align PMBASE_BOUNDARY ; PMBASE_BOUNDARY is a 2KB boundary,
                               ; which is also a 1KB boundary, so works
                               ; for character sets.

pm_graphics	; This puts a character set in the first, unused, 1KB of PMBASE 
fntScenery      ; so we're not wasting that area.
        ins '../fonts/scenery.fnt'				
                
        ; The inserted character set is 1024 bytes, so here org is at
        ; PMBASE + $400, ready for the first Player data.
        org *+69	; Offset so cloud is visible, vertically, on screen

        ; "Ugly Cloud"
        .byte %00100000
        .byte %01101010
        .byte %11111111
        .byte %11011111
        .byte %11100110
        .byte %11111100
        .byte %01111100
        .byte %11011111
        .byte %11011111
        .byte %11111010
        .byte %11001100
        
        ; "Sun"	
        org *+236       ; Skip the rest of player 0 offset, vertically.
        .byte %00011000
        .byte %00111100
        .byte %01111110
        .byte %01111110
        .byte %11111111
        .byte %11111111
        .byte %11111111
        .byte %11111111	
        .byte %01111110		
        .byte %01111110
        .byte %00111100
        .byte %00011000
        
        ; Need to ensure the full PMBASE 2KB block has NO subsequent
        ; code in it, so we don't show "noise".  (e.g., putting a
        ; loop in woebegone.asm after this code shows up under the sun).
