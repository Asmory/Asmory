.intel_syntax noprefix
.global _start
.extern simd_dot_f32

.equ SYS_write, 1
.equ SYS_clock_gettime, 228
.equ SYS_exit, 60
.equ CLOCK_MONOTONIC_RAW, 4

.equ N, 4096
.equ ITERS, 20000
.equ WARMUP, 256

.section .bss
.align 64
a_buf:      .skip N*4
.align 64
b_buf:      .skip N*4
.align 16
ts0:        .skip 16
ts1:        .skip 16
outbuf:     .skip 64
scalar_ns:  .quad 0
simd_ns:    .quad 0

.section .rodata
k_schema:       .asciz "schema=asmory-bench-v1\n"
k_n:            .asciz "n="
k_iters:        .asciz "iterations="
k_warmup:       .asciz "warmup="
k_correct:      .asciz "correctness=pass\n"
k_timer:        .asciz "timer=clock_monotonic_raw\n"
k_scalar_ns:    .asciz "scalar_total_ns="
k_simd_ns:      .asciz "simd_total_ns="
fail_msg:       .asciz "correctness=fail\n"

.section .text

_start:
    # Deterministic workload:
    #   a[i] = 1.0f
    #   b[i] = 0.5f
    # Expected dot product for N=4096: 2048.0f.
    lea r14, [rip + a_buf]
    lea r15, [rip + b_buf]
    xor rcx, rcx
.init:
    cmp rcx, N
    jae .correctness
    mov dword ptr [r14 + rcx*4], 0x3f800000
    mov dword ptr [r15 + rcx*4], 0x3f000000
    inc rcx
    jmp .init

.correctness:
    lea rdi, [rip + a_buf]
    lea rsi, [rip + b_buf]
    mov edx, N
    call simd_dot_f32

    movd eax, xmm0
    cmp eax, 0x45000000
    jne .fail

    # Warm both implementations.
    mov r12d, WARMUP
.warm_scalar:
    lea rdi, [rip + a_buf]
    lea rsi, [rip + b_buf]
    mov edx, N
    call scalar_dot_f32
    dec r12d
    jnz .warm_scalar

    mov r12d, WARMUP
.warm_simd:
    lea rdi, [rip + a_buf]
    lea rsi, [rip + b_buf]
    mov edx, N
    call simd_dot_f32
    dec r12d
    jnz .warm_simd

    # Scalar reference measurement.
    lea rsi, [rip + ts0]
    call now

    mov r12d, ITERS
.scalar_loop:
    lea rdi, [rip + a_buf]
    lea rsi, [rip + b_buf]
    mov edx, N
    call scalar_dot_f32
    dec r12d
    jnz .scalar_loop

    lea rsi, [rip + ts1]
    call now
    call elapsed_ns
    mov [rip + scalar_ns], rax

    # AVX2/FMA measurement.
    lea rsi, [rip + ts0]
    call now

    mov r12d, ITERS
.simd_loop:
    lea rdi, [rip + a_buf]
    lea rsi, [rip + b_buf]
    mov edx, N
    call simd_dot_f32
    dec r12d
    jnz .simd_loop

    lea rsi, [rip + ts1]
    call now
    call elapsed_ns
    mov [rip + simd_ns], rax

    lea rdi, [rip + k_schema]
    call print_cstr

    lea rdi, [rip + k_n]
    mov rsi, N
    call print_kv_u64

    lea rdi, [rip + k_iters]
    mov rsi, ITERS
    call print_kv_u64

    lea rdi, [rip + k_warmup]
    mov rsi, WARMUP
    call print_kv_u64

    lea rdi, [rip + k_correct]
    call print_cstr

    lea rdi, [rip + k_timer]
    call print_cstr

    lea rdi, [rip + k_scalar_ns]
    mov rsi, [rip + scalar_ns]
    call print_kv_u64

    lea rdi, [rip + k_simd_ns]
    mov rsi, [rip + simd_ns]
    call print_kv_u64

    xor edi, edi
    jmp exit_process

.fail:
    lea rdi, [rip + fail_msg]
    call print_cstr
    mov edi, 4
    jmp exit_process


# float scalar_dot_f32(const float *a, const float *b, size_t n)
# Stable in-package scalar reference, intentionally simple.
scalar_dot_f32:
    pxor xmm0, xmm0
    xor rcx, rcx
.scalar_dot_loop:
    cmp rcx, rdx
    jae .scalar_dot_done
    movss xmm1, dword ptr [rdi + rcx*4]
    mulss xmm1, dword ptr [rsi + rcx*4]
    addss xmm0, xmm1
    inc rcx
    jmp .scalar_dot_loop
.scalar_dot_done:
    ret


# rsi = struct timespec*
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


# Return ts1 - ts0 in nanoseconds.
elapsed_ns:
    mov rax, [rip + ts1]
    sub rax, [rip + ts0]
    imul rax, 1000000000
    mov rcx, [rip + ts1 + 8]
    sub rcx, [rip + ts0 + 8]
    add rax, rcx
    ret


# rdi = zero-terminated key, rsi = integer
print_kv_u64:
    push rsi
    call print_cstr
    pop rdi
    call print_u64_nl
    ret


# rdi = integer
print_u64_nl:
    lea rsi, [rip + outbuf + 63]
    mov byte ptr [rsi], 10
    mov rcx, 1
    mov rax, rdi

    test rax, rax
    jnz .u64_loop

    dec rsi
    mov byte ptr [rsi], '0'
    inc rcx
    jmp .u64_write

.u64_loop:
    xor edx, edx
    mov r8, 10
    div r8
    add dl, '0'
    dec rsi
    mov [rsi], dl
    inc rcx
    test rax, rax
    jnz .u64_loop

.u64_write:
    mov eax, SYS_write
    mov edi, 1
    mov rdx, rcx
    syscall
    ret


# rdi = zero-terminated string
print_cstr:
    mov rsi, rdi
    xor edx, edx
.cstr_len:
    cmp byte ptr [rsi + rdx], 0
    je .cstr_write
    inc rdx
    jmp .cstr_len
.cstr_write:
    mov eax, SYS_write
    mov edi, 1
    syscall
    ret


exit_process:
    mov eax, SYS_exit
    syscall
