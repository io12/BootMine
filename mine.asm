BITS 16

  ; Boot sector load address
org 0x7c00

%assign BootSectorSize 512
%assign WordSize 2

;; Width and Height apply to both the screen (in text coordinates) and the ;;
;; minefield
%assign Width 40
%assign Height 25

;; The minefield is stored after the boot sector at runtime. After the boot
;; sector, there is 480.5K of memory safe to use.
;; https://wiki.osdev.org/Memory_Map_(x86)#Overview

%assign MinefieldSize Width * Height
;; TODO: Document these
%assign MinefieldActual BootSectorEnd
%assign Minefieldvisible MinefieldActual + MinefieldSize

Entry:
  ; VGA text mode 0x00
  ; 320x200 pixel resolution
  ; 40x25 text resolution
  ; 16 colors
  ; http://www.ctyme.com/intr/rb-0069.htm
  xor ax, ax
  int 0x10

InitMinefield:

PrintHelloWorld:
  mov cx, HelloWorldStrLen
  mov bp, HelloWorldStr
  mov bx, 0x0064
  xor dx, dx
  mov ax, 0x1300
  int 0x10
  hlt

HelloWorldStr:
  db "Hello world!"
  HelloWorldStrLen equ $ - HelloWorldStr

;; Print program size at build time
%assign CodeSize $ - $$
%warning Code is CodeSize bytes

CodeEnd:
  ; Pad to size of boot sector, minus the size of a word for the boot sector
  ; magic value. If the code is too big to fit in a boot sector, the `times`
  ; directive uses a negative value, causing a build error.
  times (BootSectorSize - WordSize) - CodeSize db 0

  ; Boot sector magic
  dw 0xaa55

BootSectorEnd:
