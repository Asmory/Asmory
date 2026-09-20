# Asmory Design Philosophy

Asmory is a package ecosystem for machine-level code, but its goal is not merely
to put Assembly files behind a package index.

Its deeper goal is to make machine-level implementations:

- discoverable;
- substitutable when they really are compatible;
- free to diverge when better semantics are possible;
- measurable on real hardware;
- independently maintainable by different people;
- selectable by a resolver without pretending machines are interchangeable.

The central design tension is simple:

> We need enough structure to reuse implementations, but not so much structure
> that yesterday's interface becomes tomorrow's law.

Asmory therefore treats standards as **tools for compatibility**, not as
authorities over innovation.

---

## 1. Six layers

Asmory separates six questions that are often incorrectly collapsed.

```text
Capability
    What problem does this solve?

Semantic Facets
    What observable behavior does it require and guarantee?

Profile / Contract
    Is there a convenient name for a common Facet bundle?

Implementation
    Who wrote one concrete solution?

Machine Variant
    Where can this implementation run, and what was it tuned for?

Evidence
    Does it conform, can it be trusted, and how fast is it?
```

These layers are deliberately independent.

A package is not forced to join an existing Profile merely because it solves the
same problem. A Profile is not allowed to turn performance preferences into
correctness requirements. A benchmark result does not prove semantic
compatibility. Passing semantic tests does not automatically make native code
trusted.

---

## 2. Capability is discovery, not authority

A Capability is the broadest useful description of a problem.

Examples:

```text
math.dot.f32
memory.copy.bytes
crypto.sha256.compress
json.scan.structurals
audio.fft.complex-f32
```

A Capability does **not** define a complete API or standard.

Its job is to answer:

> What other implementations are trying to solve roughly the same problem?

This is intentionally weak. It allows the registry to group innovation without
declaring one semantic model to be official forever.

A Capability should therefore have no inherent authority over the
implementations grouped beneath it.

---

## 3. Semantic Facets are the source of truth

Asmory does not model every semantic difference as a new named standard.

Instead, observable semantics are described through a bounded set of structured
**Facets**.

Typical Facets include:

```text
interface
numeric behavior
memory behavior
aliasing
alignment
determinism
error behavior
concurrency
side effects
```

A Facet must be:

1. observable by callers;
2. meaningful for substitution;
3. as orthogonal as practical;
4. structured rather than exploded into dozens of unrelated booleans;
5. cheap for a resolver to compare.

For example:

```toml
[semantics.interface]
shape = "dot-f32-v1"

[semantics.numeric]
mode = "ieee-relaxed-reduction"
absolute_error = 1e-6
relative_error = 1e-5

[semantics.memory]
inputs = "read-only"
alignment = "arbitrary"
aliasing = "allowed"

[semantics.determinism]
level = "same-machine"
```

The Facets, after canonicalization, are the semantic truth.

---

## 4. Profile / Contract is a typedef, not a constitution

When a Facet combination becomes common, the community may give it a name.

For example:

```text
asmory/dot-core@1
```

may expand to a known set of Facets.

Conceptually:

```text
Profile / Contract = named immutable Facet bundle
```

It behaves more like a `typedef` than a law.

A package may:

- use a Profile directly;
- extend a Profile;
- override part of a Profile and become semantically different;
- define its Facets inline without using any named Profile;
- publish a completely new Profile under the same Capability.

No Profile is automatically the eternal official standard.

### Compatibility islands

A Profile can still be useful as a **compatibility island**:

```text
same normalized semantics
        ↓
safe substitution candidates
```

But the island does not define the shoreline of future innovation.

> **Contracts define compatibility islands, not the boundaries of innovation.**

---

## 5. Contract lineage records history, not authority

Profiles can form a graph:

```text
                 dot-core@1
                 /        \
                /          \
      dot-core@2        dot-fast@1
           |                 |
           |             dot-fast@2
           |
   dot-reproducible@1
```

Metadata may record:

```toml
[profile.lineage]
derived_from = ["asmory/dot-core@1"]
supersedes = []
```

