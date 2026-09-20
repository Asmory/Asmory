# Fork + Publication Candidate MVP

The dependency lifecycle now has three explicit ways to leave a Modified local
dependency:

```text
Modified dependency
├── restore  -> original exact Registry Artifact
├── patch    -> compact reproducible derivative
├── vendor   -> full source ownership inside current project
└── fork     -> new independent Package identity
```

The fork path deliberately operates at Package granularity even when the
upstream source was developed in a monorepo.

Example:

```bash
asmory fork simd-dot my-dot
```

creates:

```text
packages/my-dot/
```

and adds only that Package to the current repository workspace.

No upstream Git clone occurs.

After committing the new Package:

```bash
asmory publish-prepare my-dot
```

creates a deterministic local release candidate containing the exact source
Artifact, Git provenance and fork ancestry.

Remote upload/authentication remains separate M3 work. This keeps today's CLI
truthful while making the Package identity and publication boundary executable
end to end.
