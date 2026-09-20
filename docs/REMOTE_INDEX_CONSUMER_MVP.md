# Active Index + Remote Consumer MVP

Publication now closes the loop back into consumption.

Before this milestone:

```text
publish -> promote -> active Release
```

but normal CLI resolution was still bound to the embedded bootstrap Package.

Now:

```text
publish
  -> promote
  -> persistent active index
  -> remote search/info/versions/resolve
  -> asmory add
  -> verified cache/materialization
  -> Exact local dependency
```

The server persists `active/index.json` as derived search state and rebuilds it
from immutable active Release records on restart.

The remote resolver uses the native `asmory target` result for hard Machine
Contract filtering. It does not rank incompatible Variants.

The first consumer integration intentionally remains leaf-first and
package-name-first. Capability-wide provider selection and Evidence-driven
cross-provider ranking remain later resolver work.
