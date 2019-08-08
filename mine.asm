BITS 16

  ; Boot sector load address
org 0x7c00

%define BootSectorSize 512
%define WordSize 2

Entry:
  ; VGA text mode 0x03
  ; 640x200 resolution
  ; 16 colors
  ; http://www.ctyme.com/intr/rb-0069.htm
  mov ax, 0x03
  int 0x10

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
