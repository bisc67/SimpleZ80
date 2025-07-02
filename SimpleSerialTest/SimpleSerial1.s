
	org	$0000
acia_control:	equ %01111110
acia_data:		equ %01111111
tdre_flag:		equ %00000010
rdrf_flag:		equ %00000001

bootstrap:
	ld	a, %00000011	; Master reset
	out (acia_control),a
	ld	b,0
reset_stall:
	djnz reset_stall
	ld	a, %00010101	; Ints disabled, TX int disable, /16 clock, 8N1
	out (acia_control),a

transmit_string:
	ld	hl, test_string_to_send
tx_next_char:
tx_wait_1:
	in	a,(acia_control)
	and tdre_flag
	jr	z,tx_wait_1
forced_wait_1:
	djnz forced_wait_1
	ld	a,(hl)
	cp  0
	jr  z, string_transmit_done
	out (acia_data),a
	inc hl
	jr  tx_next_char
string_transmit_done:
	in	a,(acia_control)
	and rdrf_flag
	jr	z,transmit_string
character_received:
	in	a,(acia_data)
	ld	d,a
	ld	e,16
tx_wait_2:
	in	a,(acia_control)
	and tdre_flag
	jr  z,tx_wait_2
forced_wait_2:
	djnz forced_wait_2
	ld  a,d
	out (acia_data),a
	dec e
	jr	nz,tx_wait_2
	jp	transmit_string

test_string_to_send:
	defb	13,10,13,10,13,10
	defb	"Bootstrap ROM for proto board 1",13,10
	defb	"Hello World from Z80 land",13,10
	defb	"This is the second test string",13,10
	defb	13,10,13,10
	defb	0
	