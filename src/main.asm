global _start

%define MAP_WIDTH 16
%define MAP_HEIGHT 8

%define VIEW_WIDTH 31
%define VIEW_HEIGHT 16
%define VIEW_CENTER 15
%define ANGLE_COLUMN_SCALE 5
%define FP_SHIFT 10
%define MAX_RAY_STEPS 128

; Angle system:
; 0  = east
; 4  = south
; 8  = west
; 12 = north
; 16 total angle steps

section .data
    clear_screen db 27, "[2J", 27, "[H"
    clear_screen_len equ $ - clear_screen

    title db "asm-raycaster - fixed-point angled rays", 10
          db "W/S = move forward/backward | A/D = rotate | X = quit", 10
          db "Press a key, then ENTER.", 10, 10
    title_len equ $ - title

    map_label db "2D map:", 10
    map_label_len equ $ - map_label

    view_label db 10, "3D raycast view:", 10
    view_label_len equ $ - view_label

    angle_label db 10, "Player angle index: "
    angle_label_len equ $ - angle_label

    newline db 10

    dir_chars db ">v<^"
    wall_char db "#"
    shade_very_close db "@"
    shade_close db "#"
    shade_mid db "*"
    shade_far db "+"
    shade_very_far db "-"
    empty_char db "."

    ; Fixed-point position.
    ; 1024 = 1 tile.
    ; Start centered at map tile (4,5).
    player_x_fp dq 4608
    player_y_fp dq 5632
    player_angle dq 0

    map:
        db "################"
        db "#              #"
        db "#      ##      #"
        db "#      ##      #"
        db "#              #"
        db "#              #"
        db "#              #"
        db "################"

    ; 16 direction vectors, scaled by 1024.
    dir_dx dd 1024, 946, 724, 392, 0, -392, -724, -946
           dd -1024, -946, -724, -392, 0, 392, 724, 946

    dir_dy dd 0, 392, 724, 946, 1024, 946, 724, 392
           dd 0, -392, -724, -946, -1024, -946, -724, -392

section .bss
    input_buf resb 8
    number_buf resb 32

section .text

_start:
.game_loop:
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
    lea rsi, [rel angle_label]
    mov rdx, angle_label_len
    call print

    mov rax, [rel player_angle]
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
    mov rax, [rel player_angle]

    cmp rax, 0
    jne .not_zero

    mov rax, 15
    jmp .store

.not_zero:
    dec rax

.store:
    mov [rel player_angle], rax
    ret

rotate_right:
    mov rax, [rel player_angle]
    inc rax

    cmp rax, 16
    jne .store

    xor rax, rax

.store:
    mov [rel player_angle], rax
    ret

move_forward:
    mov rcx, [rel player_angle]
    call get_direction_vector

    ; movement speed = half tile
    sar r10, 1
    sar r11, 1

    mov rax, [rel player_x_fp]
    mov rbx, [rel player_y_fp]
    add rax, r10
    add rbx, r11
    call try_move_fp
    ret

move_backward:
    mov rcx, [rel player_angle]
    call get_direction_vector

    ; movement speed = half tile
    sar r10, 1
    sar r11, 1

    mov rax, [rel player_x_fp]
    mov rbx, [rel player_y_fp]
    sub rax, r10
    sub rbx, r11
    call try_move_fp
    ret

; rcx = angle index
; returns r10 = dx, r11 = dy
get_direction_vector:
    lea rsi, [rel dir_dx]
    movsxd r10, dword [rsi + rcx * 4]

    lea rsi, [rel dir_dy]
    movsxd r11, dword [rsi + rcx * 4]
    ret

; rax = new x fp
; rbx = new y fp
try_move_fp:
    mov r8, rax
    sar r8, FP_SHIFT

    mov r9, rbx
    sar r9, FP_SHIFT

    cmp r8, 0
    jl .blocked
    cmp r8, MAP_WIDTH
    jge .blocked
    cmp r9, 0
    jl .blocked
    cmp r9, MAP_HEIGHT
    jge .blocked

    mov rcx, r9
    imul rcx, MAP_WIDTH
    add rcx, r8

    lea rsi, [rel map]
    add rsi, rcx

    cmp byte [rsi], '#'
    je .blocked

    mov [rel player_x_fp], rax
    mov [rel player_y_fp], rbx

.blocked:
    ret

render_map:
    lea rsi, [rel map_label]
    mov rdx, map_label_len
    call print

    mov r14, [rel player_x_fp]
    sar r14, FP_SHIFT

    mov r15, [rel player_y_fp]
    sar r15, FP_SHIFT

    xor r12, r12

