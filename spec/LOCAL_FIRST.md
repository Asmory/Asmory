# Local-First Dependencies — Draft 0.1

Asmory should make machine-level code easy to inspect, modify and optimize.

The default dependency experience is therefore **local-first**, backed by an
immutable global cache.

## Two storage layers

```text
Registry
   ↓
verified immutable Artifact
   ↓
Global content-addressed cache
   ↓
Project-local materialization
   ↓
human / AI / compiler / benchmark
```

### Global cache

Conceptually:

```text
~/.cache/asmory/objects/sha256/<digest>/
```

The cache is:

- immutable;
- content-addressed;
- shared across projects;
- checksum-verified;
- safe to discard and reconstruct.

It exists for speed, bandwidth savings and reproducibility.

### Project-local materialization

By default, a resolved dependency is materialized into the project workspace,
conceptually:

```text
vendor/asmory/
└── simd-dot/
    ├── asm.toml
    ├── src/
    ├── tests/
    ├── bench/
    ├── contracts/
    └── ...
```

The exact path is not frozen by this draft.

The important rule is that the project has a real, visible local copy that can
be inspected and edited.

This is especially valuable for AI-assisted development: the agent can read the
actual implementation, modify it, assemble it, run conformance tests and
benchmark it without reconstructing the package from remote metadata.

## Cache is immutable; workspace copies are mutable

A writable project-local dependency must never be a writable hard link into the
immutable cache.

Materialization may use:

```text
reflink / copy-on-write
or
ordinary copy
```

Editing the project-local copy must not corrupt the shared cache.

## Local edits create derivative state

Once a materialized dependency is modified, it is no longer byte-identical to
the registry Artifact.

Asmory should represent that explicitly:

```text
base_artifact_sha256 = ...
local_path = ...
dirty = true
```

The lockfile should retain the immutable origin while recording that the project
is using a local derivative.

Asmory must not silently overwrite dirty local dependency changes during
`update`, `resolve` or cache refresh.

## AI-friendly, not AI-dependent

Asmory should be exceptionally convenient for coding agents, but correctness
must not depend on an AI model being present.

The package manager still owns:

```text
artifact verification
dependency resolution
semantic compatibility
machine compatibility
trust policy
lockfile reproducibility
```

AI may help with:

```text
understanding code
editing local implementations
creating new Variants
writing tests
benchmark-driven tuning
```

The platform supplies reliable structure; AI supplies flexible reasoning.

## Optional cache-only mode

CI, hermetic builds or advanced users may prefer cache-only dependencies.

A future policy may support:

```text
materialization = "local"      # default
materialization = "cache-only"
```

The default remains local because inspectability and modifiability are core
Asmory goals.

> **Cache for reuse. Local workspace for understanding and evolution.**

## Clean and Dirty are both valid local states

Local-first does not mean "local edits are invisible".

Asmory explicitly distinguishes:

```text
Clean
    local copy == locked Artifact

Dirty
    local copy != locked Artifact
```

Clean dependencies remain reconstructible from the lockfile and normally stay
out of Git.

Dirty dependencies are valid during development, but must become explicit
through vendoring, deterministic patches, a fork, or restoration before a
reproducible release.

This lets Asmory support both workflows:

```text
I only want a local readable copy.
```

and:

```text
I intentionally changed this dependency and want the project to own that
change.
```

See `DEPENDENCY_STATES.md`.
