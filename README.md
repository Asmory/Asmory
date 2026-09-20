# Asmory

> **Packages for the instruction level.**
>
> An Assembly package registry and ecosystem with explicit ISA, ABI and target
> constraints.

[![CI](https://github.com/Asmory/Asmory/actions/workflows/ci.yml/badge.svg)](https://github.com/Asmory/Asmory/actions/workflows/ci.yml)
[![Pages](https://github.com/Asmory/Asmory/actions/workflows/pages.yml/badge.svg)](https://github.com/Asmory/Asmory/actions/workflows/pages.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## The idea

What if Assembly had package-manager ergonomics comparable to crates.io or
PyPI without pretending machine differences do not exist?

For Asmory, compatibility includes:

```text
architecture
+ ISA baseline / version
+ ISA extensions
+ ABI / calling convention
+ object format
+ operating system
+ assembler/linker constraints
+ optional microarchitecture tuning
```

`x86_64` by itself is not a sufficient target description.

## Working today

The repository already contains two static Linux x86-64 ELF programs written
in Assembly:

- `asmory-registry` — syscall-only HTTP registry prototype;
- `asmory` — package-manager CLI bootstrap.

Build everything:

```bash
make clean && make -j"$(nproc)" && make check && make smoke && make cli-smoke
```

Inspect the current machine:

```bash
./build/asmory target
```

Example output:

```text
Asmory host target

Target
  arch         x86_64
  os           linux
  object       elf64
  abi          sysv64
  cpu_vendor   AuthenticAMD

ISA
  baseline     x86-64-v3

  features
    sse2       yes
    sse4.2     yes
    avx        yes
    avx2       yes
    fma        yes
    bmi1       yes
    bmi2       yes
    avx512f    no
```

The CLI uses `CPUID` and `XGETBV` directly. AVX-family instructions are only
reported as usable when the operating system has enabled the required extended
register state.

## Bootstrap CLI

```bash
asmory target
asmory search simd
asmory info simd-dot
asmory --version
```

Install the locally built CLI:

```bash
make install-user
```

## Package model

A software version can contain several machine Variants:

```text
simd-dot 0.1.0
├── x86_64 / SSE2
├── x86_64 / AVX2 + FMA
├── x86_64 / AVX-512
├── aarch64 / NEON
├── aarch64 / SVE2
└── riscv64 / RVV
```

The package version describes the software release. The Variant describes a
machine implementation.

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

## Design principles

### ISA is resolver input

ISA requirements are not search tags. They determine whether a Variant is
legal to execute.

### Runnable != optimal

Asmory separates correctness compatibility from performance preference. A
future resolver may choose between several compatible implementations using
microarchitecture information or benchmark profiles.

### Let the linker collect garbage

Packages should expose independently collectable sections where practical, so
normal linker mechanisms such as `--gc-sections` can eliminate unused code.

### Machine code + machine-readable contract

The goal is not to rebuild a high-level language around Assembly. The goal is
to make low-level code reusable by giving humans and coding agents a precise,
machine-readable interface and target contract.

## Repository

```text
registry/   Assembly HTTP registry
cli/        Assembly package-manager CLI
docs/       architecture, CLI and roadmap
spec/       package / ISA / ABI specifications
examples/   example Assembly packages
site/       GitHub Pages project site
org/        Organization profile source
tests/      integration tests
scripts/    development / publish / release helpers
```

## Roadmap

The immediate path is:

```text
host detection
    -> remote registry protocol
    -> Variant compatibility resolver
    -> asmory add
    -> lockfile/cache
    -> build/link pipeline
    -> signed publishing
```

See [docs/ROADMAP.md](docs/ROADMAP.md).

## Contributing

Asmory is especially interested in contributors familiar with:

- x86/x86-64, AArch64 or RISC-V ISA modeling;
- SIMD and optimized kernels;
- SysV AMD64, Win64 and AAPCS64 ABIs;
- ELF, COFF and Mach-O;
- GNU as, NASM and LLVM MC;
- linkers and section garbage collection;
- host feature detection and dispatch;
- dependency resolution and package registries;
- high-performance computing.

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT.