This relationship means:

> This design was influenced by that design.

It does **not** mean:

> The child must remain compatible with the parent.

A derived Profile is free to deliberately change semantics.

Standards should emerge from adoption and evidence, not registry decree.

---

## 6. Requirements and guarantees

Semantic matching is not always equality.

Asmory distinguishes what a caller can provide from what an implementation
needs, and what an implementation promises from what a caller requires.

```text
consumer guarantees
        ↓
must satisfy
        ↓
implementation requirements

implementation guarantees
        ↓
must satisfy
        ↓
consumer requirements
```

Example:

```text
consumer guarantees input alignment >= 64 bytes
implementation requires input alignment >= 32 bytes
→ compatible

implementation guarantees error <= 1e-5
consumer requires error <= 1e-4
→ compatible
```

This is closer to a small semantic type system than a traditional package tag
system.

It prevents misleading comparisons such as treating "requires 32-byte aligned
input" as if it were simply another label.

---

## 7. Implementation ownership is independent

Asmory cannot assume that one author will maintain every architecture, OS and
ISA.

That would be unrealistic.

The community model is:

```text
Capability
└── Semantic Shape / Profile
    ├── Implementation by Provider A
    │   └── machine Variant(s)
    ├── Implementation by Provider B
    │   └── machine Variant(s)
    └── Implementation by Provider C
        └── machine Variant(s)
```

One person may specialize in AVX2.

Another may maintain SVE2.

Another may know RVV.

Another may maintain Win64 ABI support.

They do not need to share repository ownership or release schedules.

What matters is whether their semantics are substitutable for the consumer's
requirements.

---

## 8. What exactly is a Variant?

Asmory uses **Machine Variant** narrowly.

A Machine Variant changes machine-level realization while preserving the
semantic shape it claims to implement.

Typical differences include:

```text
architecture
ISA baseline
ISA extensions
OS
object format
ABI
calling convention
microarchitecture tuning
instruction scheduling
unroll strategy
```

Examples:

```text
x86_64 / AVX2 + FMA
x86_64 / AVX-512
AArch64 / NEON
AArch64 / SVE2
RISC-V / RVV
```

Changing observable semantics is not merely a machine Variant.

It creates a semantic Alternative for consumers whose requirements distinguish
that difference.

This prevents the word "Variant" from hiding incompatible behavior.

---

## 9. Machine compatibility and semantic compatibility are separate

The resolver asks two fundamentally different questions.

### Semantic compatibility

```text
Does this implementation satisfy what the consumer means?
```

### Machine compatibility

```text
Can this artifact legally execute here?
```

An implementation can be semantically perfect and still be unusable because the
host lacks AVX2.

Another can run on the machine and still be unusable because it violates
required aliasing or numeric guarantees.

Asmory never treats one check as a substitute for the other.

---

## 10. Conformance is compositional

Conformance should follow the same Facet model.

Instead of requiring every new Profile to reinvent a giant monolithic test
suite, Facets can contribute reusable tests.

Conceptually:

```text
interface facet
    └── interface tests

memory/alignment facet
    └── alignment tests

aliasing facet
    └── alias tests

numeric facet
    └── numeric tests

named Profile
    └── composition of applicable suites
```

A Profile may add extra integration tests, but common semantics should reuse
common conformance logic.

This reduces standard fragmentation and test duplication at the same time.

---

## 11. Conformance does not decide whether a Contract is good

A Conformance Suite proves:

> This implementation behaves according to this declared semantic shape.

It does not prove:

- the semantic shape is well designed;
- the Profile should become popular;
- the implementation is fast;
- the implementation is secure;
- the code should be selected by default.

If a developer believes an existing Profile is wrong, they should be free to
publish a better semantic alternative under the same Capability.

They should not be forced to fake conformance.

> **Conformance enables substitution. It must not suppress experimentation.**

---

## 12. Trust is independent from conformance

Asmory distributes native machine code.

That makes trust a first-class concern.

An implementation may be:

```text
semantically conformant
extremely fast
malicious
```

