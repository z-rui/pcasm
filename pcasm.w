\datethis

@* Introduction.
This is an {\bf as}se{\bf m}bler for ECE 550 Homework 4.
It's named like this because the homework is named
{\bf P}rocessor {\bf C}ore Design.

We include some headers that seem very useful, and
also put type and function declarations at the top.
@c
#include "tools.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

@<declarations@>@;

@ The instruction set is like a stripped down version of 32-bit MIPS.
There are only a few instructions, which will be introduced in later sections.

@s word_t int
@d WORD_BIT (sizeof (word_t) * CHAR_BIT)
@<decl...@>+=
typedef uint32_t word_t;

@ We use a big structure to represent the assembler.
But the fields inside the structure will be introduced in later sections.
@<decl...@>+=
typedef struct {
	@<fields in |assembler_t|@>@;
} assembler_t;

@ Allocating and freeing an assembler.
@c
assembler_t *asm_alloc(void)
{
	assembler_t *as;

	as = mem_alloc_zero(1, sizeof *as);
	@<initialize |assembler_t|@>@;
	return as;
}

void asm_free(assembler_t *as)
{
	if (as != NULL) {
		@<finalize |assembler_t|@>@;
		mem_free(as);
	}
}

@* Instruction Set.

@d OPCODE_WIDTH 5	/* opcode is 5-bit */
@d REGNO_WIDTH 5
@d IMMEDIATE_WIDTH 17
@d TARGET_WIDTH 27
@d R_TYPE 0
@d I_TYPE 1
@d J_TYPE 2
@<decl...@>+=
struct inst_info_t {
	const char name[8];
	unsigned opcode:OPCODE_WIDTH;
	unsigned type:2;
	const char argdesc[4];
};

@ We define a global array recording the information of all instructions.
The |argdesc| field describes what arguments does a instruction take;
it will help the parsing process.
@c
struct inst_info_t inst_info[] = {
	@[@]@<list of instruction descriptions@>
	@[{"", 0, 0, ""}@]
};

@ We have six R~type instructions.
For this type of instructions, the |argdesc| field is |"rrr"|.
Each {\tt r} refers to a register argument.

@<list of inst...@>+=
{"add",	0, R_TYPE, "rrr"},@/
{"sub",	1, R_TYPE, "rrr"},@/
{"and",	2, R_TYPE, "rrr"},@/
{"or",@t\phantom{\tt0}@>3, R_TYPE, "rrr"},@/
{"sll",	4, R_TYPE, "rrr"},@/
{"srl",	5, R_TYPE, "rrr"},@[@]

@ We have an ``add immediate'' instruction, {\tt addi}.
It is I~type, and its |argdesc| field is |"rrN"|.
The last {\tt N} refers to a numeric constant argument.
@<list of inst...@>+=
{"addi", 6, I_TYPE, "rrN"},@[@]

@ We have only two instructions for accessing memory: {\tt lw} and {\tt sw},
loading and saving a word.
There are no load/save byte instructions, because our memory is word-addressed.
They are I~type instructions, but the |argdesc| fields are |"rM"|,
where {\tt M} refers to an argument of the form {\tt N(\$rs)}.

@<list of inst...@>+=
{"lw", 7, I_TYPE, "rM"},@/
{"sw", 8, I_TYPE, "rM"},@[@]

@ We have two branching instructions.
@<list of inst...@>+=
{"beq",@t\phantom0@>9, I_TYPE, "rrN"},@/
{"bgt", 10, I_TYPE, "rrN"},@[@]

@ There are three instructions related to jumping.
One of them, {\tt jr}, is (strangely) an I~type instruction,
though it does not make use of the immediate.
The other two are J~type.
@<list of inst...@>+=
{"jr",@t\phantom{\tt0}@>11, I_TYPE, "r"},@/
{"j",@t\phantom{\tt00}@>12, J_TYPE, "N"},@/
{"jal", 13, J_TYPE, "N"},@[@]

@ The last two instructions are related to I/O.
Without them, our programs will be less exciting.
@<list of inst...@>+=
{"input",@t\phantom{\tt0}@>14, I_TYPE, "r"},@/
{"output", 15, I_TYPE, "r"},@[@]

