global _start

%define MAP_WIDTH 16
%define MAP_HEIGHT 8

%define VIEW_WIDTH 63
%define VIEW_HEIGHT 24
%define VIEW_CENTER 31
%define ANGLE_COLUMN_SCALE 8
%define FP_SHIFT 10
%define MAX_RAY_STEPS 128

%define SYS_IOCTL 16

%define TCGETS 0x5401
%define TCSETS 0x5402

%define TERMIOS_SIZE 64
%define TERMIOS_LFLAG 12
%define TERMIOS_CC 17
%define VTIME_OFFSET 5
%define VMIN_OFFSET 6

%define VIEW_STRIDE (VIEW_WIDTH + 1)
%define VIEW_BUFFER_SIZE (VIEW_STRIDE * VIEW_HEIGHT)

; Clears ICANON and ECHO flags.
; ICANON = 0x00000002
; ECHO   = 0x00000008
; ~(ICANON | ECHO) = 0xfffffff5
%define RAW_LFLAG_MASK 0xfffffff5

; Angle system:
; 0  = east
; 4  = south
; 8  = west
; 12 = north
; 16 total angle steps

section .data
    clear_screen db 27, "[2J", 27, "[H"
    clear_screen_len equ $ - clear_screen

    title db "asm-raycaster", 10
        db "W/S = move | A/D = rotate | E = interact | M = minimap | X = quit", 10, 10
    title_len equ $ - title

    map_label db "2D map:", 10
    map_label_len equ $ - map_label

    view_label db 10, "3D raycast view:", 10
    view_label_len equ $ - view_label

    hud_label db 10, "HUD | x="
    hud_label_len equ $ - hud_label

    hud_y_label db " y="
    hud_y_label_len equ $ - hud_y_label

    hud_angle_label db " angle="
    hud_angle_label_len equ $ - hud_angle_label

    hud_minimap_label db " minimap="
    hud_minimap_label_len equ $ - hud_minimap_label

    hud_on db "on"
    hud_on_len equ $ - hud_on

    hud_off db "off"
    hud_off_len equ $ - hud_off

    newline db 10

    dir_chars db ">v<^"
    wall_char db "#"
    shade_very_close db "@"
    shade_close db "#"
    shade_mid db "*"
    shade_far db "+"
    shade_very_far db "-"
    empty_char db "."
    side_very_close db "%"
    side_close db "="
    side_mid db ":"
    side_far db ","
    side_very_far db "'"
    door_very_close db "H"
    door_close db "D"
    door_mid db "|"
    door_far db ";"
    door_very_far db "."

    ceiling_char db " "
    floor_char db "."

    ; Fixed-point position.
    ; 1024 = 1 tile.
    ; Start centered at map tile (4,5).
    player_x_fp dq 2560     ; x = 2.5 tiles
    player_y_fp dq 6656     ; y = 6.5 tiles
    player_angle dq 0       ; facing east

    show_minimap db 0
    ray_side db 0
    ray_tile db 0

    map:
        db "################"
        db "#      #       #"
        db "# ####D# ##### #"
        db "# #    #     # #"
        db "# # ####### #  #"
        db "# #         #  #"
        db "#     ###      #"
        db "################"

    ; 16 direction vectors, scaled by 1024.
    dir_dx dd 1024, 946, 724, 392, 0, -392, -724, -946
           dd -1024, -946, -724, -392, 0, 392, 724, 946

    dir_dy dd 0, 392, 724, 946, 1024, 946, 724, 392
           dd 0, -392, -724, -946, -1024, -946, -724, -392

section .bss
    input_buf resb 8
    number_buf resb 32

    old_termios resb TERMIOS_SIZE
    raw_termios resb TERMIOS_SIZE
    
    view_buffer resb VIEW_BUFFER_SIZE

    prev_tile_x resq 1
    prev_tile_y resq 1

section .text

_start:
    call enable_raw_mode
.game_loop:
    call clear_terminal
    call print_title
    call render_3d_view
    call print_status
    call render_minimap_if_enabled
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

; ----------------------------------------
; print_status
; Prints a simple HUD with player position,
; angle, and minimap state.
; ----------------------------------------
print_status:
    ; HUD | x=
    lea rsi, [rel hud_label]
    mov rdx, hud_label_len
    call print

    ; print player x tile
    mov rax, [rel player_x_fp]
    sar rax, FP_SHIFT
    call print_uint

    ; y=
    lea rsi, [rel hud_y_label]
    mov rdx, hud_y_label_len
    call print

    ; print player y tile
    mov rax, [rel player_y_fp]
    sar rax, FP_SHIFT
    call print_uint

    ; angle=
    lea rsi, [rel hud_angle_label]
    mov rdx, hud_angle_label_len
    call print

    ; print player angle
    mov rax, [rel player_angle]
    call print_uint

    ; minimap=
    lea rsi, [rel hud_minimap_label]
    mov rdx, hud_minimap_label_len
    call print

    ; print on/off
    mov al, [rel show_minimap]
    cmp al, 1
    je .minimap_on

