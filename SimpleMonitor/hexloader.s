;
; Assemble with  z80asm -b hexloader.s
; connect via linux picocom --send-cmd "ascii-xfr -s -l 100 -c 10" /dev/ttyUSB0 -b 28800
; convert srec_cat hexloader.bin -Binary -offset 49152 -output hexloader.hex -Intel
; Test Records
; :10246200464C5549442050524F46494C4500464C33
; :0CC0000048656C6C6F20576F726C640A0E
; abcdefghijklmnopqrstuvwxyz
; Cycle budget @ 1.864Mhz
acia_status:	equ %01111110		; 0x7e
acia_data:		equ %01111111		; 0x7f
tdre_bit:		equ 0x01
rdrf_bit:		equ 0x00

psg_wr_addr:	equ	%10111111		; 0xbf
psg_rd_data:	equ	%10111111		; 0xbf
psg_wr_data:	equ	%10111110		; 0xbe

SOH				equ 01h
ETX				equ 03h
EOT				equ 04h
ACK				equ 06h
NAK				equ 15h
CAN				equ 18h
MAX_RETRIES		equ 100
TIMEOUT_CYCLES	equ 20000
TIMEOUT_RETRIES	equ 128
BLOCK_SIZE		equ 128
;;ACIA_INIT		equ %00010101				; Ints disabled, TX int disable, /16 clock, 8N1 - 115200 baud
ACIA_INIT		equ %00010110				; Ints disabled, TX int disable, /64 clock, 8N1 - 28800 baud

workspace:		equ 0xfe00
checksum:		equ 0 					; checksum byte									; 0xff00
run_addr:		equ checksum+2 			; last loaded address							; 0xff02
xmodem_start:	equ run_addr+2 			; xmodem start address							; 0xff04
xmodem_current: equ xmodem_start+2		; xmodem current transfer completed address		; 0xff06
xmodem_csum:	equ xmodem_current+2													; 0xff08
xmodem_retries: equ xmodem_csum+2														; 0xff0a
xmodem_acks:	equ xmodem_retries+2													; 0xff0c
xmodem_naks:	equ xmodem_acks+2														; 0xff0e
xmodem_lastblk:	equ xmodem_naks+2														; 0xff10
xmodem_thisblk:	equ	xmodem_lastblk+1													; 0xff11
xmodem_blkcomp:	equ	xmodem_thisblk+1													; 0xff12
xmodem_errors:	equ xmodem_blkcomp+1													; 0xff13
acia_config:	equ	xmodem_errors+2
config:			equ	acia_config+2														; 0xff15
serial_status:	equ config+2															; 0xff17
write_index:	equ serial_status+2
read_index:		equ write_index+1
buffer:			equ read_index+1														; 0xff19
stack_end:		equ 0x100


		org 0x0000
		;org 0xc000

; At 0x0000
start:
		ld	sp,workspace+stack_end
		call acia_reset
		call start_next
start_next:
		pop hl
		ld de,start-start_next
		add hl,de
		jr boot_continue
		ds 0x38-$,0xc9
; At 0x0038
		jp acia_interrupt
boot_continue:
		push hl
		call print_str
		db "\r\n******************************************"
		db "\r\n* Bootstrap loader for Z80, v0.91        *"
		db "\r\n* Load address 0x%x                    *"
		db "\r\n******************************************\r\n\r\n",0
		ld hl,0					; Copy ROM to RAM. Write to ROM space will write to RAM.
		ld de,hl
		ld bc,$8000
		ldir
		ld iy,workspace
		ld (iy+config),hl
		ld (iy+acia_config),ACIA_INIT
main_loop:
		ld hl,stack_end
		ld bc,iy
		add hl,bc
		ld sp,hl
		call print_str
		db "Enter command (m=mem,g=go,:=load,i=in port,o=out port,r=read,w=write,f=fill,x=xmodem,e=echo,b=toggle speed,p=page RAM): ", 0
		call read_line
		ld hl, iy
		ld bc,buffer
		add hl,bc