@ Given an instruction name, we can get the related information
by searching the |inst_info| table.

Since the number of instructions is quite small,
I think a linear search is sufficient.

@c
int strcmp2(const char *s, const char *t, const char *z)
{
	while (t != z && *s == *t) {
		s++;
		t++;
	}
	return *s - ((t == z) ? '\0' : *t);
}

const struct inst_info_t *
get_inst_info(const char *name, const char *name_end)
{
	const struct inst_info_t *p;

	for (p = inst_info; p->name[0] != '\0'; p++) {
		if (strcmp2(p->name, name, name_end) == 0) {
			return p;
		}
	}
	return NULL;
}

@ Given opcode and other fields, we can pack an instruction into a word.
@d MAX_OPCODE 15
@d MAX_REGISTER ((1<<REGNO_WIDTH)-1)
@d MAX_IMMEDIATE (((word_t) 1<<IMMEDIATE_WIDTH)-1)
@d MAX_TARGET (((word_t) 1<<TARGET_WIDTH)-1)
@c
word_t
pack_rtype(unsigned opcode, unsigned rd, unsigned rs, unsigned rt)
{
	assert(opcode<=MAX_OPCODE);
	assert(rd<=MAX_REGISTER);
	assert(rs<=MAX_REGISTER);
	assert(rt<=MAX_REGISTER);
	return (opcode<<27) | (rd<<22) | (rs<<17) | (rt<<12);
}

word_t
pack_itype(unsigned opcode, unsigned rd, unsigned rs, word_t imm)
{
	assert(opcode<=MAX_OPCODE);
	assert(rd<=MAX_REGISTER);
	assert(rs<=MAX_REGISTER);
	assert(imm<=MAX_IMMEDIATE);
	return (opcode<<27) | (rd<<22) | (rs<<17) | imm;
}

word_t
pack_jtype(unsigned opcode, word_t target)
{
	assert(opcode<=MAX_OPCODE);
	assert(target<=MAX_TARGET);
	return (opcode<<27) | target;
}

@* Parsing.
We need to read an {\tt .s} file and parse its contents,
so that we know what instructions are in the program.
This is done with a parser.

The parser for an assembly language is a rather simple one
(compared to one for a ``high-level language'').
We will implement a parser that reads the file line by line,
and parses each line once it is read.

To use the parser, someone reads a line of input,
and puts its content in |linebuf|.
Then it calls |parse_line| and the parser will parse the line.

The parser will record the type of the instruction in |ins|.
It may be NULL if the current line does not have an instruction.

@<fields in |assembler_t|@>+=
char *linebuf;
size_t linebuf_sz;
int lineno;
const struct inst_info_t *ins;

@ @<finalize |assembler_t|@>+=
mem_free(as->linebuf);

@*1 Scanning tokens.
The fundamental job is to determine what tokens there are in the line.
In our assembly language, there won't be many kind of tokens,
and we define a function for parsing a kind of token.

When scanning tokens, it's necessary to determine if a character is
a letter, digit, etc.
We will use library functions in {\tt <ctype.h>} to do this job.

@c
#include <ctype.h>

@ A {\it name\/} consists of letters and digits,
and must start with a letter.
For our purpose, we count `{\tt \char`\_}' and~`{\tt .}' as letters,
i.e., we allow underscores and dots to appear in names.

@c
char *parse_name(const char *s)
{
	char ch;

	ch = *s;
	if (isalpha(ch) || ch == '_' || ch == '.') {
		do {
			ch = *++s;
		} while (isalnum(ch) || ch == '_' || ch == '.');
	}
	return (char *) s;
}

@ A {\it number\/} can be decimal, octal or hexadecimal.
The format follows \CEE/'s convention, and we will make use of |strtoull|.
@c
word_t parse_number(const char *s, char **endp)
{
	return strtoull(s, endp, 0);
}

@ A {\it register\/} is {\tt \$r0}--{\tt \$r31}.
@c
int parse_reg(const char *s, char **endp)
{
	word_t val;
	char *end;

	if (*s++ != '$')
		return 0;
	if (*s++ != 'r')
		return 0;
	val = strtoul(s, &end, 10); /* only allow decimal here */
	if (s == end || val > MAX_REGISTER) /* invalid register number */
		return 0;
	*endp = end;
	return (int) val;
}

