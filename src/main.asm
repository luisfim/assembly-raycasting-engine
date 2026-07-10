global _start

%define MAP_WIDTH 16
%define MAP_HEIGHT 8

; Direction values:
; 0 = north
; 1 = east
; 2 = south
; 3 = west

section .data
    clear_screen db 27, "[2J", 27, "[H"
    clear_screen_len equ $ - clear_screen

    title db "asm-raycaster - step 4: player direction", 10
          db "W/S = move forward/backward | A/D = rotate | X = quit", 10
          db "Press a key, then ENTER.", 10, 10
    title_len equ $ - title

    newline db 10

    dir_chars db "^>v<"

    player_x dq 4
    player_y dq 5
    player_dir dq 1        ; start facing east

    map:
        db "################"
        db "#              #"
        db "#      ##      #"
        db "#      ##      #"
        db "#              #"
        db "#              #"
        db "#              #"
        db "################"

section .bss
    input_buf resb 8

section .text

_start:
.game_loop:
    call clear_terminal
    call print_title
    call render_map
    call read_input
    call handle_input
    jmp .game_loop

; ----------------------------------------
; clear_terminal
; ----------------------------------------
clear_terminal:
    lea rsi, [rel clear_screen]
    mov rdx, clear_screen_len
    call print
    ret

; ----------------------------------------
; print_title
; ----------------------------------------
print_title:
    lea rsi, [rel title]
    mov rdx, title_len
    call print
    ret

; ----------------------------------------
; print
; rsi = buffer address
; rdx = buffer length
; ----------------------------------------
print:
    mov rax, 1      ; syscall: write
    mov rdi, 1      ; stdout
    syscall
    ret

; ----------------------------------------
; read_input
; Reads keyboard input from stdin.
; In normal terminal mode, user must press ENTER.
; ----------------------------------------
read_input:
    mov rax, 0              ; syscall: read
    mov rdi, 0              ; stdin
    lea rsi, [rel input_buf]
    mov rdx, 8
    syscall
    ret

; ----------------------------------------
; handle_input
; ----------------------------------------
handle_input:
    mov al, [rel input_buf]

    cmp al, 'x'
    je exit_program
    cmp al, 'X'
    je exit_program

    cmp al, 'w'
    je move_forward
    cmp al, 'W'
    je move_forward

    cmp al, 's'
    je move_backward
    cmp al, 'S'
    je move_backward

    cmp al, 'a'
    je rotate_left
    cmp al, 'A'
    je rotate_left

    cmp al, 'd'
    je rotate_right
    cmp al, 'D'
    je rotate_right

    ret

; ----------------------------------------
; rotate_left
; direction = direction - 1
; wraps from 0 to 3
; ----------------------------------------
rotate_left:
    mov rax, [rel player_dir]

    cmp rax, 0
    jne .not_zero

    mov rax, 3
    jmp .store

.not_zero:
    dec rax

.store:
    mov [rel player_dir], rax
    ret

; ----------------------------------------
; rotate_right
; direction = direction + 1
; wraps from 3 to 0
; ----------------------------------------
rotate_right:
    mov rax, [rel player_dir]
    inc rax

    cmp rax, 4
    jne .store

    xor rax, rax

.store:
    mov [rel player_dir], rax
    ret

; ----------------------------------------
; move_forward
; Moves based on player_dir
; ----------------------------------------
move_forward:
    mov rax, [rel player_x]     ; new x
    mov rbx, [rel player_y]     ; new y
    mov rcx, [rel player_dir]

    cmp rcx, 0
    je .north

    cmp rcx, 1
    je .east

    cmp rcx, 2
    je .south

    cmp rcx, 3
    je .west

    ret

.north:
    dec rbx
    call try_move
    ret

.east:
    inc rax
    call try_move
    ret

.south:
    inc rbx
    call try_move
    ret

.west:
    dec rax
    call try_move
    ret

; ----------------------------------------
; move_backward
; Moves opposite of player_dir
; ----------------------------------------
move_backward:
    mov rax, [rel player_x]     ; new x
    mov rbx, [rel player_y]     ; new y
    mov rcx, [rel player_dir]

    cmp rcx, 0
    je .north

    cmp rcx, 1
    je .east

    cmp rcx, 2
    je .south

    cmp rcx, 3
    je .west

    ret

.north:
    inc rbx
    call try_move
    ret

.east:
    dec rax
    call try_move
    ret

.south:
    dec rbx
    call try_move
    ret

.west:
    inc rax
    call try_move
    ret

; ----------------------------------------
; try_move
; rax = new x
; rbx = new y
; Checks collision. If target is not '#',
; updates player position.
; ----------------------------------------
try_move:
    ; index = y * MAP_WIDTH + x
    mov rcx, rbx
    imul rcx, MAP_WIDTH
    add rcx, rax

    lea rsi, [rel map]
    add rsi, rcx

    cmp byte [rsi], '#'
    je .blocked

    mov [rel player_x], rax
    mov [rel player_y], rbx

.blocked:
    ret

; ----------------------------------------
; render_map
; Draws map and player direction.
; ----------------------------------------
render_map:
    xor r12, r12        ; y = 0

.y_loop:
    cmp r12, MAP_HEIGHT
    jge .done

    xor r13, r13        ; x = 0

.x_loop:
    cmp r13, MAP_WIDTH
    jge .print_newline

    ; Is this the player position?
    cmp r13, [rel player_x]
    jne .print_map_tile

    cmp r12, [rel player_y]
    jne .print_map_tile

    ; Print player direction character
    mov rax, [rel player_dir]
    lea rsi, [rel dir_chars]
    add rsi, rax

    mov rdx, 1
    call print
    jmp .next_tile

.print_map_tile:
    ; index = y * MAP_WIDTH + x
    mov rax, r12
    imul rax, MAP_WIDTH
    add rax, r13

    lea rsi, [rel map]
    add rsi, rax

    mov rdx, 1
    call print

.next_tile:
    inc r13
    jmp .x_loop

.print_newline:
    lea rsi, [rel newline]
    mov rdx, 1
    call print

    inc r12
    jmp .y_loop

.done:
    ret

exit_program:
    mov rax, 60     ; syscall: exit
    mov rdi, 0
    syscall