.y_loop:
    cmp r12, MAP_HEIGHT
    jge .done

    xor r13, r13

.x_loop:
    cmp r13, MAP_WIDTH
    jge .print_newline

    cmp r13, r14
    jne .print_map_tile
    cmp r12, r15
    jne .print_map_tile

    ; direction char = angle / 4
    mov rax, [rel player_angle]
    shr rax, 2
    lea rsi, [rel dir_chars]
    add rsi, rax

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

    xor r12, r12

.y_loop:
    cmp r12, VIEW_HEIGHT
    jge .done

    xor r13, r13

.x_loop:
    cmp r13, VIEW_WIDTH
    jge .print_newline

    mov rdi, r13
    call calculate_wall_for_column

    cmp r12, rax
    jb .print_empty

    cmp r12, rbx
    jae .print_empty

    ; Choose wall character based on ray distance.
    ; calculate_wall_for_column returned distance in rdx.
    mov rdi, rdx
    call get_wall_shade

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

; rdi = screen column
; returns rax = wall_start_y, rbx = wall_end_y
; rdi = screen column
; returns:
; rax = wall_start_y
; rbx = wall_end_y
; rdx = ray distance
calculate_wall_for_column:
    call cast_ray_for_column

    mov r8, rax        ; save original distance for shading
    mov rbx, rax

    cmp rbx, 1
    jge .distance_ok

    mov rbx, 1

.distance_ok:
    ; wall height = (VIEW_HEIGHT * 8) / distance
    mov rax, VIEW_HEIGHT * 8
    xor rdx, rdx
    div rbx

    cmp rax, VIEW_HEIGHT
    jle .not_too_big

    mov rax, VIEW_HEIGHT

.not_too_big:
    cmp rax, 1
    jge .height_ok

    mov rax, 1

.height_ok:
    mov rcx, VIEW_HEIGHT
    sub rcx, rax
    shr rcx, 1

    mov rbx, rcx
    add rbx, rax

    mov rax, rcx       ; wall_start_y
    mov rdx, r8        ; return distance for shading
    ret
cast_ray_for_column:
    ; angle_offset = (column - VIEW_CENTER) / ANGLE_COLUMN_SCALE
    mov rax, rdi
    sub rax, VIEW_CENTER
    cqo

    mov rbx, ANGLE_COLUMN_SCALE
    idiv rbx

    add rax, [rel player_angle]
    call normalize_angle

    mov rcx, rax
    call get_direction_vector

    ; ray step = direction / 4
    sar r10, 2
    sar r11, 2

    mov r8, [rel player_x_fp]
    mov r9, [rel player_y_fp]
    xor rcx, rcx

.ray_loop:
    cmp rcx, MAX_RAY_STEPS
    jge .hit_wall

    add r8, r10
    add r9, r11
    inc rcx

    mov rax, r8
    sar rax, FP_SHIFT

    mov rbx, r9
    sar rbx, FP_SHIFT

    cmp rax, 0
    jl .hit_wall
    cmp rax, MAP_WIDTH
    jge .hit_wall
    cmp rbx, 0
    jl .hit_wall
    cmp rbx, MAP_HEIGHT
    jge .hit_wall

    mov rdx, rbx
    imul rdx, MAP_WIDTH
    add rdx, rax

    lea rsi, [rel map]
    add rsi, rdx

    cmp byte [rsi], '#'
    je .hit_wall

    jmp .ray_loop

.hit_wall:
    mov rax, rcx
    ret

; rax = any angle
; returns rax wrapped to 0..15
normalize_angle:
.low_check:
    cmp rax, 0
    jge .high_check

    add rax, 16
    jmp .low_check

.high_check:
    cmp rax, 16
    jl .done

    sub rax, 16
    jmp .high_check

.done:
    ret

; ----------------------------------------
; get_wall_shade
; rdi = ray distance
; returns:
; rsi = address of shade character
; ----------------------------------------
get_wall_shade:
    cmp rdi, 8
    jle .very_close

    cmp rdi, 16
    jle .close

    cmp rdi, 32
    jle .mid

    cmp rdi, 48
    jle .far

    lea rsi, [rel shade_very_far]
    ret

.very_close:
    lea rsi, [rel shade_very_close]
    ret

.close:
    lea rsi, [rel shade_close]
    ret

.mid:
    lea rsi, [rel shade_mid]
    ret

.far:
    lea rsi, [rel shade_far]
    ret

exit_program:
    mov rax, 60
    mov rdi, 0
    syscall