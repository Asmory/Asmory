# Asmory Architecture

## Scope

Asmory is a package registry, specification, resolver and package-manager
experiment for machine-level code.

Its central problem is not merely dependency versioning.

Asmory must model both:

```text
what code means
and
where machine code can legally run
```

while allowing independent developers to optimize the same capability for
different hardware.

## Core object model

```text
Capability
    ↓
Semantic Facets
    ↓
optional named Profile / Contract
    ↓
Implementation (Provider)
    ↓
Machine Variant
    ↓
Artifact
    ├── Conformance Evidence
    └── Performance Evidence
```

### Capability

Discovery namespace for a problem.

### Semantic Facets

Canonical observable semantics. They are the compatibility source of truth.

### Profile / Contract

Optional immutable named bundle of Facets. Useful for reuse, but not an
authority over future designs.

### Implementation

One independently maintained solution owned by one provider.

### Machine Variant

A target-specific realization of an Implementation.

### Artifact

Immutable distributable content identified by digest.

### Evidence

Append-only observations about conformance or performance of an exact Artifact.

## Resolver architecture

```text
release constraints
      ↓
Capability lookup
      ↓
semantic match
      ↓
machine legality
      ↓
toolchain/ABI
      ↓
trust
      ↓
performance ranking
      ↓
Artifact
```

Correctness and trust are filters.

Performance is ranking.

## Index architecture

Asmory should avoid global scans.

Publication canonicalizes semantic metadata and produces:

```text
Capability ID
Semantic Fingerprint
Facet index keys
Machine Contract
Provider identity
Artifact digest
```

The registry can maintain inverted indexes by Capability, selected Facets,
architecture and ISA features.

## Community architecture

Asmory does not assume one maintainer owns all Variants.

Independent providers can implement compatible semantics on different machines.

Likewise, a provider may reject an existing Profile and publish a different
semantic Alternative under the same Capability.

The registry records this diversity instead of forcing false uniformity.

## Conformance architecture

Conformance tests should be composable from Facet-level suites where practical.

A Profile may compose shared suites and add integration cases.

Conformance proves declared compatibility under test scope; it does not create
semantic authority.

## Performance architecture

Performance Evidence binds to an exact Artifact and machine profile.

Evidence is append-only, allowing the community to extend hardware coverage
without mutating releases.

Direct ranking is restricted to comparable cohorts.

## Trust architecture

Native code makes trust independent from semantic conformance.

Future resolver policy must be able to require a trust level before automatic
selection.

## Link architecture

Functions and independently removable data should use granular sections where
practical. Normal linker reachability (`--gc-sections` on ELF) should eliminate
unused code instead of making the package manager infer Assembly control flow.

## Design invariant

The architecture should preserve this distinction:

```text
Capability answers "same problem?"

Facets answer "same meaning?"

Machine Contract answers "can it run?"

Trust answers "may I select it?"

Evidence answers "does it conform, and how fast is it?"
```

## Local-first storage architecture

Asmory separates immutable acquisition from editable use:

```text
Registry Artifact
      ↓
global content-addressed cache
      ↓
project-local materialization
```

The cache is immutable and shared.

The local materialization is visible to the project and may be modified.

A dirty local materialization must retain the identity of its base Artifact
without pretending to still be that Artifact.

This split provides:

```text
fast repeated installs
offline reuse
reproducibility
AI inspectability
human inspectability
safe local experimentation
```

Writable hard links from a project into the immutable cache are not acceptable;
copy-on-write or ordinary copies are preferred.

## Dependency-state architecture

Project-local dependencies have explicit state:

```text
Clean
    exact materialization of locked Artifact

Dirty
    local derivative of locked Artifact
```

The package manager must detect the transition rather than relying on user
memory.

Dirty state carries:

```text
base Artifact identity
local tree identity
materialization path
```

Publication requires the dirty state to be converted into an explicit,
reconstructible representation.

## Leaf-first resolution architecture

Asmory v1 resolves direct dependencies independently.

```text
Project
    ↓
direct requirements[]
    ↓
semantic + machine + trust + performance resolution
    ↓
flat resolved source image
```

Recursive dependency solving is intentionally outside the initial core.

Future bundles may flatten a resolved closure into one immutable consumer-facing
release image.

## Security reporting architecture

Security feedback is modeled as a pipeline:

```text
deterministic review evidence
        ↓
Security Report
        ↓
triage
        ↓
Security Advisory
        ↓
signed advisory feed
        ↓
audit/build/status warnings or policy blocks
```

Raw report count does not change package safety state.

Advisories and quarantine/revocation actions are independent machine-readable
registry objects with auditable history.

A project's locked Artifact identity remains stable while its current safety
state can change as new Advisory information arrives.

## Review-state architecture

Artifact integrity, review evidence and registry safety are stored separately.

```text
Artifact
├── Integrity State
├── Review Evidence
│   ├── structural scan
│   ├── Capability anomaly evidence
│   ├── AI review
│   ├── human review
│   └── Reviewed Anchor status
└── Safety State / Advisories
```

A Reviewed Anchor enables efficient incremental review of descendants.

Review continuity can be invalidated by events such as ownership transfer,
provenance changes, major rewrites or build-system changes.

The registry should not infer safety from a valid digest.
