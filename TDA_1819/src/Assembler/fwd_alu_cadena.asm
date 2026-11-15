		.data
NUM1:	.word	10
NUM2:	.word	20
RES1:	.word	0
RES2:	.word	0
RES3:	.word	0
RES4:	.word	0

		.code
		lw r1, NUM1(r0)
		lw r2, NUM2(r0)
		dadd r3, r1, r2
		dadd r4, r3, r1
		dsub r5, r4, r2
		dmul r6, r5, r3
		sw r3, RES1(r0)
		sw r4, RES2(r0)
		sw r5, RES3(r0)
		sw r6, RES4(r0)
		halt