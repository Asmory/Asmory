# Project-local Materialization — Draft 0.1

Materialization converts a verified immutable source Artifact into a writable,
visible project-local working tree.

```text
verified cache object
        ↓
private snapshot
        ↓
archive structural validation
        ↓
safe extraction into staging
        ↓
complete project-local tree
        ↓
publish .asmory/deps/<package>
```

The cache object is never used as a writable project working tree.

## Security boundary

Before extraction, Draft 0.1 rejects absolute member paths, `.` / `..`
traversal components, members outside the package root, duplicate normalized
paths, symbolic links, hard links, devices, FIFOs, unsupported member types,
oversized single files, excessive member counts, and excessive expanded size.

The MVP deliberately rejects links rather than trying to prove that an
arbitrary link graph remains confined.

## Stable input bytes

The materializer first copies the cache object to a private staging snapshot,
then hashes and extracts that same snapshot. This avoids a hash-then-extract
race against a mutable local cache pathname.

## No writable hardlinks into cache

Extraction creates independent project files.

Editing `.asmory/deps/foo/...` must never mutate the content-addressed cache.

## Publication

Extraction happens under `.asmory/.staging/`. The finished tree is published
into `.asmory/deps/<package>` only after validation and extraction succeed.
Existing dependency destinations are never replaced.

## File modes

Materialized source is intentionally editable. Directories normalize to `0755`;
regular files normalize to `0644` plus their original executable bits. Special
permission bits and group/world writes are removed.

## Relationship to integrity state

Materialization does not store a mutable `Exact = true` flag. `asmory add`
records a deterministic `asmory-tree-v1` baseline derived from the safely
materialized locked Artifact. `asmory status` recomputes the current tree and
therefore reports Exact/Modified from actual local content.
