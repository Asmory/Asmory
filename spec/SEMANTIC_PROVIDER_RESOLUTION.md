# Remote Semantic Provider Resolution — Draft 0.1

Package-name resolution answers:

```text
Which Release of this Package can run here?
```

Semantic Provider resolution answers a different question:

```text
Which independently published Package can satisfy this semantic request?
```

Asmory keeps these questions separate.

## Provider index

Active immutable Releases are projected into a derived semantic index:

```text
active Release records
        ↓
semantic-index.json
        ├── providers
        ├── by_capability
        ├── by_fingerprint
        └── by_facet
```

Only the latest active Release of each Package is a Provider candidate in Draft
0.1.

Staged-only candidates are never indexed.

The index is rebuilt after promotion and on Registry startup. It is derived
state, not semantic authority.

## Facet inverted index

Every canonical implementation semantic document is flattened into exact Facet
keys such as:

```text
interface.shape="dot-f32-v1"
interface.logical_export="dot_f32"
interface.calling_convention="sysv64"
guarantees.numeric.bit_exact=false
guarantees.determinism.level="same-machine"
```

These keys are used only as cheap candidate prefilters.

They do **not** replace directional semantic matching.

A candidate that survives exact Capability/interface prefiltering is still
checked by the canonical Semantic Facet matcher:

```text
consumer guarantees >= implementation requirements
implementation guarantees >= consumer requirements
```

## Public API

```text
GET /api/v1/capabilities/<capability>/providers
GET /api/v1/semantic/providers?capability=<capability>
GET /api/v1/semantic/providers?capability=<capability>&facet=<path=json>
```

Repeated `facet` parameters are intersected.

Provider summaries contain Package/Release identity, publisher, Profile,
semantic fingerprint, review/safety state and Release endpoint.

## Client

```bash
asmory remote providers math.dot.f32
asmory remote match-profile ./profiles/core-v1.toml
asmory remote add-profile ./profiles/core-v1.toml
```

`match-profile` performs:

```text
Profile
  ↓ canonical Facets
Capability + exact interface Facet prefilter
  ↓
arbitrary active Provider candidates
  ↓
directional semantic matcher
  ↓
host Machine Contract filter
  ↓
accepted Providers
```

## Safe selection rule

Draft 0.1 has no global Evidence/trust ranking policy for choosing among
multiple semantically compatible Providers.

Therefore `add-profile` follows:

```text
0 compatible Providers -> fail
1 compatible Provider  -> install exact Package/Release/Variant/Artifact
2+ compatible Providers -> fail as ambiguous
```

It never chooses an arbitrary winner.

This deliberately leaves ranking to the later Evidence/trust policy milestone.

## Dependency handoff

After a unique semantic Provider is selected, installation enters the existing
Package dependency pipeline:

```text
semantic request
  ↓ unique Provider
Package / Release / Variant / Artifact
  ↓
verified cache
  ↓
project materialization
  ↓
Exact dependency
```

The current manifest v1 records the selected Package dependency. Persisting the
original Capability/Profile request as first-class manifest intent remains a
later manifest/resolver-schema extension.
