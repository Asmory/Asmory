# Content-addressed Artifact Cache — Draft 0.1

Asmory's global cache is an optimization, never an identity authority.

The Draft 0.1 source Artifact layout is:

```text
${ASMORY_CACHE_HOME}/objects/sha256/<artifact-sha256>
```

or:

```text
${XDG_CACHE_HOME}/asmory/objects/sha256/<artifact-sha256>
```

with fallback:

```text
${HOME}/.cache/asmory/objects/sha256/<artifact-sha256>
```

The object path contains the Artifact bytes themselves.

## Content identity

The cache key is only `SHA-256(Artifact bytes)`.

It is not package name, release, Provider, Capability, Variant, or local path.

Two identities that legitimately reference identical bytes may therefore share
one object.

## Cache hits are verified

The digest-shaped path is never trusted by itself. Every hit is re-hashed and
must equal the resolver-provided Artifact SHA-256.

A corrupt object is a hard error. Draft 0.1 deliberately refuses silent repair
or replacement so corruption remains observable.

## Cache misses

A miss delegates to verified Artifact acquisition.

After acquisition has already verified the bytes, cache publication uses an
atomic no-clobber hard link on the same filesystem. The temporary staging link
is removed immediately.

The surviving object is mode `0444`.

Read-only mode is not the trust mechanism; digest verification is.

## Global cache is not project state

`asmory cache` does not require a workspace.

Cache presence does not mean:

```text
the project depends on the package
the package is in asm.lock
the source is materialized in .asmory/deps
```

`asmory add` consumes the cache to create project state; cache presence by itself still implies none of those things.

## No extraction

This stage stores exact archive bytes only.

Archive validation, path/symlink safety, extraction and local working copies are implemented by materialization. `asmory status` computes local Exact/Modified state independently from cache presence.