check_next:
		ld a,(hl)
		inc hl
		cp 0
		jp z,main_loop
		cp ' '
		jr z,check_next
		cp '\t'
		jr z,check_next
		cp '\r'
		jr z,check_next
		cp '\n'
		jr z,check_next
		cp 'm'
		jp z,memory_viewer
		cp ':'
		jp z,parse_intel_srec
		cp 'x'
		jp z,xmodem_receive
		cp 'g'
		jr z,execute
		cp 'i'
		jr z,in_port
		cp 'o'
		jp z,out_port
		cp 'r'
		jp z,read_mem
		cp 'w'
		jp z,write_mem
		cp 'e'
		jp z,console_echo
		cp 'f'
		jp z,fill_mem
		cp 'b'
		jp z,set_baud_rate
		cp 'p'
		jp z,page_ram
		cp 'i'
		jp z,toggle_interrupt_receive
		jp main_loop
parse_intel_srec:
		call parse_record
		jp	main_loop
;;---------------------------------------------------------------------------------------
;;---------------------------------------------------------------------------------------
memory_viewer:
		call memory_viewer_line
		jp main_loop
;;---------------------------------------------------------------------------------------
;;---------------------------------------------------------------------------------------
execute:
		call get_hex_word
		jp c, syntax_error
		push de
		push de				; parameter passing
		call print_str
		db "\r\nRunning from address 0x%x...\r\n", 0
		pop hl
		call (hl)
		jp main_loop
;;---------------------------------------------------------------------------------------
;;---------------------------------------------------------------------------------------
in_port:
		call get_hex_word
		jp c,syntax_error
		ld bc,de
		in a,(c)
		push af				; parameter passing
		push de				; parameter passing
		call print_str
		db "Port 0x%x: 0x%c\r\n", 0
		jp main_loop
;;---------------------------------------------------------------------------------------
;;---------------------------------------------------------------------------------------
out_port:
		call get_hex_word
		jp c,syntax_error
		push de
		call get_hex_word
		jp c,syntax_error_pop
		ld a,e
		pop bc
		out (c),a
		jp main_loop
syntax_error_pop_2:
		pop bc
syntax_error_pop:
		pop bc
		jp syntax_error
;;---------------------------------------------------------------------------------------
;;---------------------------------------------------------------------------------------
read_mem:
		call get_hex_word
		jp c,syntax_error
		ld a,(de)
		push af				; parameter passing for print_str
		push de
		call print_str
		db "0x%x : 0x%c\r\n",0
		jp main_loop
;;---------------------------------------------------------------------------------------
;;---------------------------------------------------------------------------------------
write_mem:
		call get_hex_word
		jp c,syntax_error
		push de
		call get_hex_word
		jp c,syntax_error_pop
		pop hl
		ld (hl),e
		jp main_loop
;;---------------------------------------------------------------------------------------
;;---------------------------------------------------------------------------------------
fill_mem:
		call get_hex_word
		jp c,syntax_error
		push de
		call get_hex_word
		jp c,syntax_error_pop
		push de
		call get_hex_word
		jp c,syntax_error_pop_2
		pop bc
		pop hl
; cannot use LDIR, since memory may be R/O. This causes a problem when it
; hits RAM. We may want to zap the memory in the background.
;;---------------------------------------------------------------------------------------
fill_loop:
		ld (hl),e
		inc hl
		dec bc
		ld a,b
		or c
		jr nz,fill_loop
		jp main_loop
;;---------------------------------------------------------------------------------------
;;---------------------------------------------------------------------------------------
set_baud_rate:
		ld a,(iy+config)
		xor 1
		ld (iy+config),a
		and 1
		jr z,set_slow
set_fast:
		call print_str
		db "Set baud rate to 115,200.\r\n",0
		ld a,(iy+acia_config)
		and 0x80
		or %00010101								; Ints disabled, TX int disable, /16 clock, 8N1 - 115200 baud
		out	(acia_status),a
		ld (iy+acia_config),a
		ret
		jp main_loop
