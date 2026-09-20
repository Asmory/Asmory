# Security Review Model — Draft 0.1

Asmory must never equate artifact integrity with artifact safety.

This distinction is fundamental.

```text
Exact Artifact
    means:
        the local tree exactly matches the declared immutable Artifact

It does NOT mean:
        safe
        reviewed
        non-malicious
        trustworthy
```

Likewise:

```text
Modified / Dirty
    means:
        the local tree differs from the immutable base Artifact

It does NOT mean:
        dangerous
        malicious
        less trustworthy by definition
```

Integrity and safety are separate axes.

---

## 1. Three independent state axes

Asmory models at least three independent security-related states.

### Integrity State

```text
Exact
Modified
Unknown
```

This answers:

> Is this content identical to the Artifact identity it claims to represent?

### Review State

```text
Unreviewed
Machine-Scanned
AI-Reviewed
Human-Reviewed
Reviewed-Anchor
Suspicious
Needs-Review
```

This answers:

> What review evidence exists for this exact Artifact or Delta?

### Registry Safety State

```text
Normal
Under-Review
Warned
Quarantined
Revoked
```

This answers:

> What action has the registry/community taken based on available evidence?

These states must not be collapsed into one badge.

A package can therefore be:

```text
Integrity: Exact
Review:    Unreviewed
Safety:    Normal
```

This is a valid and common state.

It means:

> The bytes are exactly what was published, but no strong safety claim is being
> made.

---

## 2. Clean is not a security word

User interfaces should avoid presenting a green `Clean ✓` badge if it can be
misread as "safe".

Prefer explicit language:

```text
Source integrity
  Exact Artifact

Security review
  Not reviewed

Known Advisories
  None known
```

`None known` is intentionally different from `Safe`.

Asmory should communicate evidence, not certainty it cannot prove.

---

## 3. Reviewed Anchor

Delta review is only strong when its baseline deserves trust.

Asmory therefore introduces a **Reviewed Anchor**.

A Reviewed Anchor is an exact Artifact with sufficient review evidence to serve
as a trusted comparison baseline.

Conceptually:

```text
Artifact A
    ↓
structural analysis
    ↓
capability anomaly scan
    ↓
AI and/or human semantic review
    ↓
conformance / provenance checks
    ↓
Reviewed Anchor A
```

Future versions can then use A as a review baseline.

```text
Reviewed Anchor A
        ↓
Deterministic Delta
        ↓
Artifact B
        ↓
incremental review
        ↓
Reviewed Anchor B
```

This is the core rule:

> **Full review establishes an anchor; delta review maintains the chain.**

---

## 4. Unknown baselines do not transmit trust

A malicious first release can be byte-exact and still be malicious.

Therefore:

```text
Unreviewed Artifact A
       ↓
small Delta
       ↓
Artifact B
```

does not imply that B inherits any meaningful safety confidence from A.

A small diff against an untrusted baseline only proves that little changed.

It does not prove that what remained unchanged was safe.

---

## 5. Review continuity can break

A Reviewed Anchor should not transmit review confidence indefinitely.

Certain events can break review continuity and require renewed broad review.

Examples include:

```text
package ownership transfer
maintainer/signing-key change
source provenance change
build system change
major toolchain change
large-scale rewrite
generated source replacing handwritten source
semantic model change
new executable build hooks
binary reproducibility loss
large unexplained binary delta
```

The exact reset policy can evolve, but the principle is:

> Review confidence is evidence-linked, not hereditary.

---

## 6. Deterministic Delta

Asmory should define the Delta before an AI or human reviews it.

A Delta may include:

```text
source file changes
normalized Assembly changes
symbol changes
section changes
relocation changes
export changes
ABI changes
Machine Contract changes
Semantic Facet changes
syscall/import changes
control-flow changes
memory-access changes
binary/disassembly changes
```

The Delta itself should have an immutable identity:

```text
base_artifact
target_artifact_or_tree
delta_hash
analysis_version
```

> **AI reviews deltas; Asmory defines deltas.**

---

## 7. Review must not rely on textual diff alone

Assembly can be intentionally transformed in ways that make textual diff noisy:

```text
register renaming
label renaming
instruction reordering
section movement
equivalent instruction substitution
generated padding / junk instructions
```

This creates a potential **diff laundering** attack.

Therefore Asmory should support multiple views:

```text
Source Delta
Normalized Assembly Delta
Symbol Delta
Control-Flow Delta
Binary / Disassembly Delta
Behavioral Delta
Semantic Metadata Delta
```

A suspicious change that disappears in one representation may remain obvious in
another.

---

## 8. Capability-aware anomaly detection

A package's declared Capability provides useful context for security review.

Example:

```text
Capability:
    math.dot.f32
```

Expected behavior is narrow:

```text
read input memory
perform arithmetic
return a scalar
```

Unexpected behavior such as:

```text
network access
filesystem access
process creation
dynamic executable memory
credential-file access
```

should produce a **Capability Anomaly**.

This does not prove malicious intent.

It produces a high-value review signal.

Conceptually:

```text
Declared Capability
        ↓
Expected behavioral envelope
        ↓
Observed static/dynamic behavior
        ↓
Capability Anomaly Evidence
```

---

## 9. Full review pipeline

A new or unanchored Artifact can be reviewed with a structured pipeline:

```text
Artifact
   ↓
integrity verification
   ↓
static structural inventory
   ↓
Capability anomaly detection
   ↓
AI semantic review
   ↓
conformance / sandbox / provenance checks
   ↓
review evidence
   ↓
Reviewed Anchor (if policy permits)
```

The AI should not be asked to discover every objective fact itself.

Asmory should precompute facts such as:

```text
syscalls
imports
exports
sections
relocations
indirect calls
filesystem/network indicators
W+X regions
semantic metadata
Machine Contract
```

The model then focuses on semantic reasoning.

---

## 10. Incremental review pipeline

For a descendant of a Reviewed Anchor:

```text
Reviewed Anchor
       ↓
deterministic Delta
       ↓
machine security scan
       ↓
AI incremental review
       ↓
conformance / performance / provenance evidence
       ↓
new review state
```

This keeps review cost proportional to meaningful change instead of repository
size.

---

## 11. Review Evidence is not a proof of safety

Review status must remain carefully worded.

Good terms:

```text
reviewed
no obvious issue found
needs human review
suspicious
review incomplete
```

Avoid:

```text
safe
guaranteed secure
verified harmless
```

unless a future formal method can justify such language for a very narrow claim.

---

## 12. Review evidence attaches to exact identities

Every review result must bind to exact objects:

```text
Artifact digest
or
base Artifact + Delta hash + target tree hash
```

A review result for one Artifact must not silently transfer to another Artifact
with the same package name or version label.

---

## 13. Design principles

Asmory security review follows these rules:

```text
Exact != Safe

Modified != Dangerous

Small Diff != Safe Diff

Delta Review requires a Reviewed Anchor

Review confidence is evidence-linked, not hereditary

AI interprets; Asmory measures and anchors
```
