bits 16
cpu 686

;; Constants

;; Boot sector load address
%assign BootSector.Begin 0x7c00
%assign BootSector.Size 512
%assign BootSector.End BootSector.Begin + BootSector.Size

%assign WordSize 2

;; Address and dimensions of text buffer
%assign TextBuf.Seg 0xb800
%assign TextBuf.Width 40
%assign TextBuf.Height 25
%assign TextBuf.Size TextBuf.Width * TextBuf.Height
%define TextBuf.Index(y, x) ((y) * TextBuf.Width * 2 + (x) * 2)

;; Dirs data info
;; TODO: make this not hardcoded?
%assign Dirs.Len 8

;; Keyboard scan codes
;; http://www.ctyme.com/intr/rb-0045.htm#Table6
%assign Key.Space 0x39
%assign Key.Up 0x48
%assign Key.Down 0x50
%assign Key.Left 0x4b
%assign Key.Right 0x4d

%define VgaChar(color, ascii) (((color) << 8) | (ascii))

%assign Color.Veiled 0x77
%assign Color.Unveiled 0xf0
%assign Color.Cursor 0x00
%assign Color.GameWinText 0x20
%assign Color.GameOverText 0xc0

org BootSector.Begin

BootMine:
  ; VGA text mode 0x00
  ; 320x200 pixel resolution
  ; 40x25 text resolution
  ; 16 colors
  ; http://www.ctyme.com/intr/rb-0069.htm
  xor ax, ax
  int 0x10

  ; Load VGA text buffer segment into es
  mov dx, TextBuf.Seg
  mov es, dx
  mov ds, dx

ZeroTextBuf:
  xor di, di
  mov cx, TextBuf.Size
  mov ax, VgaChar(Color.Veiled, '0')
.Loop:
  stosw
  loop .Loop

;; Populate text buffer
PopulateTextBuf:
  xor di, di
  mov bx, TextBuf.Height - 2

.LoopY:
  mov cx, TextBuf.Width - 2

.LoopX:
  mov bp, Dirs.Len

  push bx
  push cx

  ; di = &TextBuf[y][x]
  call GetTextBufIndex

  pop cx
  pop bx

  ; dx = ! (bool) (rdtsc() & 0xf)
  rdtsc
  and al, 0xf
  setz dl

  jnz .LoopDir
  mov byte [di], '*'

.LoopDir:
  push di
  movsx ax, byte [bp + Dirs - 1]
  add di, ax
  mov al, [di]

  cmp al, '*'
  je .LoopDirIsMine
  add [di], dl
.LoopDirIsMine:
  pop di

  dec bp
  jnz .LoopDir

  loop .LoopX

  dec bx
  jnz .LoopY

;; Done populating text buf

  ; Set the initial cursor color for game loop
  mov dl, Color.Veiled

GameLoop:
  ; Get keystroke
  ; ah = BIOS scan code
  ; al = ASCII character
  ; http://www.ctyme.com/intr/rb-1754.htm
  xor ax, ax
  int 0x16

  ; bx and cx zeroed from PopulateTextBuf loops above
  ; bx = y coord
  ; cx = x coord

  ; di = cell pointer
  call GetTextBufIndex
  ; Apply saved cell color
  mov [di + 1], dl

  ; Detect win (a win occurs when the only unveiled cells are bombs)
  xor si, si
  push ax
  push cx
  mov cx, TextBuf.Size
.DetectWinLoop:
  lodsw
  cmp ah, Color.Veiled
  jne .DetectWinLoopEnd
  cmp al, '*'
  jne .NotGameWin
.DetectWinLoopEnd:
  loop .DetectWinLoop
  jmp GameWin
.NotGameWin:
  pop cx
  pop ax

  ; Process key press
.CmpUp:
  cmp ah, Key.Up
  jne .CmpDown
  dec bx
  jmp WrapCursor
.CmpDown:
  cmp ah, Key.Down
  jne .CmpLeft
  inc bx
  jmp WrapCursor
.CmpLeft:
  cmp ah, Key.Left
  jne .CmpRight
  dec cx
  jmp WrapCursor
.CmpRight:
  cmp ah, Key.Right
  jne .CmpSpace
  inc cx
  jmp WrapCursor