set_slow:
		call print_str
		db "Set baud rate to 28,800.\r\n",0
		ld a,(iy+acia_config)
		and 0x80
		or %00010110								; Ints disabled, TX int disable, /64 clock, 8N1 - 28800 baud
		out	(acia_status),a
		ld (iy+acia_config),a
		jp main_loop
;;---------------------------------------------------------------------------------------
;;---------------------------------------------------------------------------------------
page_ram:
		ld a,7
		out (0xb1),a
		ld a,%01000000
		out (0xb0),a
		ld a,0x0e
		out (0xb1),a
		in a,(0xb1)
		xor 1
		out (0xb0),a
		bit 0,a
		jr z,rom_disabled
		call print_str
		db "ROM enabled.\r\n",0
		jp main_loop
rom_disabled:
		ld hl,0
		ld a,(hl)
		xor 0xff
		ld (hl),a
		ld b,(hl)
		cp b
		jr nz,ram_switch_failed
		call print_str
		db "RAM enabled.\r\n",0
		jp main_loop
ram_switch_failed:
		call print_str
		db "RAM write test failed.\r\n",0
		jp main_loop

toggle_interrupt_receive:
;;---------------------------------------------------------------------------------------
;;---------------------------------------------------------------------------------------
		ld a,(iy+config)
		xor 2
		ld (iy+config),a
		bit 1,a
		jr z,interrupt_disable
		ex af,af'
		exx
		ld hl,iy
		ld de,buffer
		add hl,de
		ld c,0
		ld (iy+read_index),0
		ld b,0
		add hl,buffer
		ex af,af'
		exx
		ld a,(iy+acia_config)
		or a,0x80
		ld (iy+acia_config),a
		out (acia_status),a
		im 2
		call print_str
		db "RX Interrupt enabled.\r\n",0
		ei
		jp main_loop

interrupt_disable:
		di
		ld a,(iy+acia_config)
		and a,0x7f
		ld (iy+acia_config),a
		out (acia_status),a
		call print_str
		db "RX Interrupt disabled.\r\n",0
		jp main_loop

; ----------------------------
; Read one line into buffer
; ----------------------------
; Total budget 161 clock cycles. To hit this budget, the read/write routines need
; to be inlined here. Resulting CPU use, 88 cycles per character (32 cycles per retry).

read_line:
		ld hl, iy
		ld bc, buffer
		add hl,bc
		ld bc, 0x7f1f
		ld e,0						; Buffer characters used.
wait_next_char:
		in a, (acia_status)			; 11
		and 3						; 8
		cp 3						; 8
		jr nz,wait_next_char		; 12/7
		in a, (acia_data)			; 11
		cp b						; 4
		jr z,backspace				; 12/7
		out (acia_data), a			; 11
		cp c						; 4
		jr c,control_char			; 12/7 (assume no branch)
		ld (hl), a					; 7
		inc hl						; 6
		inc e						; 4
		jr wait_next_char			; 12
									; 100 cycles total
control_char:
		cp 0x0d
		jr z,eol2
		cp 0x07
		jr z,backspace
		jr wait_next_char
eol2:
		ld a,0x0a
		call acia_putc
		ld (hl),0
		ret
backspace:
		ld a,0
		cp e
		jr z,wait_next_char
		dec hl
		dec e
		ld (hl),0
		ld a,127
		out (acia_data), a
		jr wait_next_char

; ----------------------------
; Parse Intel HEX record
; ----------------------------
parse_record:

		ld ix, hl
		xor a
		ld (iy+checksum), a

		call hexbyte_ix					; get byte count
		ld b, a
		call update_checksum

		call hexword_ix					; get target address
		ld d, h
		ld e, l
		ld a,h
		call update_checksum
		ld a,l
		call update_checksum

		call hexbyte_ix					; get record type
		call update_checksum
		cp 1
		jr z,loadloop
		cp 0
		jp nz,bad_record

loadloop:
		call hexbyte_ix
		call update_checksum
		ld (de), a
		inc de
		djnz loadloop

		call hexbyte_ix
		ld b,a
		ld a, (iy+checksum)

		add b
		jr nz, bad_checksum

		ld hl, de
		dec hl
		ld (run_addr), hl

		ld h, d
		ld l, e
		ld a, c
		ret

