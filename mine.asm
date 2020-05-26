BITS 16
CPU 686

;; CONSTANTS

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

;; TODO: Delete these
%assign Map.Unveiled 0
%assign Map.Mines 0

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
  mov ax, 0x7700 | '0'
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
  and ax, 0xf
  setz dl

  jnz .LoopDir
  mov BYTE [di], '*'

.LoopDir:
  push di
  movsx ax, BYTE [bp + Dirs - 1]
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
  mov dl, 0x77

GameLoop:
  ; Get keystroke
  ; AH = BIOS scan code
  ; AL = ASCII character
  ; http://www.ctyme.com/intr/rb-1754.htm
  xor ax, ax
  int 0x16

  ; bx and cx zeroed from loop above
  ; bx = y coord
  ; cx = x coord

  call GetTextBufIndex
  mov [di + 1], dl

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
  mov dl, 0x24
  mov [di + 1], dl
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
  mov dl, 0x88
  xchg dl, [di + 1]

  jmp GameLoop

;; Split the linear cursor position in BP as COL:ROW in AH:AL
;;
;; Clobbered registers:
;;   * CL
GetCursorPos:
  mov ax, bp
  mov cl, TextBuf.Width
  div cl
  ret

;; di = &TextBuf[bx = y][cx = x]
GetTextBufIndex:
  push cx
  imul di, bx, TextBuf.Width * 2
  imul cx, cx, 2
  add di, cx
  pop cx
  ret

;; TODO: Use this method in more places
;;
;; Get the character at position BP in the text buffer in AL
;;
;; Clobbered registers:
;;   * DX
TextBufGetCharAt:
  push bp
  mov dx, TextBuf.Seg
  mov ds, dx
  add bp, bp
  mov al, [ds:bp]
  xor dx, dx
  mov ds, dx
  pop bp
  ret

;; TODO: Use this method in more places
;;
;; Put the character AL in the text buffer at position BP
;;
;; Clobbered registers:
;;   * DX
TextBufSetCharAt:
  push bp
  mov dx, TextBuf.Seg
  mov ds, dx
  add bp, bp
  mov [ds:bp], al
  xor dx, dx
  mov ds, dx
  pop bp
  ret

;; Flood fill empty cells
;;
;; Parameters:
;;   * BP - Cell index
;; Clobbered registers:
;;   * Yes [TODO]
Flood:
  push bp

  ; Base case: bounds check
  cmp bp, TextBuf.Size
  jae .Ret

  ; Base case: visited cell
  call TextBufGetCharAt
  cmp al, '.'
  jne .Ret

  ; Body: unveil cell
  mov al, [bp + Map.Unveiled]
  call TextBufSetCharAt

  ; Base case: nonempty cell
  cmp al, ' '
  jne .Ret

  ; Recursive case: flood adjacent cells

  ; Flood up
  push bp
  sub bp, TextBuf.Width
  call Flood
  pop bp

  ; Flood down
  push bp
  add bp, TextBuf.Width
  call Flood
  pop bp

  ; Flood left
  call GetCursorPos
  test ah, ah
  jz .Right
  push bp
  dec bp
  call Flood
  pop bp

.Right:
  ; Flood right
  inc bp
  call GetCursorPos
  test ah, ah
  jz .Ret
  call Flood

.Ret:
  pop bp
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

GameOverStr:
  db 'GAME OVER'
%assign GameOverStr.Len $ - GameOverStr

;; Unveil all the mines, print "GAME OVER" text, and allow restarting
;; TODO: Finish this
GameOver:
  ; Print "GAME OVER" in center of screen
  mov ax, 0x1300
  mov bx, 0x00c0
  mov cx, GameOverStr.Len
  mov dx, ((TextBuf.Height / 2) << 8) | (TextBuf.Width / 2 - GameOverStr.Len / 2)
  mov bp, GameOverStr
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
