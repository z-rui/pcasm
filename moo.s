; register allocation:
; $r0 - zero
; $r1, $r3, ..., $r9  - caller saved
; $r2, $r4, ..., $r10 - callee saved
; $r11, $r12, $r13, $r14 - arguments
; $r15, $r16 - return value
; $r17-29 - reserved
; $r30 - stack pointer
; $r31 - return address

.text
	addi	$r30, $r0, 4096

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	addi	$r11, $r0, strBanner1
	jal	puts
	jal	newline

.one_game:
	addi	$r11, $r0, strBanner2
	jal	puts

	addi	$r4, $r0, randSeed
	lw	$r2, 0($r4)
	jal	clrpos

.loop0:
	input	$r1
	addi	$r2, $r2, 1
	addi	$r3, $r0, 256
	and	$r3, $r3, $r1
	beq	$r3, $r0, 1	; skip next if r3==0
	j	.loop0
	add	$r2, $r2, $r1
	sw	$r2, 0($r4)	; add input to random seed
	jal	newline

	addi	$r11, $r0, digits
	addi	$r12, $r0, randdigit
	addi	$r13, $r0, 0
	jal	getdigits

	addi	$r11, $r0, digits
	jal	clrpos

.one_guess:
	addi	$r11, $r0, digits1
	addi	$r12, $r0, readdigit
	addi	$r13, $r0, 1
	jal	getdigits
	;jal	newline
	addi	$r1, $r0, 32 ; ' '
	output	$r1
	jal	checkguess
	addi	$r2, $r15, 48	; '0'
	output	$r2
	addi	$r1, $r0, 65	; 'A'
	output	$r1
	addi	$r1, $r16, 48	; '0'
	output	$r1
	addi	$r1, $r0, 66	; 'B'
	output	$r1
	jal	newline

	addi	$r11, $r0, digits1
	jal	clrpos

	addi	$r1, $r0, 52
	beq	$r2, $r1, 1	; skip next if A==4
	j	.one_guess

	addi	$r11, $r0, strCongrats
	jal	puts
	jal	newline

	j	.one_game

clrpos:
	addi	$r1, $r0, 4
.L77:
	addi	$r1, $r1, -1
	add	$r3, $r1, $r11
	lw	$r5, 0($r3)
	addi	$r3, $r5, positions
	addi	$r5, $r0, -1
	sw	$r5, 0($r3)
	bgt	$r1, $r0, .L77
	jr	$r31

# r11 - digits[]
# r12 - function to call to get a digit
# r13 - whether to echo the digit
getdigits:
	addi	$r30, $r30, -6
	sw	$r31, 0($r30)
	sw	$r2, 1($r30)
	sw	$r4, 2($r30)
	sw	$r6, 3($r30)
	sw	$r8, 4($r30)
	sw	$r10, 5($r30)

	addi	$r2, $r0, 4 ; i
	addi	$r4, $r0, 9
	add	$r6, $r0, $r11
	add	$r8, $r0, $r12
	add	$r10, $r0, $r13
.L147:				; loop i=4,3,2,1
	addi	$r31, $r0, .L150
	jr	$r8
.L150:
	bgt	$r0, $r15, .L147; if r15<0
	bgt	$r15, $r4, .L147; if r15>9
	addi	$r3, $r15, positions
	lw	$r5, 0($r3)	; r5=positions[r15]
	bgt	$r0, $r5, 1	; skip next if r5<0
	j	.L147
	beq	$r10, $r0, .L135
	addi	$r1, $r15, 48
	output	$r1
.L135:
	addi	$r2, $r2, -1	; i--
	sw	$r2, 0($r3)	; positions[r1]=i
	add	$r3, $r2, $r6
	sw	$r15, 0($r3)	; digits[i]=r15
	bgt	$r2, $r0, .L147	; if i>0

	lw	$r10, 5($r30)
	lw	$r8, 4($r30)
	lw	$r6, 3($r30)
	lw	$r4, 2($r30)
	lw	$r2, 1($r30)
	lw	$r31, 0($r30)
	addi	$r30, $r30, 6
	jr	$r31

randdigit:
	addi	$r30, $r30, -1
	sw	$r31, 0($r30)
	jal	rand
	addi	$r1, $r0, 15
	and	$r15, $r15, $r1
	lw	$r31, 0($r30)
	addi	$r30, $r30, 1
	jr	$r31

readdigit:
	addi	$r30, $r30, -1
	sw	$r31, 0($r30)
	jal	getch
	addi	$r15, $r15, -48
	lw	$r31, 0($r30)
	addi	$r30, $r30, 1
	jr	$r31

checkguess:
	addi	$r15, $r0, 0	; A
	addi	$r16, $r0, 0	; B
	addi	$r1, $r0, 4	; i
.L177:
	addi	$r1, $r1, -1
	addi	$r3, $r1, digits
	lw	$r3, 0($r3)	; r3=digits[i]
	addi	$r5, $r1, digits1
	lw	$r5, 0($r5)	; r5=digits1[i]
	beq	$r3, $r5, .L189	; skip if r3==r5
	addi	$r3, $r3, positions
	lw	$r3, 0($r3)	; r3=positions[r5]
	bgt	$r0, $r3, 1	; skip next if r3<0
	addi	$r16, $r16, 1	; B++
	j	.L191
.L189:
	addi	$r15, $r15, 1	; A++
.L191:
	bgt	$r1, $r0, .L177	; if r1>0
	jr	$r31

.data

strBanner1:
	.asciiz "=moo game, v0.2="
	;.word 10
	;.ascii "(c) 2017     Rui"
	;.word 10
	;.word 0

strBanner2:
	.asciiz "Press any key..."

strCongrats:
	.asciiz "Congratulations!"

digits:
	.word 0
	.word 0
	.word 0
	.word 0

positions:
	.word -1
	.word -1
	.word -1
	.word -1
	.word -1
	.word -1
	.word -1
	.word -1
	.word -1
	.word -1

digits1:
	.word 0
	.word 0
	.word 0
	.word 0