bad_checksum:
		call print_str
		db "checksum error\r\n", 0
		jp start
bad_record:
		call print_str
		db "Bad record type\r\n",0
		jp start

; ----------------------------
; Interactive memory viewer
; ----------------------------
memory_viewer_line:
		call get_hex_word
		jp c,syntax_error
		push de
		call get_hex_word
		pop hl
		jr nc,dump_param
		ld de, 128
dump_param:
		dec de
dumpmemloop:
		push hl
		call print_hex16
		call print_str
		db ": ", 0
		ld b, 16
dumpline:
		ld a, (hl)
		call print_hex8
		ld a,' '
		call acia_putc
		inc hl
		djnz dumpline
		call print_str
		db " : ",0
		pop hl
		ld b,16
dumpnextchar:
		ld a,(hl)
		bit 7,a
		jr nz,dumpbadchar
		cmp ' '
		jr c,dumpbadchar
		call acia_putc
dumpcont:
		inc hl
		djnz dumpnextchar
		call print_str
		db "\r\n", 0
		push hl
		ld hl,-16
		add hl,de
		ld de,hl
		pop hl
		jr c,dumpmemloop
		jp main_loop
dumpbadchar:
		ld a,'.'
		call acia_putc
		jr dumpcont
; ----------------------------
; Get 4 hex digits as 16-bit word
; IN:
;   HL -> pointer to null-terminated (or space) hex string (e.g., "1A3F")
; OUT:
;   DE = numeric value (16-bit)
; ----------------------------
get_hex_word:
		; eat any leading spaces
		ld a,(hl)
		cp ' '
		jr nz,parse_num
		inc hl
parse_num:

		ld de, 0           ; clear de to accumulate result
		; very first time, check for null string, as it's an error
		ld a,(hl)
		or a
		jr z,error_exit
nextchar:
		ld a, (hl)         ; get next character
		or a               ; end of string?
		jr z,end_of_string
		cp ' '
		jr z,end_of_string

		call hextonibble   ; convert ascii to 4-bit value (in a)
		jp c, invalidchar  ; jump if invalid character

		; shift de left 4 bits (multiply by 16)
		ld b, d
		ld c, e
		sla c
		rl b
		sla c
		rl b
		sla c
		rl b
		sla c
		rl b
		ld d, b
		ld e, c

		; add new nibble
		ld b, a
		ld a, e
		or b
		ld e, a

		inc hl
		jr nextchar
end_of_string:
		or a		; Clear carry, value was OK.
		ret
invalidchar:
		call print_str
		db	"Invalid hex digit\r\n",0
error_exit:
		scf
		ld de, 0xffff
		ret

; convert ascii hex character in a to value 0?15
; result in a, carry set on error
hextonibble:
		cp '0'
		jp c, bad
		cp '9' + 1
		jp c, convertnum

		cp 'a'
		jp c, checkupper
		cp 'f' + 1
		jp c, convertlower
		jp bad

checkupper:
		cp 'A'
		jp c, bad
		cp 'F' + 1
		jp nc, bad
		; fallthrough to convertupper
convertupper:
		sub 'A' - 10
		or a		; Clear carry
		ret

convertlower:
		sub 'a' - 10
		or a		; clear carry
		ret

convertnum:
		sub '0'
		and 0x0f
		or a	; clear carry
		ret
bad:
		scf     ; set carry
		ret
syntax_error:
		call print_str
		db "Syntax error\n\r",0
		jp main_loop
; ----------------------------
; Print 2-digit hex (A)
; ----------------------------
print_hex8:
		push af
		push af
		rra
		rra
		rra
		rra
		and 0x0f
		call print_hex_digit
		pop af
		and 0x0f
		call print_hex_digit
		pop af
		ret

; ----------------------------
; Print 4-digit hex (HL)
; ----------------------------
print_hex16:
		push af
		ld a, h
		call print_hex8
		ld a, l
		call print_hex8
		pop af
		ret

