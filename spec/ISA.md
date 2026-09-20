# ISA Model — Draft 0

ISA information is a first-class resolver input in Asmory.

## Why architecture names are insufficient

`x86_64` does not tell the resolver whether AVX2, FMA, AVX-512, AVX-VNNI, or AMX instructions are legal. Likewise, `aarch64` alone does not encode architecture revision, SVE/SVE2, CRC, crypto, BF16, or other extensions. RISC-V is explicitly extension-composed and also requires version-aware handling.

## Required concepts

Asmory's ISA model must eventually represent:

- architecture family;
- architecture/ISA baseline or version;
- required extensions;
- optional extensions;
- extension versions where the ISA defines them;
- mutually exclusive or dependent features when relevant;
- assembler support constraints;
- OS/runtime enablement requirements where hardware support alone is insufficient.

## Resolver rule

A variant is **compatible** only if every hard requirement is satisfied. Optional tuning is considered only after that filter.

Pseudo-rule:

```text
compatible(variant, target) =
    arch_matches
    && abi_matches
    && object_matches
    && os_matches
    && isa_baseline_satisfied
    && all_required_features_satisfied
    && toolchain_can_encode_required_instructions
```

## Future expression syntax

Simple `required = [...]` lists are sufficient for the first prototype. A later specification may need boolean constraints such as:

```text
avx512f && (avx512bw || avx512vl)
```

That syntax should not be standardized until real packages demonstrate the need.
