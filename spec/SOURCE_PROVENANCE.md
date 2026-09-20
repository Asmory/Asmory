# Git Source Provenance — Draft 0.1

Git provenance explains where a Release was developed.

It does not define Package identity and is not resolver authority.

A Release may record:

```json
{
  "source": {
    "kind": "git",
    "repository": "https://github.com/Asmory/Asmory",
    "commit": "<40-hex commit>",
    "subdir": "examples/simd-dot",
    "worktree_dirty": false
  }
}
```

`repository` identifies the development repository.

`commit` identifies the Git snapshot used as provenance.

`subdir` identifies the Package root within a multi-Package repository.

Together they let humans and development tooling locate upstream source without
turning repository layout into Registry identity.

## Resolver separation

The resolver must not select or reject a Release because of Git repository,
commit layout or monorepo membership.

Resolution remains:

```text
Package
 -> Release
 -> semantics
 -> machine legality
 -> trust
 -> comparable performance evidence
 -> Variant + Artifact
```

Artifact SHA-256 remains the exact distribution identity.

## Dirty development builds

Local development metadata may report `worktree_dirty = true` when the Package
root differs from the referenced commit.

This is useful during local development and testing but is not valid publish
provenance.

A publish path must require a clean Package root before accepting Git provenance
as an exact source reference.

## One commit, many Packages

A single Git commit may be provenance for several independently versioned
Packages.

A Git commit or Git tag is not itself an Asmory Release.

A commit may change multiple Packages while only one Package is published.

## Publication candidate

`asmory publish-prepare <package>` requires clean Package Git provenance and
creates a deterministic local release candidate. For forked Packages the
candidate carries `[origin]` ancestry alongside `repository + commit + subdir`
and the exact source Artifact SHA-256.

The candidate is not a remote publication. Authentication and Registry writes
remain separate M3 work.