@*1 Parsing a line.
Think the parser as a state machine.
When parsing a line, there are a few states depending on what
we are expecting to see.

@c
char *
parse_line(assembler_t *as)
{
	char *pos = NULL, *save = NULL;
	const char *argdesc = NULL;
	@<initialize line parsing@>@;
	@<parsing states@>@;
parse_success:
	return NULL;
parse_fail:
	return pos;
}

@ Before parsing a line, we need to set the parser to a proper state.

@<initialize line parsing@>=
pos = as->linebuf; /* cursor points to line head */
/* at line start, looking for an instruction name */
goto parse_op;

@ @<skip whitespaces@>=
while (isspace(*pos))
	++pos;

@ After skipping white spaces, if the next character is {\tt\char`\\0},
then we reach the line end.
To allow comments at the line end, we also allow {\tt\#} and {\tt;}
to signal a line end.

@d iseol(x) ((x) == '\0' || (x) == '#' || (x) == ';')

@ A trick to simplify the parser is to treat directives as instructions.
So we are so have entries in |inst_info| for directives.
The parser will store appropriate value to |ins| so that the assembler
will know which directive it is in the current line.

@d DIRECTIVE 3
@<list of instruction descriptions@>+=
{".text",@t\phantom{\tt00}@>0, DIRECTIVE, ""},@/
{".data",@t\phantom{\tt00}@>1, DIRECTIVE, ""},@/
{".word",@t\phantom{\tt00}@>2, DIRECTIVE, "N"},@/
{".asciiz", 3, DIRECTIVE, "S"},@/
{".ascii",@t\phantom{\tt0}@>4, DIRECTIVE, "S"},@[@]

@ When we are at the beginning of the line,
an instruction, a directive, or a label may follow.
However, we merge these into a single state because they all start
with a {\it name\/} token.
And since directives are treated as instructions,
there are only two cases, and it's easy to distinguish them:
if the name read is known (stored in |inst_info|),
then it is an instruction (or directive),
otherwise it is a label, and a colon should follow.

(Another way to distinguish an instruction and a label is to ``look ahead''
 whether a colon follows.)

@<parsing states@>=
parse_op:
	@<skip whitespaces@>@;
	if (iseol(*pos)) {
		/* a line without any instruction is OK */
		as->ins = NULL;
		goto parse_success;
	}
	save = pos;
	pos = parse_name(pos);
	if (pos == save) {
		goto parse_fail;
	}
	as->ins = get_inst_info(save, pos);
	@<skip whitespaces@>@;
	if (*pos == ':') { /* a label */
		asm_labeldef(as, save, pos);
		++pos; /* skip `{\tt:}' */
		goto parse_op;
	}
	if (as->ins == NULL) { /* not an valid instruction name */
		goto parse_fail;
	}
	argdesc = as->ins->argdesc;
	as->nreg = 0;
	as->immtarget = 0;
	goto parse_arg;

@ @<parsing states@>+=
parse_arg:
	assert(argdesc != NULL);
	@<skip whitespaces@>@;
	if (*argdesc == '\0') { /* no more arguments */
		argdesc = NULL;
		if (iseol(*pos))
			goto parse_success;
		else
			goto parse_fail;
	}
	switch (*argdesc++) {
		@<cases for different argument types@>@;
		default: assert(0); /* impossible or bug */
	}
	if (*argdesc != '\0') { /* more arguments */
		@<skip whitespaces@>@;
		if (*pos != ',') /* expecting a comma */
			goto parse_fail;
		++pos; /* skip `{\tt,}’ */
	}
	goto parse_arg;

@
@d MAX_REGARG 3
@<fields in |assembler_t|@>+=
int regno[MAX_REGARG];
int nreg;
word_t immtarget; /* immediate or target */

@ @<cases for different argument types@>=
case 'r':
	@<parse one more register@>@;
	break;