These statements can all be true simultaneously.

Therefore Asmory keeps trust on a separate axis.

Possible trust states:

```text
community
reviewed
project-approved
registry-trusted
```

Resolver policy may require both:

```text
semantic compatibility
AND
acceptable trust
```

before an implementation becomes a default candidate.

Performance alone must never silently bypass trust policy.

---

## 13. Performance is evidence, not marketing

Assembly packages exist largely because machine behavior matters.

Performance therefore belongs in the package model as structured evidence.

A performance claim should record:

```text
exact Artifact digest
Machine Variant
machine profile
workload
timer
affinity policy
sample count
raw samples
primary metric
baseline
code size
optional PMU counters
```

Asmory does not require every implementation to beat every baseline.

It requires claims to be measurable.

> **Do not require packages to win. Require them to measure.**

This discourages cherry-picked benchmark claims while still forcing the
community to think seriously about performance.

---

## 14. Performance Evidence is append-only

An immutable release should not need to be republished just because somebody
benchmarked it on another CPU.

Evidence therefore attaches to an exact Artifact digest:

```text
Artifact SHA-256
    │
    ├── Evidence: Intel machine
    ├── Evidence: AMD machine
    ├── Evidence: Arm machine
    └── future Evidence
```

Community members can continuously extend hardware coverage.

The artifact remains immutable.

---

## 15. No naive global leaderboard

Raw numbers from different machines are not automatically comparable.

Asmory only treats measurements as directly comparable inside a sufficiently
matching cohort:

```text
benchmark definition
workload
measurement protocol
thread / affinity policy
hardware class
```

A 100 GB/s result on one CPU and an 80 GB/s result on another do not prove the
first implementation is universally faster.

Cross-machine results are still valuable for:

- coverage;
- diagnosis;
- microarchitecture specialization;
- discovering weak implementations;
- deciding where contributors should optimize next.

---

## 16. Preventing a standards explosion

The Facet model is powerful enough to become dangerous if everything becomes a
new tiny dimension.

Asmory therefore follows several constraints.

### Prefer structured Facets

Bad:

```text
supports_nan = true
supports_inf = true
supports_subnormal = true
supports_negative_zero = true
...
```

Better:

```toml
[semantics.numeric]
nan = "propagate"
infinity = "ieee"
subnormal = "preserve"
negative_zero = "preserve"
reduction = "unordered"
```

### Keep the core Facet vocabulary small

New core Facets should require evidence that the difference affects real
substitution decisions across multiple packages.

Package-specific semantics belong in namespaced extension Facets first.

### Profiles are convenience, not mandatory objects

Do not create a new named Profile for every one-off combination.

A Profile is useful when a Facet bundle is reused, discussed or tested often
enough to deserve a stable name.

---

## 17. The resolver must not scan every standard

A scalable registry does not perform:

```text
new upload
    ↓
compare against every Profile ever published
```

Instead, publication performs local canonicalization:

```text
Facet document
    ↓
canonical representation
    ↓
Semantic Fingerprint
    ↓
indexes
```

Conceptually:

```text
Capability ID
Semantic Fingerprint
Machine Contract
Provider
Artifact
```

A deterministic hash can identify exact semantic shapes:

```text
semantic_hash = SHA256(canonical_semantics)
```

The registry can also maintain inverted indexes by Capability and selected
Facet keys.

Resolution becomes:

```text
Capability index
    ↓
semantic requirement filtering
    ↓
machine compatibility filtering
    ↓
trust policy
    ↓
performance ranking
```

The candidate set should become small early.

---

## 18. Keep matching intentionally limited

Asmory should not invent an arbitrary theorem prover or SAT language for
package semantics.

Early matching relations should remain simple and decidable:

```text
exact enum match
set contains / subset
minimum / maximum
numeric range
feature containment
named Profile expansion
```

Avoid arbitrary expressions such as:

```text
(A AND B) OR (C AND NOT D) OR ...
```

unless real use cases later prove they are necessary.

Simple relations are easier to:

