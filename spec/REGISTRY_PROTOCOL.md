# Registry Protocol — Draft 1

## Read API implemented by the Assembly MVP

```http
GET /api/v1/packages
GET /api/v1/packages/{name}
GET /api/v1/packages/{name}/versions
GET /api/v1/packages/{name}/{version}
GET /api/v1/packages/{name}/{version}/download
```

Current example:

```text
/api/v1/packages
/api/v1/packages/simd-dot
/api/v1/packages/simd-dot/versions
/api/v1/packages/simd-dot/0.1.0
/api/v1/packages/simd-dot/0.1.0/download
```

Release metadata includes dependencies, machine Variants and artifact SHA-256.

The old MVP endpoints remain temporary compatibility aliases:

```text
/api/v1/package/simd-dot
/download/simd-dot-0.1.0.tar.gz
```

## Planned write API

Write operations require authentication and are not implemented yet.

Conceptual publish transaction:

1. authenticate publisher;
2. normalize project identity;
3. verify ownership;
4. validate manifest/archive;
5. compute and verify digests;
6. reject an already-used project/version/artifact identity;
7. atomically expose metadata and artifact.

The server stores machine constraints exactly. The client resolver decides
whether a Variant is compatible.