.CmpSpace:
  cmp ah, Key.Space
  jne GameLoop

ClearCell:
  mov ax, [di]
  call UnveilCell
.CmpEmpty:
  cmp al, '0'
  jne .CmpMine
  call Flood
  jmp GameLoop
.CmpMine:
  cmp al, '*'
  jne .Digit
  jmp GameOver
.Digit:
  jmp GameLoop

WrapCursor:
  ; Wrap y cursor
  cmp bx, TextBuf.Height
  jb .X
  xor bx, bx

.X:
  ; Wrap x cursor
  cmp cx, TextBuf.Width
  jb SetCursorPos
  xor cx, cx

SetCursorPos:
  call GetTextBufIndex
  mov dl, Color.Cursor
  xchg dl, [di + 1]

  jmp GameLoop

;; di = &TextBuf[bx = y][cx = x]
GetTextBufIndex:
  push cx
  imul di, bx, TextBuf.Width * 2
  imul cx, cx, 2
  add di, cx
  pop cx
  ret

;; Unveil a cell so it is visible on the screen
;;
;; Parameters:
;;   * di - cell pointer in text buffer
;;   * al - cell ASCII value
;; Returns:
;;   * dl - written VGA color code
UnveilCell:
  ; Use xor magic to make the cells colored
  mov dl, al
  xor dl, '0' ^ Color.Unveiled
  mov [di + 1], dl
  ret

;; Flood fill empty cells
;;
;; Parameters:
;;   * bx - cell y coordinate
;;   * cx - cell x coordinate
;; Clobbered registers:
;;   * ax - cell value
;;   * di - cell pointer in text buffer
Flood:
  ; Init: get cell pointer and value
  call GetTextBufIndex
  mov ax, [di]

  ; Base case: bounds check y
  cmp bx, TextBuf.Height
  jae .Ret

  ; Base case: bounds check x
  cmp cx, TextBuf.Width
  jae .Ret

  ; Base case: we visited this cell already
  cmp al, ' '
  je .Ret

  ; Base case: this is a bomb
  cmp al, '*'
  je .Ret

  ; Body: unveil cell
  call UnveilCell

  ; Base case: nonempty cell
  cmp al, '0'
  jne .Ret

  ; Body: mark cell as visited and empty
  mov byte [di], ' '

  ; Recursive case: flood adjacent cells

  ; Flood up
  dec bx
  call Flood
  inc bx

  ; Flood down
  inc bx
  call Flood
  dec bx

  ; Flood left
  dec cx
  call Flood
  inc cx

  ; Flood right
  inc cx
  call Flood
  dec cx

  ; Flood up-left
  dec bx
  dec cx
  call Flood
  inc cx
  inc bx

  ; Flood up-right
  dec bx
  inc cx
  call Flood
  dec cx
  inc bx

  ; Flood down-left
  inc bx
  dec cx
  call Flood
  inc cx
  dec bx

  ; Flood down-right
  inc bx
  inc cx
  call Flood
  dec cx
  dec bx

.Ret:
  ret

Dirs:
  db TextBuf.Index(-1, -1)
  db TextBuf.Index(-1,  0)
  db TextBuf.Index(-1, +1)
  db TextBuf.Index( 0, +1)
  db TextBuf.Index(+1, +1)
  db TextBuf.Index(+1,  0)
  db TextBuf.Index(+1, -1)
  db TextBuf.Index( 0, -1)

GameWinStr:
  db 'GAME WIN'
%assign GameWinStr.Len $ - GameWinStr

GameOverStr:
  db 'GAME OVER'
%assign GameOverStr.Len $ - GameOverStr

;; Show game win screen
GameWin:
  mov cx, GameWinStr.Len
  mov bp, GameWinStr
  mov bx, Color.GameWinText
  jmp GameEndHelper

;; Show game over screen
GameOver:
  mov cx, GameOverStr.Len
  mov bp, GameOverStr
  mov bx, Color.GameOverText

;; Helper code for GameWin and GameOver
GameEndHelper:
  mov ax, 0x1300
  mov dx, ((TextBuf.Height / 2) << 8) | (TextBuf.Width / 2 - GameOverStr.Len / 2)
  ; es = 0
  xor di, di
  mov es, di
  int 0x10

  ; Halt forever
  cli
  hlt

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