@ @<parse one more register@>=
assert(as->nreg < MAX_REGARG);
save = pos;
as->regno[as->nreg++] = parse_reg(pos, &pos);
if (pos == save)
	goto parse_fail;

@ @<cases for different argument types@>=
case 'N':
	save = pos;
	as->immtarget = parse_number(pos, &pos);
	if (pos != save) /* parsed a number */
		break;
	pos = parse_name(pos); /* |pos==save|, try parsing a name instead */
	if (pos == save)
		goto parse_fail;
	asm_labelref(as, save, pos); /* a label reference */
	break;

@ @<cases for different argument types@>=
case 'M':
	save = pos;
	as->immtarget = parse_number(pos, &pos); /* must succeed */
	if (pos == save) /* no number parsed */
		goto parse_fail;
	if (*pos++ != '(')
		goto parse_fail;
	@<parse one more register@>@;
	if (*pos++ != ')')
		goto parse_fail;
	break;

@ To store a string argument, we need an additional field in |assembler_t|.
@<fields in |assembler_t|@>+=
const char *strarg;

@ @<cases for different argument types@>=
case 'S':
	if (*pos++ != '"')
		goto parse_fail;
	as->strarg = pos;
	while (*pos != '"' && *pos != '\0')
		++pos;
	if (*pos++ != '"')
		goto parse_fail;
	break;

@* Assembling.
In this assembler implementation,
the assembling process is convoluted with the parsing process.
Whenever a line is parsed, the corresponding machine code
(if any) is generated.

@<fields in |assembler_t|@>+=
FILE *input;

@ @<finalize |assembler_t|@>+=
if (as->input != NULL) {
	@<close input@>@;
}

@ @c
int asm_process_file(assembler_t *as, const char *filename)
{
	@<open input@>@;
	@<first pass@>@;
	@<close input@>@;
	return 0; /* TODO */
}

int asm_resolve_symbols(assembler_t *as)
{
	@<second pass@>@;
	return 0;
}

@ @<open input@>=
as->input = fopen(filename, "r");
if (as->input == NULL) {
	fprintf(stderr, "Open file '%s' failed.\n", filename);
	return 1;
}
as->lineno = 0;

@ @<close input@>=
fclose(as->input);
as->input = NULL;

@ One important thing that an assembler do is to allow
programmers to use symbollic labels instead of numeric values
in their instrutions.
This makes it easier to write and modify assembly programs.

To do this, we need to record the labels appeared in the assembly code.

@d LABELREF_DATA 0
@d LABELREF_IMMABS 1
@d LABELREF_RELPC 2
@d LABELREF_TARGET 3
@<declarations@>+=
struct label_ref_t {
	word_t *addr;
	int kind;
};

struct label_t {
	char *name;
	word_t addr;
	struct label_ref_t *unresolved;
	size_t len, cap;
	struct label_t *next;
	unsigned is_defined:1;
	unsigned is_global:1;
};

@ We record all labels in a hash table.
@s hash_t int
@s hash_slot int
@d LABELHASH_INIT_CAP 64
@<fields in |assembler_t|@>+=
struct label_t *last_label;
struct hash_slot *labelhash;
size_t labelhash_len, labelhash_cap;

@ @<initialize |assembler_t|@>+=
as->labelhash = mem_alloc_zero(LABELHASH_INIT_CAP, sizeof (struct hash_slot));
as->labelhash_cap = LABELHASH_INIT_CAP;

@ @<finalize |assembler_t|@>+=
{
	struct label_t *label, *next;

	for (label = as->last_label; label != NULL; label = next) {
		next = label->next;
		mem_free(label->name);
		mem_free(label->unresolved);
		mem_free(label);
	}
	mem_free(as->labelhash);
}

@ To store label in the hash table, we need to define equal function
and hash function.
@c
static int compare_token_label(const void *a, const void *b)
{
	const char *const *token = a;
	const struct label_t *label = b;
	return strcmp2(label->name, token[0], token[1]) == 0;
}

static hash_t hash_token(const char *s, const char *endp)
{
	hash_t h = 6549;
	while (s != endp) {
		h = h * 1558 + (*s++ ^ 233);
	}
	return h;
}

@ Creating a new label.
@c
static struct label_t *
lookup_label(assembler_t *as, const char *name, const char *endp)
{
	struct label_t *label;
	void **slot;
	const char *token[] = {name, endp};

	slot = hash_find(as->labelhash, as->labelhash_cap,
			hash_token(name, endp), token, compare_token_label);
	assert(slot != NULL);
	if ((label = *slot) == NULL) {
		label = *slot = mem_alloc_zero(1, sizeof *label);
		label->name = str_ndup(name, endp - name);
		@<increment |as->labelhash_len|@>@;
		label->next = as->last_label;
		as->last_label = label;
	}
	return label;
}

void asm_labeldef(assembler_t *as, const char *name, const char *endp)
{
	struct label_t *label;

	label = lookup_label(as, name, endp);
	if (label->is_defined) {
		fprintf(stderr, "warning: label '%s' already exists.\n",
			label->name);
	}
	label->addr = *as->cntptr;
	label->is_defined = 1;
}

@ @<increment |as->labelhash_len|@>=
if (++as->labelhash_len > as->labelhash_cap / 2) {
	struct hash_slot *h;
	size_t cap;

	cap = as->labelhash_cap * 2;
	h = mem_alloc_zero(cap, sizeof (struct hash_slot));
	hash_rehash(h, cap, as->labelhash, as->labelhash_cap);
	mem_free(as->labelhash);
	as->labelhash = h;
	as->labelhash_cap = cap;
}

@ Reference a label.  These references are considered ``unresolved''
in the first pass.  They will be resolved in the second pass.
@c
void asm_labelref(assembler_t *as, const char *name, const char *endp)
{
	struct label_t *label;
	struct label_ref_t *ref;

	label = lookup_label(as, name, endp);
	label->unresolved = slice_grow(label->unresolved,
			label->len, &label->cap,
			1, sizeof *label->unresolved);
	ref = &label->unresolved[label->len++];
	if (as->cntptr == &as->data_cnt) {
		ref->addr = &as->dMem[as->data_cnt];
		ref->kind = LABELREF_DATA;
	} else {
		ref->addr = &as->iMem[as->ins_cnt];
		@<determine reference kind for instrution memory@>@;
	}
}

@ @<determine reference kind for instrution memory@>=
switch (as->ins->opcode) {
	case 6: case 7: case 8: /* {\tt addi}, {\tt lw}, {\tt sw} */
		ref->kind = LABELREF_IMMABS;
		break;
	case 9: case 10: /* {\tt beq}, {\tt bgt} */
		ref->kind = LABELREF_RELPC;
		break;
	case 12: case 13: /* {\tt jal}, {\tt j} */
		ref->kind = LABELREF_TARGET;
		break;
	default: assert(0); /* impossible or bug */
}


@ These functions are called by the parser, which is defined in previous
sections.  So we need forward declarations.

@<declarations@>+=
void asm_labeldef(assembler_t *, const char *, const char *);
void asm_labelref(assembler_t *, const char *, const char *);

@ @<first pass@>=
while (get_line(&as->linebuf, &as->linebuf_sz, as->input)) {
	char *errorp;

	++as->lineno;
	errorp = parse_line(as);
	if (errorp != NULL) { 
		char *p;
		fprintf(stderr, "%s:%d: syntax error\n",
			filename, as->lineno);
		fputs(as->linebuf, stderr);
		for (p = as->linebuf; p < errorp; p++)
			fputc(*p == '\t' ? '\t' : ' ', stderr);
		fprintf(stderr, "^\n");
		return 1;
	}
	if (as->ins == NULL) /* no instruction on this line */
		continue;
	@<generate code for current instruction@>@;
}

@*1 Code generation.
We need to store the code and data in binary form.
The instruction memory and data memory have sepearate address space,
so we need to keep track of which memory are we writing to.
The directive {\tt .text} and {\tt .data} make the switch.

@d IMEM_SIZE (1<<12)
@d DMEM_SIZE (1<<16)
@<fields in |assembler_t|@>+=
word_t iMem[IMEM_SIZE];
word_t dMem[DMEM_SIZE];
word_t ins_cnt, data_cnt, cnt_lim;
word_t *memptr, *cntptr;

