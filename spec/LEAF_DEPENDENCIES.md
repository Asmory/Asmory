# Leaf-First Dependency Model — Draft 0.1

Asmory v1 prefers machine-level packages to be dependency leaves.

This is an intentional simplification.

## Motivation

Assembly packages are expected to often be small reusable machine-level
building blocks:

```text
dot-product kernel
memcpy
hash primitive
FFT kernel
JSON scanner
GEMM microkernel
DSP primitive
```

Allowing every such package to recursively resolve more Asmory packages would
multiply several already difficult problems:

```text
version solving
semantic solving
Machine Variant selection
trust policy
Provider selection
performance ranking
```

Asmory should not inherit dependency-graph complexity unless real workloads
prove that it is necessary.

## Leaf package

A Leaf package has no runtime/build dependency on another Asmory package.

```text
Project
├── Leaf A
├── Leaf B
├── Leaf C
└── Leaf D
```

Each direct dependency is resolved independently.

Conceptually:

```text
for dependency in project.dependencies:
    resolve semantics
    resolve machine compatibility
    apply trust policy
    rank performance
```

No recursive graph traversal is required.

## Composition belongs at the project level

If a program needs:

```text
FFT
vector math
memcpy
```

the application or workspace may declare all three directly.

This keeps the dependency graph shallow and visible.

## Internal code may still be bundled

A Leaf package can contain internal implementation code:

```text
foo/
├── src/main.S
└── src/internal/helper.S
```

The rule is not "one source file".

The rule is:

> The published Artifact is self-contained from the Asmory resolver's point of
> view.

## Future composite packages

Asmory should not promise that recursive dependencies are forbidden forever.

If real packages require composition, a future package kind may represent a
Composite or Bundle.

The preferred model is:

```text
resolve once
flatten early
```

A publisher resolves the dependency closure and publishes a reproducible bundle
whose consumer sees:

```text
one immutable closure
one digestable release image
```

rather than re-solving an arbitrary recursive graph on every installation.

## Why this helps AI

A flat resolved workspace is easy for an AI agent to inspect:

```text
vendor/asmory/
├── fft/
├── memcpy/
├── dot/
└── sha256/
```

The agent does not need to recursively discover hidden dependency trees before
it can understand or optimize the project.

## Design principle

> **Asmory v1 is leaf-first, not dependency-graph-first.**

Recursive composition should be introduced only when concrete package
ecosystems demonstrate that the additional complexity pays for itself.
