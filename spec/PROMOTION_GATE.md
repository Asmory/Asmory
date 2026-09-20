# Active Release Promotion Gate — Draft 0.1

Uploading bytes is not enough to create an active Asmory Release.

Asmory separates:

```text
authenticated staging
        ↓
server-derived promotion validation
        ↓
active immutable Release
        ↓
resolver-visible
```

## Command

```bash
asmory publish my-dot
asmory promote my-dot
```

`publish` stages an exact Artifact and immutable candidate.

`promote` asks the Registry to derive and validate the active Release contract
from the already-staged Artifact.

## Why the Registry derives metadata again

The promotion server does not trust the client to invent a second Release
record.

It opens the exact content-addressed Artifact referenced by the staged
candidate and independently reads:

```text
asm.toml
semantics.toml
conformance/suite.toml
declared build sources
declared conformance runner
```

Promotion rejects unsafe archive paths, links, special files, excessive member
counts and excessive unpacked size.

The Registry then verifies that:

- Artifact `asm.toml` Package name/version equals the staged Package identity;
- `asm.toml` semantic Capability/Profile agrees with `semantics.toml`;
- Semantic Facets can be canonicalized;
- the semantic fingerprint is recomputed server-side;
- target architecture / OS / object / ABI / ISA fields are present;
- toolchain fields are present;
- every declared build source exists inside the Artifact;
- exports are complete;
- the declared conformance suite exists;
- the conformance suite Profile agrees with the semantic Profile;
- the declared conformance runner exists inside the Artifact.

The resulting active Release is therefore derived from the exact Artifact bytes
rather than from an unverified client-side metadata upload.

## What this gate does not claim

Draft 0.1 does **not** execute untrusted package code on the Registry server.

Therefore:

```text
semantic fingerprint recomputed     yes
metadata consistency checked        yes
Artifact/source closure checked     yes
conformance suite declared          yes
conformance program executed        no
machine instruction proof           no
security review                     no
```

The active Release remains:

```text
review.state = unreviewed
safety.state = normal
```

until independent review/advisory systems say otherwise.

This keeps semantic truth, Artifact integrity, review state and safety state
separate.

## Fork identity coherence

A Package fork rewrites the copied source `asm.toml` Package name/version to the
new Package identity.

This is necessary because `asmory.package.toml` is repository control metadata
and is excluded from the source Artifact.

The Artifact itself must therefore carry the new Package identity in
`asm.toml`.

Fork ancestry still records the original Artifact and exact pre-fork source
tree.

## Active persistence

Active records are persisted as:

```text
data/
└── active/
    └── projects/
        └── <package>/
            └── releases/
                └── <version>.json
```

The content-addressed Artifact remains shared with staging storage.

An exact repeated promotion is idempotent.

A different candidate may never replace an existing active
`(Package, version)`.

## Public active read API

Active records are public:

```text
GET /api/v1/packages/<name>
GET /api/v1/packages/<name>/<version>
GET /api/v1/packages/<name>/<version>/download
```

An active Release returns:

```text
resolvable = true
release.state = active
```

Private staged records remain under `/api/v1/staging/...` and continue to
require publisher authentication.