- reason about;
- cache;
- index;
- explain to users;
- test;
- reproduce in other implementations of the Asmory protocol.

---

## 19. Resolver order

The conceptual resolver pipeline is:

```text
dependency / release resolution
        ↓
Capability candidate set
        ↓
Semantic requirement matching
        ↓
Machine Contract filtering
        ↓
toolchain / ABI compatibility
        ↓
trust policy
        ↓
Tuning Profile preference
        ↓
comparable Performance Evidence
        ↓
selected Variant + Artifact
```

Correctness and trust filter candidates.

Performance ranks survivors.

Performance must never make an incompatible implementation compatible.

---

## 20. Immutability without conservatism

Immutability is important for reproducibility.

But immutable does not mean sacred.

Asmory makes immutable:

```text
published release
named Profile version
Artifact digest
Evidence record
```

The community remains free to append:

```text
new release
new Profile version
derived Profile
semantic Alternative
new implementation
new Machine Variant
new Evidence
```

The result is a graph of evolution rather than one centrally controlled line of
progress.

---

## 22. Progressive disclosure: simple outside, precise inside

Asmory must serve two very different users without creating two incompatible
package systems.

An ordinary user should be able to write:

```bash
asmory add simd-dot
```

or:

```toml
[dependencies]
simd-dot = "1"
```

They should not be required to understand every Semantic Facet, ABI detail,
trust state, machine Variant, benchmark cohort or resolver policy before using
a package.

An advanced user may want to control those details explicitly.

The platform itself must always understand them.

This leads to a core rule:

> **Convenience is a property of the input syntax. Precision is a property of
> the internal model.**

Asmory therefore uses **progressive disclosure**.

### Level 0 — ordinary use

The user specifies only intent:

```toml
simd-dot = "1"
```

Asmory uses versioned defaults, package recommendations, host detection and
resolver policy to construct the full request.

### Level 1 — guided constraints

The user overrides one or two decisions:

```toml
simd-dot = {
    version = "1",
    trust = "reviewed"
}
```

or chooses a named semantic Profile:

```toml
simd-dot = {
    version = "1",
    profile = "asmory/dot-core@1"
}
```

### Level 2 — expert control

The user may pin or constrain:

```text
semantic requirements
Provider
trust policy
Machine Variant
ISA policy
microarchitecture preference
performance policy
artifact digest
```

This is not a different resolver. It is a more explicit frontend to the same
resolver.

---

## 23. Shorthand must lower to a canonical Resolution Request

Asmory should behave like a compiler frontend.

Human-friendly syntax is parsed and lowered into a canonical internal request:

```text
asmory add simd-dot
        ↓
dependency shorthand
        ↓
default/profile expansion
        ↓
host detection
        ↓
Normalized Resolution Request
        ↓
resolver
```

The canonical request contains the detail that the user did not need to type:

```text
Capability
semantic requirements
Profile expansion
machine constraints
ABI/object constraints
trust policy
provider policy
performance policy
version constraints
```

This design prevents the CLI syntax from becoming the semantic database.

A short command remains short because the resolver expands it, not because the
platform ignores important information.

---

## 24. Defaults must be explicit, versioned and inspectable

Defaults are necessary for usability, but hidden heuristics are dangerous.

Asmory should prefer:

```text
versioned default Profile
versioned resolver policy
package-declared recommended semantics
registry trust defaults
host-derived machine facts
```

over undocumented guessing.

A default must be explainable after resolution.

For example:

```text
asmory explain simd-dot

Requested:
  simd-dot ^1

Expanded defaults:
  semantic profile   asmory/dot-core@1
  trust policy       project-approved-or-reviewed
  provider policy    any accepted provider
  machine target     detected host
  performance policy comparable-evidence

Selected:
  x86_64-avx2-fma-4acc

Why:
  semantic requirements satisfied
  host supports AVX2 + FMA
  trust policy satisfied
  comparable local-machine evidence preferred this Variant
```

The goal is:

> **Defaults should hide work, not hide decisions.**

---

## 25. Never guess across a semantic boundary

Some details are safe to default.

