.intel_syntax noprefix
.global _start
.extern asmory_contract_target

.equ SYS_write, 1
.equ SYS_exit, 60

.section .rodata
msg_contract:
    .asciz "contract=asmory/simd-dot-core@1.0.0\n"
msg_pass:
    .asciz "conformance=pass\n"
msg_cases:
    .asciz "cases=9\n"
msg_fail:
    .asciz "conformance=fail\n"

.align 32
a_data:
    .rept 80
    .long 0x3f800000
    .endr

.align 32
b_data:
    .rept 80
    .long 0x3f000000
    .endr

.section .text
_start:
    lea r14, [rip + a_data]
    lea r15, [rip + b_data]

    xor edx, edx
    mov r12d, 0x00000000
    call check_case

    mov edx, 1
    mov r12d, 0x3f000000
    call check_case

    mov edx, 7
    mov r12d, 0x40600000
    call check_case

    mov edx, 8
    mov r12d, 0x40800000
    call check_case

    mov edx, 9
    mov r12d, 0x40900000
    call check_case

    mov edx, 31
    mov r12d, 0x41780000
    call check_case

    mov edx, 32
    mov r12d, 0x41800000
    call check_case

    mov edx, 33
    mov r12d, 0x41840000
    call check_case

    lea r14, [rip + a_data + 4]
    lea r15, [rip + b_data + 4]
    mov edx, 33
    mov r12d, 0x41840000
    call check_case

    lea rdi, [rip + msg_contract]
    call print_cstr
    lea rdi, [rip + msg_pass]
    call print_cstr
    lea rdi, [rip + msg_cases]
    call print_cstr

    xor edi, edi
    jmp exit_process

check_case:
    push rdx
    mov rdi, r14
    mov rsi, r15
    call asmory_contract_target
    pop rdx

    movd eax, xmm0
    cmp eax, r12d
    jne fail
    ret

fail:
    lea rdi, [rip + msg_fail]
    call print_cstr
    mov edi, 10
    jmp exit_process

print_cstr:
    mov rsi, rdi
    xor edx, edx
.len:
    cmp byte ptr [rsi + rdx], 0
    je .write
    inc rdx
    jmp .len
.write:
    mov eax, SYS_write
    mov edi, 1
    syscall
    ret

exit_process:
    mov eax, SYS_exit
    syscall
