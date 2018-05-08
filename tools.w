@* Introduction.
This file contains several useful tools for building a large piece of software.

Many ideas are brought from David R.~Hanson's book,
{\sl C Interfaces and Implementations}.

@ It exports its interface to \.{tools.h} so that
other \CEE/ files can have access to it.

@(tools.h@>=
#ifndef _TOOLS_H
#define _TOOLS_H

#include <stdio.h> /* for |FILE| */
#include <stdlib.h> /* for |size_t|, etc */

@<exported declarations in \.{tools.h}@>

#endif

@ Also include \.{tools.h} for ourselves,
so that the type and function declarations are present.

@c
#include "tools.h"

@* Exception handling.
\CEE/ has no built-in exception handling mechanism.
However, occasionally it proves useful.

Exceptions in \CEE/ can be implemented
with |setjmp|/|longjmp| and ugly macros.

@<exported...@>=
#include <setjmp.h> /* for |setjmp| and |longjmp| */

#define EXCEPT_ENTERED		0
#define EXCEPT_RAISED		1
#define EXCEPT_HANDLED		2
#define EXCEPT_FINALIZED	3

typedef struct {
	const char *what;
} except_t;

struct except_frame {
	struct except_frame *prev;
	jmp_buf env;
	const char *file;
	int lineno;
	const except_t *exception;
};

extern struct except_frame *_except_stack;


@ |TRY| begins a block where any raised exceptions can be catched.

@<exported...@>=
#define TRY do {@/ \
volatile int _except_flag; \
struct except_frame _except_frame; \
_except_frame.prev = _except_stack; \
_except_stack = &_except_frame; \
_except_flag = setjmp(_except_frame.env); \
if (_except_flag == EXCEPT_ENTERED) {

@ |EXCEPT| and |EXCEPT_ELSE| catches an exception
and executes the handling code.
The difference is |EXCEPT| only catches a specific exception
while |EXCEPT_ELSE| catches any exception.
@<exported...@>=
#define EXCEPT(e) } else if (_except_frame.exception == &(e)) { \
	_except_flag = EXCEPT_HANDLED;

#define EXCEPT_ELSE } else { \
	_except_flag = EXCEPT_HANDLED;

@ |FINALLY| contains clean-up code for the |TRY| clause.
@<exported...@>=
#define FINALLY } { \
	if (_except_flag == EXCEPT_ENTERED) \
		_except_flag = EXCEPT_HANDLED;

@  |END_TRY| closes the |TRY| block.
@<exported...@>=
#define END_TRY } \
if (_except_flag == EXCEPT_RAISED) \
	RERAISE; \
else if (_except_flag == EXCEPT_ENTERED) \
	_except_stack = _except_stack->prev; \
} while (0)

@  |RETURN| is used inside a |TRY| block instead of |return|.
@<exported...@>=
#define RETURN switch (_except_stack = _except_stack->prev, 0) default: return

@ |RAISE| raises an exception.
It is defined as a macro so that we can use
some special macros in Standard~\CEE/: |__FILE__| and |__LINE__|.

@<exported...@>=
#define RAISE(e) @[except_raise(&(e), __FILE__, __LINE__)@]
extern void except_raise(const except_t *, const char *, int);

@ |RERAISE| reraises an exception.
When handling an exception in the |EXCEPT_ELSE| clause,
sometimes it's useful to reraise the exception.

@<exported...@>=
#define RERAISE @[except_raise(_except_frame.exception, _except_frame.file, _except_frame.lineno)@]

@  |except_raise| really raises an exception.
@c
struct except_frame *_except_stack = NULL;

void except_raise(const except_t *e, const char *file, int lineno)
{
	struct except_frame *f = _except_stack;

	if (f == NULL) {
		@<announce an uncaught exception@>@;
	}
	f->exception = e;
	f->file = file;
	f->lineno = lineno;
	_except_stack = f->prev;
	longjmp(f->env, EXCEPT_RAISED);
}

@ @<announce an uncaught...@>=
fprintf(stderr, "Uncaught exception at %p raised at %s:%d\n",@|
	(void *) e, file, lineno);
if (e->what) {
	fprintf(stderr, "Reason: %s\n", e->what);
}
fprintf(stderr, "Aborting...\n");
abort();

@* Assertions.
The assertion mechanism is built on exceptions.
An exception is raised when an assertion failed.
Normally there isn't any handler and the program will abort.

Assertions can be turned off if |NDEBUG| is defined.

@<exported...@>+=
#ifdef NDEBUG
# define assert(e) ((void) 0) /* assertions are disabled */
#else
# define assert(e) ((e) ? (void) 0 : RAISE(AssertionFailure))
#endif
extern except_t AssertionFailure;

@ Definition of |AssertionFailure|.
@c
except_t AssertionFailure = { "Assertion failure" };

@* Memory management.
A thin wrapper over |malloc|/|free| is provided
so that it will raise an exception upon allocation failure.
Debugging information is also provided if |MEMDEBUG| is defined.

@<exported...@>+=
extern void *mem_alloc(size_t);
extern void *mem_alloc_zero(size_t, size_t);
extern void *mem_resize(void *, size_t);
extern void mem_free(void *);

@  |mem_alloc|, |mem_alloc_zero| and |mem_resize|
are similar to standard library functions
|malloc|, |calloc| and |realloc|.
However, they may raise |AllocationFailure|
instead of returning NULL.

@c
except_t AllocationFailure = {"Memory allocation failed"};

void *mem_alloc(size_t sz)
{
	void *p;
	
	p = malloc(sz);
	@<raise |AllocationFailure| if allocation failed@>@;
#ifdef MEMDEBUG
	fprintf(stderr, "memory allocated sz = %lu at %p.\n",
		(unsigned long) sz, p);
#endif
	return p;
}

void *mem_alloc_zero(size_t n, size_t elem_sz)
{
	void *p;

	p = calloc(n, elem_sz);
	@<raise |AllocationFailure|...@>@;
#ifdef MEMDEBUG
	fprintf(stderr, "memory allocated n = %lu, elem_sz = %lu at %p.\n",@|
		(unsigned long) n, (unsigned long) elem_sz, p);
#endif
	return p;
}

void *mem_resize(void *p, size_t sz)
{
#ifdef MEMDEBUG
	fprintf(stderr, "memory at %p resized ", p);
#endif
	p = realloc(p, sz);
	@<raise |AllocationFailure|...@>@;
#ifdef MEMDEBUG
	fprintf(stderr, "sz = %lu, new address = %p.\n",
		(unsigned long) sz, p);
#endif
	return p;
}

@ @<raise |AllocationFailure|...@>=
if (p == NULL)
	RAISE(AllocationFailure);

@  |mem_free| is identical to |free|.
@c
void mem_free(void *p)
{
	if (p) {
#ifdef MEMDEBUG
		fprintf(stderr, "memory at %p freed.\n", p);
#endif
		free(p);
	}
}

@* Slice.

@<exported...@>=
extern void *slice_grow(void *, size_t, size_t *, size_t, size_t);

@ Growing a slice.  This guarantees at least |n| more slots writable
after |base[len]|.

@c
void *slice_grow(void *base, size_t len, size_t *capp, size_t n, size_t elemsz)
{
	size_t newlen, newcap;

	newlen = len + n;
	if (newlen < len) /* overflow ? */
		RAISE(AllocationFailure);
	newcap = *capp;
	if (newcap == 0)
		newcap = 1;
	while (newcap < newlen) {
		if (newcap * 2 < newcap) /* overflow ? */
			newcap = newlen;
		else
			newcap *= 2;
	}
	assert(newcap >= *capp);
	if (newcap > *capp || base == NULL) {
		base = mem_resize(base, newcap * elemsz);
		*capp = newcap;
	}
	return base;
}

@* Hash table.
This is a low-level implementation of a hash table.
It has the following features:
\smallskip
\itemitem{1.} It does not allocate memory.
\itemitem{2.} It is open-addressing, with linear probing.
\itemitem{3.} It uses |void| pointer to store generic data.
\smallskip

To create a hash table of size |n|, allocate a
{\it zero-initialized} @^initialization@>
memory for |n| |struct hash_slot|s.

To finalize the items stored in the hash table,
examine each |struct hash_slot|, and run the finalizer on each
non-NULL |value|.

@<exported...@>=
typedef unsigned long hash_t;
struct hash_slot {
	void *value;
	hash_t key;
};
typedef int @[@](*hash_equal_fn)(const void *, const void *);

@  |hash_find| finds a position for a specified item.
You need to provide three things: the hash, the value,
and the function pointer to test for equality.

Suppose |hash_find| returns |p|.
\item{$\bullet$}
If |p==NULL|, then the item does not exist and the hash table has
no room for a new item.
In this case, you can extend the hash table and run a rehash.
However, you should do this much earlier before the hash table is full,
to avoid performance issues.
\item{$\bullet$}
If |*p!=NULL|, then an item with the same value exists.
You probably want to run finalizer for |*p| before overwriting it.
Otherwise the item does not exist.
In any case, you can write to |*p| to change the value.
@<exported...@>=
void **hash_find(struct hash_slot[], size_t, hash_t, const void *, hash_equal_fn eq);

@ @c
void **hash_find(struct hash_slot h[],
size_t size, hash_t key, const void * value, hash_equal_fn eq)
{
	struct hash_slot *p, *position, *end;

	assert(size > 0);

	position = p = &h[key % size];
	end = h + size;

	while (p->value != NULL && (p->key != key || !eq(value, p->value))) {
		if (++p == end)
			p = h; /* wrap around */
		if (p == position) /* not found and no free slot */
			return NULL;
	}
	p->key = key;
	return &p->value;
}

@  |hash_delete| deletes a value at the specified slot.
@<exported...@>=
void hash_delete(struct hash_slot[], size_t, void **);

@ @c
void hash_delete(struct hash_slot h[], size_t size, void **slot)
{
	size_t i, j, k;

	i = (size_t) ((struct hash_slot *) slot - h);
	/* the cast is valid: |slot| has an offset of 0 */
	assert(i < size);
	@<clear the slot in hash table@>@;
}

@ Deletion in a open-address hash table is involved.
Because it creates a ``hole'' at slot~|i|,
it may result in some slot no longer to be seen by the finding algorithm.

The affected slots are those immediately after slot~|i|
without a free slot in between.
Suppose slot~|j| is affected and |key| is its key.
Let |k=key%size| be the real position (where the linear probing starts)
for slot~|j|.
It is possible that |j!=k|, because there was a hash conflict and
the slot was inserted several slots after position~|k|.

If |i| is between |k| and |j|, there is a problem:
when searching for |key|, the linear probing starts at |k|,
and gives up at |i|, even though the key is present at |j|.

In this case, we need to moving slot |j| to |i|,
and then recursively |@<clear the slot...@>| for slot~|j|.
The following code uses a clever |goto| statement instead of recursion.

@<clear the slot...@>=
clear_slot:@/
	h[i].key = 0;
	h[i].value = NULL;
	j = i;
	for (;;) {
		@<advance |j| to the next slot, |break| if it's free@>@;
		k = h[j].key % size; /* the real position for slot |j| */
		@<if |i| is between |k| and |j|,
		move slot |j| to |i| and |goto clear_slot|@>@;
	}

@ @<advance |j|...@>=
if (++j == size)
	j = 0; /* wrap around if necessary */
if (h[j].value == NULL)
	break;

@ The relation ``between'' is a bit tricky to define,
because it involves wrap-around.
There are several possibilities:
\smallskip
\itemitem{1.} |k<=i<j|. No wrap-around.
\itemitem{2.} |j<k<=i|. Wrap-around after |i|.
\itemitem{3.} |i<j<k|. Wrap-around after |k|.
\smallskip
(Note that |i=j| is not possible,
because slot |i| is just cleared, and thus free.)
The code below uses a clever expression that covers exactly these cases.

@<if |i| is between...@>=
if ((k <= i) + (j < k) + (i < j) == 2) {
	h[i] = h[j];
	i = j;
	goto clear_slot; /* this does the ``recursion'' */
}


@  |hash_rehash| copies the contents from a hash table
to another with potentially different size.

The destination must be zero-initialized.
@^initialization@>

@<exported...@>=
extern void hash_rehash(struct hash_slot[], size_t,
	const struct hash_slot[], size_t);

@ @c
static int always_neq(const void *a, const void *b)
{
	return 0;
}

void hash_rehash(struct hash_slot h[], size_t size,
	const struct hash_slot oldh[], size_t oldsize)
{
	const struct hash_slot *p, *end;

	end = oldh + oldsize;
	for (p = oldh; p != end; p++) {
		void **slot;

		slot = hash_find(h, size, p->key, p->value, always_neq);
		assert(slot != NULL); /* caller must ensure sufficient space */
		*slot = p->value;
	}
}


@* Strings.
\CEE/ strings are really character arrays.
Sometimes they are cumbersome to manipulate,
so we define some convenience functions for strings.

@c
#include <string.h> /* for |memcpy|, etc. */

@  |str_dup| makes a duplicate string in dynamically allocated memory.
The underscore in the name is to avoid name clash with the (non-standard)
|strdup| found in some systems.

|str_ndup| has similar functionality but it reads the length of the string
from the arguments.

@<exported...@>=
extern char *str_dup(const char *);
extern char *str_ndup(const char *, size_t);

@ @c
char *str_dup(const char *s)
{
	return str_ndup(s, strlen(s));
}

char *str_ndup(const char *s, size_t len)
{
	char *t;

	t = mem_alloc(len + 1);
	memcpy(t, s, len);
	t[len] = '\0';
	return t;
}

@  |str_hash| computes hash for strings.
It's probably the most frequently used hash function.

@<exported...@>=
extern hash_t str_hash(const char *s);

@ @c
hash_t str_hash(const char *s)
{
	hash_t h = 6549;

	while (*s) {
		h = h * 1558 + ((unsigned char) *s++ ^ 233);
	}
	return h;
}

@ We will deal with a special kind of string which is called
{\it buffer}.
Its capacity can dynamically expand when contents are added to it.

Note: it is not zero-terminated by default.

@<exported...@>=
extern char *buf_appchr(char *, size_t *, size_t *, int);
extern char *buf_appstr(char *, size_t *, size_t *, const char *, size_t);

@  |buf_appchr| appends a character into a string buffer.

@c
char *buf_appchr(char *base, size_t *lenp, size_t *capp, int c)
{
	base = slice_grow(base, *lenp, capp, 1, sizeof (char));
	base[(*lenp)++] = c;
	return base;
}

@  |buf_appstr| appends a string into a string buffer.

@c 
char *buf_appstr(char *base, size_t *lenp, size_t *capp,
		const char *s, size_t len)
{
	base = slice_grow(base, *lenp, capp, len, sizeof (char));
	memcpy(base + *lenp, s, len);
	*lenp += len;
	return base;
}

@  |buf_applit| appends a string literal into a string buffer.
@<exported...@>=
#define buf_applit(buf, literal) \
	@[buf_appstr((buf), literal, (sizeof literal)-1)@]


@* Input/Output.

@  |get_delim| reads from the input until a delimiter.
The underscore in the name is to avoid name clash with the (non-standard)
|getdelim| found in some systems.  It is also incompatible with |getdelim|.

@<exported...@>=
extern char *get_delim(char **, size_t *, int, FILE *);
#define get_line(bufp, szp, f) \
	@[get_delim((bufp), (szp), '\n', (f))@]

@
@d LINEBUF_DEFUALT_CAP 128
@c
char *get_delim(char **bufp, size_t *capp, int delim, FILE *f)
{
	size_t len;
	int ch;

	len = 0;
	do {
		ch = fgetc(f);
		if (ch == EOF)
			break;
		*bufp = buf_appchr(*bufp, &len, capp, ch);
	} while (ch != delim);

	*bufp = buf_appchr(*bufp, &len, capp, '\0');
	return (ch == EOF) ? NULL : *bufp ;
}

@* Index.
