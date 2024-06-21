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
	;icl '../include/OS.asm'
	icl '../include/character_set.asm'
	icl '../include/display_list.asm'
	icl '../include/vertical_blank.asm'

; TODO: This is a quick-and-dirty title screen, switched to use the macros in
;       the includes folder (instead of explicit 6502 code), and just to get
;       the original "technique tests" for the title/travel screen moved to
;       the real woebegone project.

; Variables stuffed in Page 6 for now.
COLOR_FLOW_LINE = $0600
COLOR_FLOW_TOP =  $0601

SCR_IDX = 	$0602	; Scroll Index
DLI_TABLE_IDX = $0603	; DLI Color Table Index

CLOUD_POS = 	$0604	; Cloud Position
CLOUD_REDUCER = $0605	; Counter for Reducing Cloud Updates


start
	; Use our custom character set; which since we're using the shadow
	; register to do it, will be reset automatically in the VBI
	SetCharacterSet charset
	
	; Set Background Color		
	lda	#$75
	sta	COLOR4
		
	; Set Playfield Colors
	lda	#$0C
	sta	COLOR0
	lda	#$0F
	sta	COLOR1
		
	; Display Initial Player Missiles
	lda	#>pm_graphics
	sta	PMBASE
	
	; Cloud
	lda	#$8F
	sta	PCOLOR0
	lda	#PM_SIZE_QUAD
	sta	SIZEP0
	lda	#$00
	sta	HPOSP0
	
	; Sun
	lda	#$EF
	sta 	PCOLOR1
	lda	#PM_SIZE_NORMAL
	sta	SIZEP1
	lda 	#$B0
	sta	HPOSP1

	; Enable and Display!
	lda	#ENABLE_PLAYERS
	sta	GRACTL
	lda	#62
	sta	SDMCTL
					
	; Install our display list
	InstallDisplayList title_display_list
	
	;Initialize start colors

	lda	#0
	sta 	COLOR_FLOW_LINE
		
	;Initialize our scroll point
	lda	#$10
	sta	HSCROL
	sta	SCR_IDX

	;Setup VBI (Deferred)
	SetDeferredVBI vert_isr
					
	; Setup all done; now just loop forever, while incrementing the
	; color values and registers
lp	
	inc     COLOR_FLOW_LINE
	lda 	COLOR_FLOW_LINE
	sta 	WSYNC	; Wait for horizontal retrace
	sta 	COLPF2	; Use this directly for the playfield.	 	 
	jmp 	lp

	; Vertical Blank Interrupt Service Routine

vert_isr
	; Setup the FIRST DLI here in the VBI so we know it will be the
	; first DLI to be called when the frame is drawn.

	lda	#$00		; First we initialize the color lookup index
	sta	DLI_TABLE_IDX
	SetDLI  dl_set_clouds	; Then we set the first DLI, which changes
				; the character set to the clouds.
	
	;Color Cycling Index Points for COLOR FLOW color scrolling
	inc     COLOR_FLOW_TOP
	ldx     COLOR_FLOW_TOP
	stx	COLOR_FLOW_LINE	
				
	; Do Smooth Scrolling
	lda	SCR_IDX
	cmp	#$0
	bne	cont
	
	; Update the LMS address to coarse scroll	
	clc	
	lda	scroll_lms
	adc	#$02
	sta	scroll_lms
	lda	scroll_lms + 1
	adc	#$00
	sta	scroll_lms + 1		
	
	; Reset the smooth scroll location
	sec
	lda	#$10		
