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
;	testrom.asm
;

;
;	Spectrum Diagnostics ROM
;
;	v0.1 by Dylan 'Winston' Smith
;	v0.2 modifications and 128K testing by Brendan Alford.
;

	include "defines.asm"
	include "version.asm"

;
;	Define a build timestamp
;
	LUA ALLPASS

	file = io.open("branch.txt", "r")
	io.input(file)
	branch = io.read()
	io.close(file)
	sj.insert_define("GIT_BRANCH", '"' .. branch .. '"');


	sj.insert_define("BUILD_TIMESTAMP", '"' .. os.date("%d/%m/%Y %H:%M:%S") .. '"');

	ENDLUA

	org 0

; 	Ints must be disabled as we don't have
; 	anywhere reliable to put a stack yet

	di
	jp start

;	Define a version string in the dead space between the ROM start and the
;	NMI/start vector

	BLOCK 0x0038-$, 0xff

isr
	jp isr_main

	BLOCK 0x0066-$, 0xff

nmi

;	Start the keyboard test routine.
;	Handle this via NMI as the user may not be able
;	to hold down the K key if the keyboard membrane
;	is suspect.

	ld hl, 48878
	jp keyboard_test

	BLOCK 0x0080-$, 0xff

str_build

	defb	"ZX Diagnostics ", VERSION, "\nBuilt: ", BUILD_TIMESTAMP , 0

str_gitbranch

	defb  "Branch: ", GIT_BRANCH, 0

	BLOCK 0x0100-$, 0xff

start

;	I = 0 to signify basic ISR functionality

	ld a, 0
	ld i, a
	im 1

;	Blank the screen, (and all lower RAM)

	BLANKMEM 16384, 16384, 0

	ld a, 0xff
	out (LED_PORT), a		; Light all LED's on startup

;	Sound a brief tone to indicate tests are starting.
;	This also verifies that the CPU and ULA are working.

	ld l, 1				; Border colour to preserve
	BEEP 0x48, 0x0300
	BEEP 0x23, 0x0150

	xor a
	out (LED_PORT), a		; Extinguish the LED's

;	Tone done, check if space is being pressed

	ld bc, 0x7ffe
	in a, (c)

; 	Only interested in SPACE key, start testcard if pressed

	bit 0, a
	jp z, testcard

;	Launch about screen if Symbol shift is pressed

	bit 1, a
	jp z, about

;	Jump to memory browser if M is pressed

	bit 2, a
	jp z, mem_browser

;	Jump to ULA test routine if U key is pressed

	ld bc, 0xdffe
	in a, (c)
	bit 3, a
	jp z, ulatest

;	Jump to keyboard test if K is pressed

	ld bc, 0xbffe
	in a, (c)
	bit 2, a
	jp z, keyboard_test

;	Set up for tests

	xor a
	ld b, a		; using ixh to store a flag to tell us whether upper
                	; ram is good (if it is we continue testing)
	ld c, a
	ld ix, bc
	ld iy, bc 	; iy is our soak test status register
			; 0 - no soak test being performed; else
			; holds the current iteration of the test

;	Test if the S key is being pressed, if true then go into soaktest mode

	ld bc, 0xfdfe
	in a, (c)
	bit 1, a
	jr z, enable_soak_test

;	Andrew Bunker special :) Check if FIRE button of a Kempston interface
;	is being held, initiate soak tests if so

	ld bc, 0xff10

kemp_fire_test

	xor a
	in a, (0x1f)
	and 0x1f
	and c
	ld c, a
	djnz kemp_fire_test

	bit 4, c
	jr nz, enable_soak_test

	jr start_testing

enable_soak_test

	ld iy, 1	; Soak testing - start at iteration 1
	BEEP 0x10, 0x300

start_testing

;	Blue border - signal no errors (yet)

	ld a, BORDERGRN
	out (ULA_PORT), a

;	Same for LED's - all off signifies no errors

	xor a
	out (LED_PORT), a

;	Set all RAM to zero.

	BLANKMEM 16384, 49152, 0

;	Remove comment to bypass lower RAM test

	;jp use_uppermem

;	Start lower RAM 'walking bit' test

lowerram_walk

    	WALKLOOP 16384,16384

;	Then the inversion test

lowerram_inversion

    	ALTPATA 16384, 16384, 0
    	ALTPATA 16384, 16384, 255
    	ALTPATB 16384, 16384, 0
    	ALTPATB 16384, 16384, 255

