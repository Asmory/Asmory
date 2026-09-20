# Semantic Matching — Draft 0.1

Asmory treats semantic compatibility as a small directional type system.

## Two directions

For an implementation to satisfy a consumer:

```text
consumer guarantees
        >=
implementation requirements
```

and:

```text
implementation guarantees
        >=
consumer requirements
```

Example:

```text
consumer guarantees alignment >= 64
implementation requires alignment >= 32
→ compatible
```

Example:

```text
implementation guarantees absolute error <= 1e-6
consumer requires absolute error <= 1e-4
→ compatible
```

The reverse directions are not equivalent.

## Bounded relations

Draft 0.1 deliberately implements only:

```text
exact
minimum
maximum
contains
subset
```

There is no arbitrary SAT/Boolean constraint language.

The resolver should stay understandable before it becomes clever.

## Semantic Fingerprint

Exact identity is:

```text
SHA256(canonical semantic document)
```

The canonical document includes observable Facets and their directional
requirements/guarantees.

It excludes:

```text
Profile name
Profile publisher
Implementation Provider
popularity
Performance Evidence
Review state
```

Therefore two independently published implementations can have the same exact
semantic fingerprint.

## Profiles

A Profile is an immutable name for a semantic document.

It is not semantic authority.

The resolver expands the Profile and compares Facets.

Profile names are useful for humans, shared tests and dependency syntax; the
expanded Facets remain the source of truth.

## Compatibility Islands

Two implementations are substitutable for a consumer when the directional
Facet matcher accepts both.

A different semantic shape is not an invalid package.

It is another compatibility island under the same Capability.

This allows experimentation without forcing every implementation into one
central standard.
