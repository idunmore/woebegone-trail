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
HILL_SCROLL_IDX = $0092  ; Hill Smooth-Scroll Index
TEXT_SCROLL_IDX =  $0093 ; Text Smooth-Scroll Index

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
        lda #PM_SIZE_QUAD
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
        cmp #>[cloud_scroller_top + 2 ]	; Branch two bytes early, as the line is offset by HSCROL
        bcc reset_cloud_scroller	; Examine how this yields <= in conjunction with next instruction
        bne do_not_reset_cloud_scroller	; Examine how this yields <= in conjunciton with previous instruction

        lda cst_lms
        cmp #<[cloud_scroller_top + 2]	; Branch two bytes early, as the line is offset by HSCROL
        bcs do_not_reset_cloud_scroller	; Don't branch if we're not at, or before, the first address (see above)
        
reset_cloud_scroller
        mwa #[cloud_scroller_top_end - 48] cst_lms
        mwa #[cloud_scroller_bottom_end -48 ] csb_lms
        
do_not_reset_cloud_scroller

        ; RESET the HILL Scroller?
        lda hst_lms + 1
        cmp #>[hills_scroller_top + 2 ]	; Branch two bytes early, as the line is offset by HSCROL
        bcc reset_hills_scroller	; Examine how this yields <= in conjunction with next instruction
        bne do_not_reset_hills_scroller	; Examine how this yields <= in conjunciton with previous instruction

        lda hst_lms
        cmp #<[hills_scroller_top + 2]	; Branch two bytes early, as the line is offset by HSCROL
        bcs do_not_reset_hills_scroller	; Don't branch if we're not at, or before, the first address (see above)
        
reset_hills_scroller
        mwa #[hills_scroller_top_end - 48] hst_lms
        mwa #[hills_scroller_bottom_end -48 ] hsb_lms    

do_not_reset_hills_scroller   
        
        ; Update the position of the clouds, every 8th frame
        inc cloud_reducer
        lda cloud_reducer
        cmp #$08
        bne skip_cloud
        inc cloud_pos	; Move the PMG cloud 2 pixels to the right
        inc cloud_pos
        lda #$00
        sta cloud_reducer	
        
        ; Do CLOUD scrolling
        lda CLOUD_SCROLL_IDX
        cmp #$0F
        bne cont_clouds

        ; FOR CLOUDS ONLY: Update the LMS address to coarse scroll
        sbw cst_lms #$04	; Four bytes per coarse scroll in Mode 4
        sbw csb_lms #$04

        ; Reset the cloud scroll location
        lda #$FF
        sta CLOUD_SCROLL_IDX       

cont_clouds
        clc		     ; Necessary to avoid adding #$02 when the
        adc #$01	     ; last load was #$FF and sets the carry bit
        sta CLOUD_SCROLL_IDX

        ; Do HILL scrolling
        lda HILL_SCROLL_IDX
        cmp #$0F
        bne cont_hills

        ; FOR HILLS ONLY: Update the LMS address to coarse scroll
        sbw hst_lms #$04	; Four bytes per coarse scroll in Mode 4
        sbw hsb_lms #$04

        ; Reset the hill scroll location
        lda #$FF
        sta HILL_SCROLL_IDX       

cont_hills
        clc		     ; Necessary to avoid adding #$02 when the
        adc #$01	     ; last load was #$FF and sets the carry bit
        sta HILL_SCROLL_IDX

skip_cloud	
        lda CLOUD_POS
        sta HPOSP0	        
                        
exit_vb	        
        ExitDeferredVBI

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
        ChainDLI dl_set_hills, dl_set_clouds 	  ; Next do the color-update DLI

dl_set_hills
        pha
        txa
        pha      

        ldx DLI_TABLE_IDX  ;Get the NEXT color ...
        lda color_table, X ;from the table and
        sta WSYNC	   ;wait for the next scan line
        sta COLBK	   ;to update color register	
        inc DLI_TABLE_IDX  ;Move to NEXT color in table
               
        ldx DLI_TABLE_IDX  
        cpx #$04           ; Chain to the next DLI if we're 4 colors into the
        bne skip_color     ; color table.   

        ; Set the fixed colors for the hills
        lda #$28
        sta COLPF0
        lda #$24
        sta COLPF1

        lda HILL_SCROLL_IDX	; Get the smooth-scroll hill position ...
        sta WSYNC
        sta HSCROL		; ... and update the HSCROL register

        ; Done and move to the next DLI
        pla
        tax
        ChainDLI dl_isr, dl_set_hills

