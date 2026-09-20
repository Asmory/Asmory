.intel_syntax noprefix
.global _start
.extern simd_dot_f32
.extern simd_dot_f32_4acc

.equ SYS_write, 1
.equ SYS_clock_gettime, 228
.equ SYS_exit, 60
.equ CLOCK_MONOTONIC_RAW, 4
.equ N, 4096
.equ ITERS, 20000
.equ WARMUP, 256

.section .bss
.align 64
a_buf:       .skip N*4
.align 64
b_buf:       .skip N*4
.align 16
ts0:         .skip 16
ts1:         .skip 16
outbuf:      .skip 64
generic_ns:  .quad 0
acc4_ns:     .quad 0
order_ba:    .byte 0

.section .rodata
arg_ba:      .asciz "ba"
k_schema:    .asciz "schema=asmory-variant-comparison-v2\n"
k_n:         .asciz "n="
k_iters:     .asciz "iterations="
k_warmup:    .asciz "warmup="
k_correct:   .asciz "correctness=pass\n"
k_timer:     .asciz "timer=clock_monotonic_raw\n"
k_order_ab:  .asciz "order=ab\n"
k_order_ba:  .asciz "order=ba\n"
k_generic:   .asciz "generic_total_ns="
k_acc4:      .asciz "acc4_total_ns="
fail_msg:    .asciz "correctness=fail\n"

.section .text
_start:
    # Optional argv[1] == "ba" reverses measured order.
    mov rax, [rsp]
    cmp rax, 2
    jb .args_done
    mov rdi, [rsp + 16]
    lea rsi, [rip + arg_ba]
    call streq
    test eax, eax
    jz .args_done
    mov byte ptr [rip + order_ba], 1

.args_done:
    lea r14, [rip + a_buf]
    lea r15, [rip + b_buf]
    xor rcx, rcx
.init:
    cmp rcx, N
    jae .check
    mov dword ptr [r14 + rcx*4], 0x3f800000
    mov dword ptr [r15 + rcx*4], 0x3f000000
    inc rcx
    jmp .init

.check:
    lea rdi, [rip + a_buf]
    lea rsi, [rip + b_buf]
    mov edx, N
    call simd_dot_f32
    movd eax, xmm0
    cmp eax, 0x45000000
    jne .fail

    lea rdi, [rip + a_buf]
    lea rsi, [rip + b_buf]
    mov edx, N
    call simd_dot_f32_4acc
    movd eax, xmm0
    cmp eax, 0x45000000
    jne .fail

    # Warm both implementations before measurement.
    mov r12d, WARMUP
.warm_a:
    lea rdi, [rip + a_buf]
    lea rsi, [rip + b_buf]
    mov edx, N
    call simd_dot_f32
    dec r12d
    jnz .warm_a

    mov r12d, WARMUP
.warm_b:
    lea rdi, [rip + a_buf]
    lea rsi, [rip + b_buf]
    mov edx, N
    call simd_dot_f32_4acc
    dec r12d
    jnz .warm_b

    cmp byte ptr [rip + order_ba], 1
    je .measure_ba

.measure_ab:
    call bench_generic
    mov [rip + generic_ns], rax
    call bench_acc4
    mov [rip + acc4_ns], rax
    jmp .report

.measure_ba:
    call bench_acc4
    mov [rip + acc4_ns], rax
    call bench_generic
    mov [rip + generic_ns], rax

.report:
    lea rdi, [rip + k_schema]
    call print_cstr
    lea rdi, [rip + k_n]
    mov rsi, N
    call print_kv
    lea rdi, [rip + k_iters]
    mov rsi, ITERS
    call print_kv
    lea rdi, [rip + k_warmup]
    mov rsi, WARMUP
    call print_kv
    lea rdi, [rip + k_correct]
    call print_cstr
    lea rdi, [rip + k_timer]
    call print_cstr

    cmp byte ptr [rip + order_ba], 1
    je .print_ba
    lea rdi, [rip + k_order_ab]
    call print_cstr
    jmp .print_values
.print_ba:
    lea rdi, [rip + k_order_ba]
    call print_cstr

.print_values:
    lea rdi, [rip + k_generic]
    mov rsi, [rip + generic_ns]
    call print_kv
    lea rdi, [rip + k_acc4]
    mov rsi, [rip + acc4_ns]
    call print_kv

    xor edi, edi
    jmp exit_process

.fail:
    lea rdi, [rip + fail_msg]
    call print_cstr
    mov edi, 4
    jmp exit_process

bench_generic:
    lea rsi, [rip + ts0]
    call now
    mov r12d, ITERS
.bg_loop:
    lea rdi, [rip + a_buf]
    lea rsi, [rip + b_buf]
    mov edx, N
    call simd_dot_f32
    dec r12d
    jnz .bg_loop
    lea rsi, [rip + ts1]
    call now
    call elapsed_ns
    ret

bench_acc4:
    lea rsi, [rip + ts0]
    call now
    mov r12d, ITERS
.ba_loop:
    lea rdi, [rip + a_buf]
    lea rsi, [rip + b_buf]
    mov edx, N
    call simd_dot_f32_4acc
    dec r12d
    jnz .ba_loop
    lea rsi, [rip + ts1]
    call now
    call elapsed_ns
    ret

now:
    mov eax, SYS_clock_gettime
    mov edi, CLOCK_MONOTONIC_RAW
    syscall
    test rax, rax
    js .clock_fail
    ret
.clock_fail:
    mov edi, 5
    jmp exit_process

elapsed_ns:
    mov rax, [rip + ts1]
    sub rax, [rip + ts0]
    imul rax, 1000000000
    mov rcx, [rip + ts1 + 8]
    sub rcx, [rip + ts0 + 8]
    add rax, rcx
    ret

streq:
    xor eax, eax
.st_loop:
    mov dl, byte ptr [rdi]
    mov cl, byte ptr [rsi]
    cmp dl, cl
    jne .st_no
    test dl, dl
    je .st_yes
    inc rdi
    inc rsi
    jmp .st_loop
.st_yes:
    mov eax, 1
.st_no:
    ret

print_kv:
    push rsi
    call print_cstr
    pop rdi
    call print_u64
    ret

print_u64:
    lea rsi, [rip + outbuf + 63]
    mov byte ptr [rsi], 10
    mov rcx, 1
    mov rax, rdi
    test rax, rax
    jnz .digits
    dec rsi
    mov byte ptr [rsi], '0'
    inc rcx
    jmp .write_num
.digits:
    xor edx, edx
    mov r8, 10
    div r8
    add dl, '0'
    dec rsi
    mov [rsi], dl
    inc rcx
    test rax, rax
    jnz .digits
.write_num:
    mov eax, SYS_write
    mov edi, 1
    mov rdx, rcx
    syscall
    ret

print_cstr:
    mov rsi, rdi
    xor edx, edx
.strlen:
    cmp byte ptr [rsi + rdx], 0
    je .write_str
    inc rdx
    jmp .strlen
.write_str:
    mov eax, SYS_write
    mov edi, 1
    syscall
    ret

exit_process:
    mov eax, SYS_exit
    syscall
