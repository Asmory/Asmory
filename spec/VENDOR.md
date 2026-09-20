# Explicit Vendor Ownership — Draft 0.1

`asmory vendor <package>` is an ownership transition.

It is not another integrity state and it is not an alias for copying a directory.

Before the transition:

```text
source      registry
ownership   registry-derived
working     .asmory/deps/<package>
```

After the transition:

```text
source      vendor
ownership   project
working     vendor/<package>
```

## Why vendor exists

A deterministic patch is ideal when a project wants to preserve a compact
derivative relative to a Registry Artifact.

Vendoring is different.

It says:

> This project now owns the complete dependency source tree.

The whole source tree becomes ordinary Git-visible project content.

## Manifest

The user-intent manifest changes from a Registry request:

```toml
[dependencies]
simd-dot = "*"
```

to an explicit local path:

```toml
[dependencies]
simd-dot = { path = "vendor/simd-dot" }
```

This is the semantic ownership transition.

## Lock provenance

Asmory keeps the original Registry Release, semantic fingerprint, Provider,
Machine Variant, Artifact SHA-256 and base tree fingerprint as provenance.

The lockfile adds:

```toml
source_kind = "vendor"
vendor_path = "vendor/simd-dot"
vendor_origin_tree_sha256 = "<tree at transition>"
```

`vendor_origin_tree_sha256` records the exact tree that crossed the ownership
boundary. It is provenance, not a requirement that future project edits keep
matching it.

## Transaction

The transition is fail-closed:

```text
hash registry-derived local tree
    ↓
copy into private staging
    ↓
hash source again + hash staged copy
    ↓
all fingerprints identical
    ↓
prepare + parse new manifest/lock
    ↓
move old materialization to rollback slot
    ↓
publish vendor tree
    ↓
publish metadata
    ↓
verify tree + metadata
    ↓
discard rollback
```

Failure restores the original dependency and metadata.

## Interaction with integrity

Integrity remains relative to the original locked Registry base.

Therefore vendoring an unchanged dependency may report:

```text
source      vendor
ownership   project
state       Exact
```

and later project edits may report:

```text
source      vendor
ownership   project
state       Modified
```

This does not make project-owned edits unsafe or invalid.

It only preserves useful provenance information.

## Interaction with patch / restore

Registry lifecycle commands do not silently take control back from a vendored
dependency.

`restore`, `patch`, and `reapply` refuse `source_kind = "vendor"`.

The project may use normal Git operations on the vendored tree.

A future explicit unvendor/fork/publication workflow may transition ownership
again. No implicit transition is allowed.

## Git policy

`.asmory/deps/` remains ignored.

`vendor/` is not ignored.

This is the full-source form of:

> **Local-visible by default, Git-tracked when diverged.**
