# Authenticated Remote Publication Staging — Draft 0.1

Asmory separates **uploading a release candidate** from **promoting an active
resolver-visible Release**.

This separation is intentional.

A forked or newly developed Package can produce exact source bytes and exact Git
provenance before it has complete, independently validated semantic and Machine
Variant metadata.

Asmory must not turn incomplete metadata into an immutable active Release.

## Flow

```text
clean Package commit
    ↓
asmory publish-prepare <package>
    ↓
deterministic source Artifact + canonical release-candidate.json
    ↓
asmory publish <package>
    ↓ authenticated upload
persistent staging store
    ↓
state = staged
resolvable = false
    ↓
future validation / promotion
active immutable Release
```

## CLI

```bash
ASMORY_PUBLISH_URL=https://registry.example
ASMORY_PUBLISH_TOKEN_FILE=~/.config/asmory/publish-token \
  asmory publish my-dot
```

Plain HTTP is accepted only for loopback development endpoints.

The client refuses token files with group/other permissions.

## Authentication

The staging write service stores only SHA-256 digests of bearer tokens.

Development token bootstrap:

```bash
asmory-registry-auth issue \
  /srv/asmory/auth.json \
  alice \
  ~/.config/asmory/publish-token
```

The token output is mode `0600`.

The auth database is also mode `0600`.

A token maps to a Registry publisher identity.

## Package ownership

The first successful candidate staging for a normalized Package name claims that
Package for the authenticated publisher.

Subsequent staging for that Package requires the same owner.

This is registry state, not user-controlled package manifest metadata.

Owner transfer and maintainer roles remain future work.

## Persistent layout

```text
data/
├── objects/
│   └── sha256/
│       └── <Artifact SHA-256>
├── projects/
│   └── <package>/
│       ├── owner.json
│       └── candidates/
│           └── <version>.json
├── incoming/
└── locks/
```

Artifact objects are content-addressed and immutable.

Candidate records are immutable by `(Package, version)`.

Repeated upload of the same exact object/candidate is idempotent.

Different bytes for an existing staged `(Package, version)` are rejected.

## Write protocol

Authenticated endpoints:

```text
PUT  /api/v1/staging/artifacts/sha256/<digest>
POST /api/v1/staging/releases

GET  /api/v1/staging/packages/<name>/<version>
GET  /api/v1/staging/packages/<name>/<version>/download
```

Health:

```text
GET /healthz
```

Artifact upload verifies:

- Content-Length;
- configured maximum size;
- SHA-256 identity;
- immutable no-clobber publication.

Candidate upload verifies:

- canonical JSON encoding;
- candidate schema/kind;
- normalized Package/version identity;
- clean Git provenance;
- source Artifact filename/size/digest;
- self-contained Package boundary declaration;
- referenced Artifact already exists;
- authenticated Package ownership;
- immutable Package/version staging.

## Why staging is not active publication yet

`release-candidate.json` currently proves source identity and provenance.

It does **not** yet carry the complete independently validated Release/Variant
contract needed by Asmory's resolver.

Therefore the write service returns:

```text
state      staged
resolvable false
```

Calling this distinction out is part of the security model, not an unfinished
error message.

A future promotion step will require complete semantic facets, Variant Machine
Contracts, conformance evidence and policy checks before creating the active
immutable Release.

## Deployment boundary

`asmory-registry-write` is a persistent authenticated write-side service.

The current syscall-only Assembly registry remains the read-only bootstrap
server.

Production deployment should place the write service behind TLS. The client
will not send bearer credentials over non-loopback plaintext HTTP.
