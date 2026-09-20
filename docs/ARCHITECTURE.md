# Asmory Architecture

## 1. Scope

Asmory is a package registry, package specification, resolver, and eventually a package-manager CLI for Assembly code.

The central difference from language package managers is that a package is not compatible merely because the CPU architecture name matches. Machine-code legality and ABI correctness depend on a much more precise target description.

## 2. Major components

### Registry

Stores package metadata, versions, variants, manifests, checksums, source archives, and eventually prebuilt objects where policy permits.

The current MVP under `registry/src/server.S` is deliberately tiny: an x86-64 Linux syscall HTTP server proving that the public service itself can begin in Assembly.

### CLI

The future `asmory` executable will:

1. parse `asm.toml`;
2. detect or accept a target;
3. resolve dependencies and ISA constraints;
4. fetch source/package artifacts;
5. invoke a supported assembler;
6. assemble objects;
7. link with section GC where requested;
8. produce a reproducible lockfile/target decision record.

### Specification

`spec/` is the stable contract. Registry and CLI implementations must follow it rather than embedding ad-hoc assumptions.

## 3. Package model

```text
Package
└── Version
    ├── Variant A: target constraints + sources/objects
    ├── Variant B: target constraints + sources/objects
    └── Variant C: target constraints + sources/objects
```

A semantic package version describes API/behavioral versioning. ISA variants are a separate axis and must not be encoded by pretending every hardware target is a different semantic version.

## 4. Compatibility pipeline

```text
host/explicit target
        ↓
architecture filter
        ↓
OS + object + ABI filter
        ↓
ISA baseline/version filter
        ↓
required-extension solver
        ↓
assembler/toolchain support filter
        ↓
optional tuning/ranking policy
        ↓
selected variant
```

Correctness compatibility must be resolved before performance preference.

## 5. Link model and dead-code elimination

Asmory packages should expose functions and independently removable data in their own sections. On ELF this enables linker `--gc-sections` to discard unreachable content.

This is preferable to asking the package manager to reason about arbitrary source-level control/data flow in Assembly.

## 6. MVP limitations

The current registry is intentionally static and single-process. It does not yet provide uploads, persistence, authentication, search indexing, dependency resolution, or a dynamic package database.
