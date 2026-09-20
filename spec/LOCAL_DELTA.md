# Reproducible Local Delta — Draft 0.1

A Modified dependency is useful during experimentation, but a change that exists
only under one developer's `.asmory/deps/` directory is not reproducible.

Asmory therefore separates two questions:

```text
Integrity
  Exact / Modified / Missing / Unknown

Divergence capture
  none / uncaptured / captured-patch
```

These are not the same axis.

## Capture

```bash
asmory patch simd-dot
```

requires a Modified local tree.

Asmory reconstructs the exact locked base Artifact, compares the base
materialization with the current local tree, and creates a deterministic delta
under:

```text
.asmory/patches/simd-dot/
├── active
├── deltas/
│   └── <delta-sha256>.json
└── blobs/
    └── <blob-sha256>
```

Unlike `.asmory/deps/`, `.asmory/patches/` is intentionally **not ignored**.

This is the executable meaning of:

> **Local-visible by default, Git-tracked when diverged.**

## Delta identity

`asmory-delta-v1` uses canonical JSON.

The delta digest is:

```text
SHA-256(canonical delta JSON bytes)
```

The JSON binds:

- package identity;
- locked base Artifact SHA-256;
- locked base materialized-tree SHA-256;
- target materialized-tree SHA-256;
- sorted removals;
- sorted directory/file writes;
- normalized Unix modes;
- content-addressed blob SHA-256 values.

Every file payload is stored by its own SHA-256.

## Capture validates replay

A delta is not published merely because a diff could be computed.

Capture performs:

```text
locked Artifact
   ↓
exact base materialization
   ↓
compute delta against local Modified tree
   ↓
second exact base materialization
   ↓
replay candidate delta
   ↓
target tree fingerprint must match local tree
   ↓
publish delta/blobs/active
```

Thus the patch record proves it can reconstruct the state it claims to capture.

## Reapply

```bash
asmory reapply simd-dot
```

reconstructs the exact locked base, verifies the active delta and every blob,
replays it in staging, verifies the target tree fingerprint, and only then
publishes the result.

Reapply is allowed from:

```text
Exact
Missing
already-captured target
```

It refuses to overwrite an unrelated uncaptured Modified tree.

## Restore remains base-oriented

`asmory restore simd-dot` keeps its original meaning:

> return the local dependency to the exact Registry Artifact locked in
> `asm.lock`.

Captured patches remain available after restore.

Therefore:

```text
Modified + captured patch
    ↓ restore
Exact + saved patch
    ↓ reapply
Modified + captured patch
```

No re-resolution occurs.

## MVP representation limits

Patch v1 represents regular files and directories.

If a Modified tree introduces symlinks or special files, capture fails instead
of silently producing an incomplete handoff.

Future vendor/fork workflows may support a broader source-tree representation.
