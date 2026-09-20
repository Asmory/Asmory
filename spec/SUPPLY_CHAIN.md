# Supply-Chain Safety — Draft 0.1

Asmory's local-first workflow must not allow local state to silently change
dependency identity.

## Core invariants

1. **Local presence never changes dependency identity.**
2. **Dirty state is computed, never trusted.**
3. **Dirty dependencies never masquerade as clean Artifacts.**
4. **Local overrides are explicit and hash-bound.**
5. **Global cache content is immutable and content-addressed.**
6. **Source and Binary Artifacts have independent identities.**
7. **Binary provenance binds to the source state it claims to represent.**
8. **Dirty source invalidates Registry prebuilt binaries.**
9. **Package installation must not execute arbitrary package-provided code by
   default.**
10. **Performance never overrides verification, semantic compatibility or trust.**

## Resolve before materialize

Never resolve by searching for convenient local directories.

Correct order:

```text
Manifest
   ↓
Resolution
   ↓
exact Artifact identity
   ↓
Acquire + Verify
   ↓
Materialize
   ↓
Clean / Dirty state
```

A local directory cannot shadow a locked Registry dependency merely by existing.

## Dirty state

`dirty = false` is not trusted package metadata.

Asmory derives state by comparing the materialized tree with the expected
Artifact/tree identity.

## Local overrides

A Dirty tree participates in a reproducible build only through an explicit,
hash-bound local representation such as:

```text
vendor
deterministic patch
fork
explicit path override + tree hash
```

## Path safety

Local dependency roots must defend against:

```text
path traversal
escaping symlinks
writable hardlinks into immutable cache
unexpected external filesystem references
```

Build inputs must remain inside the declared dependency root unless an explicit
capability permits otherwise.

## Build execution

Asmory v1 should prefer declarative Assembly builds:

```text
sources
assembler
assembler flags
objects
exports
sections
link requirements
```

Installing a package should not imply permission to execute arbitrary shell,
Python or native setup programs.

Any future executable build hook should be treated as an explicit unsafe
capability governed by trust policy.

## Review baseline

Clean Artifacts provide a security comparison baseline.

Asmory defines the exact Delta.

AI and humans can then review the Delta rather than repeatedly re-auditing the
entire repository.

See `SECURITY_REPORTING.md` for rapid reporting and Advisory propagation.

## Integrity is not safety

The immutable Artifact model protects identity and reproducibility.

It does not prove that the Artifact was safe when first published.

A malicious publisher can create a perfectly valid, byte-exact Artifact.

Therefore:

```text
Exact Artifact
    ≠
Reviewed Artifact
    ≠
Safe Artifact
```

Security review state must be modeled separately.

Delta-based review is only considered a strong incremental review strategy when
the baseline is a Reviewed Anchor.

A Delta from an unreviewed base is still useful, but it does not inherit trust
from the base.

See `SECURITY_REVIEW.md`.
