# Source and Binary Artifacts — Draft 0.1

Asmory distinguishes semantic identity, source identity and binary identity.

```text
Capability
   ↓
Semantic Facets / fingerprint
   ↓
Implementation
   ↓
Machine Variant
   ├── Source Artifact
   └── Binary Artifact(s)
```

## Source Artifact

A Source Artifact is immutable content identified by digest.

It contains the source state from which local builds and AI modifications can
begin.

## Binary Artifact

A Binary Artifact has its own independent digest and trust/provenance state.

Trusting Source Artifact A does not automatically imply trusting Binary Artifact
B.

Binary metadata should bind to:

```text
semantic fingerprint
Implementation
Machine Variant
source Artifact digest
build recipe identity
toolchain identity
builder/provenance information
```

## Source-preferred default

Asmory is an AI-friendly Assembly ecosystem, so the ordinary default should be
source-preferred:

```text
resolve
   ↓
fetch / verify source
   ↓
cache
   ↓
materialize locally
   ↓
build locally
```

A compatible trusted prebuilt binary can be used as an optimization.

Future user policies may include:

```text
source-preferred
binary-preferred
source-only
binary-only
```

## Dirty source invalidates prebuilt binary selection

If a local source tree differs from the source Artifact used to build a Registry
binary, that binary is no longer a valid representation of the local code.

```text
Clean source SRC-A
   ↔ prebuilt BIN-A may be valid

Dirty source LOCAL-B
   ↛ prebuilt BIN-A
```

The Dirty tree must be rebuilt locally.

## Acquisition pipeline

Resolution and download are separate:

```text
Resolve
   ↓
Acquisition record
   ↓
Acquire exact Artifact
   ↓
Verify digest / provenance
   ↓
Cache
   ↓
Materialize
   ↓
Build if required
```

The resolver should return identities and policy decisions, not merely an
unverified URL.

## Binary review

Binary comparison can produce deterministic structural evidence:

```text
ELF/COFF/Mach-O section changes
symbol changes
relocation changes
import changes
disassembly changes
new executable/writable regions
```

That evidence can feed AI/human review and security reporting.

## Artifact identity does not imply safety

A valid digest proves identity.

It does not prove benign behavior.

Source and Binary Artifacts therefore have independent:

```text
integrity state
review evidence
provenance evidence
Advisory state
```

An exact Source Artifact may still be malicious.

A Binary Artifact may also be dangerous even when it correctly matches its
declared digest.

Digest verification is necessary, but not sufficient, for trust.
