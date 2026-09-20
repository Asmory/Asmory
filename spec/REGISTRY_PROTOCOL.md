# Registry Protocol — Draft 0

The current Assembly HTTP server exposes only a demonstration API. It is not yet the stable protocol.

Current MVP endpoint:

```text
GET /api/v1/packages
```

A future protocol needs at minimum:

- package search;
- package/version metadata;
- variant target constraints;
- dependency metadata;
- immutable source archive download;
- checksums;
- publication/ownership operations;
- yanking/deprecation without mutating historical artifacts.

Protocol design should follow the target/ISA specification rather than collapsing ISA requirements into textual labels.