.minimap_off:
    lea rsi, [rel hud_off]
    mov rdx, hud_off_len
    call print
    jmp .done

.minimap_on:
    lea rsi, [rel hud_on]
    mov rdx, hud_on_len
    call print

.done:
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
    ; Clear input buffer first.
    ; If read() times out, input_buf stays 0.
    mov byte [rel input_buf], 0

    mov rax, 0              ; syscall: read
    mov rdi, 0              ; stdin
    lea rsi, [rel input_buf]
    mov rdx, 1              ; read one byte
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

    cmp al, 'm'
    je toggle_minimap
    cmp al, 'M'
    je toggle_minimap

    cmp al, 'e'
    je interact_door
    cmp al, 'E'
    je interact_door

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

    cmp byte [rsi], 'D'
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

; ----------------------------------------
; render_3d_view
; Builds the whole 3D view in memory first,
; then prints it with one write syscall.
; ----------------------------------------
render_3d_view:
    lea r14, [rel view_buffer]      ; current buffer position
    xor r12, r12                    ; y = 0

.y_loop:
    cmp r12, VIEW_HEIGHT
    jge .print_buffer

    xor r13, r13                    ; x = 0

.x_loop:
    cmp r13, VIEW_WIDTH
    jge .end_line

    ; Calculate wall slice for this screen column.
    mov rdi, r13
    call calculate_wall_for_column
    ; returns:
    ; rax = wall_start_y
    ; rbx = wall_end_y
    ; rdx = ray distance

    ; Is current y inside the wall slice?
    cmp r12, rax
    jb .print_empty

    cmp r12, rbx
    jae .print_empty

    ; Choose wall shade based on distance.
    mov rdi, rdx
    call get_wall_shade
    mov al, [rsi]
    mov [r14], al
    jmp .next_col

.print_empty:
    ; Ceiling on upper half, floor on lower half.
    cmp r12, VIEW_HEIGHT / 2
    jb .print_ceiling

    mov al, [rel floor_char]
    mov [r14], al
    jmp .next_col

.print_ceiling:
    mov al, [rel ceiling_char]
    mov [r14], al

.next_col:
    inc r14
    inc r13
    jmp .x_loop

.end_line:
    mov byte [r14], 10              ; newline
    inc r14

    inc r12
    jmp .y_loop

.print_buffer:
    lea rsi, [rel view_buffer]
    mov rdx, VIEW_BUFFER_SIZE
    call print
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

    ; Store starting tile as previous tile.
    mov rax, r8
    sar rax, FP_SHIFT
    mov [rel prev_tile_x], rax

    mov rax, r9
    sar rax, FP_SHIFT
    mov [rel prev_tile_y], rax

.ray_loop:
    cmp rcx, MAX_RAY_STEPS
    jge .hit_normal_wall

    add r8, r10
    add r9, r11
    inc rcx

    mov rax, r8
    sar rax, FP_SHIFT

    mov rbx, r9
    sar rbx, FP_SHIFT
    ; Detect whether the ray crossed into a new tile horizontally or vertically.
    ; This gives us a simple side-wall shading approximation.
    mov rdx, [rel prev_tile_x]
    cmp rax, rdx
    jne .x_side_hit

    mov rdx, [rel prev_tile_y]
    cmp rbx, rdx
    jne .y_side_hit

    jmp .side_done

.x_side_hit:
    mov byte [rel ray_side], 0
    jmp .side_done

.y_side_hit:
    mov byte [rel ray_side], 1

.side_done:

    cmp rax, 0
    jl .hit_normal_wall
    cmp rax, MAP_WIDTH
    jge .hit_normal_wall
    cmp rbx, 0
    jl .hit_normal_wall
    cmp rbx, MAP_HEIGHT
    jge .hit_normal_wall

    mov rdx, rbx
    imul rdx, MAP_WIDTH
    add rdx, rax

    lea rsi, [rel map]
    add rsi, rdx

    cmp byte [rsi], '#'
    je .hit_normal_wall

    cmp byte [rsi], 'D'
    je .hit_door

    ; Current tile becomes previous tile for the next ray step.
    mov [rel prev_tile_x], rax
    mov [rel prev_tile_y], rbx

    jmp .ray_loop

.hit_normal_wall:
    mov byte [rel ray_tile], '#'
    mov rax, rcx
    ret

.hit_door:
    mov byte [rel ray_tile], 'D'
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
    mov al, [rel ray_tile]
    cmp al, 'D'
    je .door_wall
    mov al, [rel ray_side]
    cmp al, 1
    je .side_wall

.front_wall:
    cmp rdi, 8
    jle .front_very_close

    cmp rdi, 16
    jle .front_close

    cmp rdi, 32
    jle .front_mid

    cmp rdi, 48
    jle .front_far

    lea rsi, [rel shade_very_far]
    ret

