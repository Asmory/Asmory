# Asmory roadmap

## M0 — Registry shell

- [x] x86-64 syscall HTTP server
- [x] embedded HTML/CSS/JS/JSON assets
- [x] package index and detail page
- [x] working search/filter/sort UI
- [x] downloadable example package
- [x] ISA/ABI/target specification drafts

## M1 — Real index/storage

- package index binary format or compact JSON schema
- package/version/Variant records
- content-addressed source archives
- checksums and package immutability
- publisher namespace model

## M2 — CLI resolver

- `asmory init`
- `asmory search`
- `asmory info`
- `asmory add`
- host ISA detection
- target/Variant compatibility resolution
- lockfile

## M3 — Build/link pipeline

- GAS/NASM/LLVM-MC adapters
- object-level dependency graph
- section GC defaults
- archive/static library support
- symbol/export contract validation

## M4 — Publish/security

- authentication
- package signing/provenance
- immutable releases/yanking
- ownership transfer
- malicious object/source scanning
