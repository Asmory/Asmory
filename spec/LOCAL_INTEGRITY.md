# Local Dependency Integrity — Draft 0.1

Asmory does not store a mutable `exact = true` flag.

Local dependency integrity is computed from the actual project tree and the
immutable base recorded by the lockfile.

## States

The project-facing states are:

```text
Exact
Modified
Missing
Unknown
```

`Exact` and `Modified` are the normative content-integrity states.

`Missing` is an operational state: the locked dependency has no local tree.

`Unknown` means Asmory cannot establish a v1 comparison, for example because an
older lockfile has no materialization baseline.

## Canonical materialized-tree fingerprint

Draft 0.1 uses:

```text
tree_hash_schema = "asmory-tree-v1"
materialized_tree_sha256 = "<sha256>"
```

The fingerprint covers the deterministic project-local materialization, not the
compressed tar representation.

The hash includes, in sorted relative-path order, entry type, relative path,
Unix permission bits, regular-file size and SHA-256, symlink target when a local
edit introduces a symlink, and special-file type metadata.

Therefore editing bytes, adding/removing/renaming a path, changing executable
bits, introducing a link, or replacing the package root changes integrity.

## Why the baseline is in the lockfile

During `asmory add`, Asmory safely materializes the exact locked Artifact and
records the deterministic tree fingerprint produced by the materialization
schema.

This is a reproducibility baseline, not a cached state flag.

`asmory status` always hashes the current tree again.

## Status is local-only

`asmory status` must not contact the Registry. It reads `asm.lock` and
`.asmory/deps/` and computes state locally.

## Restore uses the locked identity

`asmory restore <package>` never means "resolve the newest package again."

It reads the exact locked Artifact identity, obtains that Artifact from verified
cache/acquisition, safely materializes it into staging, verifies the restored
tree fingerprint, and replaces the local tree.

Manifest and lockfile remain unchanged.

## Important distinction

```text
Exact != Safe
Modified != Dangerous
```

Integrity describes relationship to the locked Artifact. Review/advisory safety
is a separate axis.