Others are not.

Asmory may automatically choose among Machine Variants that preserve the same
accepted semantics.

Asmory must not silently cross into materially different semantics merely
because another implementation benchmarks faster.

For example:

```text
ieee-oriented
        vs
fast-math
```

should not be silently substituted unless the consumer's semantic requirements
allow both.

If no safe default exists, the resolver should:

```text
ask
or
fail with an explanation
```

rather than invent user intent.

This keeps beginner ergonomics without turning convenience into semantic
surprise.

---

## 26. Package authors also need progressive disclosure

Authors should not need to repeat a hundred fields either.

A simple implementation can reference a reusable Profile and Machine Profile:

```toml
[semantics]
profile = "asmory/dot-core@1"

[machine]
profile = "linux-x86_64-sysv-v3"
required = ["avx2", "fma"]
```

Only differences need to be written explicitly.

The registry then expands those references into canonical Facets and machine
constraints during publication.

For advanced packages, authors may declare Facets directly.

Thus:

```text
authoring syntax
    may be concise

registry representation
    is fully expanded
```

The registry should reject fields it cannot safely infer rather than filling
semantic gaps with guesses.

---

## 27. Lockfiles record the expanded decision, not the shorthand

A user may write:

```toml
simd-dot = "1"
```

but the lockfile should remember what actually happened.

Conceptually:

```text
package
release
Capability
semantic fingerprint
Profile/version
Provider
Machine Variant
Artifact SHA-256
trust decision
resolver-policy version
```

This is essential for reproducibility.

The manifest records intent.

The lockfile records the resolved reality.

---

## 28. Three views of the same dependency

Asmory therefore maintains three representations:

```text
User View
    concise intent

Resolver View
    normalized complete constraints

Lockfile View
    exact historical decision
```

They are not three different package systems.

They are three levels of detail over the same model.

This is the ergonomics principle that lets Asmory remain both approachable and
machine-precise.

## Local-first code is part of the product

Asmory should not treat dependencies as opaque blobs hidden behind the package
manager.

The default workflow should make resolved source available inside the project:

```text
resolve
  -> verify Artifact
  -> populate global cache
  -> materialize project-local dependency
  -> build / inspect / edit / benchmark
```

This matters for both humans and AI agents.

An AI that can directly inspect a dependency's source, tests, semantic metadata
and benchmark harness often needs less user-facing configuration than an AI that
must reason only from a remote package interface.

### Rich internally, light externally

Asmory still needs precise internal models for:

```text
semantic compatibility
machine compatibility
trust
artifact identity
performance evidence
```

But users should not be forced to manipulate every abstraction explicitly.

The default path should be:

```text
use sensible defaults
materialize code locally
let the user or agent inspect reality
override details only when necessary
```

The abstractions exist to make automation reliable, not to replace direct access
to code.

### AI reduces ceremony, not invariants

AI can often understand a local dependency, modify it and validate the result
without the user configuring every semantic dimension by hand.

That is a reason to keep the user interface thin.

It is not a reason to remove internal invariants.

The resolver still needs enough metadata to avoid:

```text
illegal instructions
ABI mismatch
unsafe semantic substitution
untrusted native code
unreproducible dependency drift
```

A useful distinction is:

```text
user-facing abstraction
    minimal

registry/resolver representation
    precise

local source
    always inspectable
```

### Local modification is a first-class workflow

A dependency should move naturally through:

```text
registry Artifact
      ↓
local materialization
      ↓
local modification
      ↓
tests + conformance + benchmark
      ↓
new Implementation / Machine Variant
      ↓
optional publication
```

This loop is central to Asmory's community optimization model.

## Clean and Dirty dependencies serve different goals

Local-first dependencies create an important tension.

We want:

```text
source visible locally
AI can modify it
human can modify it
```

but also:

```text
another developer can reproduce the project
```

Asmory resolves this by treating Clean and Dirty dependencies as different
states rather than pretending every local tree is still the registry package.

### Clean

```text
local tree == immutable Artifact
```

The lockfile is the reproducibility record.

