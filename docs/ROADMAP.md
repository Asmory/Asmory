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
- [x] `asmory init`
- [x] `asmory add` first leaf dependency MVP
- [x] bootstrap target/Variant compatibility resolution
- [x] project workspace + empty lockfile v1 foundation
- [x] resolved dependency records in lockfile v1

## M2.75 — Local workspace foundation

- [x] native syscall-only `asmory init`
- [x] `asm.toml` user-intent manifest
- [x] generated `asm.lock` exact-resolution foundation
- [x] `.asmory/deps/` local-visible materialization root
- [x] non-overwriting / partial-state initialization rules
- [x] `asmory acquire` bootstrap transport command
- [x] fail-closed digest verification + atomic no-clobber output
- [x] Exact / Modified terminology in dependency UX
- [x] Artifact acquisition + SHA-256 verification
- [x] SHA-256-only global object identity
- [x] verified cache hits and corruption rejection
- [x] atomic no-clobber cache publication
- [x] content-addressed global cache
- [x] safe project-local materialization
- [x] archive traversal/link/special-file rejection
- [x] transactional first dependency manifest + lockfile update
- [x] offline add from verified cache
- [x] computed Exact / Modified status
- [x] deterministic materialized-tree fingerprint v1
- [x] local-only `asmory status`
- [x] Missing operational state
- [x] `asmory restore` exact locked-Artifact recovery
- [x] restore rollback / corrupt-cache preservation tests
- [x] deterministic local delta capture
- [x] Git-visible `.asmory/patches/` handoff
- [x] captured/uncaptured divergence status
- [x] offline transactional `asmory reapply`
- [x] explicit vendor transition
- [x] project-owned path dependency + Registry provenance
- [x] transactional vendor ownership handoff
- [x] Registry lifecycle refusal for vendored source
- [x] multi-package repository workspace model
- [x] explicit Package-root self-contained boundary
- [x] deterministic workspace-member source packaging
- [x] existing Release identity preserved across workspace metadata migration
- [x] publish provenance model: repository + commit + subdir
- [x] dirty-worktree publish provenance guard
- [x] Package-level fork identity transition
- [x] fork ancestry binds original Artifact + actual local source tree
- [x] deterministic local publication candidate
- [x] authenticated remote candidate + Artifact staging transition
- [x] persistent staged Package/version ownership state
- [x] server-derived promotion from staged candidate to active Release
- [x] server-side semantic fingerprint recomputation during promotion
- [x] public resolver-facing active Package/Release/download API

## M3 — Real index/storage

- [x] Draft 1 JSON Project/Release/Variant/Artifact schema
- [x] Project/Release/Variant/Artifact records
- [x] SHA-256 integrity metadata for source archives
- [x] checksum + immutable Release semantics specified
- [x] normalized global Project names + owner/maintainer model specified

- [x] persistent content-addressed publication staging backend
- [x] bearer-token authenticated candidate/Artifact write API
- [x] immutable + idempotent staged Package/version records
- [x] active Release promotion/index backend
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
