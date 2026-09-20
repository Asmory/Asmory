# Local Workspace Foundation

This milestone introduces the first project-level workflow:

```bash
asmory init
```

It creates:

```text
asm.toml
asm.lock
.asmory/.gitignore
.asmory/deps/
```

No Registry request occurs during initialization.

```text
asm.toml = what the user asked for
asm.lock = what Asmory resolved exactly
```

The staged future flow is:

```text
manifest intent
  -> resolver
  -> lock exact identity
  -> acquire verified Artifact
  -> cache
  -> local materialization
```

Artifact acquisition and digest verification are implemented in the next layer; content-addressed cache is the following milestone.
