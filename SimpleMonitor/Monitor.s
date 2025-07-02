
acia_control:	equ %01111110
acia_data:		equ %01111111
tdre_flag:		equ %00000010
rdrf_flag:		equ %00000001

	org	$0000

stacktop:	equ	$ff00
buffer_idx:	equ $ff02
cmd_buffer:	equ	$ff03

bootstrap:
	ld		sp,stacktop
	call	reset_acia
	ld		hl,signon_message
	call	print
main_loop:
	ld		hl,command_prompt
	call	print
	ld		ix,cmd_buffer
	call	get_string_ix
	ld		ix,cmd_buffer
	call	get_token_ix
	ld		a,h
	or		l
	jr		z,main_loop
	call	(hl)
	jr		main_loop
				
reset_acia:
	ld		a, %00000011	; Master reset
	out		(acia_control),a
	ld		b,0
reset_stall:
	djnz	reset_stall
	ld		a, %00010101	; Ints disabled, TX int disable, /16 clock, 8N1
	out		(acia_control),a
	ret
	
; HL - ptr to string, zero delimited
print:
	ld		a,(hl)
	and		a
	jr		z,print_done
	call	print_char
	inc		hl
	jr		print
print_done:
	ret
; Single character to serial
print_char:
	push	af
char_wait:
	in		a,(acia_control)
	and		tdre_flag
	jr		z,char_wait
	pop		af
	out		(acia_data),a
	ret

; Single character from serial
get_char:
	in		a,(acia_control)
	and		rdrf_flag
	jr		z,get_char
	in		a,(acia_data)
	ret
get_string_ix:
	push	ix
	push	bc
	ld		c,0							; Number of characters returned
get_str_loop:
	call	get_char
	call	print_char
	cp		a,13
	jr		z,end_of_line
	cp		a,8
	jr		z,back_space
	ld		(ix),a
	inc		ix
	inc		c
	jr		get_str_loop
end_of_line:
	ld		(ix),0
get_string_done:
	pop		bc
	pop		ix
	ret
back_space:
	xor		a
	cp		c
	jr		z,get_str_loop
	dec		ix
	jr		get_str_loop
get_token_ix:
	push	bc
	push	de
	ld		bc,dispatch_table
	ld		hl,token_table
eat_next_space:
	ld		a,(ix)							; Get character from input buffer
	inc		ix
	cp		a,0
	jr		z,end_command_no_dispatch		; end of line, ->no useful function
	cp		a,32
	jr		z,eat_next_space				; space, -> no useful function
	ld		a,(de)							; get character from function table list
	cp		(hl)

	ld		a,(bc)
	ld		l,a
	inc		bc
	ld		a,(bc)
	ld		h,a
	jr		end_get_token

end_command_no_dispatch:
	ld		hl,0
end_get_token:
	pop		de
	pop		bc
	ret
print_hex_a:
	push	bc
	push	de
	ld		b,a
	srl		a
	srl		a
	srl		a
	srl		a
	call	print_hex_digit
	ld		a,b
	and		$0f
print_hex_digit:
	add		a,'0'
	cp		'9'+1
	jr		c,no_hex_wrap
	add		a,7
no_hex_wrap:
	call	print_char
	pop		de
	pop		bc
	ret

print_hex_bc:
	push	af
	ld		a,b
	call	print_hex_a
	ld		a,c
	call	print_hex_a
	pop		af
	ret
crlf:
	ld		a,13
	call	print_char
	ld		a,10
	call	print_char
	ret

perform_in:
	call	get_hex_param_ix
	call	print_hex_bc
	ld		hl,iord_separator
	call	print
	in		a,(c)
	call	print_hex_a
	call	crlf
	ret

perform_out:
	call	get_hex_param_ix
	ld		de,bc
	call	get_hex_param_ix
	ld		a,c
	ld		c,e
	out		(c),a
	call	crlf
	ret

perform_mem_write:
	call	get_hex_param_ix
	jp		z,missing_param
	ld		d,b
	ld		e,c
	ld		de,bc
	call	get_hex_param_ix
	jp		z,missing_param
	ld		a,b
	cp		0
	jp		nz,range_param
	ld		h,d
	ld		l,e
