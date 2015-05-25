;
;	ZX Diagnostics - fixing ZX Spectrums in the 21st Century
;	https://github.com/brendanalford/zx-diagnostics
;
;	Original code by Dylan Smith
;	Modifications and 128K support by Brendan Alford
;
;	This code is free software; you can redistribute it and/or
;	modify it under the terms of the GNU Lesser General Public
;	License as published by the Free Software Foundation;
;	version 2.1 of the License.
;
;	This code is distributed in the hope that it will be useful,
;	but WITHOUT ANY WARRANTY; without even the implied warranty of
;	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;	Lesser General Public License for more details.
;
;	print.asm
;	

;	Routines for printing a string to the screen. 
;	Control codes AT, PAPER, INK, BRIGHT 
;	and INVERSE are handled as you'd expect.
;	HL holds the location of the string to print

;	Defines for in-string control codes 

	define LEFT		8
	;define	RIGHT		9
	;define	DOWN		10
	;define	UP		11
	define	CR		13
	define	TAB		14
	define	ATTR		15
	define	INK		16
	define	PAPER		17
	define	FLASH		18
	define	BRIGHT		19
	define	TEXTBOLD	20
	define  TEXTNORM	21
	define	AT		22
	define	WIDTH		23
;
;	Prints a string to the screen.
;	Inputs: HL=location of string to be printed
;

print

;	Save all registers that are used by this routine

	push hl
	push de
	push bc
	push af

;	Once we have the current char value, HL always points to the next value to be read.

print_nextchar
	
	ld a, (hl)
	inc hl

;	Check for end of printable string, zero terminated
	
	cp 0 
	jp z, print_done

;	Check for carriage return
	
	cp '\n'
	jr nz, print_chk_left
	ld a, 0
	ld (v_column), a
	ld a,(v_row)
	inc a
	ld (v_row), a
	cp 24
	jr nz, print_nextchar
	ld a, 0
	ld (v_row), a
	jr print_nextchar

;	Check for Cursor Left control code

print_chk_left

	cp LEFT
	jr nz, print_chk_attr
	ld a, (v_width)
	ld b, a
	ld a, (v_column)
	sub b
	ld (v_column), a
	cp 0xff
	jr nz, print_nextchar
	ld a, 31
	ld (v_column), a
	ld a, (v_row)
	dec a
	ld (v_row), a
	cp 0xff
	jr nz, print_nextchar
	ld a, 23
	ld (v_row), a
	jr print_nextchar

;	Check for ATTR control code

print_chk_attr
	
	cp ATTR
	jp nz, print_chk_ink
	ld a, (hl)
	inc hl
	ld (v_attr), a
	jr print_nextchar

;	Check for INK control code

print_chk_ink

	cp INK
	jr nz, print_chk_tab
	ld a, (hl)
	inc hl
	and 7
	ld d, a
	ld a, (v_attr)
	and 0xf8
	or d
	ld (v_attr), a
	jr print_nextchar

;	Check for TAB control code

print_chk_tab

	cp TAB
	jr nz, print_chk_paper
	ld a, (hl)
	inc hl
	ld (v_column), a
	jr print_nextchar

;	Check for PAPER control code

print_chk_paper

	cp PAPER
	jr nz, print_chk_cr
	ld a, (hl)
	inc hl
	and 7
	rla
	rla
	rla
	ld d, a
	ld a, (v_attr)
	and 0xc7
	or d
	ld (v_attr), a
	jp print_nextchar

;	Check for carriage return (CR)s control code

print_chk_cr

	cp CR
	jr nz, print_chk_bright
	ld a, 0
	ld (v_column), a
	jp print_nextchar

;	Check for BRIGHT control code

print_chk_bright

	cp BRIGHT
	jr nz, print_chk_flash
	ld a, (hl)
	inc hl
	cp 0
	jr z, print_chk_bright_2
	ld a, 64

print_chk_bright_2

	ld d, a
	ld a, (v_attr)
	and 0xbf
	or d
	ld (v_attr), a
	jp print_nextchar

;	Check for FLASH control code

print_chk_flash

	cp FLASH
	jr nz, print_chk_at
	ld a, (hl)
	inc hl
	cp 0
	jr z, print_chk_flash_2
	ld a, 128

print_chk_flash_2

	ld d, a
	ld a, (v_attr)
	and 0x7f
	or d
	ld (v_attr), a
	jp print_chk_bold

;	Check for AT control code

print_chk_at

	cp AT
	jr nz, print_chk_bold
	ld a, (hl)
	inc hl
	cp 24
	jr c, print_chk_at_2
	ld a, 0

