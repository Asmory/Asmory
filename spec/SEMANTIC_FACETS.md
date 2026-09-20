# Semantic Facets — Draft 0.1

Semantic Facets are the canonical compatibility model of Asmory.

Named Profiles / Contracts are optional aliases for reusable Facet bundles.

## 1. Semantic document

Conceptual example:

```toml
[semantics]
capability = "math.dot.f32"

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

The final schema is intentionally not frozen by this draft.

The purpose of Draft 0.1 is to establish the model.

## 2. Requirements and guarantees

Future manifests should be able to distinguish:

```toml
[semantics.requires]
# Conditions the implementation needs from its caller.

[semantics.guarantees]
# Observable behavior the implementation promises.
```

Likewise, a consumer can express what it guarantees and what it requires.

Compatibility is directional, not merely equality.

## 3. Canonicalization

Before indexing or hashing, semantic documents must be canonicalized.

Canonicalization should eventually define:

- normalized keys;
- normalized enum spelling;
- deterministic ordering;
- explicit defaults;
- normalized numeric representation;
- versioned Facet schemas.

Equivalent semantic declarations should produce the same canonical form.

## 4. Semantic fingerprint

Exact semantic shapes may use:

```text
semantic_fingerprint =
    SHA256(canonical_semantic_document)
```

The fingerprint is an identity/cache/index primitive.

It is not a replacement for directional requirement/guarantee matching.

## 5. Core Facets

Draft candidates:

```text
interface
numeric
memory
aliasing
alignment
determinism
error behavior
concurrency
side effects
```

The core set should remain intentionally small.

## 6. Extension Facets

Experimental or package-specific semantics should use namespaced extensions
instead of immediately expanding the core vocabulary.

Conceptually:

```toml
[semantics.extensions."org.example.audio"]
denormal_policy = "flush"
```

Repeated community adoption can later justify promotion into a shared Facet.

## 7. Matching relations

Initial resolver relations should be limited to:

```text
exact
subset
superset
contains
minimum
maximum
range
```

No arbitrary Boolean constraint language is planned for Draft 0.1.

## 8. Profile expansion

A declaration may reference a Profile:

```toml
[semantics]
profile = "asmory/dot-core@1"
```

The resolver expands the immutable Profile into its canonical Facet bundle
before matching.

Semantic truth remains the expanded Facets, not the Profile name.
