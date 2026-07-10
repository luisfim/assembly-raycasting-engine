global _start

%define MAP_WIDTH 16
%define MAP_HEIGHT 8

%define VIEW_WIDTH 31
%define VIEW_HEIGHT 12
%define VIEW_CENTER 15

; Direction values:
; 0 = north
; 1 = east
; 2 = south
; 3 = west

section .data
    clear_screen db 27, "[2J", 27, "[H"
    clear_screen_len equ $ - clear_screen

    title db "asm-raycaster - step 7: first 3D wall slice", 10
          db "W/S = move forward/backward | A/D = rotate | X = quit", 10
          db "The 3D preview uses ray distance to draw wall height.", 10
          db "Press a key, then ENTER.", 10, 10
    title_len equ $ - title

    view_label db 10, "Single-ray 3D preview:", 10
    view_label_len equ $ - view_label

    distance_label db 10, "Ray distance to wall: "
    distance_label_len equ $ - distance_label

    newline db 10

    dir_chars db "^>v<"
    hit_char db "*"
    wall_char db "#"
    empty_char db "."

    player_x dq 4
    player_y dq 5
    player_dir dq 1

    ray_hit_x dq 0
    ray_hit_y dq 0
    ray_dist dq 0

    wall_height dq 0
    wall_start_y dq 0
    wall_end_y dq 0

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
    call calculate_wall_slice

    call clear_terminal
    call print_title
    call render_map
    call render_3d_view
    call print_status

    call read_input
    call handle_input
    jmp .game_loop

clear_terminal:
    lea rsi, [rel clear_screen]
    mov rdx, clear_screen_len
    call print
    ret

print_title:
    lea rsi, [rel title]
    mov rdx, title_len
    call print
    ret

print:
    mov rax, 1
    mov rdi, 1
    syscall
    ret

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
    div rbx

    dec rsi
    add dl, '0'
    mov [rsi], dl

    inc rcx

    test rax, rax
    jnz .convert_loop

    mov rdx, rcx
    call print
    ret

read_input:
    mov rax, 0
    mov rdi, 0
    lea rsi, [rel input_buf]
    mov rdx, 8
    syscall
    ret

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

rotate_right:
    mov rax, [rel player_dir]
    inc rax

    cmp rax, 4
    jne .store

    xor rax, rax

.store:
    mov [rel player_dir], rax
    ret

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

cast_single_ray:
    mov r8, [rel player_x]
    mov r9, [rel player_y]
    mov rcx, [rel player_dir]
    xor r10, r10

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

calculate_wall_slice:
    ; wall_height = VIEW_HEIGHT / ray_dist
    mov rax, VIEW_HEIGHT
    xor rdx, rdx

    mov rbx, [rel ray_dist]
    cmp rbx, 0
    jne .divide

    mov rbx, 1

.divide:
    div rbx

    ; minimum wall height = 1
    cmp rax, 1
    jge .height_ok

    mov rax, 1

.height_ok:
    mov [rel wall_height], rax

    ; wall_start_y = (VIEW_HEIGHT - wall_height) / 2
    mov rcx, VIEW_HEIGHT
    sub rcx, rax
    shr rcx, 1

    mov [rel wall_start_y], rcx

    ; wall_end_y = wall_start_y + wall_height
    add rax, rcx
    mov [rel wall_end_y], rax

    ret

render_map:
    xor r12, r12

.y_loop:
    cmp r12, MAP_HEIGHT
    jge .done

    xor r13, r13

.x_loop:
    cmp r13, MAP_WIDTH
    jge .print_newline

    cmp r13, [rel player_x]
    jne .check_ray_hit

    cmp r12, [rel player_y]
    jne .check_ray_hit

    mov rax, [rel player_dir]
    lea rsi, [rel dir_chars]
    add rsi, rax

    mov rdx, 1
    call print
    jmp .next_tile

.check_ray_hit:
    cmp r13, [rel ray_hit_x]
    jne .print_map_tile

    cmp r12, [rel ray_hit_y]
    jne .print_map_tile

    lea rsi, [rel hit_char]
    mov rdx, 1
    call print
    jmp .next_tile

.print_map_tile:
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

render_3d_view:
    lea rsi, [rel view_label]
    mov rdx, view_label_len
    call print

    xor r12, r12        ; y = 0

.y_loop:
    cmp r12, VIEW_HEIGHT
    jge .done

    xor r13, r13        ; x = 0

.x_loop:
    cmp r13, VIEW_WIDTH
    jge .print_newline

    ; Only draw the center column for now.
    cmp r13, VIEW_CENTER
    jne .print_empty

    ; Is y inside wall_start_y <= y < wall_end_y?
    cmp r12, [rel wall_start_y]
    jb .print_empty

    cmp r12, [rel wall_end_y]
    jae .print_empty

    lea rsi, [rel wall_char]
    mov rdx, 1
    call print
    jmp .next_col

.print_empty:
    lea rsi, [rel empty_char]
    mov rdx, 1
    call print

.next_col:
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