print_chk_at_2

	ld (v_row), a
	ld a, (hl)
	inc hl
	cp 249
	jr c, print_chk_at_3
	ld a, 0

print_chk_at_3

	ld (v_column), a
	jp print_nextchar

;	Check for BOLD control code

print_chk_bold

	cp TEXTBOLD
	jr nz, print_chk_norm
	ld a, 1
	ld (v_bold), a
	jp print_nextchar

;	Check for NORM (restores normal text) control code

print_chk_norm

	cp TEXTNORM
	jr nz, print_chk_width
	xor a
	ld (v_bold), a
	jp print_nextchar

print_chk_width

	cp WIDTH
	jr nz, print_char
	ld a, (hl)
	inc hl
	ld (v_width), a
	jp print_nextchar
	
;	Print a single character to screen

print_char

	call putchar

;	Update the print position, wrapping around
;	to screen start if necessary

	ld a, (v_width)
	ld b, a
	ld a, (v_column)
	add b
	ld (v_column), a
	cp 0
	jp nz, print_nextchar
	ld a, 0
	ld (v_column), a
	ld a, (v_row)
	inc a
	ld (v_row), a
	cp 24
	jp nz, print_nextchar
	ld a, 0
	ld (v_row), a

;	Return without printing the rest if we overflowed the bottom
;	of the screen.

print_done

;	Done, restore registers before returning

	pop af
	pop bc
	pop de
	pop hl
	ret
	
;
;	Puts a single character on screen. 
;	Inputs: A=character to print, HL=y,x coordinates to print at.
;	This routine drops directly into the putchar routine.
;

putchar_at

	push af
	ld a, h
	ld (v_row), a
	ld a, l
	ld (v_column), a
	pop af

;
;	Puts a single character on screen at the location in the
;	v_col and v_row variables, with v_attr colours.
;	Inputs: A=character to print.
;	

putchar

	push hl
	push bc
	push de
      
;	Find the address of the character in the bitmap table

	sub 32      ; space = offset 0
	ld hl, 0
	ld l, a

;	Multiply by 8 to get the byte offset
    
	add hl, hl
	add hl, hl
	add hl, hl

;	Add the offset
    
	ld bc, charset
	add hl, bc

;	Store result in de for later use
	
	ex de, hl
      
;	Now find the address in the frame buffer to be written.
	
	ld a, (v_row)
	and 0x18
	or 0x40
	ld h, a
	ld a, (v_row)
	and 0x7
	rla
	rla
	rla
	rla
	rla
	ld l, a
	ld a, (v_column)
	and 0x7
	ld (v_offset), a
	ld a, (v_column)
	srl a
	srl a
	srl a
	add a, l
	ld l, a

;	DE contains the address of the char bitmap
;	HL contains address in the frame buffer

;	Calculate mask for printing partial characters
	
	push hl
	push de
	ld a, (v_offset)
	ld hl, mask_bits
	ld e, a
	xor a
	ld d, a
	add hl, de
	ld a, (hl)
	ld (v_mask), a
	pop de
	pop hl

	ld b, 8

.putchar.loop

;	Move character bitmap into the frame buffer
	
	ld a, (de)        
	ld (v_prbyte), a
	
;	Do we need to print the character in bold?

	ld a, (v_bold)
	cp 0
	jr z, .putchar.afterbold

;	Bold character, grab byte, rotate it right then
;	OR it with the original value

	ld a, (v_prbyte)
	ld c, a
	rl c
	ld a, (v_prbyte)
	or c
	ld (v_prbyte), a
	
.putchar.afterbold

	push bc
	
;	Apply mask to first byte 

	ld a, (v_mask)
	ld b, (hl)
	and b
	ld (hl), a
	
	ld a, (v_offset)
	cp 0
	jr z, .putchar.norot
	ld b, a
	ld a, (v_prbyte)

.putchar.rot1

	srl a
	djnz .putchar.rot1
	jr .putchar.byte1
	
.putchar.norot

	ld a, (v_prbyte)
	
.putchar.byte1

	ld b, (hl)
	or b
	ld (hl), a
	pop bc

;	Check if we need to do second byte
	
	ld a, (v_offset)
	cp 0
	jr z, .putchar.nextbmpline
	inc hl

	push bc

;	Apply mask to second byte	

	ld a, (v_mask)
	cpl
	ld b, (hl)
	and b 
	ld (hl), a
	
	ld a, (v_offset)
	ld b, a
	ld a, 8
	sub b
	ld b, a
	
	ld a, (v_prbyte)