cont
	sbc	#$01
	sta	SCR_IDX
	sta	HSCROL
	
	; RESET THE OVERALL SCROLLER  (Resets when scroll_lms points beyond blank_line
	lda	scroll_lms + 1
	cmp	#>blank_line
	bcc	do_not_reset_scroller	;Branch if the LMS HIGH pointer is lower than the last page of scroller data.
	
	lda	scroll_lms
	cmp	#<blank_line
	bcc	do_not_reset_scroller	;Bracnh of the LMS LOW pointer is lower than the last desired byte into the current page
			
	; RESET the scroller to the beginning of the text.
	lda	#<scroll_line
	sta	scroll_lms
	lda	#>scroll_line
	sta	scroll_lms + 1		

do_not_reset_scroller		
			
	
	; Update the position of the cloud, every 8th frame
	inc	cloud_reducer
	lda	cloud_reducer
	cmp	#$08
	bne	skip_cloud
	inc	cloud_pos
	lda	#$00
	sta	cloud_reducer
	
skip_cloud	
	lda	cloud_pos
	sta	HPOSP0
			
exit_vb	
	ExitDeferredVBI

; Display List Interrupt Service Routines
;
; These are broken out into short, simple, routines, to minimize DLI execution
; time for any one scan line or mode line.		

dl_set_clouds
	; Set the character set to the clouds
	pha
	SetCharacterSet cloud_chars, TRUE
	ChainDLI dl_isr, dl_set_clouds ; Next do the color-update DLI

dl_set_chars
	; Set the character set to the text
	pha
	SetCharacterSet charset, TRUE
	ChainDLI dl_set_colors, dl_set_chars ; Next to the fixed colors DLI

dl_set_colors
	; Set the colors for the remainder of the screen
	pha
	lda	#$26
	sta	COLPF0
	lda	#$46
	sta	COLPF1
	pla
	rti

dl_isr	
	; Changes the background color based on a table of colors and the
	; DLI_TABLE_IDX value.  It runs once per mode line, for 9 mode lines,
	; then chains the next DLI, which changes the character set back to
	; text ready for the status display.

	pha	;Store A and X
	txa
	pha
			
	ldx	DLI_TABLE_IDX		;Get the NEXT color ...
	lda	color_table, X		;from the table and
	sta	WSYNC			;wait for the next scan line
	sta	COLBK			;to update color register	
	inc	DLI_TABLE_IDX		;Move to NEXT color in table

	lda	DLI_TABLE_IDX		;Last Index/Color?
	cmp	#$09
	bne	exit_dli		; If not, exit here ...

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
				
; Macro Built Display List
title_display_list
		DL_TOP_OVERSCAN
		DL_LMS_MODE_ADDR [DL_TEXT_7 | DL_DLI], first_line ; Change to Clouds Character Set
		DL_BLANK_LINES	 1
		DL_MODE		 [DL_TEXT_4 | DL_DLI]	; Change Background Color
		DL_MODE		 [DL_TEXT_4 | DL_DLI]	
		DL_MODE		 [DL_TEXT_4 | DL_DLI]
		DL_MODE		 [DL_TEXT_4 | DL_DLI]
		DL_MODE		 [DL_TEXT_4 | DL_DLI]
		DL_MODE		 [DL_TEXT_4 | DL_DLI]
		DL_MODE		 [DL_TEXT_4 | DL_DLI]
		DL_MODE		 [DL_TEXT_4 | DL_DLI]
		DL_MODE		 [DL_TEXT_4 | DL_DLI]
		DL_MODE		 [DL_TEXT_4 | DL_DLI]   ; Resets Character Set
		DL_BLANK	 DL_BLANK_1, TRUE	; Set Final Colors
		DL_MODE		 DL_TEXT_6
		DL_MODE		 DL_TEXT_6
		DL_MODE		 DL_TEXT_6
		DL_MODE		 DL_TEXT_7
		DL_BLANK_LINES	 8		
		DL_MODE		 DL_TEXT_2
		DL_BLANK_LINES 	 8
		DL_LMS_MODE	 [DL_TEXT_7 | DL_HSCROLL]
scroll_lms	DL_LMS_ADDR	 scroll_line
		DL_BLANK_LINES	 8
		DL_BLANK_LINES 	 8	
		DL_JVB		 title_display_list	
		
		
; Data for the Title Screen	
		
first_line	dta	d'THE: WOEBEGONE TRAIL'*
		dta	d'                                        '
		dta	d'                                        '

		; Two lines of MODE 4 characters for the CLOUDS
		.HE 00 00 41 00 00 00 42 43 00 00 00 00 47 00 00 00 4B 4C 00 00
		.HE 00 58 59 00 00 4F 00 00 00 00 00 00 00 00 00 00 55 56 57 00
		.HE 00 60 61 62 63 00 00 00 00 64 65 66 67 68 69 6A 6B 6C 6D 00
		.HE 00 00 00 00 6E 6F 70 71 72 73 74 00 00 00 00 00 75 76 77 00
				
		dta	d'                                        '
		dta	d'                                        '
		dta	d'                                        '
		dta	d'                                        '
		dta	d'                                        '
		dta	d'                                        '
		dta	d'   CURRENT STATUS   '*
		dta	d' EVERYONE IS:alive. '
		dta	d'MORALE IS:faltering.'
		dta	d'location'*
		dta	d':'
		dta	d'SNAKE RIVER'*
		dta	d'   Press [START] to Die of Dysentery.   '*
		
scroll_line	dta	d"                      WELCOME TO "
		dta	d'THE WOEBEGONE TRAIL'*
		dta	d" ... A MODERN HOMAGE TO "
		dta	d'THE OREGON TRAIL'*
		dta	d' FOR '
		dta	d'ATARI 8-BIT'*
		dta	d' COMPUTERS'
		dta	d' ... '
		dta	d' FONT (provisional) BY "damieng" (damieng.com/typography) '
		dta	d' .......... press ['
		dta	d'START'*
		dta	d'] to die of dysentery.'	
blank_line	dta	d'                                        '
		dta	d'                                        '
	
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
		ins '../fonts/clouds.fnt'				
		
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
		.byte %0111110
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
		