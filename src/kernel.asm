;;; =========================================================================== 
;;; Kernel.asm: basic 'kernel' loaded from our bootsector
;;; ===========================================================================
        ;; --------------------------------------------------------------------
        ;; Screen & Menu Set up
        ;; --------------------------------------------------------------------
main_menu:
		;; Get passed drive number
		mov byte [kernel_drive_num], dl

        ;; Reset screen state
        call clear_screen_text_mode
        
        ; Print OS boot message
        mov si, menuString
		push si
		push word kernel_cursor_y		
		push word kernel_cursor_x
        call print_string_text_mode
		add sp, 6

        ;; --------------------------------------------------------------------
        ;; Get user input, print to screen & choose menu option/run command
        ;; --------------------------------------------------------------------
get_input:
	mov ax, 200h		; reset ES & DS segments to kernel area
	mov es, ax
	mov ds, ax

	; Reset tokens data, arrays, and variables for next input line
	mov di, tokens
	xor ax, ax
	mov cx, 50
	rep stosb

	mov di, tokens_length
	mov cx, 5
	rep stosw

	mov byte [token_count], 0	

	xor al, al
	mov di, token_file_name1
	mov cx, 10
	rep stosb
	mov di, token_file_name2
	mov cx, 10
	rep stosb

	; Print prompt
	mov si, prompt
	push si						; Address of string to print - input 1
	push word kernel_cursor_y	; Row to print to - input 2
	push word kernel_cursor_x	; Col to print to - input 3
	call print_string_text_mode
	add sp, 6

	; Move cursor after prompt
	push word [kernel_cursor_y]
	push word [kernel_cursor_x]
	call move_cursor
	add sp, 4
	
	xor cx, cx			; reset byte counter of input
    mov si, cmdString   ; si now pointing to command string
	
keyloop:
    xor ax, ax              ; ah = 00h al = 00h
    int 16h                 ; BIOS int get keystroke ah=0, al <- character

    cmp al, 0Dh             ; user pressed enter?
    je tokenize_input_line	; tokenize user input line
	
	cmp al, 08h				; backspace?
	jne .not_backspace

	dec si					; yes, go back one char in cmdString
	jcxz .there
	dec cx					; byte counter - 1
	
	.there:
	cmp word [kernel_cursor_x], 0	; At start of line?
	je keyloop						; Yes, skip

	; Move cursor back 1 space
	dec word [kernel_cursor_x]		; Otherwise move back

	;; Print a space at cursor
	push word 0020h
	push word kernel_cursor_y
	push word kernel_cursor_x
	call print_char_text_mode
	add sp, 6

	; Move cursor back 1 space again because print_char moves it forward
	dec word [kernel_cursor_x]
	push word [kernel_cursor_y]
	push word [kernel_cursor_x]
	call move_cursor
	add sp, 4

	jmp keyloop

.not_backspace:
    mov [si], al            ; store input char to string
	inc cx					; increment byte counter of input
	mov word [save_cx], cx
    inc si                  ; go to next byte at si/cmdString

	; Print input character to screen
	xor ah, ah
	push ax						; Character to print - input 1
	push word kernel_cursor_y	; Row to print to - input 2
	push word kernel_cursor_x	; Column to print to - input 3
	call print_char_text_mode
	add sp, 6					; Clean up stack

	; Move cursor 
	push word [kernel_cursor_y]
	push word [kernel_cursor_x]
	call move_cursor
	add sp, 4

	mov cx, word [save_cx]
    jmp keyloop             ; loop for next character from user

	;; Prompt/"Shell" commands
