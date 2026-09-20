# Remote Publication Staging MVP

Asmory now has a real authenticated network transition after local publication
preparation.

```text
Package
  -> publish-prepare
  -> exact local candidate
  -> publish
  -> authenticated Artifact upload
  -> authenticated candidate upload
  -> persistent staged Registry state
```

The write side intentionally does not claim the candidate is resolver-visible.

The current candidate format does not yet contain a complete validated Machine
Variant publication contract. The server therefore persists it as:

```text
state = staged
resolvable = false
```

This avoids weakening Release immutability merely to make the first write API
look more complete.

The staging backend already enforces content-addressed objects, token
authentication, first-publisher Package ownership, immutable Package/version
records, idempotent retries, restart persistence and fail-closed digest
verification.

The next publication milestone is promotion: enrich/validate the candidate with
full Release + Semantic + Variant metadata and atomically promote it into the
active resolver index.
