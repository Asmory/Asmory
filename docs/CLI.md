# Asmory CLI architecture

## Principle

The resolver must never treat `x86_64`, `aarch64`, or `riscv64` as sufficient
compatibility descriptions.

The CLI first builds a host target record, then resolves package Variants
against that record.

```text
host machine
    |
    +-- architecture
    +-- OS / object format / ABI
    +-- ISA baseline
    +-- ISA extensions
    +-- OS extended-state support
    +-- assembler / linker capabilities
    |
    v
Asmory Target
    |
    v
Variant compatibility filtering
    |
    v
performance preference / tuning
```

## x86-64 host detection

The bootstrap CLI uses `CPUID` and `XGETBV` directly.

`CPUID` feature bits alone are not enough for AVX-family instructions. The OS
must also save and restore the relevant state. Therefore Asmory only reports
AVX as usable when XCR0 enables XMM/YMM state, and only reports AVX-512 as
usable when XCR0 also enables opmask and ZMM state.

The initial baseline classifier recognizes the x86-64-v1/v2/v3/v4 levels from
the corresponding CPU feature sets.

## Compatibility vs optimization

A compatible Variant is not automatically the fastest Variant.

Asmory keeps these stages separate:

1. correctness compatibility;
2. optional microarchitecture/performance preference;
3. future benchmark/profile-driven selection.
