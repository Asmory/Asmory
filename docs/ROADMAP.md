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
- [ ] remote registry client
- [ ] `asmory init`
- [ ] `asmory add`
- [ ] target/Variant compatibility resolution
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
