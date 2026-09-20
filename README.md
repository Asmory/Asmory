# Asmory

> **A package registry and ecosystem for Assembly.**

Publish, discover, resolve and reuse machine-level code with explicit ISA,
ABI and target constraints.

[![CI](https://github.com/Asmory/Asmory/actions/workflows/ci.yml/badge.svg)](https://github.com/Asmory/Asmory/actions/workflows/ci.yml)
[![Pages](https://github.com/Asmory/Asmory/actions/workflows/pages.yml/badge.svg)](https://github.com/Asmory/Asmory/actions/workflows/pages.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Why Asmory?

Modern AI-assisted development makes Assembly practical at a scale that was
previously difficult to maintain manually.

Asmory explores a simple idea:

**What if Assembly had a package ecosystem comparable to crates.io or PyPI?**

Assembly has one important difference: compatibility cannot stop at `x86_64`
or `aarch64`.

For Asmory, a package target includes:

```text
architecture
+ ISA baseline
+ ISA version
+ ISA extensions
+ ABI
+ calling convention
+ object format
+ operating system
+ assembler requirements
+ optional microarchitecture tuning
```

ISA information is therefore not metadata decoration. It participates in
dependency resolution.

## Example manifest

```toml
[package]
name = "simd-dot"
version = "0.1.0"
license = "MIT"

[target]
arch = "x86_64"
os = "linux"
object = "elf64"
abi = "sysv64"

[target.isa]
baseline = "x86-64-v3"
required = ["avx2", "fma"]

[toolchain]
assembler = "gas"
min_version = "2.40"
```

A package may expose several machine variants:

```text
simd-dot 0.1.0
├── x86_64 / SSE2
├── x86_64 / AVX2 + FMA
├── x86_64 / AVX-512
├── aarch64 / NEON
├── aarch64 / SVE2
└── riscv64 / RVV
```

The version describes the software release.

The **Variant** describes the machine implementation.

## Project goals

- Assembly-native package registry
- machine-readable ISA and ABI contracts
- strict target compatibility resolution
- multiple optimized variants per package version
- linker-assisted dead-code elimination
- reproducible package manifests
- package search and publishing
- host ISA detection
- future performance-aware variant selection
- AI-friendly package metadata
- minimal runtime abstraction

## Repository layout

```text
registry/   Assembly HTTP registry
cli/        Asmory command-line client
spec/       package / ISA / ABI specifications
examples/   example Assembly packages
docs/       architecture and roadmap
site/       GitHub Pages project site
tests/      integration tests
scripts/    development tools
```

## Planned CLI

```bash
asmory init
asmory target
asmory search gemm
asmory info simd-dot
asmory add simd-dot
asmory build
asmory publish
```

## Design principles

### ISA is part of compatibility

`x86_64` is not enough information.

```text
x86_64 + SSE2
x86_64 + AVX2 + FMA
x86_64 + AVX-512
x86_64 + AMX
```

are distinct execution requirements.

### Runnable is not the same as optimal

Asmory keeps these concepts separate:

```text
correctness compatibility
        !=
performance preference
```

### Let the linker remove unused code

Assembly packages should favor independently collectable sections:

```asm
.section .text.foo,"ax",@progbits
.section .text.bar,"ax",@progbits
```

allowing linkers to use mechanisms such as:

```bash
ld --gc-sections
```

### Machine code + machine-readable contract

Asmory should preserve low-level control without sacrificing reusable package
boundaries.

## Contributing

Asmory is at the stage where architectural discussion is especially valuable.

Useful contribution areas include:

- x86 ISA modeling
- AArch64 feature/version modeling
- RISC-V extension modeling
- ABI modeling
- ELF / COFF / Mach-O integration
- assembler compatibility
- package resolver design
- linker garbage collection
- CPU feature detection
- SIMD kernels
- benchmarking
- registry protocol design

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Status

Asmory is experimental and under active development.

The current registry server is intentionally implemented in Linux x86-64
Assembly using direct syscalls.

## License

MIT.
