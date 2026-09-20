.intel_syntax noprefix
.global simd_dot_f32_4acc
.type simd_dot_f32_4acc, @function
.section .text.simd_dot_f32_4acc,"ax",@progbits

# float simd_dot_f32_4acc(const float *a, const float *b, size_t n)
# Four independent FMA accumulators, 32 floats per main-loop iteration.
simd_dot_f32_4acc:
    vxorps ymm0, ymm0, ymm0
    vxorps ymm3, ymm3, ymm3
    vxorps ymm4, ymm4, ymm4
    vxorps ymm5, ymm5, ymm5
    xor rcx, rcx

.loop32:
    lea rax, [rcx + 32]
    cmp rax, rdx
    ja .reduce

    vmovups ymm1, YMMWORD PTR [rdi + rcx*4]
    vmovups ymm2, YMMWORD PTR [rsi + rcx*4]
    vfmadd231ps ymm0, ymm1, ymm2

    vmovups ymm1, YMMWORD PTR [rdi + rcx*4 + 32]
    vmovups ymm2, YMMWORD PTR [rsi + rcx*4 + 32]
    vfmadd231ps ymm3, ymm1, ymm2

    vmovups ymm1, YMMWORD PTR [rdi + rcx*4 + 64]
    vmovups ymm2, YMMWORD PTR [rsi + rcx*4 + 64]
    vfmadd231ps ymm4, ymm1, ymm2

    vmovups ymm1, YMMWORD PTR [rdi + rcx*4 + 96]
    vmovups ymm2, YMMWORD PTR [rsi + rcx*4 + 96]
    vfmadd231ps ymm5, ymm1, ymm2

    add rcx, 32
    jmp .loop32

.reduce:
    vaddps ymm0, ymm0, ymm3
    vaddps ymm4, ymm4, ymm5
    vaddps ymm0, ymm0, ymm4

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

.size simd_dot_f32_4acc, .-simd_dot_f32_4acc