@ By default we are writing to the instruction memory.
Although the assembly program really should explicitly specify
{\tt .text} before writing code.

@<initialize |assembler_t|@>=
@<switch to instruction memory@>@;

@ @<generate code for current instruction@>=
{
	word_t instcode = 0;
	int code_stat; /* 0---no code; 1---one code; 2---several codes */

	do {
		code_stat = 1;
		switch (as->ins->type) {
			@<cases in code generation@>@;
			default: assert(0); /* impossible or bug */
		}
		if (code_stat) {
			@<write instruction code@>@;
		}
	} while (code_stat > 1);
}

@ @<write instruction code@>=
if (*as->cntptr < as->cnt_lim) {
	as->memptr[(*as->cntptr)++] = instcode;
} else {
	fprintf(stderr, "Memory limit exceeded\n");
	return 1;
}

@ @<cases in code generation@>+=
case R_TYPE:
	assert(as->nreg == 3);
	instcode = pack_rtype(as->ins->opcode,
			as->regno[0], as->regno[1], as->regno[2]);
	break;

@ @<cases in code generation@>+=
case I_TYPE:
	if (as->nreg == 1) {
		/* {\tt jr}, {\tt input} or {\tt output} has only one
		   register argument, and no immediate */
		instcode = pack_itype(as->ins->opcode,
				as->regno[0], 0, 0);
	} else {
		assert(as->nreg == 2);
		instcode = pack_itype(as->ins->opcode,
				as->regno[0], as->regno[1],
				as->immtarget & MAX_IMMEDIATE);
	}
	break;

@ @<cases in code generation@>+=
case J_TYPE:
	assert(as->nreg == 0);
	instcode = pack_jtype(as->ins->opcode, as->immtarget & MAX_TARGET);
	break;

@ @<cases in code generation@>+=
case DIRECTIVE:
	switch (as->ins->opcode) {
		@<cases for directives@>@;
	default: assert(0); /* impossible or bug */
	}
	break;

@ @<cases for directives@>=
case 0: /* \tt .text */
	@<switch to instruction...@>@;
	code_stat = 0;
	break;

@ @<cases for directives@>+=
case 1: /* \tt .data */
	@<switch to data...@>@;
	code_stat = 0;
	break;

@ For {\tt .word} directive, just write the word into the memory.
@<cases for directives@>+=
case 2: /* \tt .word */
	instcode = as->immtarget;
	break;

@ @<cases for directives@>+=
case 3: case 4: /* {\tt .asciiz} and {\tt .ascii} */
	instcode = (unsigned char) *as->strarg++;
	assert(instcode != 0);
	if (instcode == '"') {
		if (as->ins->opcode == 3) {
			instcode = '\0';
		} else {
			code_stat = 0;
		}
	} else {
		code_stat = 2;
	}
	break;

@ @<switch to instruction...@>=
as->memptr = as->iMem;
as->cntptr = &as->ins_cnt;
as->cnt_lim = IMEM_SIZE;

@ @<switch to data memory...@>=
as->memptr = as->dMem;
as->cntptr = &as->data_cnt;
as->cnt_lim = DMEM_SIZE;

@*1 Resolving label references.
@<second pass@>=
{
	size_t i;
	struct label_t *label;

	for (label = as->last_label; label != NULL; label = label->next) {
		if (!label->is_defined) {
			fprintf(stderr, "label '%s' not defined\n",
					label->name);
		} else {
			for (i = 0; i < label->len; i++) {
				struct label_ref_t *ref;
				ref = &label->unresolved[i];
				@<resolve label reference@>@;
			}
		}
	}
}

@ @<resolve label reference@>=
#if DEBUG_LABEL
fprintf(stderr, "resolved label '%s' in %s memory %lx, ",@|
	label->name,
	(ref->kind == LABELREF_DATA) ? "data" : "instruction",@|
	(unsigned long) (ref->addr - as->dMem));
