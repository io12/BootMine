# BootMine

*Ever wanted to play minesweeper but didn't have an OS to run it in? No? Really no??*

BootMine is an entire minesweeper game crammed into 512 bytes, the size of a BIOS boot sector. It can boot on any PC that supports BIOS booting, without running inside an OS. In a sense, BootMine is its own OS that can do nothing but run minesweeper.

![demo](demo.gif)

## Controls

* <kbd>Space</kbd>
  * 🔲 Clear cell
* <kbd>↑</kbd>/<kbd>↓</kbd>/<kbd>←</kbd>/<kbd>→</kbd>
  * 🕹 Move cursor
* <kbd>Enter</kbd>
  * 🚩 Place flag
* <kbd>R</kbd>
  * 💣 Restart game (only works on GAME WIN and GAME OVER screens)

## Building

Make sure `nasm` and `make` are installed, then run:

```sh
make
```

## Installing

This 512-byte file `bootmine`, can be written to the first sector of a floppy disk (or USB drive), with a command like `dd if=bootmine of=/dev/sdb`. Keep in mind that this will effectively destroy all data on the drive.

### Emulation

Makefile targets are provided for emulating in QEMU and Bochs.

```sh
make qemu
```

```sh
make bochs
```

**NOTE**: The way Bochs implements the `rdtsc` instruction appears to be bad as a source of entropy, so the bomb locations are predictable.
