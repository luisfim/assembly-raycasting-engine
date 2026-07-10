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

    title db "asm-raycaster - step 6: ray distance", 10
          db "W/S = move forward/backward | A/D = rotate | X = quit", 10
          db "The * shows where the ray hits a wall.", 10
          db "Press a key, then ENTER.", 10, 10
    title_len equ $ - title

    distance_label db "Ray distance to wall: "
    distance_label_len equ $ - distance_label

    newline db 10

    dir_chars db "^>v<"
    hit_char db "*"

    player_x dq 4
    player_y dq 5
    player_dir dq 1        ; start facing east

    ray_hit_x dq 0
    ray_hit_y dq 0
    ray_dist dq 0

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
    number_buf resb 32

section .text

_start:
.game_loop:
    call cast_single_ray
    call clear_terminal
    call print_title
    call render_map
    call print_status
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
; print_status
; Prints ray distance.
; ----------------------------------------
print_status:
    lea rsi, [rel distance_label]
    mov rdx, distance_label_len
    call print

    mov rax, [rel ray_dist]
    call print_uint

    lea rsi, [rel newline]
    mov rdx, 1
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
; print_uint
; rax = unsigned integer to print
; ----------------------------------------
print_uint:
    cmp rax, 0
    jne .convert

    lea rsi, [rel number_buf]
    mov byte [rsi], '0'
    mov rdx, 1
    call print
    ret

.convert:
    lea rsi, [rel number_buf]
    add rsi, 32

    mov rbx, 10
    xor rcx, rcx

.convert_loop:
    xor rdx, rdx
    div rbx                 ; rax = quotient, rdx = remainder

    dec rsi
    add dl, '0'
    mov [rsi], dl

    inc rcx

    test rax, rax
    jnz .convert_loop

    mov rdx, rcx
    call print
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
; ----------------------------------------
move_forward:
    mov rax, [rel player_x]
    mov rbx, [rel player_y]
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
; ----------------------------------------
move_backward:
    mov rax, [rel player_x]
    mov rbx, [rel player_y]
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
; ----------------------------------------
try_move:
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
; cast_single_ray
; Shoots one ray from the player in the
; current direction until it hits '#'.
; Stores hit position and distance.
; ----------------------------------------
cast_single_ray:
    mov r8, [rel player_x]      ; ray x
    mov r9, [rel player_y]      ; ray y
    mov rcx, [rel player_dir]   ; direction
    xor r10, r10                ; distance counter

.ray_loop:
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
    dec r9
    inc r10
    jmp .check_tile

.east:
    inc r8
    inc r10
    jmp .check_tile

.south:
    inc r9
    inc r10
    jmp .check_tile

.west:
    dec r8
    inc r10
    jmp .check_tile

.check_tile:
    ; index = y * MAP_WIDTH + x
    mov rax, r9
    imul rax, MAP_WIDTH
    add rax, r8

    lea rsi, [rel map]
    add rsi, rax

    cmp byte [rsi], '#'
    je .hit_wall

    jmp .ray_loop

.hit_wall:
    mov [rel ray_hit_x], r8
    mov [rel ray_hit_y], r9
    mov [rel ray_dist], r10
    ret

; ----------------------------------------
; render_map
; Draws map, player direction, and ray hit.
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
    jne .check_ray_hit

    cmp r12, [rel player_y]
    jne .check_ray_hit

    ; Print player direction character
    mov rax, [rel player_dir]
    lea rsi, [rel dir_chars]
    add rsi, rax

    mov rdx, 1
    call print
    jmp .next_tile

.check_ray_hit:
    ; Is this the ray hit position?
    cmp r13, [rel ray_hit_x]
    jne .print_map_tile

    cmp r12, [rel ray_hit_y]
    jne .print_map_tile

    lea rsi, [rel hit_char]
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
    mov rax, 60
    mov rdi, 0
    syscall