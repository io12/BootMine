QEMU = qemu-system-i386
NASM = nasm

.PHONY: all clean qemu

all: bootmine

bootmine: mine.asm
	$(NASM) $< -o $@

clean:
	rm -f bootmine

qemu: bootmine
	$(QEMU) $<
