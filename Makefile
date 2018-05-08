CFLAGS=-Wall -Wextra -ggdb3
#CFLAGS+=-DDEBUG_LABEL=1
CFLAGS+=-flto -O2
LDFLAGS=-flto -O2

all: doc prog moo-{i,d}mem

moo-{i,d}mem: moo.s std.s
	./pcasm $^

doc: pcasm.pdf

%.pdf: %.tex
	pdftex $<

prog: pcasm

pcasm: pcasm.o tools.o
	$(CC) $(LDFLAGS) -o $@ pcasm.o tools.o

pcasm.o: tools.h

%.c %.h: %.w
	ctangle $<

clean:
	rm -f pcasm *.idx *.scn *.toc *.log *.o *.pdf *.c *.h

.PHONY: all doc prog clean
