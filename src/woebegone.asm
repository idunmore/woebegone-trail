; woebegone.asm - An homage to "The Oregon Trail" for Atari 8-bit Computers
;
;                 This is the main source code file for the game.
;
;                 It is written using the MADS assembler and may not assemble
;                 correctly with other assemblers.

; Copyright (C) 2024, Ian Michael Dunmore
;
; Licensed Under: GNU Public License v3.0
; See: https://github.com/idunmore/woebegone-trail/blob/main/LICENSE

; Include Main Macros and Definitions

        icl '../include/common.asm'

; Program

        ; Program Entry Point
        org $2000

        icl 'title.asm'

        ; For now, do nothing and keep doing it.
                
;iloop
        ;jmp iloop