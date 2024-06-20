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
	; Use our custom character set
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
	
	; Setup DLI
	lda	#$00		; Initial Color Table Index
	sta	DLI_TABLE_IDX   ; Reset the Index for the DLI
	SetDLI  dl_isr
			
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
	;Color Cycling Index Points for VENETIAN scrolling
	ldx	COLOR_FLOW_TOP
	inx
	stx	COLOR_FLOW_TOP
	stx	COLOR_FLOW_LINE	
				
	; Do Scrolling
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
		
	; Reset the Table Lookup Index for our DLI
	lda	#$00
	sta	DLI_TABLE_IDX
	
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
			

	; Display List Interrupt Service Routine

dl_isr	
	; This routine runs too slowly.  Fixing it probably requires doing
	; DLI chaining so that we're only changing colors in one routine,
	; and character sets in another - rather than trying to conditionalize
	; both and get them done in one scan line.

	pha	;Store A and X
	txa
	pha
		
	; Change the colors first, as this is the most visible change and
	; we don't want to change an EXTRA scanline after the DLI has been
	; called as we're already on the last scan line of the mode line.

	ldx	DLI_TABLE_IDX		;Get the NEXT color ...
	lda	color_table, X		;from the table and
	sta	WSYNC			;wait for the next scan line
	sta	COLBK			;to update color register

	; This occurs partway across the screen, so we have an extra blank
	; scanline in the display list to allow for the character set change
	; to occur cleanly.
	SetCharacterSet cloud_chars, TRUE

	inc	DLI_TABLE_IDX		;Move to NEXT color in table

	lda	DLI_TABLE_IDX		;IF we're done with the TABLE-driven changes ... reset some values:
	cmp	#$0B
	bne	exit_dli

	; This occurs partway across the screen, so we have an extra blank
	; scanline in the display list to allow for the character set change
	; to occur cleanly.	
	SetCharacterSet charset, TRUE

	; TODO: These colors should be set once, AFTER we're done with the
	;       color gradient for the sky/landscape - so will need to be in a
	;       final, chained, DLI routine:

	;Set colors for remainder of screen
	 lda	#$26
	 sta	COLPF0
	 lda	#$46
	 sta	COLPF1
		
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
		DL_LMS_MODE_ADDR [DL_TEXT_7 | DL_DLI], first_line
		DL_BLANK_LINES	 1
		DL_MODE		 [DL_TEXT_4 | DL_DLI]
		DL_MODE		 [DL_TEXT_4 | DL_DLI]	
		DL_MODE		 [DL_TEXT_4 | DL_DLI]
		DL_MODE		 [DL_TEXT_4 | DL_DLI]
		DL_MODE		 [DL_TEXT_4 | DL_DLI]
		DL_MODE		 [DL_TEXT_4 | DL_DLI]
		DL_MODE		 [DL_TEXT_4 | DL_DLI]
		DL_MODE		 [DL_TEXT_4 | DL_DLI]
		DL_MODE		 [DL_TEXT_4 | DL_DLI]
		DL_MODE		 [DL_TEXT_4 | DL_DLI]
		DL_BLANK_LINES	 1
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
		.byte	$75, $75, $87, $9A, $BC, $BA, $B7, $E7, $F5, $F3, $F3

; Character SETs ... first for the text ...	
                AlignCharacterSet
charset
		ins '../fonts/high_noon.fnt'
		
; ... and then for the cloud and terrain graphics ...
		;AlignCharacterSet
		.align $800 ; Is ALSO a $400 boundary, so works for CHBASE and PMBASE

pm_graphics	; This puts a character set in the first, unused, 1KB of PMBASE 
cloud_chars     ; so we're not wasting that area.
		ins '../fonts/clouds.fnt'				
		
;.align		$800
;pm_graphics
;:1024		.byte $00	;Skip the first 1KB of the PMTable, so we start at PM0.
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
		