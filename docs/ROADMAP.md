# Asmory roadmap

## M0 — Registry shell

- [x] x86-64 syscall HTTP server
- [x] embedded HTML/CSS/JS/JSON assets
- [x] package index and detail page
- [x] working search/filter/sort UI
- [x] downloadable example package
- [x] ISA/ABI/target specification drafts

## M1 — Public project infrastructure

- [x] GitHub Organization and public repository
- [x] GitHub Actions CI
- [x] GitHub Pages deployment
- [x] contribution/security documentation
- [x] Release workflow
- [x] Organization profile source

## M2 — CLI resolver

- [x] Assembly CLI executable
- [x] `asmory target`
- [x] x86-64 CPUID/XGETBV host ISA detection
- [x] x86-64-v1/v2/v3/v4 baseline classification
- [x] bootstrap `asmory search`
- [x] bootstrap `asmory info`
- [x] `asmory resolve` bootstrap Machine Contract filtering
- [x] `asmory explain` resolution trace
- [x] `asmory audit` Artifact/Review/Advisory separation
- [x] Registry Release JSON -> generated Assembly metadata bridge
- [ ] remote registry client
- [ ] `asmory init`
- [ ] `asmory add`
- [x] bootstrap target/Variant compatibility resolution
- [ ] lockfile

## M3 — Real index/storage

- [x] Draft 1 JSON Project/Release/Variant/Artifact schema
- [x] Project/Release/Variant/Artifact records
- [x] SHA-256 integrity metadata for source archives
- [x] checksum + immutable Release semantics specified
- [x] normalized global Project names + owner/maintainer model specified

- [ ] real persistent storage backend
- [ ] authenticated publish/write API
- [ ] server-side search index

## M2.5 — Semantic Type System MVP

- [x] canonical Semantic Facet document
- [x] SHA-256 semantic fingerprint
- [x] directional requirements / guarantees matcher
- [x] exact / minimum / maximum / contains / subset relations
- [x] Profile expansion and compatibility-island example
- [x] Capability and Profile Registry resources
- [x] compositional conformance coverage metadata
- [x] CLI `asmory semantics` / `asmory match`
- [ ] arbitrary remote Provider candidate index
- [ ] resolver Facet inverted indexes
- [ ] namespaced extension Facets

## M3.5 — Evidence loop

- [x] Performance Evidence API for exact Release Artifacts
- [x] Artifact + Performance Contract digest binding
- [x] alternating AB/BA Variant benchmark protocol
- [x] local Evidence validation
- [x] machine-readable optimization report
- [x] CLI `asmory evidence`
- [ ] append-only remote Evidence submission
- [ ] hardware cohort indexing
- [ ] accepted Evidence driven Variant ranking

## M4 — Build/link pipeline

- [ ] GAS/NASM/LLVM-MC adapters
- [ ] object-level dependency graph
- [ ] section GC defaults
- [ ] archive/static library support
- [ ] symbol/export contract validation

## M5 — Publish/security

- [ ] authentication
- [ ] package signing/provenance
- [ ] immutable releases/yanking
- [ ] ownership transfer
- [ ] malicious object/source scanning
