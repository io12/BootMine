.POSIX:

QEMU = qemu-system-i386
BOCHS = bochs
NASM = nasm

.PHONY: all clean qemu bochs

all: bootmine

bootmine: mine.asm
	$(NASM) $< -o $@

clean:
	rm -f bootmine

qemu: bootmine
	$(QEMU) $<

bochs: bootmine
	$(BOCHS) -q -f bochsrc.txt