fprintf(stderr, "before = %lx, ", (unsigned long) (*ref->addr));
#endif
switch (ref->kind) {
case LABELREF_DATA:
	*ref->addr = label->addr;
	break;
case LABELREF_IMMABS:
	*ref->addr |= (label->addr) & MAX_IMMEDIATE;
	break;
case LABELREF_RELPC:
	*ref->addr |= (label->addr
			- (word_t)(ref->addr-as->iMem)-1U) & MAX_IMMEDIATE;
	break;
case LABELREF_TARGET:
	*ref->addr |= (label->addr) & MAX_TARGET;
	break;
default: assert(0); /* impossible or bug */
}
#if DEBUG_LABEL
fprintf(stderr, "after = %lx, ", (unsigned long) (*ref->addr));
fprintf(stderr, "label addr = %lx\n", (unsigned long) label->addr);
#endif

@* Hex writer.
We can write out the instruction/data memory in a hex format,
so it can be easily recognized by other programs.
@c
static void
hex_writebyte(int b, FILE *output, unsigned char *checksum)
{
	assert(0 <= b && b < 256);
	fprintf(output, "%02X", b);
	*checksum += b;
}

void
hexwriter(word_t *mem, word_t size, FILE *output)
{
	unsigned char checksum = 0;
	word_t addr, code;
	size_t i;

	for (addr = 0; addr < size; addr++) {
		fputc(':', output);
		hex_writebyte(sizeof (word_t), output, &checksum);
		hex_writebyte(addr >> 8, output, &checksum);
		hex_writebyte(addr & 255, output, &checksum);
		hex_writebyte(0, output, &checksum);
		code = mem[addr];
		for (i = sizeof (word_t); i-- > 0; ) {
			hex_writebyte(((code >> (8*i))) & 255,
						output, &checksum);
		}
		hex_writebyte((-(unsigned) checksum) & 255,
				output, &checksum);
		fputc('\n', output);
	}
	fputs(":00000001FF\n", output);
}

@* The main program.
@p
void write_mem(word_t *, word_t, const char *);
/* defined later */

int main(int argc, char **volatile argv)
{
	const char *filename;
	size_t filename_len;
	char *volatile outname = NULL;
	assembler_t *volatile as = NULL;

	if (argc < 2) {
		fprintf(stderr, "usage: %s asm-file\n", argv[0]);
		return 1;
	}
	filename = *++argv; /* ``main'' file name */
	filename_len = strlen(filename);
	TRY@+{
		int rc = 0;
		as = asm_alloc();
		while (rc == 0 && *argv != NULL) /* process each input file */
			rc = asm_process_file(as, *argv++);
		if (rc == 0) {
			asm_resolve_symbols(as);
			@<construct output filename
				{\tt basename-imem.hex}@>@;
			write_mem(as->iMem, as->ins_cnt, outname);
			@<change output filename to
				{\tt basename-dmem.hex}@>@;
			write_mem(as->dMem, as->data_cnt, outname);
		}
	}FINALLY@+{
		asm_free(as);
		mem_free(outname);
	}END_TRY;
	return 0;
}

@ Output filenames are {\tt basename-imem.hex} and {\tt basename-dmem.hex},
where {\tt basename} is the input filename with the ending {\tt .s}
stripped.  First we append {\tt -imem.hex} to the basename.
@<construct output filename...@>=
if (filename_len >= 2
		&& filename[filename_len-2] == '.'
		&& filename[filename_len-1] == 's') {
	filename_len -= 2; /* remove {\tt .s} */
}
outname = mem_alloc(filename_len + 10);
memcpy(outname, filename, filename_len);
memcpy(outname+filename_len, "-imem.hex", 10);

@ And later we replace the {\tt i} in the output filename with {\tt d}.
It's like a trick as it does not require reconstructing the output filename.

@<change output filename...@>=
outname[filename_len+1] = 'd';

@ The following auxillary function writes the memory into a hex file.
It opens the file, and calls |hexwriter| to do the formatting.

@c
void write_mem(word_t *mem, word_t size, const char *outname)
{
	FILE *output = NULL;

	output = fopen(outname, "w");
	if (output == NULL) {
		fprintf(stderr, "failed to open %s\n", outname);
	} else {
		hexwriter(mem, size, output);
		fclose(output);
	}
}

@* Index.

