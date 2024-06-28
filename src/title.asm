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
        icl '../include/display_list.asm'	
        icl '../include/vertical_blank.asm'

; TODO: Quick/dirty title screen.  Moves title screen "technique tests" to real
;       woebegone project. Uses MADS macros and thoses from the "include" folder
;       (instead of explicit, long-hand, 6502 code).

; Time-Critical PAGE ZERO variables

DLI_TABLE_IDX =    $0090 ; Put this in page zero to save enough time for HSCROL
                         ; on DLI lines without beam ovverun.

CLOUD_SCROLL_IDX = $0091 ; Cloud Smooth-Scroll Index
HILL_SCROLL_IDX =  $0092 ; Hill Smooth-Scroll Index
ROCK_SCROLL_IDX =  $0093 ; Rocks Smooth-Scroll Index
TEXT_SCROLL_IDX =  $0094 ; Text Smooth-Scroll Index

; Variables stuffed in Page 6 for now.

; COLOR FLOW variables
COLOR_FLOW_LINE = $0600	; Current color for the COLOR FLOW scan line
COLOR_FLOW_TOP =  $0601 ; First color (top scan line) for COLOR FLOW

; Cloud PMG Position and cycle counter
CLOUD_POS = 	  $0602	; Cloud PMG Position
CLOUD_REDUCER =   $0603	; Counter for Reducing Cloud Updates

start
        ; Use our custom character set; which since we're using the shadow
        ; register to do it, will be reset automatically in the VBI
        SetCharacterSet charset
        
        ; Set Background Color		
        lda #$75
        sta COLOR4
                
        ; Set Playfield Colors
        lda #$0C
        sta COLOR0
        lda #$0F
        sta COLOR1
                
        ; Display Initial Player Missiles
        lda #>pm_graphics
        sta PMBASE
        
        ; Cloud
        lda #$8F
        sta PCOLOR0
        lda #PM_SIZE_DOUBLE
        sta SIZEP0
        lda #$00
        sta HPOSP0
        
        ; Sun
        lda #$EF
        sta PCOLOR1
        lda #PM_SIZE_NORMAL
        sta SIZEP1
        lda #$B0
        sta HPOSP1

        ; Enable and Display!
        lda #ENABLE_PLAYERS
        sta GRACTL
        lda #62
        sta SDMCTL
                                        
        ; Install our display list
        InstallDisplayList title_display_list
        
        ; Initialize start colors
        lda #0
        sta  COLOR_FLOW_LINE
                
        ; Initialize our text scroll point - text scrolls from RIGHT to LEFT so
        ; we start at max HSCROL and work backwards to zero.
        lda #$10	
        sta TEXT_SCROLL_IDX

        ; Initialize our cloud scroll point - clouds (etc.) scroll from LEFT to
        ; RIGHT so we start at zero and work up to max HSCROL.
        lda #$00
        sta CLOUD_SCROLL_IDX

        ; Setup VBI (Deferred) - Where most of our non-DLI work happens.
        SetDeferredVBI vert_isr
                                        
        ; Setup all done; now just loop forever, while incrementing the
        ; color values and registers
lp	
        inc COLOR_FLOW_LINE ; Increment to the next color for COLOR FLOW
        lda COLOR_FLOW_LINE ; Get that color
        sta WSYNC	    ; Wait for horizontal retrace
        sta COLPF2	    ; Then set the hardware color register directly 	 
        jmp lp

        ; Vertical Blank Interrupt Service Routine

vert_isr
        ; Setup the FIRST DLI here in the VBI so we know it will be the
        ; first DLI to be called when the frame is drawn.

        lda #$00		; First we initialize the color table lookup
        sta DLI_TABLE_IDX       ; index to its start.
        SetDLI dl_set_clouds	; Then we set the first DLI, which changes
                                ; the character set to the clouds.
        
        ;Color Cycling Index Points for COLOR FLOW color scrolling
        inc COLOR_FLOW_TOP
        ldx COLOR_FLOW_TOP
        stx COLOR_FLOW_LINE	
                                
        ; Do Smooth Text-Scroller Scrolling
        lda TEXT_SCROLL_IDX
        cmp #$0
        bne cont_text_scroll
        
        ; Update the LMS address to coarse scroll
        adw scroll_lms #$02	; Two bytes per coarse scroll in Mode 7
                
        ; Reset the smooth scroll location
        sec
        lda #$10	