tokenize_input_line:
	cmp cx, 0
	je input_not_found  	; handle empty input
	
    mov byte [si], 0        ; else null terminate cmdString from si
	mov si, cmdString		; reset si to point to start of user input

	;; Tokenize input string "cmdString" into separate tokens
	mov di, tokens			; DI <- tokens array		[5][10]
	mov bx, tokens_length	; BX <- tokens_length array [5][2]
	.get_token_loop:
		lodsb				; mov al, [ds:si] & inc si
		cmp al, 0h			; At end of input?
		je check_commands

		; Skip whitespace between tokens
		.whitespace_loop:
			cmp al, ' ' 
			jne .alphanum_loop	
			lodsb
		jmp .whitespace_loop

		; Get all alphanumeric characters for current token
		; when not alphanumeric, skip and go to next token/whitespace check
		.alphanum_loop:
			cmp al, '0'					; Check numeric first
			jl .next_token
			cmp al, '9'
			jg .check_uppercase
			stosb
			inc word [bx]		; increment length of current token
			lodsb
			jmp .alphanum_loop
			
			.check_uppercase:
				cmp al, 'A'
				jl .next_token
				cmp al, 'Z'
				jg .check_underscore
				stosb
				inc word [bx]
				lodsb
				jmp .alphanum_loop

			.check_underscore:
				cmp al, '_'
				jl .next_token
				jg .check_lowercase
				stosb
				inc word [bx]
				lodsb
				jmp .alphanum_loop

			.check_lowercase:
				cmp al, 'a'
				jl .next_token
				cmp al, 'z'
				jg .next_token
				stosb
				inc word [bx]			
				lodsb
				jmp .alphanum_loop

			.next_token:
				inc byte [token_count]		; next token

				; Move di to next token position in tokens array
				mov word [kernel_save_bx], bx

				xor bx, bx
				mov bl, byte [token_count]
				imul bx, 10
				lea di, [tokens+bx]

				; Move to next position in tokens_length array
				mov bx, word [kernel_save_bx]
				add bx, 2				; each length is 1 word long 
				
				dec si					; get token loop does lodsb again, prevent error here
	jmp .get_token_loop

check_commands:	
	;; Get first token (command to run) & second token (if applicable e.g. file name)
	xor ch, ch
	mov cx, word [tokens_length]

	mov si, tokens
	push cx
	mov di, cmdDir
	repe cmpsb
	je fileTable_print

	pop cx
	push cx
	mov di, cmdReboot
	mov si, cmdString
	repe cmpsb
	je reboot

	pop cx
	push cx
    mov di, cmdPrtreg
	mov si, cmdString
	repe cmpsb
	je registers_print

	pop cx
	push cx
	mov di, cmdGfxtst
	mov si, cmdString
	repe cmpsb
	je graphics_test

	pop cx
	push cx
	mov di, cmdHlt
	mov si, cmdString
	repe cmpsb
	je end_program

	pop cx
	push cx
	mov di, cmdCls
	mov si, cmdString
	repe cmpsb
	je clear_screen

	pop cx
	push cx
	mov di, cmdShutdown
	mov si, cmdString
	repe cmpsb
	je shutdown

	pop cx
	push cx
	mov di, cmdDelFile
	mov si, cmdString
	repe cmpsb
	je del_file

	pop cx			
	push cx
	mov di, cmdRenFile
	mov si, cmdString
	repe cmpsb
	je ren_file

	pop cx			; reset command length

	;; If command not input, search file table entries for user input file
check_files:
	mov ax, 100h		; reset ES:BX to start of file table (100h:0000h = 1000h)
	mov es, ax
    xor di, di
	
	mov si, cmdString	; reset si to start of user input string