.front_very_close:
    lea rsi, [rel shade_very_close]
    ret

.front_close:
    lea rsi, [rel shade_close]
    ret

.front_mid:
    lea rsi, [rel shade_mid]
    ret

.front_far:
    lea rsi, [rel shade_far]
    ret


.side_wall:
    cmp rdi, 8
    jle .side_very_close

    cmp rdi, 16
    jle .side_close

    cmp rdi, 32
    jle .side_mid

    cmp rdi, 48
    jle .side_far

    lea rsi, [rel side_very_far]
    ret

.side_very_close:
    lea rsi, [rel side_very_close]
    ret

.side_close:
    lea rsi, [rel side_close]
    ret

.side_mid:
    lea rsi, [rel side_mid]
    ret

.side_far:
    lea rsi, [rel side_far]
    ret
.door_wall:
    cmp rdi, 8
    jle .door_very_close

    cmp rdi, 16
    jle .door_close

    cmp rdi, 32
    jle .door_mid

    cmp rdi, 48
    jle .door_far

    lea rsi, [rel door_very_far]
    ret

.door_very_close:
    lea rsi, [rel door_very_close]
    ret

.door_close:
    lea rsi, [rel door_close]
    ret

.door_mid:
    lea rsi, [rel door_mid]
    ret

.door_far:
    lea rsi, [rel door_far]
    ret

; ----------------------------------------
; enable_raw_mode
; Disables canonical input and echo.
; This allows reading one key at a time
; without pressing ENTER.
; ----------------------------------------
enable_raw_mode:
    ; ioctl(stdin, TCGETS, old_termios)
    mov rax, SYS_IOCTL
    mov rdi, 0
    mov rsi, TCGETS
    lea rdx, [rel old_termios]
    syscall

    ; copy old_termios into raw_termios
    lea rsi, [rel old_termios]
    lea rdi, [rel raw_termios]
    mov rcx, TERMIOS_SIZE
    rep movsb

    ; raw_termios.c_lflag &= ~(ICANON | ECHO)
    and dword [rel raw_termios + TERMIOS_LFLAG], RAW_LFLAG_MASK

    ; raw_termios.c_cc[VMIN] = 0
    ; read() can return even if no key was pressed.
    mov byte [rel raw_termios + TERMIOS_CC + VMIN_OFFSET], 0

    ; raw_termios.c_cc[VTIME] = 1
    ; wait up to 0.1 seconds for input.
    mov byte [rel raw_termios + TERMIOS_CC + VTIME_OFFSET], 1

    ; ioctl(stdin, TCSETS, raw_termios)
    mov rax, SYS_IOCTL
    mov rdi, 0
    mov rsi, TCSETS
    lea rdx, [rel raw_termios]
    syscall

    ret

; ----------------------------------------
; restore_terminal
; Restores original terminal settings.
; ----------------------------------------
restore_terminal:
    mov rax, SYS_IOCTL
    mov rdi, 0
    mov rsi, TCSETS
    lea rdx, [rel old_termios]
    syscall
    ret

; ----------------------------------------
; toggle_minimap
; show_minimap = !show_minimap
; ----------------------------------------
toggle_minimap:
    mov al, [rel show_minimap]

    cmp al, 0
    je .turn_on

    mov byte [rel show_minimap], 0
    ret

.turn_on:
    mov byte [rel show_minimap], 1
    ret


; ----------------------------------------
; render_minimap_if_enabled
; Calls render_map only when show_minimap = 1.
; ----------------------------------------
render_minimap_if_enabled:
    mov al, [rel show_minimap]

    cmp al, 1
    jne .skip

    lea rsi, [rel newline]
    mov rdx, 1
    call print

    call render_map

.skip:
    ret

; ----------------------------------------
; interact_door
; Opens a door directly in front of player.
; D becomes empty space.
; ----------------------------------------
interact_door:
    ; Get player direction vector.
    mov rcx, [rel player_angle]
    call get_direction_vector
    ; returns r10 = dx, r11 = dy

    ; target position = player position + one tile forward
    mov rax, [rel player_x_fp]
    add rax, r10
    sar rax, FP_SHIFT        ; target tile x

    mov rbx, [rel player_y_fp]
    add rbx, r11
    sar rbx, FP_SHIFT        ; target tile y

    ; bounds check
    cmp rax, 0
    jl .done
    cmp rax, MAP_WIDTH
    jge .done

    cmp rbx, 0
    jl .done
    cmp rbx, MAP_HEIGHT
    jge .done

    ; index = y * MAP_WIDTH + x
    mov rcx, rbx
    imul rcx, MAP_WIDTH
    add rcx, rax

    lea rsi, [rel map]
    add rsi, rcx

    ; If tile is D, open it.
    cmp byte [rsi], 'D'
    jne .done

    mov byte [rsi], ' '

.done:
    ret

exit_program:
    call restore_terminal

    mov rax, 60
    mov rdi, 0
    syscall