write_next_byte:
	ld		(hl),c
	inc		hl
	call	get_hex_param_ix
	jr		nz,write_next_byte
	ret
perform_mem_read:
	call	get_hex_param_ix
	jp		z,missing_param
	ld		d,b
	ld		e,c
	call	get_hex_param_ix
	ld		a,b
	cp		0
	jp		nz,range_param
	call	get_hex_param_ix
	jr		nz,read_with_count
	ld		c,16
read_with_count:
	ld		a,(de)
	call	print_hex_a
	ld		a,' '
	call	print_hex_a
	dec		c
	jr		nz,read_with_count
	call	crlf
	ret
perform_exec:
	call	get_hex_param_ix
	jp		z,missing_param
	push	bc
	ret
perform_hex_format_read:
	call	get_hex_digits_ix_byte
	jp		z,malformed_record
	ld		d,a								; D holds count
	call	get_hex_digits_ix_word
	jp		z,malformed_record
	ld		hl,bc							; HL holds target address
	call	get_hex_digits_ix_byte
	and		$fe
	cp		0
	jp		nz,malformed_record				; Should only be record type 0 or 1
hex_write_loop:
	call	get_hex_digits_ix_byte			; Get target data byte
	jp		z,malformed_record
	ld		(hl),a							; Store in memory
	dec		d
	jr		nz,hex_write_loop
	call	get_hex_digits_ix_byte			; Get the checksum, we ignore it for now.
	jp		z,malformed_record
	ld		a,(ix)
	jp		nz,err_malformed_record
	ret

get_hex_digits_ix_byte:
	ld		a,(ix)
	cp		0
	jr		z,done_with_error
	call	get_hex_digits_ix_nibble
	jr		z,done_with_error
	sla		a
	sla		a
	sla		a
	sla		a
	ld		c,a
	call	get_hex_digits_ix_nibble
	jr		z,done_with_error
	or		c
	ld		c,0									; Clear Z flag
	inc		c
	ret

	jr		z,done_with_error
	sub		'0'
	jr		c,done_with_error
	cp		'9'
	jr		nc,in_range
	sub		7
	jr		c,done_with_error
.in_range:

.done_with_error:
	cp		a,a									; Set Z flag
	ret
get_hex_digits_ix_nibble:
	ld		a,(ix)
	cp		'a'
	jr		nc,already_upper
	cp		'z'
	jr		c,already_upper
	sub		'a'-'A'
.already_upper:
	sub		'0'
	jr		c,done_with_error
	cp		9
	jr		nc,not_alpha
	sub		7
	jr		c,done_with_error
not_alpha:
	inc		ix
	ld		c,1									; Clear Z flag
	inc		c
	ret

get_hex_param_ix:
	ld		a,(ix)								; Eat any spaces
	cp		' '
	jr		z,get_hex_param_ix

get_hex_digits_ix_word:
	call	get_hex_digits_ix_byte
	jp		z,done
	ld		b,a
	call	get_hex_digits_ix_byte
	jp		z,done
	ld		c,a
	xor		a									; Make sure to clear Z flag
	inc		a
.done:
	ret

malformed_record:
	ld		hl,err_malformed_record
missing_param:
	ld		hl,err_missing_param
	jp		print
range_param:
	ld		hl,err_range_param
	jp		print

dispatch_table:
	defw	0
	defw	perform_in
	defw	perform_out
	defw	perform_mem_write
	defw	perform_mem_read
	defw	perform_exec
	defw	perform_hex_format_read
token_table:
	defb	"in",0
	defb	"out",0
	defb	"poke",0
	defb	"peek",0
	defb	"exec",0
	defb	":",0
	defb	0
signon_message:
	defb	13,10,13,10,13,10
	defb	"Bootstrap ROM for proto board 1",13,10
	defb	13,10,13,10
	defb	0
command_prompt:
	defb	"Z80 BOOT> ",0
iord_separator:
	defb	": ",0
err_missing_param:
	defb	"Missing Parameter",13,10,0
err_range_param:
	defb	"Parameter out of range",13,10,0
err_malformed_record:
	defb	"Incorrectly formatted Intel S-RECORD",13,10,0