skip_color
        ; We're not adjusting the color, nor chaning to the next DLI, so just
        ; restore the registers and return.
        pla
        tax
        pla
        rti

dl_set_chars	
        pha
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

dl_isr	
        ; Changes the background color based on a table of colors and the
        ; DLI_TABLE_IDX value.  It runs once per mode line, for 9 mode lines,
        ; then chains the next DLI.

        pha	;Store A and X
        txa
        pha
                        
        ldx DLI_TABLE_IDX  ;Get the NEXT color ...
        lda color_table, X ;from the table and
        sta WSYNC	   ;wait for the next scan line
        sta COLBK	   ;to update color register	
        inc DLI_TABLE_IDX  ;Move to NEXT color in table

        lda DLI_TABLE_IDX  ;Last Index/Color?
        cmp #$09
        bne exit_dli	   ; If not, exit here ...

        pla				
        tax				; ... otherwise, restore X and chain to
        ChainDLI dl_set_chars, dl_isr	; the next DLI to reset character set
                
exit_dli
        pla	;Restore A and X
        tax
        pla
        rti

END:	
        run start
                                
; Macro Built Title Display List
title_display_list
        DL_TOP_OVERSCAN
        DL_LMS_MODE_ADDR [DL_TEXT_7 | DL_DLI], first_line  ; Change to Clouds Character Set
        DL_BLANK_LINES	 1
        DL_MODE		 [DL_TEXT_4 | DL_DLI]		   ; Change Background Color
        DL_MODE		 [DL_TEXT_4 | DL_DLI]	
        DL_LMS_MODE	 [DL_TEXT_4 | DL_DLI | DL_HSCROLL]
cst_lms	DL_LMS_ADDR	 [cloud_scroller_top_end - 48]	   ; Scrolling LEFT to RIGHT, so start at END of data - 1 line of chars
        DL_LMS_MODE	 [DL_TEXT_4 | DL_DLI | DL_HSCROLL]
csb_lms	DL_LMS_ADDR	 [cloud_scroller_bottom_end - 48]  ; Scrolling LEFT to RIGHT, so start at END of data - 1 line of chars
        DL_LMS_MODE      [DL_TEXT_4 | DL_DLI | DL_HSCROLL]
hst_lms DL_LMS_ADDR	 [hills_scroller_top_end - 48]	   ; Scrolling LEFT to RIGHT, so start at END of data - 1 line of chars 
        DL_LMS_MODE      [DL_TEXT_4 | DL_DLI | DL_HSCROLL]
hsb_lms DL_LMS_ADDR	 [hills_scroller_bottom_end - 48]  ; Scrolling LEFT to RIGHT, so start at END of data - 1 line of chars  
        DL_LMS_MODE_ADDR [DL_TEXT_4 | DL_DLI], main_text      
        DL_MODE		 [DL_TEXT_4 | DL_DLI]
        DL_MODE		 [DL_TEXT_4 | DL_DLI]
        DL_MODE		 [DL_TEXT_4 | DL_DLI]   	   ; Resets Character Set
        DL_BLANK	 DL_BLANK_1, TRUE		   ; Set Final Colors
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
first_line
        dta d'THE: WOEBEGONE TRAIL'*       	
main_text        
        dta d'                                        '
        dta d'                                        '
        dta d'                                        '
        dta d'                                        '
        dta d'   CURRENT STATUS   '*
        dta d' EVERYONE IS:alive. '
        dta d'MORALE IS:faltering.'
        dta d'location'*
        dta d':'
        dta d'SNAKE RIVER'*
        dta d'   Press [START] to Die of Dysentery.   '*
scroll_line
        dta d"                      WELCOME TO "
        dta d'THE WOEBEGONE TRAIL'*
        dta d" ... A MODERN HOMAGE TO "
        dta d'THE OREGON TRAIL'*
        dta d' FOR '
        dta d'ATARI 8-BIT'*
        dta d' COMPUTERS'
        dta d' ... '
        dta d' FONT (provisional) BY "damieng" (damieng.com/typography) '
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

hills_scroller_top
        .HE 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
hills_scroller_top_end
hills_scroller_bottom
        .HE 00 00 00 00 00 00 00 00 00 00 21 22 23 24 25 26 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 21 22 23 24 25 26 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
hills_scroller_bottom_end

; Colors for the BACKGROUND in main cloud/scenery area		
color_table
        .byte	$75, $87, $9A, $BC, $BA, $B7, $E7, $F5, $F3

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
        .byte %11111111
        .byte %11111110
        .byte %11111100
        .byte %01111100
        .byte %11111111
        .byte %11111111
        .byte %11111110
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