lowerram_march

	MARCHTEST 16384, 16384

;	Lastly the Random fill test

lowerram_random

    	RANDFILLUP 16384, 8192, 11
    	RANDFILLDOWN 32766, 8191, 17

;	This gives the opportunity to visually see what's happening in
;	lower memory in case there is a problem with it.
;	Conveniently, if there's some lower RAM, then this'll give us
;	a pattern to lock onto with the floating bus sync test.

    	BLANKMEM 16384, 6144, 0

;	Attributes - white screen, blank ink.

	BLANKMEM 22528, 768, 56

;	Check if lower ram tests passed

    	ld a, ixh
    	cp 0
    	jp z, use_uppermem

;	Lower memory is no good, give up now.
;	We won't be able to test anything else effectively.
;	Finish with painting border with bad bits: black border
;	with red stripes for failed IC's, green for good ones.
;	Topmost stripe is bit 0, lowermost is bit 7.

;	Set diag board LED's to outline failed IC's

	ld de, ix
	ld a, d
	out (LED_PORT), a

lower_ram_fail

;
;	Paint the RAM FAIL message on screen
;	Set a black border here too
;

	ld hl, 0x5880
	ld de, 0x5881
	ld bc, 0x1ff
	ld (hl), 0
	ldir

	ld hl, fail_ram_bitmap
	ld de, 0x5880
	ld b, 0x40

fail_msg_loop

	ld c, 8
	ld a, (hl)

fail_msg_byte

	bit 7, a
	jr z, fail_msg_next

	ex de, hl
	ld (hl), 0x7f
	ex de, hl

fail_msg_next

	inc de
	rla
	dec c
	jr nz, fail_msg_byte

	inc hl
	dec b
	jr nz, fail_msg_loop


;	Blank out the working RAM digits

	ld hl, 0x5980
	ld c, ixh

	ld d, 8

fail_bits_outer_loop

	ld b, 8

fail_bits_loop

	bit 0, c
	jr nz, fail_bits_ok
	ld a, 0
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	jr fail_bits_next

fail_bits_ok

	inc hl
	inc hl
	inc hl
	inc hl

fail_bits_next

	rrc c
	djnz fail_bits_loop

	dec d
	ld a, d
	cp 0
	jr nz, fail_bits_outer_loop


;
;	Lower RAM failure detected, default ISR with I=0
;	jumps to routine that paints the bits in the border.
;	This'll work on a machine with no RAM and no floating bus.
;

	ei
	halt

;	Called from the ISR we just pointed at.
;	Start painting border, start with black

fail_border

	; Lose the return address, YAGNI
	pop bc

	; Failed bitmap is in IXH, transfer to DE
	ld de, ix

	ld a, d
	cp 0
	jr nz, fail_border_init

