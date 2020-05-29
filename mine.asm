bits 16
cpu 686

;; Constants

;; Boot sector load address
%assign BootSector.Begin 0x7c00

;; Boot sector size in bytes
%assign BootSector.Size 512

;; Words in 16 bit x86 are 2 bytes
%assign WordSize 2

;; This is the value to store in segment register to access the VGA text buffer.
;; In 16 bit x86, segmented memory accesses are of the form:
;;
;;   (segment register) * 0x10 + (offset register)
;;
;; The VGA text buffer is at 0xb80000, so if 0xb800 is stored in a segment
;; register, then memory access instructions will be relative to the VGA text
;; buffer, allowing easier access. For example, trying to access the nth byte of
;; memory will *actually* access the nth byte of the text buffer.
%assign TextBuf.Seg 0xb800

;; Dimensions of text buffer
%assign TextBuf.Width 40
%assign TextBuf.Height 25
%assign TextBuf.Size (TextBuf.Width * TextBuf.Height)

;; Macro to get the index of a text buffer cell from coordinates
%define TextBuf.Index(y, x) ((y) * TextBuf.Width * 2 + (x) * 2)

;; Length of Dirs array defined below
%assign Dirs.Len 8

;; Keyboard scan codes
;; http://www.ctyme.com/intr/rb-0045.htm#Table6
%assign Key.ScanCode.Space 0x39
%assign Key.ScanCode.Up 0x48
%assign Key.ScanCode.Down 0x50
%assign Key.ScanCode.Left 0x4b
%assign Key.ScanCode.Right 0x4d
%assign Key.ScanCode.Enter 0x1c

;; Keyboard ASCII codes
%assign Key.Ascii.RestartGame 'r'

;; This is a convenience macro for creating VGA characters. VGA characters are
;; 16 bit words, with the lower byte as the ASCII value and the upper byte
;; holding the foreground and background colors.
%define VgaChar(color, ascii) (((color) << 8) | (ascii))

;; VGA colors to use for game items
;; https://wiki.osdev.org/Text_UI#Colours
%assign Color.Veiled 0x17
%assign Color.Unveiled 0xf0
%assign Color.Cursor 0x00
%assign Color.Flag 0xcc
%assign Color.GameWinText 0x20
%assign Color.GameOverText 0xc0

org BootSector.Begin

;; Entry point: set up graphics and run game
BootMine:
  ; VGA text mode 0x00
  ; 320x200 pixel resolution
  ; 40x25 text resolution
  ; 16 colors
  ; http://www.ctyme.com/intr/rb-0069.htm
  xor ax, ax
  int 0x10

  ; Disable VGA text mode cursor
  ; https://wiki.osdev.org/Text_Mode_Cursor#Disabling_the_Cursor
  mov ah, 0x01
  mov ch, 0x3f
  int 0x10

  ; Disable blinking text
  ; https://www.reddit.com/r/osdev/comments/70fcig/blinking_text/dn2t6u8?utm_source=share&utm_medium=web2x
  ; Read I/O Address 0x03DA to reset index/data flip-flop
  mov dx, 0x03DA
  in al, dx
  ; Write index 0x30 to 0x03C0 to set register index to 0x30
  mov dx, 0x03C0
  mov al, 0x30
  out dx, al
  ; Read from 0x03C1 to get register contents
  inc dx
  in al, dx
  ; Unset Bit 3 to disable Blink
  and al, 0xF7
  ; Write to 0x03C0 to update register with changed value
  dec dx
  out dx, al

;; Run game (the game is restarted by jumping here)
RunGame:
  ; Load VGA text buffer segment into segment registers
  mov dx, TextBuf.Seg
  mov es, dx
  mov ds, dx

;; Set all cells of game map to veiled '0' cells
ZeroTextBuf:
  xor di, di
  mov cx, TextBuf.Size
  mov ax, VgaChar(Color.Veiled, '0')
.Loop:
  stosw
  loop .Loop

;; Populate text buffer with mines and digits
;;
;; This is done with a single triple-nested loop. The nested loops iterate over
;; y coordinates, then x coordinates, then over the 8 adjacent cells at (y, x).
;;
;; Inside the inner loop is bomb generation and digit incrementing logic.
;;
;; Note that the coordinates on the outside border are skipped to avoid bounds
;; checking logic.
PopulateTextBuf:
  xor di, di                    ; TODO: delete this
  ; Iterate over y coordinates
  mov bx, TextBuf.Height - 2

.LoopY:
  ; Iterate over x coordinates
  mov cx, TextBuf.Width - 2

.LoopX:
  ; Iterate over adjacent cells (directions)
  mov bp, Dirs.Len

  push bx                       ; TODO: delete this
  push cx                       ; TODO: delete this

  ; di = &TextBuf[y][x]
  call GetTextBufIndex

  pop cx                        ; TODO: delete this
  pop bx                        ; TODO: delete this

  ; dx = ! (bool) (rdtsc() & 0xf)
  rdtsc
  and al, 0x0
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

  ; Detect win (a win occurs when every veiled cell is a mine)
DetectWin:
  xor si, si
  push ax
  push cx
  mov cx, TextBuf.Size
.Loop:
  lodsw
  cmp ah, Color.Veiled
  je .CheckMine
  cmp ah, Color.Flag
  jne .Continue
.CheckMine:
  cmp al, '*'
  jne .Break
.Continue:
  loop .Loop
  jmp GameWin
.Break:
  pop cx
  pop ax

  ; Process key press
CmpUp:
  cmp ah, Key.ScanCode.Up
  jne CmpDown
  dec bx
  jmp WrapCursor
CmpDown:
  cmp ah, Key.ScanCode.Down
  jne CmpLeft
  inc bx
  jmp WrapCursor
CmpLeft:
  cmp ah, Key.ScanCode.Left
  jne CmpRight
  dec cx
  jmp WrapCursor
CmpRight:
  cmp ah, Key.ScanCode.Right
  jne CmpEnter
  inc cx
  jmp WrapCursor
CmpEnter:
  cmp ah, Key.ScanCode.Enter
  jne CmpSpace
  ; Place flag
  mov dl, Color.Flag
  mov [di + 1], dl
  jmp GameLoop
CmpSpace:
  cmp ah, Key.ScanCode.Space
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

;; Compute the text buffer index from y and x coordinates
;;
;; di = &TextBuf[bx = y][cx = x]
;;
;; This computes the equivalent of the TextBuf.Index(y, x) macro, but at runtime
;;
;; Parameters:
;;   * bx - y coordinate
;;   * cx - x coordinate
;; Returns:
;;   * di - text buffer index
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

;; Wait for restart key to be pressed, then restart game
WaitRestart:
  xor ax, ax
  int 0x16
  cmp al, Key.Ascii.RestartGame
  jne WaitRestart
  jmp RunGame


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
