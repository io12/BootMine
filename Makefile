.POSIX:

QEMU = qemu-system-i386
BOCHS = bochs
NASM = nasm
DOSBOX = dosbox
DOSEMU = dosemu

.PHONY: all clean qemu bochs dosbox dosemu

all: bootmine.img bootmine.com

bootmine.img: mine.asm
	$(NASM) $< -o $@

bootmine.com: mine.asm
	$(NASM) -DDOS $< -o $@

clean:
	rm -f bootmine.img bootmine.com

qemu: bootmine.img
	$(QEMU) $<

bochs: bootmine.img
	$(BOCHS) -q -f bochsrc.txt

dosbox: bootmine.com
	$(DOSBOX) $<

dosemu: bootmine.com
	$(DOSEMU) $<
