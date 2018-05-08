.text

puts:
	lw	$r1, 0($r11)
	beq	$r1, $r0, .puts_ret
	output	$r1
	addi	$r11, $r11, 1
	j	puts
.puts_ret:
	jr	$r31

newline:
	addi	$r1, $r0, 13
	output	$r1
	jr	$r31

getch:
	input	$r15
	addi	$r3, $r0, 0x100
	and	$r3, $r3, $r15
	bgt	$r3, $r0, getch
	jr	$r31

mul:
	addi	$r15, $r0, 0
	addi	$r1, $r0, 1
.mul_loop:
	beq	$r1, $r0, .mul_ret
	and	$r3, $r1, $r11
	beq	$r3, $r0, 1	; skip next if r3==0
	add	$r15, $r15, $r12
	addi	$r3, $r0, 1
	sll	$r1, $r1, $r3	; r1<<=1
	sll	$r12, $r12, $r3	; r12<<=1
	j	.mul_loop
.mul_ret:
	jr	$r31

rand:
	addi	$r30, $r30, -2
	sw	$r31, 0($r30)
	sw	$r2, 1($r30)

	addi	$r2, $r0, randSeed
	lw	$r11, 0($r2)
	lw	$r12, 1($r2)
	jal	mul
	addi	$r15, $r15, 1
	sw	$r15, 0($r2)

	lw	$r2, 1($r30)
	lw	$r31, 0($r30)
	addi	$r30, $r30, 2
	jr	$r31

.data

randSeed:
	.word 1
	.word 429196821
