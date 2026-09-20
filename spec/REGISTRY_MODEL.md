# Registry Model — Draft 1

Asmory is a **package registry**, not a source-code forge.

GitHub, GitLab, Forgejo and similar systems are places to develop a project:
commits, branches, pull requests and issue history belong there.

Asmory's role is closer to crates.io or PyPI:

```text
development repository
        ↓
      publish
        ↓
      Asmory
        ↓
versioned immutable release metadata + downloadable artifacts
        ↓
resolver / build / linker
```

## Four registry objects

### Project

A Project is the stable package name and registry-level metadata.

It owns the normalized package name, description, owners/maintainers,
keywords/categories, project links, status and ordered Release history.

### Release

A Release is an immutable version of a Project, such as `simd-dot@0.1.0`.

It records version, publish time, dependencies, yank state, Variants and
Artifacts. Fixes require a new version rather than silently rewriting an old
release.

### Variant

A Variant is one machine implementation inside a Release.

It carries architecture, OS/environment, object format, ABI, ISA baseline and
required extensions, toolchain constraints, optional tuning metadata and
exports.

### Artifact

An Artifact is a downloadable file belonging to a Release. Every artifact has
a stable filename, byte size and cryptographic digest.

## Development repository and source provenance

A Git repository is not a fifth Registry identity object.

One repository may develop many independent Asmory Projects / Packages.

A Release may carry descriptive Git provenance: repository URL, commit and
Package subdirectory. This lets development tools find exact upstream source
without making repository layout resolver authority.

Repository membership never merges Package identities. Artifact SHA-256
remains the exact distribution identity.

## Resolver order

```text
project name
    ↓
version requirement
    ↓
non-yanked release
    ↓
hard target compatibility
    ↓
compatible Variants
    ↓
performance preference
    ↓
artifact fetch + checksum verify
```

Correctness always precedes tuning.

## Publication staging is not an active Release

Authenticated upload first creates a persistent **staged release candidate**.

```text
source Artifact + canonical candidate
        ↓ authenticated write API
persistent staging
        ↓
state = staged
resolvable = false
```

This is deliberately separate from the immutable active Release object.

The current candidate proves source identity, Package boundary and Git
provenance, but does not yet contain every validated Semantic and Machine
Variant field required for resolver-visible publication.

Promotion to an active Release is therefore an explicit later transition, not
an automatic side effect of byte upload.

## Immutability

A previously published `(project, version, artifact filename)` may not be
replaced with different bytes. This protects lockfiles, caches and
reproducibility.

## Yank

Yanking is non-destructive. A yanked Release remains downloadable and
addressable by exact version, but normal new resolution excludes it.

## Ownership

Ownership is registry state, not manifest-controlled metadata.

Draft roles:

- **owner** — publish/yank and manage owners;
- **maintainer** — publish/yank but cannot change ownership.

## Project status

Project-wide status is separate from release yanking:

- active;
- archived;
- quarantined.