The dependency can stay outside Git.

### Dirty

```text
local tree != immutable Artifact
```

The project must explicitly capture the divergence:

```text
vendor
patch
fork
or restore
```

A Dirty tree that exists only on one developer's disk is not a valid released
dependency state.

This gives AI freedom during experimentation without allowing invisible
dependency drift.

---

## Leaf-first keeps machine-level reuse understandable

Asmory should begin with one-level dependency composition.

```text
Application
├── Leaf A
├── Leaf B
└── Leaf C
```

rather than immediately adopting arbitrary recursive dependency graphs.

This keeps semantic resolution, Machine Variant selection, trust and performance
ranking local to each direct dependency.

If large ecosystems later demonstrate a real need for nested composition,
Asmory can introduce Composite/Bundle packages with a preference for:

```text
resolve once
flatten early
```

The principle is not that composition is bad.

The principle is that machine-level packages should not inherit dependency hell
before they actually need it.

## Danger must be easy to report and fast to propagate

Local-first, AI-modifiable dependencies create a powerful optimization workflow,
but they also make security feedback part of the package ecosystem itself.

Asmory separates:

```text
Review
    identify suspicious behavior

Report
    submit a precise reproducible finding

Advisory
    propagate confirmed risk
```

Reports should be cheap to create.

Accusations should be anchored to exact hashes, Delta identities and provenance.

Enforcement should be evidence-based.

Confirmed danger should propagate through a signed advisory channel to projects
that already have the affected Artifact locked.

A lockfile guarantees identity; it does not mean that identity remains safe
forever.

Asmory should therefore support:

```text
asmory report
asmory audit
asmory status
```

with automatic attachment of Artifact hashes, Dirty Delta information, machine
metadata and Review Evidence where available.

A serious vulnerability report should be confidential by default until triage,
while confirmed Advisories should be machine-readable and rapidly visible.

> **Make reporting cheap, make accusations precise, make enforcement
> evidence-based, and make confirmed danger propagate quickly.**

## Exact is not safe

Asmory must not confuse reproducibility with security.

A package can be perfectly reproducible and still be malicious.

Therefore:

```text
Integrity
Review
Registry Safety
```

are separate dimensions.

An ordinary Artifact may be:

```text
Integrity: Exact
Review:    Unreviewed
Safety:    Normal
```

This means only:

> the bytes exactly match what was published and no current Advisory has changed
> its registry safety state.

It does not mean the code is safe.

### Reviewed Anchors

Incremental AI review becomes powerful only after a trustworthy baseline exists.

Asmory therefore introduces the idea of a Reviewed Anchor:

```text
Artifact
  -> structured full review
  -> Reviewed Anchor
  -> deterministic Delta
  -> incremental review
  -> next Reviewed Anchor
```

This avoids the dangerous assumption that a small diff against an unknown or
malicious baseline is itself safe.

### Capability-aware review

Capability metadata also becomes a security signal.

A dot-product kernel that opens files or creates sockets should be flagged for
review even if its digest is valid and its code is byte-exact.

Asmory can therefore combine:

```text
deterministic structural analysis
Capability anomaly detection
AI semantic reasoning
conformance
provenance
Advisories
```

instead of asking either humans or AI to blindly audit every repository from
scratch.

> **Exact proves identity. Review builds confidence. Neither is the same thing
> as absolute safety.**

## 21. Design summary

Asmory's model can be summarized as:

```text
Capability
    describes the problem.

Facets
    describe observable semantics.

Profile / Contract
    names a reusable Facet bundle.

Implementation
    provides one concrete solution.

Machine Variant
    realizes it for a machine.

Conformance Evidence
    demonstrates semantic compatibility.

Trust
    controls what may be selected.

Performance Evidence
    drives optimization.
```

And the two most important principles are:

> **Contracts define compatibility islands, not the boundaries of innovation.**

> **Performance Evidence drives optimization; it does not redefine
> correctness.**

Asmory should make it easier for a community to agree where agreement is useful,
and equally easy to disagree when a better design is worth exploring.
