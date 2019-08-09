BITS 16
CPU 8086

;; CONSTANTS

;; Boot sector load address
%assign BootSector.Begin 0x7c00
%assign BootSector.Size 512
%assign BootSector.End BootSector.Begin + BootSector.Size

%assign WordSize 2

;; Width and Height apply to both the screen (in text coordinates) and the
;; minefield
%assign Width 40
%assign Height 25

;; GLOBAL VARIABLES

;; TODO: Change global vars to a state struct

;; Global variables are stored after the boot sector at runtime. After the boot
;; sector, there is 480.5K of memory safe to use.
;; https://wiki.osdev.org/Memory_Map_(x86)#Overview

%assign Vars.Begin BootSector.End

%assign Map.Size Width * Height
;; TODO: Document these
%assign Map.Mines Vars.Begin
%assign Map.Unveiled Map.Mines + Map.Size
%assign Map.Displayed Map.Unveiled + Map.Size

;; Distance between Map.Mines and Map.Unveiled
%assign Map.Mines.ToUnveiled (Map.Unveiled - Map.Mines)

;; Seed used for random number generation
%assign RandomSeed Map.Displayed + Map.Size

%assign Vars.End RandomSeed + WordSize

%assign Vars.Size Vars.End - Vars.Begin

org BootSector.Begin

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

  ; TODO: Remove hard-coded seed
  mov dx, 12345

  ; Seed the RNG with the amount of ticks
  mov [RandomSeed], dx

;; Populate Map.Mines with mines
PopulateMines:
  mov di, Map.Mines
  mov cx, Map.Size
.Loop:
  ; ax = Rand() & 0b111 ? 0 : 1
  call Rand
  test ax, 0b111
  jz .Mine
.Empty:
  xor ax, ax
  jmp .WriteCell
.Mine:
  mov ax, 1
.WriteCell:
  stosb
  loop .Loop

;; Number empty cells with amount of neighboring mines
NumCells:
  mov di, Map.Unveiled
  mov cx, Map.Size
.Loop:
  ; Get digit for the cell at DI
  mov ax, [di - Map.Mines.ToUnveiled]
  test ax, ax
  jz .Empty
.Mine:
  mov ax, '*'
  jmp .WriteCell
.Empty:
  mov ax, '0'

  ; Straight
  lea bx, [di - 1 - Map.Mines.ToUnveiled]
  call LeftIncIfMineAtCell
  lea bx, [di + 1 - Map.Mines.ToUnveiled]
  call RightIncIfMineAtCell
  lea bx, [di - Width - Map.Mines.ToUnveiled]
  call IncIfMineAtCell
  lea bx, [di + Width - Map.Mines.ToUnveiled]
  call IncIfMineAtCell

  ; Diagonal
  lea bx, [di - 1 - Width - Map.Mines.ToUnveiled]
  call LeftIncIfMineAtCell
  lea bx, [di - 1 + Width - Map.Mines.ToUnveiled]
  call LeftIncIfMineAtCell
  lea bx, [di + 1 - Width - Map.Mines.ToUnveiled]
  call RightIncIfMineAtCell
  lea bx, [di + 1 + Width - Map.Mines.ToUnveiled]
  call RightIncIfMineAtCell

  cmp ax, '0'
  jne .WriteCell
.Zero:
  mov ax, ' '
.WriteCell:
  stosb
  loop .Loop

PrintMinefield:
  mov cx, Map.Size
  mov bp, Map.Unveiled
  mov bx, 0x0064
  xor dx, dx
  mov ax, 0x1300
  int 0x10
  hlt

LeftIncIfMineAtCell:
  push bx
  push ax
  push dx
  sub bx, Map.Mines
  div bx
  test dx, dx
  pop bx
  pop ax
  pop dx
  jz IncIfMineAtCell.RetZero
  jmp IncIfMineAtCell
RightIncIfMineAtCell:
  push bx
  push ax
  push dx
  sub bx, Map.Mines
  div bx
  cmp dx, Width - 1
  pop bx
  pop ax
  pop dx
  je IncIfMineAtCell.RetZero
;; TODO: Update comment
;;
;; Increment AX if there is a mine in Map.Mines at index BX, where BX is a
;; pointer inside Map.Mines. In the case where BX is outside Map.Mines, AX is
;; NOT incremented.
;;
;; Parameters
;;   * BX - Pointer inside Map.Mines
;; Clobbered registers
;;   * AX - either incremented or unchanged, depending on whether there is or
;;          isn't a mine at BX, respectively
IncIfMineAtCell:
  ; Bounds check
  cmp bx, Map.Mines
  jb .RetZero
  cmp bx, Map.Mines + Map.Size
  jae .RetZero
  ; Within map bounds. Dereference and add map pointer.
  add ax, [bx]
  ret
.RetZero:
  ; Outside map bounds. Do not increment.
  ret

;; Return a random value in AX
Rand:
  ; 16 bit xorshift
  ;
  ;   xs ^= xs << 7;
  ;   xs ^= xs >> 9;
  ;   xs ^= xs << 8;
  ;   return xs;
  ;
  ; http://www.retroprogramming.com/2017/07/xorshift-pseudorandom-numbers-in-z80.html
  push bx
  push cx
  mov ax, [RandomSeed]

  ; ax ^= ax << 7
  mov bx, ax
  mov cx, 7
  shl bx, cl
  xor ax, bx

  ; ax ^= ax >> 9
  mov bx, ax
  mov cx, 9
  shr bx, cl
  xor ax, bx

  ; ax ^= ax << 8
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
  times (BootSector.Size - WordSize) - CodeSize db 0

  ; Boot sector magic
  dw 0xaa55

;; Boot sector ends here