.putchar.rot2

	sla a
	djnz .putchar.rot2

	ld b, (hl)
	or b
	ld (hl), a
	
	pop bc
	dec hl
	
.putchar.nextbmpline

	inc de            ; next line of bitmap
	inc h             ; next line of frame buffer

.putchar.next

	djnz .putchar.loop

.putchar.attr

;	Now calculate attribute address

	ld a, (v_row)
	srl a
	srl a
	srl a
	and 3
	or 0x58
	ld h, a
	ld a, (v_row)
	sla a
	sla a
	sla a
	sla a
	sla a
	ld l, a
	ld a, (v_column)
	srl a
	srl a
	srl a
	add a, l
	ld l, a

;	Write the current colour values in the v_attr
;	sysvar to the just printed character

	ld a, (v_attr)
	ld (hl), a
	
	ld a, (v_offset)
	cp 0
	jr z, .putchar.end

;	Do adjacent character if it straddles two characters

	ld a, (v_attr)
	inc hl
	ld (hl), a
	
;	Done, restore registers and return

.putchar.end
	pop de
	pop bc
	pop hl
	ret

;
;	Sets the current print position.
;	Inputs: HL=desired print position y,x.
;

set_print_pos

	ld a, h
	ld (v_row), a
	ld a, l
	ld (v_column), a
	ret

;
;	Prints a 16-bit hex number to the buffer pointed to by DE.
;	Inputs: HL=number to print.
;

Num2Hex

	ld	a,h
	call	Num1
	ld	a,h
	call	Num2
	ld	a,l
	call	Num1
	ld	a,l
	jr	Num2

Num1

	rra
	rra
	rra
	rra

Num2

	or	0xF0
	daa
	add	a,#A0
	adc	a,#40

	ld	(de),a
	inc	de
	ret

;
;	Prints a 16-bit decimal number to the buffer pointed to by DE.
;	Inputs: HL=number to print.
;
Num2Dec	
	
	ld	bc, -10000
	call	Num1D
	ld	bc, -1000
	call	Num1D
	ld	bc, -100
	call	Num1D
	ld	c, -10
	call	Num1D
	ld	c, b

Num1D	

	ld	a, '0'-1

Num2D	

	inc	a
	add	hl,bc
	jr	c, Num2D
	sbc	hl,bc

	ld	(de),a
	inc	de
	ret

;
;	Checks to see if printing a string will overwrite the end of the line;
;	if so, it will advance the print position to the start of the next line.
;	Inputs: A=length of string to be printed in pixels.
;

check_end_of_line
	
	push bc
	ld b, a
	ld a, (v_column)
	add b
	pop bc
	ret nc
	xor a
	ld (v_column), a
	ld a, (v_row)
	inc a
	ld (v_row), a
	cp 24
	ret nz
	xor a
	ld (v_row), a
	ret

;
;	Clear the screen.
;

cls
	push hl
	push de
	push bc
	push af

;	Clear the bitmap locations

	ld a, 0
	ld hl, 16384
	ld (hl), a
	ld de, 16385
	ld bc, 6144
	ldir

;	Clear the attribute area. Use the attribute
;	value in v_attr for this.

	ld a, (v_attr)
	ld (hl), a
	ld bc, 768
	ldir
	pop af
	pop bc
	pop de
	pop hl
	ret

;
;	Moves print position to a new line.
;

newline

	push af
	xor a
	ld (v_column), a
	ld a, (v_row)
	inc a 
	ld (v_row), a
	pop af
	ret

;
;	Prints header with Spectrum stripe at top of screen.
;	Text to be printed in HL.
;

print_header

	push hl
	ld a, 0x47
	ld hl, 0x5800
	ld de, 0x5801
	ld bc, 0x1f
	ld (hl), a
	ldir
	pop hl
	ld a, (v_attr)
	push af
	ld a, 0x47
	ld (v_attr), a
	xor a
	ld (v_row), a
	ld a, (v_width)
	ld (v_column), a
	call print
	pop af
	ld (v_attr), a
	
	ld hl, stripe_attr
	ld de, 0x581a
	ld bc, 6
	ldir 
	
	ld a, 8
	ld b, a
	
	ld a, 1
	ld hl, 0x401a

.stripeloop

	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ld (hl), a
	dec hl
	dec hl
	dec hl
	dec hl
	inc h
	rla
	set 0, a
	djnz .stripeloop
	
	ret

mask_bits

	defb 0, 128, 192, 224, 240, 248, 252, 254
	
stripe_attr
	
	defb 0x42, 0x56, 0x74, 0x65, 0x68, 0x40 