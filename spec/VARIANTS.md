# Implementations and Machine Variants — Draft 0.1

Asmory does not require one publisher to support every machine.

## Community model

```text
Capability
└── semantic shape
    ├── Implementation by Provider A
    │   ├── Variant A1
    │   └── Variant A2
    ├── Implementation by Provider B
    │   └── Variant B1
    └── Implementation by Provider C
        └── Variant C1
```

An Implementation is an independently maintained solution.

A Machine Variant is a machine-specific realization of that implementation.

## Machine Contract

Hard execution requirements include:

```text
architecture
OS
object format
ABI
calling convention
ISA baseline
required ISA extensions
toolchain constraints
```

If the host does not satisfy them, the Variant must not execute.

## Tuning Profile

Performance preference is separate:

```text
microarchitecture
unroll strategy
instruction scheduling
cache assumptions
```

`tuned_for = zen4` must never silently mean `requires = zen4`.

## Semantic boundary

Changing machine realization while preserving declared semantics creates a
Machine Variant.

Changing observable semantics changes the semantic candidate itself.

The resolver may still group both under one Capability, but it must not silently
treat them as interchangeable.

## Provider independence

Different providers may maintain compatible implementations.

The resolver is allowed to select across providers only when semantic, machine
and trust policies all permit it.
