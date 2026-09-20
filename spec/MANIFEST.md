# `asm.toml` Manifest — Draft 0

A package manifest describes semantic package metadata separately from machine-target constraints.

Example:

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
optional = []

[toolchain]
assembler = "gas"
min_version = "2.40"
syntax = "intel"

[build]
sources = ["src/dot.S"]

[link]
gc_sections = true
pic = false

[exports.simd_dot_f32]
symbol = "simd_dot_f32"
section = ".text.simd_dot_f32"
calling_convention = "sysv64"
```

## Design rules

1. `package.version` is semantic versioning, not an ISA identifier.
2. Target/ISA data must be machine-readable, not free-form tags.
3. Required ISA features are correctness requirements.
4. Tuning preferences must never silently become correctness requirements.
5. An implementation variant may refine target constraints without changing the package API version.
