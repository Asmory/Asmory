# Semantic Type System MVP

This milestone makes Semantic Facets executable.

## Canonical semantic identity

`examples/simd-dot/semantics.toml` describes the implementation independently
from Provider and Profile metadata.

Build tooling canonicalizes the document and computes:

```text
semantic_fingerprint = SHA256(canonical semantic document)
```

The current implementation exactly matches:

```text
asmory/simd-dot-core@1.0.0
```

A second Profile:

```text
asmory/simd-dot-strict@1.0.0
```

belongs to the same Capability but requires bit-exact numeric behavior and
stronger determinism.

The current implementation is therefore correctly rejected for that Profile.

That rejection is not a package failure. It demonstrates a legitimate semantic
alternative / compatibility island.

## CLI

```bash
asmory semantics simd-dot
asmory match simd-dot asmory/simd-dot-core@1.0.0
asmory match simd-dot asmory/simd-dot-strict@1.0.0
```

The first match succeeds with exact fingerprint identity.

The second exits non-zero and explains the first rejected Facet.

## Registry

New read resources:

```text
/api/v1/packages/simd-dot/0.1.0/semantics
/api/v1/capabilities/math.dot.f32
/api/v1/profiles/asmory/simd-dot-core/1.0.0
/api/v1/profiles/asmory/simd-dot-strict/1.0.0
```

Capability explicitly reports:

```text
authority = none
```

Provider identity is also separate from semantic fingerprint identity.

## Conformance composition

`conformance/suite.toml` maps test responsibilities to Facet paths.

The renderer refuses to publish the semantic resource if required Facets are
missing from the suite coverage metadata.

This is not formal verification.

It is the first executable version of:

```text
Facet
  -> tests
Profile
  -> composed Facet tests
Implementation
  -> conformance evidence
```

## Current limits

The Assembly CLI still consumes a generated bootstrap semantic table.

A future remote resolver will retrieve and index arbitrary Capability/Profile
resources rather than knowing only the example package.
