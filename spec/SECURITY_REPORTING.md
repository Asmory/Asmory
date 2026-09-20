# Security Reporting and Advisories — Draft 0.1

Asmory should make dangerous-code reporting fast enough that users actually use
it, precise enough that maintainers can reproduce it, and resistant to abuse.

The security pipeline has three distinct objects:

```text
Review Evidence
    What looks suspicious?

Security Report
    Who is reporting what exact object, and why?

Security Advisory
    What risk has the registry/community confirmed and propagated?
```

A Report is not automatically an Advisory.

## 1. Fast reporting

Reporting should be available from both CLI and registry UI.

Conceptually:

```bash
asmory report simd-dot
asmory report --artifact sha256:...
asmory report --dependency simd-dot --reason suspicious-code
```

The package page should expose a visible `Report security issue` action.

A basic report should require only:

```text
target
category
short description
contact preference
```

Everything else should be auto-attached where possible.

## 2. Reports bind to exact identities

Asmory should never accept an ambiguous report such as:

```text
"foo is malicious"
```

without recording the exact object under discussion.

A report should bind to one or more of:

```text
Project / Release
Provider
Source Artifact SHA-256
Binary Artifact SHA-256
local tree hash
Review Delta hash
semantic fingerprint
Machine Variant
```

If the report is generated from a Dirty dependency, Asmory can automatically
attach:

```text
base Artifact
dirty tree
patch hash
changed files
changed symbols
new syscalls/imports
ABI changes
semantic changes
```

This gives reviewers a reproducible starting point immediately.

## 3. Confidential by default for serious security issues

Reports that may disclose an exploitable vulnerability or active supply-chain
attack should be private by default.

Public discussion can happen after triage or coordinated disclosure.

Less sensitive reports such as misleading metadata or spam may be public.

The reporter should not need to understand disclosure policy to choose safely.

## 4. Categories

Initial categories may include:

```text
suspected malicious code
unexpected filesystem/network behavior
binary/source provenance mismatch
compromised maintainer or signing identity
dependency shadowing/confusion
unsafe build behavior
semantic misrepresentation
known vulnerability
tampered Artifact
other
```

Categories are triage hints, not proof.

## 5. Report state

A report can move through:

```text
submitted
triaged
needs-more-information
confirmed
rejected
duplicate
resolved
```

The state transition history should be auditable.

## 6. Artifact safety state

Artifact safety state is separate from report state.

Possible states:

```text
normal
under-review
warned
quarantined
revoked
```

A single unverified user report should not automatically quarantine an Artifact.

However, strong machine-verifiable evidence can justify rapid temporary action,
for example:

```text
digest mismatch
signature/provenance failure
confirmed malicious binary/source mismatch
registry-side integrity failure
```

Human/community/security triage can then confirm longer-lived action.

## 7. Fast propagation

Once an Advisory exists, users should learn about it without needing to revisit
the package page.

Security metadata should be available through a compact signed advisory feed.

Commands that touch dependencies should refresh advisory state when network
access is available:

```text
asmory add
asmory update
asmory build
asmory status
asmory audit
```

Offline operation may use the most recent cached advisory snapshot and should
show its age.

## 8. Lockfiles do not hide advisories

A lockfile pins identity.

It must not suppress later security information about that identity.

If:

```text
asm.lock -> Artifact SHA-256 A
```

and A later becomes quarantined, Asmory should surface that fact even though the
lockfile remains unchanged.

Depending on user policy:

```text
warn
block build
require explicit override
```

The resolver must not silently replace A with another Artifact merely because of
an Advisory. Reproducibility and security response are separate decisions.

## 9. Overrides are explicit and auditable

Advanced users may need to continue using a warned or quarantined Artifact for
forensics, compatibility testing or emergency operation.

An override should require explicit intent, for example conceptually:

```bash
asmory build --allow-quarantined sha256:...
```

The decision should be visible in logs/status output.

No global silent `ignore all security warnings` default should exist.

## 10. AI-assisted report creation

Asmory can make reporting dramatically easier by converting deterministic review
data into a report draft.

Conceptually:

```text
Clean Artifact
      ↓
Dirty / suspicious object
      ↓
deterministic Delta
      ↓
AI semantic review
      ↓
"Report this finding?"
      ↓
prefilled Security Report
```

The AI may summarize:

```text
what changed
why it looks suspicious
which code paths are involved
which assumptions remain uncertain
```

Asmory supplies exact hashes and structural facts.

> **AI explains the risk; Asmory anchors the report to reproducible evidence.**

## 11. Reporter safety and anti-abuse

The reporting system must not become a harassment or reputation weapon.

Therefore:

```text
reports are evidence, not verdicts
reporter identity may be protected where policy allows
rate limits / spam controls apply
duplicate reports are merged
public package labels come from Advisory state, not raw report count
```

Popularity of a report is not proof of maliciousness.

## 12. Advisory identity

An Advisory should be immutable/versioned and machine-readable.

Conceptually:

```text
advisory ID
revision
affected Artifact digests
affected releases/Variants
severity
status
summary
evidence references
recommended action
published time
updated time
```

Corrections create a new revision rather than rewriting history invisibly.

## 13. Transparency

Confirmed Advisories and registry actions should be auditable.

Asmory should eventually maintain an append-only transparency record for events
such as:

```text
Artifact quarantined
Artifact restored
Artifact revoked
Advisory published
Advisory corrected
signing identity revoked
```

This protects both users and publishers from silent administrative changes.

## 14. Design principle

> **Make reporting cheap, make accusations precise, make enforcement evidence-based,
> and make confirmed danger propagate quickly.**

## Reports may target an Exact but unreviewed Artifact

A security report does not require local modification.

An Artifact can be:

```text
Integrity: Exact
Review:    Unreviewed
```

and still contain malicious or dangerous behavior.

Reports can therefore target:

```text
an exact Registry Artifact
a Binary Artifact
a Dirty/Modified local derivative
a Review Delta
a provenance relationship
```

The reporting system must never imply that Exact/clean content is exempt from
security investigation.

## Reviewed Anchor information

When a report concerns a descendant of a Reviewed Anchor, the report should
include:

```text
anchor Artifact
Delta hash
review continuity state
changed security surface
```

If review continuity has been broken, the report should say so explicitly.