cont_text_scroll
        sbc #$01
        sta TEXT_SCROLL_IDX
                        
        ; RESET THE OVERALL SCROLLER  (Resets when scroll_lms points beyond blank_line
        lda scroll_lms + 1
        cmp #>blank_line
        bcc do_not_reset_scroller ;Branch if the LMS HIGH pointer is lower than the last page of scroller data.
        
        lda scroll_lms
        cmp #<blank_line
        bcc do_not_reset_scroller ;Branch if the LMS LOW pointer is lower than the last desired byte into the current page
                        
        ; RESET the scroller to the beginning of the text.
        mwa #scroll_line scroll_lms ; Reset the LMS address to the start of the scroller
        
do_not_reset_scroller		

        ; RESET the CLOUD Scroller?
        lda cst_lms + 1
        cmp #>[cloud_scroller_top + 1 ]	; Branch two bytes early, as the line is offset by HSCROL
        bcc reset_cloud_scroller	; Examine how this yields <= in conjunction with next instruction
        bne do_not_reset_cloud_scroller	; Examine how this yields <= in conjunciton with previous instruction

        lda cst_lms
        cmp #<[cloud_scroller_top + 1]	; Branch two bytes early, as the line is offset by HSCROL
        bcs do_not_reset_cloud_scroller	; Don't branch if we're not at, or before, the first address (see above)
        
reset_cloud_scroller
        mwa #[cloud_scroller_top_end - 48] cst_lms
        mwa #[cloud_scroller_bottom_end -48 ] csb_lms
        
do_not_reset_cloud_scroller

        ; RESET the HILL Scroller?
        lda hst_lms + 1
        cmp #>[hills_scroller_top + 1 ]	; Branch two bytes early, as the line is offset by HSCROL
        bcc reset_hills_scroller	; Examine how this yields <= in conjunction with next instruction
        bne do_not_reset_hills_scroller	; Examine how this yields <= in conjunciton with previous instruction

        lda hst_lms
        cmp #<[hills_scroller_top + 1]	; Branch two bytes early, as the line is offset by HSCROL
        bcs do_not_reset_hills_scroller	; Don't branch if we're not at, or before, the first address (see above)
        
reset_hills_scroller
        mwa #[hills_scroller_top_end - 48] hst_lms
        mwa #[hills_scroller_bottom_end -48 ] hsb_lms    

do_not_reset_hills_scroller   

        ; RESET the ROCKS Scroller?
        lda rck_lms + 1
        cmp #>[rocks_scroller + 1 ]	; Branch two bytes early, as the line is offset by HSCROL
        bcc reset_rocks_scroller	; Examine how this yields <= in conjunction with next instruction
        bne do_not_reset_rocks_scroller	; Examine how this yields <= in conjunciton with previous instruction

        lda rck_lms
        cmp #<[rocks_scroller + 1]	; Branch two bytes early, as the line is offset by HSCROL
        bcs do_not_reset_rocks_scroller	; Don't branch if we're not at, or before, the first address (see above)

reset_rocks_scroller
        mwa #[rocks_scroller_end - 48] rck_lms

do_not_reset_rocks_scroller
        ; We've skipped resetting the rocks, so continue with the next tasks
        
        ; Update the position of the cloud, every 16th frame
        inc cloud_reducer
        lda cloud_reducer
        cmp #$10
        bne skip_cloud
        inc cloud_pos	; Move the PMG cloud 1 pixel to the right      
        lda #$00
        sta cloud_reducer	

skip_cloud	
        lda CLOUD_POS
        sta HPOSP0        

        ldx #$02                ; Last Index into hscrol_fractions + hscrol_delta
move    lda hscrol_fractions, x ; Get the current fraction
        clc
        adc hscrol_delta, x     ; Add the delta
        sta hscrol_fractions, x ; Store the new fraction
        lda CLOUD_SCROLL_IDX, x ; Get the current HSCROL position
        adc #$00                ; Add the overflow value from the fraction (fraction rolled over)
        sta CLOUD_SCROLL_IDX, x ; Store the new HSCROL position
        cmp #$04                ; We're in Mode 4, so 4 color-clocks (scroll values)
        bcc nope                ; Done with this band

        cpx #$00                ; Coarse scroll the clouds
        bne ck_hill
        jsr coarse_scroll_cloud
        bcc next

ck_hill cpx #$01                ; Coarse scroll the hills
        bne ck_rock
        jsr coarse_scroll_hill
        bcc next
        
ck_rock cpx #$02
        bne next
        jsr coarse_scroll_rock  ; Coarse scroll the rocks

next    lda #$00                ; Reset the fraction after a coarse scroll
        sta CLOUD_SCROLL_IDX, x

nope    dex                     ; Do the next band
        bpl move

        ; Done with the VBI, so exit              
exit_vb	        
        ExitDeferredVBI

; Coarse Scrolling Routines for VBI

coarse_scroll_cloud
        ; To scroll CLOUDS RIGHT, we set the LMS address to a LOWER (LEFT)
        ; position, resulting in data appearing later on the display line.

        sbw cst_lms #$01 ; One byte per coarse scroll in Mode 4
        sbw csb_lms #$01
        clc              ; Force branch in our caller
        rts

coarse_scroll_hill
        ; To scroll HILLS RIGHT, we set the LMS address to a LOWER (LEFT)
        ; position, resulting in data appearing later on the display line.
       
        sbw hst_lms #$01 ; One bytes per coarse scroll in Mode 4
        sbw hsb_lms #$01
        clc              ; Force branch in our caller
        rts

coarse_scroll_rock
        ; To scroll ROCKS RIGHT, we set the LMS address to a LOWER (LEFT)
        ; position, resulting in data appearing later on the display line.

        sbw rck_lms #$01 ; One bytes per coarse scroll in Mode 4
        clc              ; Force branch in our caller
        rts

; Display List Interrupt Service Routines
;
; These are broken out into short, simple, routines, to minimize DLI execution
; time for any one scan line or mode line.		

dl_set_clouds
        pha
        sta WSYNC                         ; Wait for the next scan line
        SetCharacterSet cloud_chars, TRUE ; Set the character set to the clouds
        lda CLOUD_SCROLL_IDX	          ; Get the smooth-scroll cloud position	
        sta HSCROL			  ; Update the HSCROL register
        ChainDLI dl_background, dl_set_clouds 	  ; Next do the color-update DLI

dl_background
        pha
        txa
        pha      

        ldx DLI_TABLE_IDX  ; Get the NEXT color ...
        lda color_table, x ; from the table and
        sta WSYNC	   ; wait for the next scan line
        sta COLBK	   ; to update color register	
        inc DLI_TABLE_IDX  ; Move to NEXT color in table
    
        cpx #$02           ; Chain next DLI if we're 2 colors into the table
        bne do_not_chain 
        
        ; Done and move to the next DLI 
        inc DLI_TABLE_IDX  ; Move to the next color in the table, so the next
                           ; table read is correct for the next DLI        
        pla
        tax
        ChainDLI dl_hill_colors, dl_background

do_not_chain
        ; Used in several places to exit the DLI
        
        ; We're not adjusting the color, nor chaning to the next DLI, so just
        ; restore the registers and return.
        pla
        tax
        pla
        rti
          
dl_hill_colors
        pha
        lda #$BC
        sta WSYNC
        sta COLBK
        lda #$28
        sta COLPF0
        lda #$24
        sta COLPF1
        ChainDLI dl_hill_scroll, dl_hill_colors

dl_hill_scroll
        pha        
        lda HILL_SCROLL_IDX	; Get the smooth-scroll hill position ...
        sta WSYNC
        sta HSCROL		; ... and update the HSCROL register
        ChainDLI dl_background_lower, dl_hill_scroll

dl_background_lower
        pha
        txa
        pha      
        
        ldx DLI_TABLE_IDX  ; Get the NEXT color ...
        lda color_table, x ; from the table and
        sta WSYNC	   ; wait for the next scan line
        sta COLBK	   ; to update color register               
        inc DLI_TABLE_IDX  ; Move to NEXT color in table
        cpx #$06           ; Chain next DLI if we're 8 colors into the table
        bne do_not_chain   ; Exit the DLI without chaining, using an the same
                           ; routine as dl_background does (see above) 
        
         ; Done and move to the next DLI
        pla
        tax
        ;ChainDLI dl_set_chars, dl_background_lower
        ChainDLI dl_rock_scroll, dl_background_lower

dl_rock_scroll
        pha
        lda #$B4                ; Set colors for the rocks
        sta COLPF0
        lda #$C6
        sta COLPF1
        lda color_table + 7
        sta WSYNC
        sta COLBK
        lda ROCK_SCROLL_IDX	; Get the smooth-scroll rock position ...
        sta WSYNC
        sta HSCROL		; ... and update the HSCROL register
        ChainDLI dl_set_chars, dl_rock_scroll

dl_set_chars	
        pha       
        sta WSYNC                            ; Wait for scan line to finish
                                             ; to avoid corrupting bottom line of rocks
        lda color_table + 8                  ; Set the background color for the
        sta COLBK                            ; last rost of the scrolling area
        SetCharacterSet charset, TRUE        ; Set character set to the text set
        ChainDLI dl_set_colors, dl_set_chars ; Next do the fixed colors DLI

dl_set_colors	
        pha
        lda #$26	; Set the background color for remainder of screen
        sta COLPF0
        lda #$46	; Set the text color for remainder of screen
        sta COLPF1
        
        lda  TEXT_SCROLL_IDX	; Get the smooth-scroll text position ...
        sta  HSCROL		; ... and update the HSCROL register; scrolls
                                ; in the opposite direction of clouds/scenery.
        pla
        rti

END:	
        run start
                                
; Macro Built Title Display List
title_display_list
        DL_TOP_OVERSCAN
        DL_LMS_MODE_ADDR [DL_TEXT_7 | DL_DLI], first_line  ; Change to Clouds Character Set
        DL_BLANK_LINES	 2
        DL_MODE		 [DL_TEXT_4 | DL_DLI]		   ; Change Background Color
        DL_MODE		 [DL_TEXT_4 | DL_DLI]	
        DL_LMS_MODE	 [DL_TEXT_4 | DL_DLI | DL_HSCROLL]
cst_lms	DL_LMS_ADDR	 [cloud_scroller_top_end - 48]	   ; Scrolling LEFT to RIGHT, so start at END of data - 1 line of chars
        DL_LMS_MODE	 [DL_TEXT_4 | DL_DLI | DL_HSCROLL]
csb_lms	DL_LMS_ADDR	 [cloud_scroller_bottom_end - 48]  ; Scrolling LEFT to RIGHT, so start at END of data - 1 line of chars
        DL_BLANK         DL_BLANK_2, TRUE                  ; Updates HSCROL for the HILLS; needs 2 blank lines or ANITC gets upset.
        DL_LMS_MODE      [DL_TEXT_4 | DL_DLI | DL_HSCROLL]
hst_lms DL_LMS_ADDR	 [hills_scroller_top_end - 48]	   ; Scrolling LEFT to RIGHT, so start at END of data - 1 line of chars 
        DL_LMS_MODE      [DL_TEXT_4 | DL_DLI | DL_HSCROLL]
hsb_lms DL_LMS_ADDR	 [hills_scroller_bottom_end - 48]  ; Scrolling LEFT to RIGHT, so start at END of data - 1 line of chars  
        DL_LMS_MODE_ADDR [DL_TEXT_4 | DL_DLI], blank_text      
        DL_MODE		 [DL_TEXT_4 | DL_DLI] 
        DL_BLANK         DL_BLANK_1, TRUE                  ; Updates HSCROL for the ROCKS   
        DL_LMS_MODE      [DL_TEXT_4 | DL_DLI | DL_HSCROLL] ; Switches character set (remember it occurs AFTER the line)
rck_lms DL_LMS_ADDR      [rocks_scroller_end - 48]	   ; Scrolling LEFT to RIGHT, so start at END of data - 1 line of chars         	   
        DL_LMS_MODE_ADDR [DL_TEXT_4 | DL_DLI], status_text ; Set Final Colors
        DL_MODE		 DL_TEXT_6
        DL_MODE		 DL_TEXT_6
        DL_MODE		 DL_TEXT_6
        DL_MODE		 DL_TEXT_7
        DL_BLANK_LINES	 8		
        DL_MODE		 DL_TEXT_2
        DL_BLANK_LINES 	 8
        DL_LMS_MODE	 [DL_TEXT_7 | DL_HSCROLL]
scroll_lms
        DL_LMS_ADDR	 scroll_line
        DL_BLANK_LINES	 8
        DL_BLANK_LINES 	 8	
        DL_JVB		 title_display_list

; Data for the Title Screen

        .align BOUNDARY_1K ; Align to a 1KB boundary, so we don't cross a 4K
                           ; boundary and get ANTIC all upset.

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
scroll_line
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
blank_line
        dta d'                                        '
        dta d'                                        '

; Two blocks of MODE 4 characters for the CLOUDS
cloud_scroller_top
        .HE 00 00 00 00 00 00 00 00 00 00 00 41 00 00 00 42 43 00 00 00 00 47 00 00 00 4B 4C 00 00 00 58 59 00 00 4F 00 00 00 00 00 00 00 00 00 00 55 56 57 00 00 00 00 00 00 00 00 00 00 00 41 00 00 00 42 43 00 00 00 00 47 00 00 00 4B 4C 00 00 00 58 59 00 00 4F 00 00 00 00 00 00 00 00 00 00 55 56 57
cloud_scroller_top_end
cloud_scroller_bottom		
        .HE 00 00 00 00 00 00 00 00 00 00 60 61 62 63 00 00 00 00 64 65 66 67 68 69 6A 6B 6C 6D 00 00 00 00 00 6E 6F 70 71 72 73 74 00 00 00 00 00 75 76 77 00 00 00 00 00 00 00 00 00 00 60 61 62 63 00 00 00 00 64 65 66 67 68 69 6A 6B 6C 6D 00 00 00 00 00 6E 6F 70 71 72 73 74 00 00 00 00 00 75 76 77 
cloud_scroller_bottom_end

; Two blocks of MODE 4 characters for the HILLS
hills_scroller_top        
        .HE 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 08 09 0A 0B 00 00 00 00 00 00 00 00 0D 0E 0F 08 09 0A 0B 0D 0E 0B 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 08 09 0A 0B 00 00 00 00 00 00 00 00 0D 0E 0F 08 09 0A 0B 0D 0E 0B 00 00 00 00 00 00 00 00 00
hills_scroller_top_end
hills_scroller_bottom     
        .HE 23 24 25 26 01 02 03 04 05 06 21 22 23 24 25 26 27 28 29 2A 2B 2C 21 01 22 23 24 25 06 2D 2E 2F 28 29 2A 2B 2D 2E 2A 21 22 01 23 25 26 03 01 02 23 24 25 26 01 02 03 04 05 06 21 22 23 24 25 26 27 28 29 2A 2B 2C 21 01 22 23 24 25 06 2D 2E 2F 28 29 2A 2B 2D 2E 2A 21 22 01 02 25 26 03 11 12
hills_scroller_bottom_end

; One block of MODE 4 characters for the ROCKS
rocks_scroller       
        .HE 00 00 05 03 04 00 00 00 21 22 23 00 00 00 00 05 02 03 04 00 00 00 00 3F 00 00 00 78 00 00 00 00 00 00 08 09 0A 0B 00 00 00 00 00 00 00 00 63 64 00 00 05 03 04 00 00 00 21 22 23 00 00 00 00 05 02 03 04 00 00 00 00 3F 00 00 00 78 00 00 00 00 00 00 08 09 0A 0B 00 00 00 00 00 00 00 00 63 64
rocks_scroller_end

; Colors for the BACKGROUND in main cloud/scenery area		
color_table
        .byte	$75, $87, $9A, $BC, $BA, $B7, $E7, $F5, $F3

hscrol_fractions        
        .byte   $00, $00, $00
; How fast each band scrolls - Lower is Slower; First value is the clouds.
hscrol_delta
        .byte   $4, $10, $40

; Character SETs ... first for the text ...	
        AlignCharacterSet
charset
        ins '../fonts/high_noon.fnt'
                
; ... and then for the cloud and terrain graphics ...
        .align PMBASE_BOUNDARY ; PMBASE_BOUNDARY is a 2KB boundary,
                               ; which is also a 1KB boundary, so works
                               ; for character sets.

pm_graphics	; This puts a character set in the first, unused, 1KB of PMBASE 
cloud_chars     ; so we're not wasting that area.
        ins '../fonts/scenery.fnt'				
                
        ; The inserted character set is 1024 bytes, so here org is at
        ; PMBASE + $400, ready for the first Player data.
        org *+69	;SKip on 64 bytes

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
        org *+236
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
