# Asmory CLI

The Asmory CLI is intentionally Assembly-first.

The current Linux x86-64 bootstrap client is a static ELF built with GNU `as`
and `ld`, with no libc and no language runtime.

## Implemented

```text
asmory target
asmory search [query]
asmory info <package>
asmory --version
asmory help
```

`asmory target` is real host detection. It uses `CPUID` and `XGETBV` to inspect
CPU capabilities and verify that the operating system enables the extended
register state required for AVX / AVX-512 before reporting those features as
usable.

The current `search` and `info` commands use the bootstrap index bundled with
the CLI. They exist to stabilize the command UX before the network registry
protocol is wired in.

## Next

- HTTP registry client
- target negotiation against remote package Variants
- `asmory add`
- lockfile
- source/object cache
- assembler adapter selection
