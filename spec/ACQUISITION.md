# Artifact Acquisition — Draft 0.1

Acquisition is the transport stage between resolution and storage.

```text
resolved exact Artifact identity
        ↓
transport bytes into a temporary file
        ↓
SHA-256 verification
        ↓
atomic publication to the requested destination
```

This stage does **not** define cache policy, extraction policy, local
materialization, or dependency state.

## Identity comes before transport

The acquisition backend receives an expected Artifact SHA-256 from the resolver.
It does not fetch a digest from the same download response and then treat that
as independent proof.

## Fail closed

The destination must not become visible as a successful Artifact until digest
verification passes. Existing destinations are never overwritten.

## No execution and no extraction

Acquisition does not execute package code, run build scripts, extract archives,
or mutate `asm.toml` / `asm.lock`.

Archive path and symlink safety belong to the later materialization stage.

## Bootstrap transport backend

The current Assembly CLI delegates byte transport and SHA-256 computation to an
explicit companion helper using system `curl` and `sha256sum`.

This is an implementation bootstrap, not semantic authority. Resolver identity
remains in the Assembly CLI / generated Registry metadata.

## Transport policy

Remote registries require HTTPS. Plain HTTP is accepted only for loopback
addresses in the local development Registry. Redirect protocols are restricted
to HTTP/HTTPS.

## Relationship to future cache

The next stage is:

```text
verified Artifact
      ↓
content-addressed immutable cache
```

The explicit acquisition destination remains caller-selected. A separate cache
layer now consumes verified acquisition without changing acquisition semantics.
