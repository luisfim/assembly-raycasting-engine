global _start

%define MAP_WIDTH 16
%define MAP_HEIGHT 8

section .data
    clear_screen db 27, "[2J", 27, "[H"
    clear_screen_len equ $ - clear_screen

    title db "asm-raycaster - step 2: dynamic player render", 10, 10
    title_len equ $ - title

    newline db 10
    player_char db "@"

    player_x dq 4
    player_y dq 5

    ; Map is now stored without newlines and without the player.
    map:
        db "################"
        db "#              #"
        db "#      ##      #"
        db "#      ##      #"
        db "#              #"
        db "#              #"
        db "#              #"
        db "################"

section .text

_start:
    ; Clear terminal
    mov rsi, clear_screen
    mov rdx, clear_screen_len
    call print

    ; Print title
    mov rsi, title
    mov rdx, title_len
    call print

    ; Render map with player position
    call render_map

    ; Exit
    mov rax, 60
    mov rdi, 0
    syscall

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
; render_map
; Draws map and places player dynamically
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

    ; Check if current position is player position
    cmp r13, [rel player_x]
    jne .print_map_tile

    cmp r12, [rel player_y]
    jne .print_map_tile

    ; Print player
    lea rsi, [rel player_char]
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