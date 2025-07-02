
acia_control:	equ %01111110
acia_data:		equ %01111111
tdre_flag:		equ %00000010
rdrf_flag:		equ %00000001

scall: macro address
	ld ix,$+7
	jp address
	endm

	org	$0000

bootstrap:
	ld		a, %00000011	; Master reset
	out		(acia_control),a
	ld		b,0
reset_stall:
	djnz	reset_stall
	ld		a, %00010101	; Ints disabled, TX int disable, /16 clock, 8N1
	out		(acia_control),a

transmit_string:
	ld		hl,test_string_to_send
tx_next_char:
	ld		a,(hl)
	and		a
	jr		z,string_transmit_done
	scall	out_char
	inc		hl
	jr		tx_next_char
string_transmit_done:

	; memory test
	ld		hl,$8000
memtest_loop:
	ld		(hl),$ff
	ld		a,(hl)
	cp		$ff
	jr		nz, memtest_done
	ld		(hl),$00
	ld		a,(hl)
	cp		$00
	jr		nz, memtest_done
	inc		hl
	ld		a,h
	or		l
	jr		nz,memtest_loop
memtest_done:
	dec		hl
	ld		b,h
	ld		c,l
	ld		a,b					; Send high nibble of B
	scall	out_hex_hi
	ld		a,b					; Send low nibble of B
	scall	out_hex_lo
	ld		a,c					; Send high nibble of C
	scall	out_hex_hi
	ld		a,c					; Send low nibble of C
	scall	out_hex_lo
	ld		bc,0
rx_wait_1:
	in		a,(acia_control)
	and		rdrf_flag
	jr		nz,character_received
	dec		bc
	ld		a,b
	or		c
	jr		z,transmit_string
	jr		rx_wait_1
character_received:
	in		a,(acia_data)
	ld		d,a
	ld		e,16
tx_wait_2:
	in		a,(acia_control)
	and		tdre_flag
	jr		z,tx_wait_2
	ld		a,d
	out		(acia_data),a
	dec		e
	jr		nz,tx_wait_2
	jp		transmit_string
out_hex_hi:
	srl		a
	srl		a
	srl		a
	srl		a
out_hex_lo:
	and		$0f
out_hex_char:
	add		a,"0"
	cp		"9"+1
	jr		c, out_char
	add		a,7
out_char:
	out		(acia_data),a
hex_tx_wait:
	in		a,(acia_control)
	and		tdre_flag
	jr		z,hex_tx_wait
	jp		(ix)

test_string_to_send:
	defb	13,10,13,10,13,10
	defb	"Bootstrap ROM for proto board 1",13,10
	defb	"Hello World from Z80 land",13,10
	defb	"This is the second test string",13,10
	defb	13,10,13,10
	defb	"RAMTOP="
	defb	0
	