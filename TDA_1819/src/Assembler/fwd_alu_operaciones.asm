		.data
VAL:	.word	15
RES_A:	.word	0
RES_B:	.word	0
RES_C:	.word	0

		.code
		lw r1, VAL(r0)
		daddi r2, r1, 5
		dsli r3, r2, 2
		dadd r4, r3, r2
		andi r5, r4, 255
		sw r3, RES_A(r0)
		sw r4, RES_B(r0)
		sw r5, RES_C(r0)
		halt