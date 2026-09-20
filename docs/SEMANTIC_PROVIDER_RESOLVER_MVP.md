# Semantic Provider Resolver MVP

This milestone moves Asmory from "remote packages can be consumed" to
"independent implementations of the same Capability can be discovered and
semantically filtered."

The Registry now builds a persistent derived semantic Provider index with:

```text
Capability -> Providers
semantic fingerprint -> Providers
exact Facet key -> Providers
```

The client accepts a local Profile document, uses exact interface Facets only to
narrow the server-side candidate set, then runs the existing directional
Semantic Facet matcher on each candidate's canonical semantics.

Machine compatibility is checked only after semantic compatibility.

The first installation policy is intentionally conservative: a Profile may be
installed automatically only when exactly one active Provider is both
semantically and machine compatible. Multiple compatible Providers are reported
as ambiguous until Evidence/trust ranking exists.
