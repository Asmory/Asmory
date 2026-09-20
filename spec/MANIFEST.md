# `asm.toml` Manifest — Draft 0.1

The manifest is a concise authoring interface.

It is not required to expose every internal resolver field.

Asmory lowers manifest shorthand, named Profiles and defaults into a normalized
machine-readable representation before resolution.

## Minimal example

```toml
[package]
name = "simd-dot"
version = "0.1.0"
license = "MIT"

[semantics]
capability = "math.dot.f32"
profile = "asmory/simd-dot-core@1.0.0"

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
syntax = "intel"
```

## Progressive disclosure

Ordinary authors should be able to reuse named Profiles and machine Profiles.

Advanced authors may declare Semantic Facets, requirements and guarantees
directly.

The registry stores the expanded canonical representation.

## Design rules

1. `package.version` is semantic versioning, not an ISA identifier.
2. Capability is discovery, not semantic authority.
3. Semantic Facets are the compatibility source of truth.
4. A Profile/Contract is an immutable name for a reusable Facet bundle.
5. Required ISA features are execution correctness requirements.
6. Tuning preferences never silently become correctness requirements.
7. Provider identity is independent from Contract/Profile authorship.
8. Local dependency state never changes dependency identity implicitly.
9. Artifact hashes identify content; they do not imply safety.
10. User-facing shorthand must lower to an explicit normalized resolver request.
