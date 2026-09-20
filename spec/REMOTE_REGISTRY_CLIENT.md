# Remote Active Registry Client — Draft 0.1

Asmory's bootstrap index remains useful for development, but promoted Packages
must be consumable without rebuilding the CLI.

This milestone connects the active publication backend to normal dependency
consumption.

## Active index

The Registry maintains a deterministic persistent index derived only from
active immutable Releases:

```text
data/
└── active/
    ├── index.json
    └── projects/
        └── <package>/
            └── releases/
                └── <version>.json
```

Staged-only candidates never appear in this index.

The index is rebuilt:

- after a successful first promotion;
- at write-service startup from immutable active Release records.

Therefore the search view is derived state, not an additional source of truth.

## Read API

```text
GET /api/v1/packages
GET /api/v1/packages?q=<text>
GET /api/v1/packages?capability=<capability>&arch=<arch>
GET /api/v1/packages/<name>
GET /api/v1/packages/<name>/versions
GET /api/v1/packages/<name>/<version>
GET /api/v1/packages/<name>/<version>/download
```

Search results contain only active resolver-visible Packages.

## Remote client

Explicit remote operations:

```bash
asmory remote search [query]
asmory remote info <package>
asmory remote versions <package>
asmory remote resolve <package>
asmory remote add <package>
```

The normal CLI also falls back to the active Registry for arbitrary promoted
Package names:

```bash
asmory search my-dot
asmory info my-dot
asmory versions my-dot
asmory resolve my-dot
asmory add my-dot
```

The embedded `simd-dot` bootstrap record remains an offline fast path.

## Resolver order

Remote add follows the same correctness-first order:

```text
Package name
    ↓
latest active Release
    ↓
host target
    ↓
hard arch / OS / object / ABI compatibility
    ↓
ISA baseline legality
    ↓
required ISA feature legality
    ↓
compatible Variant selection
    ↓
exact Artifact SHA-256
    ↓
existing cache/acquire/materialize/add transaction
```

The client asks the native Assembly CLI for `asmory target`, so host ISA
selection continues to use Asmory's CPUID/XGETBV logic rather than trusting
generic platform strings for AVX-family usability.

## Transport

`ASMORY_REGISTRY_URL` selects the active Registry endpoint.

External plaintext HTTP is rejected. Loopback HTTP remains available for local
development.

Artifact download still goes through the existing verified acquisition and
content-addressed cache pipeline.

## Local lifecycle continuity

Once remotely added, a promoted Package is indistinguishable from another
registry-derived Exact dependency for local lifecycle purposes:

```text
remote active Release
    ↓ add
Exact
    ↓ edit
Modified
    ↓
restore / patch / vendor / fork
```

A remote Registry outage does not prevent local status or cache-backed restore.
