# Contributing to Asmory

Asmory is building a reusable package ecosystem for Assembly.

Contributions are welcome in code, specifications, documentation, tests,
benchmarks and architecture discussions.

## Areas where help is especially useful

- x86 / x86-64 ISA feature modeling
- AArch64 architecture revisions and extensions
- RISC-V extensions and profiles
- SysV AMD64 ABI
- Win64 ABI
- AAPCS64
- ELF / COFF / Mach-O
- GNU as / LLVM MC / NASM compatibility
- linker section garbage collection
- CPU feature detection
- dependency and Variant resolution
- reproducible builds
- optimized Assembly kernels

## Development

Build and test:

```bash
make clean && make -j"$(nproc)" && make check && make smoke
```

## Design rule

Do not describe compatibility using architecture names alone.

Bad:

```text
x86_64
```

Better:

```text
x86_64
Linux
ELF64
SysV AMD64 ABI
x86-64-v3
AVX2
FMA
GNU as >= required version
```

ISA requirements must remain distinguishable from performance tuning hints.

## Pull requests

Please include:

1. what changed;
2. why it is needed;
3. affected architectures / ISAs / ABIs;
4. tests performed;
5. compatibility implications.