print_hex_digit:
		cp 10
		jr c, num_digit
		add a, 'a' - 10
		jp acia_putc
num_digit:
		add a, '0'
		jp acia_putc

; Routine to print unsigned 16-bit HL as decimal
print_dec16:
		push af
		push bc
		push hl
		ld b, 5           ; max 5 digits for 16-bit decimal
		ld c, 0

		; store digits in reverse order in stack
store_digits:
		call divmod10
		push af            ; store remainder (digit) on stack
		inc c
		ld a, h
		or l
		jr z, print_digits  ; if HL = 0, we're done
		djnz store_digits

print_digits:
		ld b,c
digit_loop:
		pop af
		add a, '0'         ; convert to ASCII
		call acia_putc
		djnz digit_loop
		pop hl
		pop bc
		pop af
		ret

; Input:  HL = 16-bit unsigned dividend
; Output: HL = quotient, A = remainder

divmod10:
	push bc
	ld c,10
div_hl_c:
	xor a           ; Clear A (remainder = 0)
	ld b, 16        ; We'll shift 16 bits
div_loop:
	add hl, hl      ; Shift HL left, MSB into carry
	rla             ; Shift A left through carry (A = remainder)
	jr c, skip_cmp  ; If carry set, remainder ? 128 ? definitely ? C
	cp c            ; Compare remainder to divisor
	jr c, skip_sub  ; If A < C, skip subtraction
skip_cmp:
	sub c           ; A -= C (remainder -= divisor)
	inc l           ; L = L + 1 (quotient bit set)
skip_sub:
	djnz div_loop   ; Repeat for all bits
	pop bc
	ret             ; L = quotient, A = remainder
   
; ----------------------------
; Print null-terminated string
; Destroys DE,HL
; ----------------------------
print_str:
		pop ix						; Get format string address
		push af						; save AF for now. We want to be non-destructive.
print_str_next:
		ld a, (ix)
		inc ix
		and a
		jr z,print_str_done
		cp '%'
		jr z,escape_character
not_escape:
		call acia_putc
		jr print_str_next
print_str_done:
		pop af
		jp (ix)
escape_character:
		ld a,(ix)
		inc ix
		and a
		jr z,print_str_done
		cp 'x'
		jr z,embedded_hex
		cp 'c'
		jr z,embedded_char
		cp 'd'
		jr z,embedded_int
		jp not_escape
embedded_hex:
		pop af
		pop hl
		push af
		call print_hex16
		jp print_str_next
embedded_char:
		pop de
		pop af
		push de
		call print_hex8
		jp print_str_next
embedded_int:
		pop af
		pop hl
		push af
		call print_dec16
		jp print_str_next

; ----------------------------
; Add A to checksum
; ----------------------------
update_checksum:
		push af
		add a, (iy+checksum)
		ld (iy+checksum), a
		pop af
		ret

; ----------------------------
; Read hex byte at (IX)
; ----------------------------
hexbyte_ix:
		ld a, (ix)
		call hextonibble
		sla a
		sla a
		sla a
		sla a
		ld iyh, a
		inc ix
		ld a, (ix)
		call hextonibble
		or iyh
		inc ix
		ret

; ----------------------------
; Read hex word from (IX)
; ----------------------------
hexword_ix:
		call hexbyte_ix
		ld h, a
		call hexbyte_ix
		ld l, a
		ret

send_ack:
		ld a, ACK
		jp acia_putc

send_nak:
		ld a, NAK
		jp acia_putc

; ----------------------------
; Main XMODEM Receive
xmodem_receive:
		call get_hex_word
		jp c,syntax_error
		ld (iy+xmodem_start),de
		ld (iy+xmodem_current),de
		push de
		call print_str
		db "Begin xmodem receive to 0x%x...\r\n"
		db "CTRL-D cancels\r\n",0
		ld b, TIMEOUT_RETRIES
		ld de,0
		ld (iy+xmodem_errors),de
		ld (iy+xmodem_lastblk),de
		ld (iy+xmodem_acks),de
		ld (iy+xmodem_naks),de
xmodem_send_initial_nak:
		call send_nak
