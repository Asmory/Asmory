# Repository Workspace and Package Boundary — Draft 0.1

Asmory separates development topology from distribution identity.

```text
Git Repository
    ↓
Repository Workspace
    ↓ 1:N
Package
    ↓
Release
    ↓
Variant
    ↓
Artifact
```

A Git repository is a development container.

A Package is a distribution identity.

A Repository Workspace may connect many Packages, but it never merges their
identities.

## Repository cardinality

Asmory explicitly allows:

```text
one Git repository -> many Packages
```

Each Package keeps its own normalized name, version and Release history,
Capability / Semantic identity, Provider relationship, Machine Variants,
Artifact identities and dependency state.

Repository membership is not resolver identity.

## Repository workspace manifest

A development repository may declare:

```toml
schema = 1

[workspace]
repository = "https://github.com/example/kernels"
members = [
    "packages/dot-f32",
    "packages/softmax",
]
```

The manifest is `asmory.workspace.toml`.

V1 members are explicit sorted relative paths. Globs are intentionally omitted.

Nested member roots are rejected because overlapping Package ownership makes
Artifact boundaries ambiguous.

## Package manifest

Each member root contains `asmory.package.toml`:

```toml
schema = 1

[package]
name = "dot-f32"
version = "0.3.0"
```

V1 requires the Package directory basename to equal the normalized Package
name. This keeps archive roots and Registry identities unambiguous.

`asmory.package.toml` is repository/development control metadata. Source Artifact v1 does not copy it into the Artifact payload. Changing workspace metadata therefore does not silently rewrite an already-published immutable Release.

## Package state is independent of repository state

Dependency state belongs to Package identity, never Repository identity.

```text
one Package Modified
!=
repository Modified
```

Likewise:

```text
fork Package
!=
fork Git repository
```

Patch, restore, vendor, future fork and publication actions operate at Package
granularity. Sibling Packages are not implicitly included.

## Self-contained source boundary

A published source Artifact is constructed only from the declared Package source closure.

That closure is rooted at the Package root but excludes repository-control metadata such as `asmory.package.toml`.

Repository siblings, root-level build tooling and unrelated Packages are not
part of that Artifact unless they are explicit dependencies.

Asmory v1 rejects source-Package symlinks and special files.

Literal Assembly includes (`.include`, `%include`, `#include`) must remain
inside the Package root. A `../` include is only legal when it still resolves
inside that same Package root.

Shared reusable source across Package roots should become an explicit Package
dependency.

This boundary is what makes Package-level materialization, patch, vendor and
future fork behavior correct even for monorepos.

## Forking never widens to repository scope

`asmory fork <package> <new-package>` creates one new workspace member from one
active Package tree.

It does not clone the upstream repository and does not copy sibling workspace
members. The current repository is merely the development container for the
new Package.

> **Dependency state belongs to Package identity, never Repository identity.**

## Machine Variant is not a Package split

Different ISA realizations of the same semantic software Release remain
Variants:

```text
dot-f32@0.3.0
├── x86_64-avx2
├── x86_64-avx512
├── aarch64-neon
└── riscv64-rvv
```

Do not create sibling Packages merely for ISA differences.

## Consumer workspace vs repository workspace

`asm.toml` remains the consumer dependency-intent manifest.

`asmory.workspace.toml` describes development-repository topology.

Draft 0.1 keeps these separate so dependency intent and repository layout cannot
silently overwrite one another.