kernel_check_next_name:
        mov al, [ES:DI]         ; get file table character
        cmp al, 0               ; at end of file table?
        je input_not_found		; if so, no file/pgm found for user input :(

        cmp al, [si]            ; does user input match file table character?
        je start_compare

		add di, 16              ; if not, go to next file entry in table
        jmp kernel_check_next_name

start_compare:
        push di                 ; save file table position

		rep cmpsb
		je found_program
        mov si, cmdString       ; otherwise reset to start of user input
        pop di                  ; get saved file table position
		add di, 16				; Next file table entry
        jmp kernel_check_next_name     ; start checking again

	;; Read disk sector of program to memory and execute it by far jumping
    ;; -------------------------------------------------------------------
found_program:
	pop di		; start_compare above pushes di, restore here to start of file name/table entry

	;; Get file extension - bytes 10-12 of file table entry
	.file_extension:
	mov al, [ES:DI+10]
	mov [fileExt], al
	mov al, [ES:DI+11]
	mov [fileExt+1], al
	mov al, [ES:DI+12]
	mov [fileExt+2], al
	
    mov cl, [ES:DI+14]     ; sector number to start reading at
	;; Get correct track # & sector #
	xor ah, ah
	mov al, cl
	mov cl, 18	; 18 = number of sectors per track for a floppy disk
	div cl		; AX / byte value (in CL); AL = quotient, AH = remainder
	mov ch, al	; CH = track #, quotient
	mov cl, ah	; CL = sector #, remainder
	cmp cl, 0
	jne .after
	mov cl, 18	

	.after:
	mov bl, [ES:DI+15]		; file size in sectors / # of sectors to read
	mov byte [fileSize], bl

	xor ax, ax
	xor dh, dh
    mov dl, [kernel_drive_num]	; drive #
    int 13h     		; int 13h ah 0 = reset disk system

    mov ax, 800h        ; memory location to load pgm to
    mov es, ax
	mov al, bl  		; # of sectors to read
    xor bx, bx          ; ES:BX <- 800h:0000h = 8000h

    mov ah, 02h         ; int 13h ah 2 = read disk sectors to memory
    mov ch, 00h         ; track #
    mov dh, 00h         ; head #
    mov dl, [kernel_drive_num]	; drive #

    int 13h
    jnc run_program	        ; carry flag not set, success

    mov si, pgmNotLoaded    ; else error, program did not load correctly
	;; Print string
	push si
	push word kernel_cursor_y
	push word kernel_cursor_x
    call print_string_text_mode
	add sp, 6

	;; Move cursor
	push word [kernel_cursor_y]
	push word [kernel_cursor_x]
	call move_cursor
	add sp, 4

    jmp get_input		    ; go back to prompt for input

run_program:
	;; Check file extension in file table entry, if 'bin'/binary, then far jump & run
	;;   Else if 'txt', then print content to screen
	mov cx, 3
	mov si, fileExt
	mov ax, 200h  		; Reset es to kernel space for comparison (ES = DS)
	mov es, ax	    	; ES <- 2000h
	mov di, fileBin
	repe cmpsb
	jne print_txt_file

	;; Reset cursor positions so printing is good when returning to kernel later
	mov word [kernel_cursor_y], 0
	mov word [kernel_cursor_x], 0

	mov dl, [kernel_drive_num]	; Store drive # to use

    mov ax, 800h       ; program loaded, set segment registers to location
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    jmp 800h:0000h     ; far jump to program to execute
	
print_txt_file:
	mov ax, 800h 		; Set ES back to file memory location
	mov es, ax	    	; ES <- 8000h
	xor cx, cx
	mov ah, 0Eh
	
	;; Get size of filesize in bytes (512 byte per sector)
add_cx_size:		
	imul cx, word [fileSize], 512 

print_file_char:
	mov al, [ES:BX]
	cmp al, 0Fh
	jle call_h_to_a
	
return_file_char:	
	;; Print file character to screen
	mov word [kernel_save_bx], bx
	xor ah, ah
	push ax
	push word kernel_cursor_y
	push word kernel_cursor_x
	call print_char_text_mode
	add sp, 6

	;; Move cursor
	push word [kernel_cursor_y]
	push word [kernel_cursor_x]
	call move_cursor
	add sp, 4

	mov bx, word [kernel_save_bx]
	inc bx
	loop print_file_char	; Keep printing characters and decrement CX till 0

	;; Print newline after done printing file contents
	push word 000Ah
	push word kernel_cursor_y
	push word kernel_cursor_x
	call print_char_text_mode
	add sp, 6

	;; Move cursor
	push word [kernel_cursor_y]
	push word [kernel_cursor_x]
	call move_cursor
	add sp, 4
	
	push 000Dh
	push word kernel_cursor_y
	push word kernel_cursor_x
	call print_char_text_mode
	add sp, 6

	;; Move cursor
	push word [kernel_cursor_y]
	push word [kernel_cursor_x]
	call move_cursor
	add sp, 4

	jmp get_input   		; after all printed, go back to prompt

call_h_to_a:
	call hex_to_ascii		; convert AL hex character to ASCII character 
	jmp return_file_char
	
input_not_found:
	pop cx					; In case program was not found
    mov si, failure         ; command not found! boo D:
	;; Print string
	push si
	push word kernel_cursor_y
	push word kernel_cursor_x
	call print_string_text_mode
	add sp, 6

	;; Move cursor
	push word [kernel_cursor_y]
	push word [kernel_cursor_x]
	call move_cursor
	add sp, 4

    jmp get_input 

        ;; --------------------------------------------------------------------
        ;; File/Program browser & loader   
        ;; --------------------------------------------------------------------
fileTable_print: 
	mov dl, [kernel_drive_num]			; pass drive #
	push word kernel_cursor_y
	push word kernel_cursor_x
	call print_fileTable
	add sp, 4

	jmp get_input

        ;; --------------------------------------------------------------------
        ;; Reboot: far jump to reset vector
        ;; --------------------------------------------------------------------
reboot: 
    jmp 0FFFFh:0000h

        ;; --------------------------------------------------------------------
        ;; Print Register Values
        ;; --------------------------------------------------------------------
registers_print:
	push word kernel_cursor_y
	push word kernel_cursor_x
    call print_registers
	add sp, 4

	jmp get_input		; return to prompt '>:'
	
        ;; --------------------------------------------------------------------
        ;; Graphics Mode Test(s)
        ;; --------------------------------------------------------------------
graphics_test:
        call resetGraphicsScreen

        ;; Test Square
        mov ah, 0Ch           ; int 10h ah 0Ch - write gfx pixel
        mov al, 02h           ; green
        mov bh, 00h           ; page number

        ;; Starting pixel of square
        mov cx, 100           ; column #
        mov dx, 100           ; row #
        int 10h

        ;; Pixels for columns 
squareColLoop:
        inc cx
        int 10h
        cmp cx, 150
        jne squareColLoop

        ;; Go down one row
        inc dx
        int 10h
        mov cx, 99 
        cmp dx, 150
        jne squareColLoop       ; pixels for next row

        mov ah, 00h
        int 16h                 ; get keystroke

		; Temp Fix: reset text mode screen
		mov ax, 0003h			; int 10h ah00 = set video mode; 80x25 16 colors text mode
		int 10h
		
		mov ah, 0Bh				; int 10h ah 0Bh = set palette
		mov bx, 0001h			; bl = bg color for text mode; blue
		int 10h

        jmp main_menu

        ;; --------------------------------------------------------------------
        ;; Clear Screen
        ;; --------------------------------------------------------------------
clear_screen:
	call clear_screen_text_mode

	; Update cursor values for new position
	mov word [kernel_cursor_y], 0
	mov word [kernel_cursor_x], 0

	jmp get_input

        ;; --------------------------------------------------------------------
        ;; Delete a file from the disk
        ;; --------------------------------------------------------------------
del_file:
	;; 1 - File name to delete
	;; 2 - Length of file name
	mov si, tokens	; File name is 2nd token in array, each token is 10 char max
	add si, 10
	mov di, token_file_name1
	xor ch, ch
	mov cx, word [tokens_length+2]
	rep movsb
	mov cx, word [tokens_length+2]

	push word token_file_name1	; File name
	push cx						; Length of file name

	mov dl, [kernel_drive_num]
	call delete_file

	;; Clean up stack after call
	add sp, 4

	;; TODO: Check return code for errors
	cmp ax, 0	; 0 = Success/Normal return

	; Print newline when done
	push 000Ah
	push kernel_cursor_y
	push kernel_cursor_x
	call print_char_text_mode
	add sp, 6

	; Move cursor 
	push word [kernel_cursor_y]
	push word [kernel_cursor_x]
	call move_cursor
	add sp, 4

	push 000Dh
	push kernel_cursor_y
	push kernel_cursor_x
	call print_char_text_mode
	add sp, 6

	; Move cursor 
	push word [kernel_cursor_y]
	push word [kernel_cursor_x]
	call move_cursor
	add sp, 4

	jmp get_input

        ;; --------------------------------------------------------------------
        ;; Rename a file in the file table
        ;; --------------------------------------------------------------------
ren_file:
	;; 1 - File to rename
	;; 2 - Length of name to rename
	;; 3 - New file name
	;; 4 - New file name length
	mov si, tokens	; File name is 2nd token in array, each token is 10 char max
	add si, 10
	mov di, token_file_name1
	mov cx, word [tokens_length+2]
	rep movsb
	push word token_file_name1	; File name			- input 1
	push word [tokens_length+2]	; File name length  - input 2

	mov si, tokens	; New file name is 3rd token in array, each token is 10 char max
	add si, 20
	mov di, token_file_name2
	mov cx, word [tokens_length+4]
	rep movsb
	push word token_file_name2	; New file name		   - input 3
	push word [tokens_length+4] ; New file name length - input 4

	mov dl, [kernel_drive_num]
	call rename_file

	;; Clean up stack after call
	add sp, 8

	;; TODO: Check return code for errors
	cmp ax, 0	; 0 = Success/Normal return

	; Print newline when done
	push 000Ah
	push kernel_cursor_y
	push kernel_cursor_x
	call print_char_text_mode
	add sp, 6

	; Move cursor 
	push word [kernel_cursor_y]
	push word [kernel_cursor_x]
	call move_cursor
	add sp, 4

	push 000Dh
	push kernel_cursor_y
	push kernel_cursor_x
	call print_char_text_mode
	add sp, 6

	; Move cursor 
	push word [kernel_cursor_y]
	push word [kernel_cursor_x]
	call move_cursor
	add sp, 4

	jmp get_input

	    ;; --------------------------------------------------------------------
        ;; Shutdown (QEMU)
        ;; --------------------------------------------------------------------
shutdown:
	mov ax, 2000h
	mov dx, 604h
	out dx, ax

        ;; --------------------------------------------------------------------
        ;; End Program  
        ;; --------------------------------------------------------------------
end_program:
    cli                     ; clear interrupts
    hlt                     ; halt cpu

        ;; ====================================================================
        ;; End Main Logic
        ;; ====================================================================
	
        ;; --------------------------------------------------------------------
        ;; Include Files
        ;; --------------------------------------------------------------------
		include "../include/print/print_char_text_mode.inc"
		include "../include/print/print_string_text_mode.inc"
        include "../include/print/print_hex.inc"
        include "../include/print/print_registers.inc"
		include "../include/print/print_fileTable.inc"
		include "../include/screen/clear_screen_text_mode.inc"
        include "../include/screen/resetGraphicsScreen.inc"
		include "../include/screen/move_cursor.inc"
		include "../include/type_conversions/hex_to_ascii.inc"
		include "../include/disk/file_ops.inc"
	
        ;; --------------------------------------------------------------------
        ;; Variables
        ;; --------------------------------------------------------------------
;; CONSTANTS
nl equ 0Ah,0Dh	; Carriage return/linefeed; "newline"
SPACE equ 20h	; ASCII space character	

;; REGULAR VARIABLES
menuString:     db '---------------------------------',nl,\
        'Kernel Booted, Welcome to QuesOS!',nl,\
        '---------------------------------',nl,nl,0
	
prompt:	db '>:',0
	
success:        db nl,'Program Found!',nl,0
failure:	db nl,'Command/Program not found, Try again',nl,0
	
windowsMsg:     db nl,'Oops! Something went wrong :(',nl,0
pgmNotLoaded:   db nl,'Program found but not loaded, Try Again',nl,0
	
	;; Prompt commands
cmdDir:		db 'dir',0	; directory command; list all files/pgms on disk
cmdReboot:	db 'reboot',0   ; 'warm' reboot option
cmdPrtreg:	db 'prtreg',0	; print register values
cmdGfxtst:	db 'gfxtst',0   ; graphics mode test
cmdHlt:		db 'hlt',0      ; e(n)d current program by halting cpu
cmdCls:		db 'cls',0	; clear screen by scrolling
cmdShutdown: db 'shutdown',0 ; Close QEMU emulator
cmdEditor:	db 'editor',0	; launch editor program
cmdDelFile: db 'del',0		; Delete a file from disk
cmdRenFile: db 'ren',0		; Rename a file in the file table
        
notFoundString: db nl,'Program/file not found!, Try again? (Y)',nl,0
sectNotFound:   db nl,'Sector not found!, Try again? (Y)',nl,0

cmdLength:      db 0

goBackMsg:      db nl,nl,'Press any key to go back...', 0
dbgTest:        db nl,'Test',nl,0
fileExt:	db '   ',0
fileSize:	db 0
fileBin:	db 'bin',0
fileTxt:	db 'txt',0
tokens: times 50 db 0		; tokens array, equivalent-ish to tokens[5][10]
tokens_length: times 5 dw 0	; length of each token in tokens array (0-10)
token_count: db 0			; How many tokens did the user enter?
kernel_save_bx:	dw 0
token_file_name1: times 10 db 0
token_file_name2: times 10 db 0
kernel_cursor_x: dw 0
kernel_cursor_y: dw 0
kernel_drive_num: db 0
cmdString: times 255 db 0

        ;; --------------------------------------------------------------------
        ;; Sector Padding magic
        ;; --------------------------------------------------------------------
        times 5120-($-$$) db 0   ; pads out 0s until we reach 1536th byte

