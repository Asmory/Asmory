## Integrity terminology

`Clean` and `Dirty` are convenient development terms, but they must not be
interpreted as security labels.

The normative integrity states are:

```text
Exact
    local content matches the immutable Artifact identity

Modified
    local content differs from the immutable Artifact identity
```

User interfaces may still use `Clean` / `Dirty` as secondary wording if the
meaning is explicit, but should prefer:

```text
Integrity: Exact
Integrity: Modified
```

This prevents `Clean` from being misread as `Safe`.

Security review state is defined separately in `SECURITY_REVIEW.md`.

# Dependency States — Draft 0.1

Asmory supports two first-class dependency states.

The goal is to keep dependencies locally inspectable without allowing invisible
local modifications to destroy reproducibility.

## 1. Clean dependency

A Clean dependency is byte-identical to a verified Registry Artifact.

Conceptually:

```text
Registry Artifact
      ↓
SHA-256 verified
      ↓
global immutable cache
      ↓
project-local materialization
```

The project-local copy may be visible to humans and AI agents, but while it
remains unchanged its identity is still the Registry Artifact.

The lockfile is sufficient to reproduce it:

```text
package
release
Provider
Machine Variant
Artifact SHA-256
semantic fingerprint
```

A Clean dependency normally does **not** need to be committed to Git.

It can be regenerated from:

```text
asm.toml
+
asm.lock
+
Registry/cache
```

## 2. Dirty dependency

The moment a local dependency differs from its base Artifact, it becomes Dirty.

Conceptually:

```text
base Artifact SHA-256
      +
local modified tree
      ↓
Dirty dependency
```

A Dirty dependency must never continue pretending to be the original Registry
Artifact.

Asmory should record:

```text
base_artifact_sha256
local_path
local_tree_hash
dirty = true
```

## 3. Dirty dependencies must become explicit

Asmory should not allow a Dirty dependency to remain an invisible local fact.

Before a reproducible release, project handoff or publication, the user must
choose an explicit representation.

Possible workflows:

```bash
asmory vendor foo
asmory patch foo
asmory fork foo
asmory restore foo
```

### vendor

The full modified dependency becomes project-owned source and should be tracked
by Git.

### patch

The project records:

```text
immutable base Artifact
+
deterministic patch set
```

Both must be sufficient to reconstruct the exact modified source tree.

### fork

The local derivative becomes a new independently versioned
Implementation/Variant that may later be published.

### restore

Discard local changes and return to the locked immutable Artifact.

## 4. Publishing rule

A project must not publish while depending on an unrecorded Dirty dependency.

Conceptually:

```text
clean dependency
    → publishable

vendored dependency
    → publishable

base + deterministic patch
    → publishable

explicit fork
    → publishable

unrecorded dirty working tree
    → reject
```

This is a reproducibility rule, not a restriction on experimentation.

Local development is allowed to be messy.

Released state must be reconstructible.

## 5. Git policy

Asmory therefore follows:

> **Local-visible by default, Git-tracked when diverged.**

Clean dependency:

```text
visible locally
not normally committed
lockfile reconstructs it
```

Dirty dependency:

```text
visible locally
must become explicit
Git/vendor/patch/fork reconstructs it
```

There should be no third state meaning:

```text
"the real dependency only exists on the original developer's disk"
```

## 6. Cache safety

The immutable global cache must never be mutated by editing a local dependency.

Writable hard links from project materializations into the cache are forbidden.

Use:

```text
reflink / copy-on-write
or
ordinary copy
```

so local edits naturally detach from the cached object.

## 7. AI workflow

This state model is designed for AI-assisted optimization:

```text
asmory add foo
      ↓
Clean local copy
      ↓
AI inspects / edits foo
      ↓
Dirty detected
      ↓
tests + conformance + benchmark
      ↓
vendor / patch / fork / restore
```

AI is free to experiment.

Asmory is responsible for making the final dependency state explicit and
reproducible.
