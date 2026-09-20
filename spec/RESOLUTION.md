# Resolution Model — Draft 0.1

Asmory resolution is a filtering pipeline followed by ranking.

```text
dependency / release constraints
        ↓
Capability index
        ↓
semantic requirements
        ↓
Machine Contract
        ↓
toolchain / ABI
        ↓
trust policy
        ↓
tuning preference
        ↓
Performance Evidence
        ↓
selected Artifact
```

## Semantic filtering

Semantic compatibility uses canonical Facets and directional
requirements/guarantees.

Named Profiles are expanded before matching.

## No global Profile scan

Publishing a package must not compare it against every Profile in the registry.

Instead:

```text
declaration
   -> canonical Facets
   -> semantic fingerprint
   -> Capability / Facet indexes
```

Exact semantic matches can use fingerprints.

Compatible-but-not-identical matches use indexed Facet relations.

## Bounded relation language

Draft 0.1 intends to support cheap, explainable relations such as:

```text
exact
contains
subset / superset
minimum / maximum
range
```

Arbitrary Boolean/SAT expressions are deliberately excluded.

## Explainability

A resolver should be able to explain rejection:

```text
candidate rejected:
  ISA requires AVX-512F, host lacks AVX-512F

candidate rejected:
  implementation requires 32-byte alignment,
  consumer only guarantees 16-byte alignment

candidate rejected:
  trust policy requires project-approved

candidate accepted:
  semantic requirements satisfied
  machine compatible
  trust accepted
```

Performance ranks accepted candidates; it never overrides rejection.

## Progressive disclosure

Dependency syntax is a frontend, not the resolver's internal model.

The same resolver accepts requests produced from several levels of user input.

### Minimal

```toml
[dependencies]
simd-dot = "1"
```

### Constrained

```toml
[dependencies]
simd-dot = {
    version = "1",
    profile = "asmory/dot-core@1",
    trust = "reviewed"
}
```

### Expert

Conceptually, an expert may additionally constrain:

```text
Provider
semantic Facets
Machine Variant
ISA policy
microarchitecture preference
trust
performance policy
artifact digest
```

All forms lower into one **Normalized Resolution Request**.

## Normalized Resolution Request

The internal request should eventually contain explicit fields for:

```text
release/version constraints
Capability
expanded semantic requirements
machine target
ABI/object/toolchain requirements
provider policy
trust policy
performance policy
pinning/lock constraints
```

Missing user syntax is expanded from versioned defaults or named Profiles.

The internal request must never rely on UI shorthand.

## Default policy

Defaults should be:

```text
explicit
versioned
inspectable
explainable
lockable
```

A resolver may hide complexity but must not hide semantic changes.

Automatic selection across Machine Variants is appropriate when accepted
semantics remain satisfied.

Automatic selection across incompatible semantic shapes is not.

## Explainability

Resolution should produce an explanation graph sufficient for commands such as:

```bash
asmory explain <package>
```

The explanation should distinguish:

```text
user requirement
expanded default
host fact
semantic rejection
machine rejection
trust rejection
performance ranking
final selection
```

This makes simple defaults compatible with expert-level auditability.
