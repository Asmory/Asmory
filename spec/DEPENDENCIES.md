# Dependency Ergonomics — Draft 0.1

Asmory dependency resolution follows one UX principle:

> **Simple for ordinary users, controllable for experts, explicit inside the
> platform.**

## The problem

A machine-level resolver may know about:

```text
version
Capability
Semantic Facets
Profile
Provider
trust
architecture
ISA
ABI
object format
toolchain
microarchitecture
performance evidence
artifact digest
```

Requiring every user to write all of this would make the package manager
unusable.

Ignoring these details would make the resolver incorrect.

Asmory solves this by separating input syntax from normalized resolver state.

## Minimal dependency

```toml
[dependencies]
simd-dot = "1"
```

This means:

> Resolve a compatible and trusted implementation using the current default
> policy.

It does **not** mean the platform forgets the detailed constraints.

## Progressive control

Users can opt into more precision only when needed:

```toml
simd-dot = {
    version = "1",
    profile = "asmory/dot-core@1",
    trust = "reviewed"
}
```

Expert policy may additionally constrain Provider, semantic Facets, Machine
Variant, tuning, performance policy or artifact identity.

## Lowering

Every dependency form lowers to a canonical request:

```text
human syntax
    ↓
Profile/default expansion
    ↓
host facts
    ↓
Normalized Resolution Request
    ↓
resolver
```

The normalized request is the resolver API.

CLI syntax is only a frontend.

## Safe defaults

Defaults may fill in detail when the choice is non-semantic or when a
well-defined package/profile default exists.

Defaults must not silently change observable semantics.

When multiple incompatible semantic choices remain and no declared default is
safe, resolution must request a choice or fail clearly.

## Platform completeness

The registry stores or derives the complete form even when authors and consumers
use shorthand.

This allows:

```text
simple manifests
precise validation
deterministic resolution
explainable decisions
reproducible lockfiles
```

at the same time.

## Lockfile

The manifest records user intent.

The lockfile records the exact chosen reality:

```text
release
semantic fingerprint
Profile/version
Provider
Machine Variant
Artifact SHA-256
trust decision
resolver-policy version
```

The user should not need to write these details manually for them to be
preserved.

## Explain command

A future:

```bash
asmory explain simd-dot
```

should answer both beginner and expert questions:

```text
What did Asmory choose?
Why did it choose it?
Which values came from me?
Which came from defaults?
Which came from my machine?
Which candidates were rejected, and why?
Which performance evidence affected ranking?
```

This is how Asmory can hide complexity without becoming opaque.

## Default materialization

Resolution and storage are separate decisions.

After choosing an Artifact, the default workflow is:

```text
download / cache
      ↓
verify digest
      ↓
materialize into project
```

The project-local copy is intentionally visible and editable.

This reduces the need for users to pre-configure every advanced resolver option:
when deeper customization is needed, the actual dependency is already available
for inspection and modification.

The global cache remains immutable.

A modified local copy becomes a local derivative and must not be silently
treated as the original Artifact.

## First executable add pipeline

The first end-to-end implementation lowers:

```bash
asmory add simd-dot
```

through:

```text
resolver identity
    -> verified cache object
    -> safe materialization
    -> asm.toml intent
    -> asm.lock exact record
```

The local copy is independent and writable. The cache object is not.

The first MVP accepts one direct leaf dependency so state and reproducibility
rules remain explicit before multi-dependency editing is added.

## AI-assisted dependencies

A coding agent should be able to:

```text
open dependency source
read its manifest and semantic metadata
run its conformance suite
run its benchmark
modify the implementation
compare Performance Evidence
```

without requiring the user to manually restate all package metadata.

Advanced constraints remain available when automated selection itself needs to
be controlled.

## Dependency state after resolution

Materialization does not imply ownership.

The normative integrity states are **Exact** and **Modified**.

A resolved dependency begins Exact:

```text
source = registry
artifact = sha256:...
integrity = Exact
```

If the project-local tree changes, Asmory computes it as Modified:

```text
source = local-derivative
base_artifact = sha256:...
tree_hash = sha256:...
integrity = Modified
```

Integrity state is computed from content; it is not a mutable flag that local
metadata may simply claim.

A normal `asmory update` may replace an Exact dependency after updating the
lockfile.

It must not silently replace a Modified dependency.

## Executable local state lifecycle

Local edits are first-class state:

```text
asmory add
    -> Exact
edit local source
    -> Modified
asmory restore
    -> Exact
```

`asmory status` computes integrity from the current materialized tree and the
lockfile baseline. It performs no Registry access.

`asmory restore <package>` is deliberately destructive to local edits, but it
restores the exact locked Artifact rather than re-running current dependency
resolution.

A missing local tree is reported as `Missing` and can also be restored from the
locked Artifact.

## Reproducible Modified handoff

A Modified tree must not become invisible project state.

The first capture workflow is:

```text
edit local dependency
    -> Modified / uncaptured
asmory patch <package>
    -> Modified / captured-patch
asmory restore <package>
    -> Exact / saved patch remains
asmory reapply <package>
    -> Modified / captured-patch
```

Captured deltas live under `.asmory/patches/`, which is intentionally not
ignored by the workspace.

This allows Git to carry the divergence while `.asmory/deps/` remains a
reconstructible working materialization.

`reapply` refuses to overwrite unrelated uncaptured local work.

## Explicit full-source ownership

Patch capture preserves a derivative relative to a Registry base.

Vendoring is the explicit alternative when the project wants the complete tree
to become ordinary project-owned source:

```text
registry-derived .asmory/deps/<package>
    -> asmory vendor <package>
project-owned vendor/<package>
```

The manifest becomes a local path dependency and the whole vendored tree is
Git-visible.

The lockfile retains Registry ancestry but marks the active source as `vendor`.

Registry-oriented restore/patch/reapply commands refuse to silently retake
control of project-owned source.

## Leaf-first default

Asmory v1 should default to direct, leaf dependencies.

Dependencies of dependencies are not part of the initial resolution model.

If future Composite packages are introduced, their closure should preferably be
resolved and flattened before consumer installation.

See `LEAF_DEPENDENCIES.md`.
