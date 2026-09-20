# Capabilities — Draft 0.1

A Capability is a discovery namespace for implementations that solve broadly
the same problem.

Examples:

```text
math.dot.f32
memory.copy.bytes
crypto.sha256.compress
json.scan.structurals
```

A Capability is intentionally weaker than a standard.

It does not decide:

- exact semantics;
- ABI;
- numeric guarantees;
- memory guarantees;
- which Profile is official;
- which implementation is preferred.

Those decisions belong to Semantic Facets, consumers, trust policy and Evidence.

The primary purpose of a Capability is to reduce the search space:

```text
all registry artifacts
        ↓
Capability
        ↓
semantically relevant candidates
```

This is both a community organization mechanism and a resolver index.
