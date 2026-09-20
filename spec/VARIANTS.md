# Machine Variants — Draft 0

Asmory separates three questions that must never be collapsed:

```text
Can it run?
    ↓
Machine Contract

What machine was it tuned for?
    ↓
Tuning Profile

How did it actually perform?
    ↓
Performance Evidence
```

## Model

```text
Project
└── Release
    ├── Variant
    │   ├── Machine Contract
    │   ├── Tuning Profile
    │   ├── Artifact
    │   └── Performance Evidence[]
    └── Variant
        └── ...
```

A Variant is not a Git branch. It is one machine implementation of the same
semantic package Release.

## Machine Contract

Hard correctness requirements:

```toml
[variant.compatibility]
arch = "x86_64"
os = "linux"
object = "elf64"
abi = "sysv64"
baseline = "x86-64-v3"
required = ["avx2", "fma"]
```

If the target does not satisfy these fields, the Variant must not execute.

## Tuning Profile

Performance preference, not correctness:

```toml
[variant.tuning]
microarch = ["zen4"]
```

A Zen 4 tuned Variant may still execute on another compatible x86-64 CPU.
`tuning` must never silently become a hard ISA requirement.

## Performance Evidence

Evidence is attached to:

```text
Release
+ Variant
+ Artifact SHA-256
+ Benchmark Contract
+ Machine Profile
```

The same immutable Artifact can accumulate Evidence from many CPUs over time.

## Resolver order

```text
version resolution
      ↓
Machine Contract filtering
      ↓
compatible Variants
      ↓
Tuning Profile preference
      ↓
comparable Performance Evidence
      ↓
selected Variant
```

Correctness always wins over performance preference.
