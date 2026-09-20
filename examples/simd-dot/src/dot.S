.intel_syntax noprefix
.global simd_dot_f32
.type simd_dot_f32, @function
.section .text.simd_dot_f32,"ax",@progbits

# float simd_dot_f32(const float *a, const float *b, size_t n)
# rdi=a, rsi=b, rdx=n, xmm0=return
simd_dot_f32:
    vxorps ymm0, ymm0, ymm0
    xor rcx, rcx

.loop8:
    lea rax, [rcx + 8]
    cmp rax, rdx
    ja .reduce
    vmovups ymm1, YMMWORD PTR [rdi + rcx*4]
    vmovups ymm2, YMMWORD PTR [rsi + rcx*4]
    vfmadd231ps ymm0, ymm1, ymm2
    add rcx, 8
    jmp .loop8

.reduce:
    vextractf128 xmm1, ymm0, 1
    vaddps xmm0, xmm0, xmm1
    vhaddps xmm0, xmm0, xmm0
    vhaddps xmm0, xmm0, xmm0

.tail:
    cmp rcx, rdx
    jae .done
    vmovss xmm1, DWORD PTR [rdi + rcx*4]
    vmovss xmm2, DWORD PTR [rsi + rcx*4]
    vfmadd231ss xmm0, xmm1, xmm2
    inc rcx
    jmp .tail

.done:
    vzeroupper
    ret
.size simd_dot_f32, .-simd_dot_f32