;	Don't paint stripes if all RAM has passed
;	(We've ended up here from one of the other
;	test routines that's done a cursory RAM check)

	ei
	halt

fail_border_init

;	Starting border black until we need stripes

	ld a, 0
	out (ULA_PORT), a

;	Add a small delay so that the stripes begin when
;	paper begins

	ld a, 0x24
	ld c, a
	ld a, 0x2
	ld b, a


fail_border_wait

	dec bc
	ld a, b
	or c
	jr nz, fail_border_wait

fail_border_1

	xor a
	ld c, a


; Change border to green or red depending on whether the current
; bit has been determined bad or not

fail_border_2

	ld a, 4
	bit 0, d
	jr z, fail_border_3
	ld a, 2

; Output the status colour for this bit

fail_border_3

	out (ULA_PORT), a
	ld a, 0xff
	ld b, a

fail_border_4

	djnz fail_border_4

; Change back to black for gap between stripes

	ld a, 0
	out (ULA_PORT), a
	ld a, 0xa8
	ld b, a

fail_border_5

	djnz fail_border_5
	rr d
	inc c
	ld a, c
	cp 8
	jr nz, fail_border_2

; Done, now delay a little

	ld bc, 0x40

fail_border_6

	dec bc
	ld a, c
	or b
	jr nz, fail_border_6

fail_border_7

;
;	Check if we're doing a soak test
;
	ld a, iyh
	or iyl
	jr z, fail_border_end
;
;	Yes, output an additional yellow stripe to signify this
;
	ld a, BORDERYEL
	out (ULA_PORT), a
	ld a, 0x8a
	ld b, a

fail_border_8

	djnz fail_border_8
	ld a, 0
	out (ULA_PORT), a

; And repeat for next frame - enable ints and wait for and interrupt
; to carry us back

fail_border_end

	ld de, ix
	ei
	halt

;
;	Upper / 128K RAM Testing
;

; We can initialise the screen/system vars now that we have verified
; lower RAM and can create a stack.

use_uppermem

;	Clear the rest of lower memory we just trashed

	BLANKMEM 0x5b00, 0x2500, 0

;	Init stack

    ld sp, sys_stack

	; Initialize system variables without performing additional RAM checks
	call initialize_no_ram_check

;	Clear the screen and print the top and bottom banners

	ld a, BORDERWHT
	out (ULA_PORT), a
	call cls
    ld hl, str_banner
    call print_header

	ld hl, str_lowerrampass
	call print

;	Are we in a soak test?

	ld a, iyh
	or iyl
	jr z, print_testrom_footer

;	Yes, print the current iteration

	ld hl, str_soaktest
	call print
	ld hl, iy
	ld de, v_decstr
	call Num2Dec
	ld hl, v_decstr
	call print
	jr rom_test

print_testrom_footer

	call print_footer

rom_test

;	Perform some ROM checksum testing to determine what
;	model we're running on

; 	Assume 128K toastrack (so far)

	xor a
	ld (v_128type), a

	ld a, (v_testhwtype)
	cp 0
	jr nz, rom_test_1

;	No diagnostic hardware, skip the check

	ld (v_column), a
	ld hl, str_romdiagboard
	call print
	jp rom_unknown_2

rom_test_1

; 	Call CRC generator in RAM, CRC ends up in HL

	ld hl, str_romcrc
    call print

   	call sys_romcrc

;	Save it in DE temporarily

	ld de, hl
	ld hl, rom_signature_table

; 	Check for a matching ROM

rom_check_loop

;	Check for 0000 end marker

	ld bc, (hl)
	ld a, b
	or c
	jp z, rom_unknown

;	Check saved ROM CRC in DE against value in table

	ld a, d
	xor b
	jr nz, rom_check_next
	ld a, e
	xor c
	jr z, rom_check_found

rom_check_next

	ld bc, 8
	add hl, bc
	jr rom_check_loop

rom_check_found

;	Print the appropriate ROM type to screen

	push hl
	inc hl
	inc hl
	ld de, (hl)
	ld hl, de
	xor a
	ld (v_column), a
	call print
	pop hl

;	Store the address of the testing routine

	ld de, 4
	add hl, de
	ld bc, (hl)
	ld (v_test_rtn), bc

;	Check if additional ROM tests need to be run (128 machines)

	inc hl
	inc hl
	ld de, (hl)
	ld a, d
	or e
	jr z, rom_test_pass

;	Extra ROM tests here
;	HL points to the ROM check table address
;	Pop it into IX for handiness sake

	ld de, (hl)
	ld ix, de

;	D tracks page number
	ld d, 1

additional_rom_check_loop

;	Page in ROM number (d)

	ld a, d
	call pagein_rom

	push de
	call sys_romcrc
	pop de

;	Check against the value at IX

	ld a, (ix)
	cp l
	jr nz, additional_rom_fail
	ld a, (ix + 1)
	cp h
	jr nz, additional_rom_fail

;	This ROM passed, skip ROM fail string pointer
;	and increment ROM page

	inc d
	inc ix
	inc ix
	inc ix
	inc ix

;	Any more ROM checksums?

	ld b, (ix)
	ld a, (ix + 1)
	or b
	jr nz, additional_rom_check_loop

;	All passed, say so and continue with a call to the routine at v_test_rtn

	jr rom_test_pass

additional_rom_fail

	ld hl, str_testfail
	call print
	call newline

	ld hl, str_check_rom
	call print
	ld de, (ix + 2)
	ld hl, de
	call print
	ld hl, str_check_rom_2
	call print

;	Signify a ROM checksum failure

	ld a, 0xff
	ld (v_fail_rom), a

	jp run_upper_ram_tests

rom_test_pass

;	Page in start ROM 0 again

	xor a
	call pagein_rom

	push hl
	ld hl, str_testpass
	call print
	call newline
	pop hl

run_upper_ram_tests

;	Call the appropriate testing routine
;	Set up return address to be the testinterrupts label

	ld de, testinterrupts
	push de

	ld de, (v_test_rtn)
	ld hl, de
	jp hl

; Unknown ROM, say so and prompt the user for manual selection

rom_unknown

	push de
	ld hl, str_romunknown
	xor a
	ld (v_column), a
	call print
	pop hl
    	ld de, v_hexstr
    	call Num2Hex
    	xor a
    	ld (v_hexstr+4), a
    	ld hl, v_hexstr
    	call print

rom_unknown_2

; 	Check if we're in soak test mode, if so assume 48K mode

	ld a, iyh
	or iyl
	jr z, rom_unknown_3

;	ROM unknown and in soak test, assume 48K

	ld hl, str_assume48k
	call print
	call newline
	call test_48k
	jr testinterrupts

rom_unknown_3

; 	Uncomment to disable user selection

	;call test_48k
	;jr testinterrupts

; 	end disable user selection

; 	Allow user to choose model if ROM version can't be determined

	ld hl, str_testselect
	call print

select_test

	ld bc, 0xf7fe
	in a, (c)

; 	Only interested in keys 1,2,3 and 4

	and 0xf
	cp 0xf
	jr z, select_test

;	Scan the test vector table and call the appropriate routine

	ld hl, test_vector_table
	ld b, a

select_test_1

	ld de, (hl)
	ld a, d
	or e
	jr z, select_test

	bit 0, b
	jr nz, select_test_2

	push hl
	ld de, (hl)
	ld hl, de
	call print

	pop hl
	inc hl
	inc hl
	ld de, (hl)
	ld hl, de
	ld de, testinterrupts
	push de
	jp hl

select_test_2

	ld de, 4
	add hl, de
	rr b
	jr select_test_1

testinterrupts

; 	Test ULA's generation of interrupts

;	Are we in a soak test situation?
;	Skip interrupt test if so

	ld a, iyh
	or iyl
	jr nz, tests_complete

	ld hl, str_interrupttest
	call print

; 	Save current print row

	ld a, (v_row)
	ld b, a

	ld hl, 0
	ld (v_intcount), hl
	ld (v_intcount + 2), hl

;	Enable interrupts to get counter running

	ei

intloop

; 	We'll start again as soon as an interrupt is raised

	halt

; 	Print the current counter value to screen. If the number is
; 	incrementing, interrupts are being generated correctly.

	push hl
	push bc
	ld hl, (v_intcount)
	ld de, v_hexstr
	call Num2Hex
	pop bc
	ld a, b
	ld (v_row), a
	ld a, 38 * 6
	ld (v_column), a
	ld hl, v_hexstr
	call print
	pop hl

;	Set LED's to LSB of counter word for visual feedback

	ld a, (v_intcount)
	out (LED_PORT), a

	cp 0
	jr nz, intloop
	ld hl, (v_intcount)
	ld a, h
	cp 3

;	Done if we've counted 0x300 interrupts

	jr nz, intloop

	ld a, b
	ld (v_row), a
	ld a, 38 * 6
	ld (v_column), a
	ld hl, str_testpass
	call print

;
;	All testing complete.
;

tests_complete

	di
	ld hl, 0
	ld (v_intcount), hl

;	Did we encounter any failures?

	xor a
	ld b, a
	ld a, (v_fail_ic)
	or b
	ld b, a
	ld a, (v_fail_ic_contend)
	or b
	ld b, a
	ld a, (v_fail_ic_uncontend)
	or b
	jr nz, tests_failed_halt

;	Did we hit a ROM checksum failure?

	ld a, (v_fail_rom)
	cp 0
	jr z, soak_test_check

;	Yes we did - say so and halt

tests_failed_halt

	call newline
	ld hl, str_halted_fail
	call print
	di
	halt

soak_test_check

;	All tests passed.
;	Are we in a soak test situation?

	ld a, iyh
	or iyl
	jr z, diaghw_present

	call newline
	ld hl, str_soakcomplete
	call print

;	A short delay before recommencing testing

	ld hl, 0x08
innerdelay_1
	ld bc, 0xffff
innerdelay_2
	dec bc
	ld a, b
	or c
	jr nz, innerdelay_2

	dec hl
	ld a, h
	or l
	jr nz, innerdelay_1

; 	Bump soak test iteration count and restart

	inc iy
	im 0
	jp start_testing


;	Check if we have diagboard hardware - if not, we're done here

diaghw_present

	ld a, (v_testhwtype)
	cp 0
	jr nz, diaghw_ok

;	No diagboard hw - say so and halt as we can't page system's ROM in

	ld hl, str_halted
	call print
	di
	halt

;	Announce that we're about to page the machine's own ROM in

diaghw_ok

	ld hl, str_pagingin
	call print
	ld a, (v_row)
	ld c, a

;	Print countdown

	ld b, 9
	ei

waitloop

	call check_spc_key
	jp z, testcard
	ld a, c
	ld (v_row), a
	ld a, 41 * 6
	ld (v_column), a

	ld a, b
	add '0'
	call putchar

; 	Wait 50 frames (or 1 second, depending how you count it)
;	Just use the least significant word of v_intcount for this.

	halt
	ld a, (v_intcount)
	cp 50
	jr nz, waitloop
	ld a, 0
	ld (v_intcount), a
	dec b
	ld a, b
	cp 0xff
	jr nz, waitloop

	im 0
	di

; 	WAIT message - about to page ROM in

	ld a, c
	ld (v_row), a
	ld a, 38 * 6
	ld (v_column), a
	ld hl, str_testwait
	call print

;	Copy the page in routine to RAM as we will need some
; 	code to init the machine's ROM once we release /ROMCS

page_speccy_rom

;	Passing 0x1234 to the pageout routine forces a jump to
;	the system ROM when done

	ld a, 2
	ld bc, 0x1234

;	We won't ever return from this call

	call sys_rompaging

;
;	Testing Routines
;

	include "48tests.asm"
	include "128tests.asm"

;
;	Subroutine to print a list of failing IC's.
;   	Inputs: D=bitmap of failed IC's, IX=start of IC number list
;

print_fail_ic

	ld b, 0

fail_print_ic_loop

	bit 0, d
	jr z, ic_ok

;	Bad IC, print out the corresponding location for a 48K machine

	ld hl, str_ic
	ld a, (v_128type)
	cp 3
	jr nz, print_ic_label

	ld hl, str_u

print_ic_label

	call print
	ld hl, ix

;	Strings are aligned to nearest 32 bytes, so we can just replace
;	this much the LSB

	ld a, b
	rlca
	rlca
	or l
	ld l, a

	call print
	ld a, 30
	call check_end_of_line

ic_ok

;	Rotate D register right to line up the next IC result
;	for checking in bit 0

	rr d

;	Loop round if we've got more bits to check

	inc b
	ld a, b
	cp 8
	jr nz, fail_print_ic_loop

	ret

;
;	Subroutines to print a list of failing IC's for 4 bit wide
;	memories (+2A/+3).
;   	Inputs: D=bitmap of failed IC's, IX=start of IC number list
;

print_fail_ic_4bit


	ld a, d
	and 0x0f
	jr z, next_4_bits

;	Bad IC, print out the correspoding location

	ld hl, str_ic
	call print
	ld hl, ix
	call print

next_4_bits

	ld bc, 4
	add ix, bc

	ld a, d
	and 0xf0
	jr z, bit4_check_done

	ld hl, str_ic
	call print
	ld hl, ix
	call print

bit4_check_done

	ret

;
;	Checks to see if the SPACE key was pressed.
;	Result: Z set if pressed, reset otherwise
;

check_spc_key

	ld a, 0x7f
	in a, (0xfe)
	bit 0, a
	ret

;
;	Initialise system variables.
;

initialize

;	Quick RAM integrity check from 5B00-7FFF.
;	This isn't as exhaustive as the main RAM
;	tests but aims to make sure the RAM is
;	somewhat working for testcard, ULA test,
;	memory browser etc.

	ld hl, 0x5b00
	ld ix, 0

; 	Save return address from the stack

	pop de

init_loop

	ld (hl), 0x00
	ld a, (hl)
	cp 0x00
	jp nz, lower_ram_fail
	ld (hl), 0xff
	ld a, (hl)
	cp 0xff
	jp nz, lower_ram_fail
	inc hl
	ld a, h
	cp 0x80
	jr c, init_loop

initialize_ram_good

;	Restore return address

	push de

initialize_no_ram_check

	xor a
	out (LED_PORT), a		; Extinguish the LED's
	ld (v_fail_ic), a
	ld (v_fail_ic_contend), a
	ld (v_fail_ic_uncontend), a
	ld (v_fail_rom), a
	ld (v_ay_present), a
	ld (v_column), a
    	ld (v_row), a
	ld (v_pr_ops), a
	ld a, 56
	ld (v_attr), a
	ld a, 2
	ld (v_scroll), a
	ld a, 21
	ld (v_scroll_lines), a

	ld a, 6
	ld (v_width), a
	ld a, 0xff
	ld (v_scroll), a
	cpl
	ld (v_scroll_lines), a

	ld hl, 0
	ld (v_paging), hl
	ld (v_userint), hl
	ld (v_intcount), hl
	ld (v_intcount + 2), hl

	xor a
	ld (v_ulatest_pos), a
	cpl
	ld (v_ulatest_dir), a

	ld b, 5
	xor a
	ld hl, v_hexstr

hexstr_init

	ld (hl), a
	inc hl
	djnz hexstr_init

	ld b, 6
	ld hl, v_decstr
	xor a

decstr_init

	ld (hl), a
	inc hl
	djnz decstr_init

;	Copy ROMCRC and ROM paging routines to RAM
;	We'll need them here as ROM code won't be accessible
;	during ROM checksums etc

	ld hl, romcrc
	ld de, sys_romcrc
	ld bc, romcrc_end-romcrc
	ldir

	ld hl, rompage_reloc
	ld de, sys_rompaging
	ld bc, end_rompage_reloc-rompage_reloc
	ldir

;	Ensure that on 128 machines, the default ROM is paged in.
;	This'll do nothing on 48K models.

	xor a
	ld bc, 0x7ffd
	out (c), a
	ld bc, 0x1ffd
	out (c), a

;	Signify that extended ISR can be called by setting
;	I to non-zero value. Don't use 0x3F as this'll upset
;	the ZXC4.

	ld a, 0x1f
	ld i, a

;	Check for whatever diagnostic hardware is present.
;	Result will be stored in system variable v_testhwtype.

	xor a
	call sys_rompaging

;	Reset the AY chip if present.

	call ay_reset
	ret

;
;	Called when the Diagnostic ROM wants to exit to BASIC.
;
diagrom_exit

;	Just do a simple reset if diagboard hardware isn't detected

	ld a, (v_testhwtype)
	cp 0
	jp z, 0000

;	Else page the diagnostic ROM out and start the machine's own ROM

	ld bc, 0x1234
	ld a, 2
	call sys_rompaging 	; Page out and restart the machine


	include "crc16.asm"
	include "input.asm"
	include "print.asm"
	include "scroll.asm"
	include "paging.asm"
	include "diagboard.asm"
	include "testcard.asm"
	include "ulatest.asm"
	include "keyboardtest.asm"
	include "membrowser.asm"
	include "romtables.asm"
	include "about.asm"

str_romdiagboard

	defb	AT, 4, 0, "Diagnostic hardware not detected", 0

;
;	Table to define pointers to test routines
;

test_vector_table

	defw str_select48k, test_48k
	defw str_select128k, test_128k
	defw str_selectplus2, test_plus2
	defw str_selectplus3, test_plus3
	defw 0x0000

;
;	String tables
;

; the ZX Spectrum Diagnostics Banner

str_banner

	defb	TEXTBOLD, "ZX Spectrum Diagnostics", TEXTNORM, 0

str_lowerrampass

	defb	AT, 2, 0, "Lower 16K RAM tests...      ", TAB, 38 * 6, TEXTBOLD, INK, 4, "PASS", TEXTNORM, INK, 0, 0

str_soaktest

	defb 	AT, 23, 8 * 6, "Soak test: iteration ", INK, 0, 0

str_test4

	defb	"\nUpper RAM Walk test...      ", 0

str_test5

	defb	"Upper RAM Inversion test... ", 0

str_test6

	defb	"Upper RAM March test...     ", 0

str_test7

	defb	"Upper RAM Random test...    ", 0


str_48ktestsfail

	defb	"\n", TEXTBOLD, PAPER, 2, INK, 7, "             48K tests FAILED             \n", TEXTNORM, ATTR, 56, 0

str_isthis16k

	defb	"This appears to be be a 16K Spectrum\n"
	defb    "If 48K, check IC23-IC26 (74LS157, 32, 00)",0

str_128ktestsfail

	defb	"\n", TEXTBOLD, PAPER, 2, INK, 7, "            128K tests FAILED             \n\n", TEXTNORM, ATTR, 56, 0


str_128kpagingfail

	defb	"\n", TEXTBOLD, PAPER, 2, INK, 7, "         128K Paging tests FAILED         \n\n", TEXTNORM, ATTR, 56, 0

str_romcrc

	defb	AT, 4, 0, "Checking ROM version...     ", 0

str_romunknown

	defb	AT, 4, 0, INK, 2, TEXTBOLD, "Unknown or corrupt ROM... ", TEXTNORM, INK, 0, "            ", ATTR, 56, 0

str_testselect

	defb	AT, 5, 0, "Press: 1..48K  2..128K  3..+2  4..+2A/+3", 0

str_assume48k

	defb 	AT, 5, 0, "Assuming 48K mode...", 0

str_select48k

	defb	AT, 5, 7 * 6, TEXTBOLD, INK, 4, "1..48K\n", TEXTNORM, ATTR, 56, 0

str_select128k

	defb	AT, 5, 15 * 6, TEXTBOLD, INK, 4, "2..128K\n", TEXTNORM, ATTR, 56, 0

str_selectplus2

	defb	AT, 5, 24 * 6, TEXTBOLD, INK, 4, "3..+2\n", TEXTNORM, ATTR, 56, 0

str_selectplus3

	defb	AT, 5, 31 * 6, TEXTBOLD, INK, 4, "4..+2A/+3\n", TEXTNORM, ATTR, 56, 0

str_dblbackspace

	defb	LEFT, LEFT, 0

str_testpass

	defb	INK, 4, TAB, 38 * 6, TEXTBOLD, "PASS", TEXTNORM, INK, 0, 0

str_testfail

	defb	INK, 2, TAB, 38 * 6, TEXTBOLD, "FAIL", TEXTNORM, INK, 0, 0

str_testwait

	defb	"WAIT", 0

str_newline

	defb	"\n",	0

str_testingbank

	defb	"\nTesting RAM bank  ", 0

str_testingpaging

	defb	"Testing paging    ", 0

str_bankm

	defb	"x ", 0

str_48ktestspass

	defb	"\n", PAPER, 4, INK, 7, BRIGHT, 1, TEXTBOLD, "           48K RAM Tests Passed           ", TEXTNORM, ATTR, 56, 0

str_128ktestspass

	defb	"\n", PAPER, 4, INK, 7, BRIGHT, 1, TEXTBOLD, "          128K RAM Tests Passed           ", TEXTNORM, ATTR, 56, 0

str_interrupttest

	defb	"\n\nTesting interrupts...", 0

str_interrupt_tab

	defb	TAB, 28, 0

str_soakcomplete

	defb	"\n       Soak test iteration complete  ", 0

str_halted

	defb	TEXTBOLD, "\n\n        *** Testing Completed ***", TEXTNORM, 0

str_halted_fail

	defb	TEXTBOLD, "\n      Failures found, system halted ", TEXTNORM, 0

str_pagingin

	defb	"\n\nPaging in Spectrum ROM...", 0

str_pagingtab

	defb	TAB, 41 * 6, 0

str_check_128_hal

	defb	"Check IC29 (PAL10H8CN) and IC31 (74LS174N)", 0

str_check_js128_hal

	defb	"Check HAL (GAL16V8) and U6 (74LS174N)", 0

str_check_plus2_hal

	defb	"Check IC7 (HAL10H8ACN) and IC6 (74LS174N)", 0

str_check_plus3_ula

	defb	"Check IC1 (ULA 40077)", 0

str_check_ic

	defb	"Check the following IC's:\n", 0

str_ic

	defb "IC", 0
str_u

	defb "U", 0

str_check_rom

	defb "Check ROM (", 0

str_check_rom_2

	defb ")\n", 0

;
;	This ISR operates in two modes.
;	If I = 0, then we are in lower RAM test mode. If ints are
;	enabled here, lower RAM testing as failed, so unconditionally
;	call the fail_border routine.
;	Otherwise, the ISR increments the v_intcount system variable and
;	if v_userint is non-zero, calls the interrupt service
;	routine at that address.
;
; 	v_intcount is a 32-bit number.

isr_main

	push af
	ld a, i
	cp 0
	jr nz, isr_2
	pop af
	jp fail_border
isr_2

	push hl
	push de
	push bc

	ld hl, (v_intcount)
	inc hl
	ld (v_intcount), hl
	ld a, h
	or l
	jr nz, intservice_user

	ld hl, (v_intcount + 2)
	inc hl
	ld (v_intcount + 2), hl

intservice_user

;	Is a user interrupt service configured (v_userint <> 0)

	ld hl, (v_userint)
	ld a, h
	or l
	jr z, intservice_exit

;	Yes, call it and set intservice_exit as the return address

	ld hl, intservice_exit
	push hl
	ld hl, (v_userint)
	jp hl

intservice_exit

	pop bc
	pop de
	pop hl
	pop af
	ei
	reti

;	Magic string to tell if we can page out our ROM (so that we can
;	tell the difference between Diagboard hardware and generic external
;	ROM boards)

str_rommagicstring

	defb "TROM"

;
;	Bitmap used to display RAM FAIL in attributes
;	if lower RAM tests fail
;
fail_ram_bitmap

	defb %00000000, %00000000, %00000000, %00000000
	defb %01100010, %01010000, %11100100, %11101000
	defb %01010101, %01110000, %10001010, %01001000
	defb %01010101, %01110000, %11001010, %01001000
	defb %01100111, %01010000, %10001110, %01001000
	defb %01010101, %01010000, %10001010, %01001000
	defb %01010101, %01010000, %10001010, %11101110
	defb %00000000, %00000000, %00000000, %00000000

	defb %00000000, %00000000, %00000000, %00000000
	defb %01000100, %01001110, %00101110, %01101110
	defb %10101100, %10100010, %10101000, %10000010
	defb %10100100, %00100100, %10100100, %11000100
	defb %10100100, %01000010, %11100010, %10100100
	defb %10100100, %10001010, %00101010, %10101000
	defb %01001110, %11100100, %00100100, %01001000
	defb %00000000, %00000000, %00000000, %00000000

free_space

;	Page align the IC strings to make calcs easier
;	Each string block needs to be aligned to 32 bytes

	BLOCK 0x3ae0-$, 0xff

free_space_end

str_bit_ref

	defb "0 ", 0, 0,  "1 ", 0, 0, "2 ", 0, 0, "3 ", 0, 0, "4 ", 0, 0, "5 ", 0, 0, "6 ", 0, 0, "7 ", 0, 0

str_48_ic

	defb "15 ",0, "16 ",0, "17 ",0, "18 ",0, "19 ",0, "20 ",0, "21 ",0, "22 ", 0

str_128k_ic_contend

	defb "6  ",0, "7  ",0, "8  ",0, "9  ",0, "10 ",0, "11 ",0, "12 ",0, "13 ", 0

str_128k_ic_uncontend

	defb "15 ",0, "16 ",0, "17 ",0, "18 ",0, "19 ",0, "20 ",0, "21 ",0, "22 ", 0

str_js128_ic_contend

	defb "20 ",0, "21 ",0, "22 ",0, "23 ",0, "24 ",0, "25 ",0, "26 ",0, "27 ", 0

str_js128_ic_uncontend

	defb "29 ",0, "28 ",0, "10 ",0, "9  ",0, "30 ",0, "31 ",0, "32 ",0, "33 ", 0

str_plus2_ic_contend

	defb "32 ",0, "31 ",0, "30 ",0, "29 ",0, "28 ",0, "27 ",0, "26 ",0, "25 ", 0

str_plus2_ic_uncontend

	defb "17 ",0, "18 ",0, "19 ",0, "20 ",0, "21 ",0, "22 ",0, "23 ",0, "24 ", 0

str_plus3_ic_contend

	defb "3  ", 0, "4  ", 0

str_plus3_ic_uncontend

	defb "5  ", 0, "6  ", 0


	BLOCK 0x3c00-$, 0xff

;	Character set at 0x3C00

	include "charset.asm"


;	Fill ROM space up to 0x3FBF with FF's

	BLOCK 0x3FC0-$, 0xff

;	3FC0 to 3FFF must be left unused for compatibility with the
;	ZXC3/ZXC4 cartridge paging mechanism.

	BLOCK 0x4000-$, 0x00

;	Define the system variable locations in upper RAM

	include "vars.asm"