xmodem_next_command:
		call acia_getc_timeout
		jp c, xmodem_retry_start     ; Timeout
		cp SOH
		jp z, xmodem_read_block
		cp EOT
		jp z, xmodem_end_receive
		cp CAN
		jp nz,xmodem_bad_ack
		jr xmodem_send_initial_nak
xmodem_bad_ack:
		push af
		call print_str
		db 0x18,0x18,0x18,0x18
		db "Bad ACK byte 0x%c\r\n",0
		jr xmodem_send_initial_nak

xmodem_retry_start:
		ld a,'?'
		call acia_putc
		djnz xmodem_send_initial_nak
		call print_str
		db 0x18,0x18,0x18,0x18
		db "xmodem timed out\r\n",0
		ret                     ; Too many timeouts

; ----------------------------
; Block reception
xmodem_read_block:
		ld a, MAX_RETRIES
		ld (iy+xmodem_retries),a
xmodem_retry_block:
		call acia_getc_timeout			; block #						; 66
		jp c,xmodem_retry_data											; 10
		ld (iy+xmodem_thisblk),a										; 19(!)
		call acia_getc_timeout			; block # complement			; 66
		jp c, xmodem_retry_data											; 10
		ld (iy+xmodem_blkcomp),a
		ld d, BLOCK_SIZE
		ld e, 0							; checksum
		ld hl,(iy+xmodem_current)
		ld a,h
		cp iyh
		jp z,xmodem_would_overwrite

xmodem_read_data_loop:
		call acia_getc_timeout
		jp c,xmodem_retry_data
		ld (hl),a
		inc hl
		add e						; Update checksum
		ld e,a
		dec d
		jr nz, xmodem_read_data_loop
		; All validation is done when the entire block has been received.
		call acia_getc_timeout		; checksum byte
		jp c, xmodem_checksum_timeout
		; Do checksum validation
		ld b,a						; Expected checksum
		ld c,e						; Calculated checksum
		cp e
		ld (iy+xmodem_csum),bc
		jp nz, xmodem_checksum_error
		; Do block number validation
		ld a,(iy+xmodem_thisblk)
		xor (iy+xmodem_blkcomp)
		cp 0xff
		jp nz,xmodem_invalid_complement
		; Do expected block number check
		ld a,(iy+xmodem_lastblk)			; This is the received block # from last time
		inc a
		cp (iy+xmodem_thisblk)
		jp nz,xmodem_sequence_jumped
		ld (iy+xmodem_lastblk),a
		ld (iy+xmodem_current),hl
		call send_ack
		ld bc,(iy+xmodem_acks)
		inc bc
		ld (iy+xmodem_acks),bc
		jp xmodem_next_command

xmodem_sequence_jumped:
		ld de,(iy+xmodem_errors)
		inc de
		ld (iy+xmodem_errors),de
		push bc				; Parameter, B=actual block sequence
		push af				; Parameter, A=expected block sequence
		call print_str
		db 0x18,0x18,0x18,0x18
		db "\r\nSequence number jumped. Expected 0x%c, got 0x%c.\r\n",0
		jp xmodem_done

xmodem_would_overwrite:
		ld de,(iy+xmodem_errors)
		inc de
		ld (iy+xmodem_errors),de
		push hl				; Parameter
		call print_str
		db 0x18,0x18,0x18,0x18
		db "\r\nNext block at 0x%x would overwrite workspace.\r\n",0
		jp xmodem_done

xmodem_invalid_complement:
		ld de,(iy+xmodem_errors)
		inc de
		ld (iy+xmodem_errors),de
		ld a,b
		cpl
		push af
		ld a,c
		push af
		ld a,b
		push af
		call print_str
		db "\r\nBlock number 0x%c and compliment 0x%c do not match. Expected 0x%c.\r\n",0
		jp retry_next
xmodem_give_up:
		call print_str
		db 0x18,0x18,0x18,0x18
		db "\r\nToo many block retries.\r\n",0
		jp xmodem_done
