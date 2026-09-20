# Conformance — Draft 0.1

Conformance demonstrates declared semantic behavior.

It does not define that behavior.

## Compositional suites

Where practical, tests should be attached to reusable Semantic Facets:

```text
interface Facet
    -> interface tests

numeric Facet
    -> numeric tests

memory/alignment Facet
    -> memory tests
```

A named Profile can compose those suites and add integration tests.

## What conformance proves

A passing result means:

> Under the declared test scope, this implementation behaved consistently with
> the declared semantics.

It does not prove:

- universal correctness;
- security;
- trustworthiness;
- performance;
- that the semantics are a good community standard.

## Divergence is allowed

If a developer wants different observable semantics, the correct response is a
different Facet declaration or Profile.

Asmory must not pressure them to claim compatibility that does not exist.

## Evidence identity

A conformance result should eventually bind to:

```text
semantic fingerprint
Profile/version if used
implementation/provider
Machine Variant
Artifact SHA-256
suite versions
test environment
```
