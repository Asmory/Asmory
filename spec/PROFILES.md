# Profiles and Contracts — Draft 0.1

Asmory uses the terms **Profile** and **Contract** for named, immutable bundles
of Semantic Facets.

The word "Contract" must not imply central authority.

## Why Profiles exist

Profiles provide:

- concise dependency declarations;
- shared vocabulary;
- reusable conformance suites;
- stable discussion targets;
- adoption metrics;
- lineage metadata.

They are optional.

An implementation may declare Facets directly.

## Immutability

Once published:

```text
profile ID + version -> immutable Facet bundle
```

A changed bundle requires a new version or a new Profile.

This protects reproducibility without making old semantics permanent law.

## Lineage

Profiles may declare:

```toml
[profile.lineage]
derived_from = ["asmory/dot-core@1"]
supersedes = []
```

Lineage describes history only.

Derived Profiles may intentionally break compatibility.

## Authority

Profiles are namespaced by their publishers.

The registry should not imply:

```text
older == official
registry-owned == superior
popular == universally correct
```

Adoption can be displayed as evidence, not transformed into mandatory authority.

## When to create a Profile

Create one when a Facet combination is reused enough to benefit from:

- a stable name;
- shared tests;
- multiple independent implementations;
- dependency references.

Do not create one merely because a single package has one unusual configuration.