xmodem_checksum_timeout:
		ld de,(iy+xmodem_errors)
		inc de
		ld (iy+xmodem_errors),de
		call print_str
		db "\r\nTimeout while waiting for checksum.\r\n",0
		jp retry_next
xmodem_checksum_error:
		ld a,c
		push af				; Parameter, expected value
		ld a,b
		push af				; Parameter, calculated value
		ld de,(iy+xmodem_errors)
		inc de
		ld (iy+xmodem_errors),de
		call print_str
		db "\r\nChecksum did not match. Expected 0x%c, got 0x%c.\r\n",0
		jp retry_next
xmodem_retry_data:
		call print_str
		db "\r\nTimeout while waiting for data block.\r\n",0
		jp retry_next
retry_next:
		ld a,(iy+xmodem_retries)
		dec a
		ld (iy+xmodem_retries),a
		jp z,xmodem_give_up
		call send_nak
		ld de,(iy+xmodem_naks)
		inc de
		ld (iy+xmodem_naks),de
		jp xmodem_retry_block
xmodem_end_receive:
		call send_ack
xmodem_done:
		ld de,(iy+xmodem_start)
		ld hl,(iy+xmodem_current)
		sub hl,de
		push hl
		call print_str
		db 0x18,0x18,0x18,0x18
		db "\r\nxmodem receive completed. Received 0x%x bytes.\r\n",0
		ld de,(iy+xmodem_errors)
		push de
		ld de,(iy+xmodem_naks)
		push de
		ld de,(iy+xmodem_acks)
		push de
		call print_str
		db "%d ACKs, %d NAKs, %d errors.\r\n",0
		jp	main_loop
console_echo:
		call print_str
		db "Console Echo mode. CTRL-C quits.\r\n",0
		ld de,0
echo_loop:
		call acia_getc				; 52 cycles
		call acia_putc				; 74 cycles
		inc de
		cp 3						; 8
		jr nz,echo_loop				; 12/7
		push de
		call print_str
		db "\r\nEcho received %d bytes\r\n.",0
		jp main_loop
acia_reset:
		ld a, %00000011	; Master reset
		out	(acia_status),a
		ld	a, ACIA_INIT
		out	(acia_status),a
		ret

; ----------------------------
; Read character from 6850
; ----------------------------
acia_getc:
		;bit 0,(iy+config)
		;jr nz,interrupt_getc
		in a, (acia_status)			; 11
		bit rdrf_bit,a   			; 8
		jr z,acia_getc				; 12/7
		in a, (acia_data)			; 11
		ret							; 10
									; 52 cycles
interrupt_getc:
		ret
acia_interrupt:
		exx
		ex af,af'
		in a,(acia_status)
		bit 0,a
		jr z,interrupt_done
		add hl,bc
		ld (hl),a
		sub hl,bc
		ld a,c
		inc a
		and 0x7f
		cp e
		jr z,interrupt_done
		ld c,a
interrupt_done:
		ex af,af'
		exx
		ei
		reti

; ----------------------------
; Read character from 6850, with timeout
; Output A - character
; ----------------------------
acia_getc_timeout:
		bit 0,(iy+config)
		push bc						; 11
		ld bc, TIMEOUT_CYCLES		; 10
getch_wait_loop:
		in a, (acia_status)			; 11
		bit rdrf_bit,a				; 8
		jr z, getch_not_ready		; 7/12
		in a, (acia_data)			; 11
		or a						; 4 - clear carry
		pop bc						; 11
		ret							; 10 - carry clear = success
									; 83 cycles best case
getch_not_ready:
		dec bc						; 6
		ld a, b						; 4
		or c						; 4
		jr nz, getch_wait_loop		; 12/7
		scf							; 4 - set carry (timeout)
		pop bc
		ret							; 10
									; 61 cycles Best case 

; ----------------------------
; Write character to 6850
; ----------------------------
acia_putc:
		push af						; 11
acia_putc_wait:
		in a, (acia_status)			; 11
		bit tdre_bit,a				; 8
		jr z, acia_putc_wait		; 12/7
		pop af						; 11
		out (acia_data), a			; 11
		ret							; 10
									; 74 cycles

