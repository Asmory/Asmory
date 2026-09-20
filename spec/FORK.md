# Package Fork and Publication Candidate — Draft 0.1

Fork is a Package identity transition.

It is not a Git repository fork and it does not clone the upstream repository.

## Core rule

```text
fork Package
!=
fork Git repository
```

If a dependency came from a monorepo, `asmory fork` copies only the active
Package tree that the consumer actually resolved/materialized.

Sibling Packages and unrelated repository files are not copied.

## Command

```bash
asmory fork simd-dot my-dot
```

The source may be either:

```text
registry-derived .asmory/deps/simd-dot
project-owned vendor/simd-dot
```

The new independent Package is created at:

```text
packages/my-dot/
```

and is added to the current repository's `asmory.workspace.toml`.

The original dependency is not deleted, restored, renamed or rewired.

## Fork identity manifest

The new Package receives:

```toml
schema = 1

[package]
name = "my-dot"
version = "0.1.0"

[origin]
kind = "asmory-fork"
package = "simd-dot"
release = "0.1.0"
source_kind = "registry"
artifact_sha256 = "<original Artifact>"
base_tree_sha256 = "<original exact materialization>"
source_tree_sha256 = "<tree actually forked>"
semantic_fingerprint = "<original semantics>"
profile = "<original profile>"
provider = "<original Provider>"
variant = "<original Variant>"
```

`source_tree_sha256` is important: a fork from a Modified dependency binds the
actual bytes that crossed the identity boundary, not merely the older Registry
base.

The fork ancestry is provenance. It does not make the new Package a mutable
alias of the old Package.

## Transaction

Fork uses the project workspace mutation lock.

It:

```text
select active Package tree
    ↓
hash source tree
    ↓
copy only that tree to private staging
    ↓
verify copied tree hash
    ↓
write new independent Package identity
    ↓
prepare sorted repository workspace membership
    ↓
publish new Package + workspace metadata
    ↓
run repository workspace boundary validation
    ↓
verify deterministic source packaging
```

Failure rolls back the new Package and repository-workspace metadata.

The source dependency remains untouched.

## Publication prepare

Remote authenticated Registry writes are a later M3 capability.

The local publication boundary is already executable:

```bash
asmory publish-prepare my-dot
```

This requires the Package root to be clean in Git.

Asmory produces:

```text
.asmory/.publish/my-dot/0.1.0/
├── my-dot-0.1.0.tar.gz
└── release-candidate.json
```

The candidate binds:

- new Package name/version;
- exact Git repository/commit/subdir provenance;
- exact source Artifact SHA-256 and size;
- self-contained boundary statement;
- fork ancestry, when present.

The candidate is deterministic and idempotent for the same clean Git state.

It is deliberately labeled a local candidate:

```text
remote = not uploaded
```

so the CLI does not pretend that an authenticated Registry API exists yet.

## Package manifest vs Artifact

`asmory.package.toml` is repository control metadata and is not copied into
source Artifact v1.

Its identity/provenance information is lifted into publication metadata instead.

## Git visibility

Forked `packages/<name>/` source is ordinary Git-visible project source.

Temporary fork/publication transaction directories under `.asmory/` are
ignored.

## Authenticated remote staging

After local preparation:

```bash
asmory publish my-dot
```

uploads the exact source Artifact and canonical candidate through the
authenticated staging API.

The resulting remote state is persistent and immutable for the staged
`(Package, version)`, but remains `resolvable = false` until a future promotion
step validates a complete Release/Variant publication contract.

## Forked source identity

A fork rewrites the copied source `asm.toml` Package name/version to the new
identity after verifying the copied tree still matches the exact source tree.

The pre-rewrite tree remains recorded as fork ancestry. The rewritten
`asm.toml` then becomes part of the new source Artifact and is independently
checked by the Registry promotion gate.

## Forked source identity

A fork rewrites the copied source `asm.toml` Package name/version to the new
identity after verifying the copied tree still matches the exact source tree.

The pre-rewrite tree remains recorded as fork ancestry. The rewritten
`asm.toml` then becomes part of the new source Artifact and is independently
checked by the Registry promotion gate.
