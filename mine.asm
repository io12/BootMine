BITS 16
CPU 8086

;; CONSTANTS

;; Boot sector load address
%assign BootSectorAddr 0x7c00

%assign BootSectorSize 512
%assign WordSize 2

;; Width and Height apply to both the screen (in text coordinates) and the ;;
;; minefield
%assign Width 40
%assign Height 25

;; GLOBAL VARIABLES

;; TODO: Change global vars to a state struct

;; Global variables are stored after the boot sector at runtime. After the boot
;; sector, there is 480.5K of memory safe to use.
;; https://wiki.osdev.org/Memory_Map_(x86)#Overview

%assign MinefieldSize Width * Height
;; TODO: Document these
%assign MinefieldActual BootSectorAddr + BootSectorSize
%assign MinefieldVisible MinefieldActual + MinefieldSize

;; Seed used for random number generation
%assign RandomSeed MinefieldVisible + MinefieldSize

org BootSectorAddr

Entry:
  ; VGA text mode 0x00
  ; 320x200 pixel resolution
  ; 40x25 text resolution
  ; 16 colors
  ; http://www.ctyme.com/intr/rb-0069.htm
  xor ax, ax
  int 0x10

  ; Store number of clock ticks since midnight in CX:DX
  ; http://www.ctyme.com/intr/rb-2271.htm
  xor ax, ax
  int 0x1a

  ; Seed the RNG with the amount of ticks
  mov [RandomSeed], dx

  ; Populate MinefieldActual with mines and empty cells
  mov di, MinefieldActual
  mov cx, MinefieldSize
.PopulateMinefieldActualLoop:
  ; ax = Rand() & 0b111 ? ' ' : '*'
  call Rand
  test ax, 0b111
  jz .Mine
.Empty:
  mov ax, ' '
  jmp .WriteCell
.Mine:
  mov ax, '*'
.WriteCell:
  stosb
  loop .PopulateMinefieldActualLoop

PrintMinefield:
  mov cx, MinefieldSize
  mov bp, MinefieldActual
  mov bx, 0x0064
  xor dx, dx
  mov ax, 0x1300
  int 0x10
  hlt

;; Return a random value in AX
Rand:
  ; TODO: Document algorithm
  push bx
  push cx
  mov ax, [RandomSeed]

  mov bx, ax
  mov cx, 7
  shl bx, cl
  xor ax, bx

  mov bx, ax
  mov cx, 9
  shr bx, cl
  xor ax, bx

  mov bx, ax
  mov cx, 8
  shl bx, cl
  xor ax, bx

  mov [RandomSeed], ax
  pop bx
  pop cx
  ret

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

;; Boot sector ends here
