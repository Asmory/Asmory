# Asmory

> **Packages for the instruction level.**
>
> An Assembly package registry and ecosystem with explicit ISA, ABI and target
> constraints.

[![CI](https://github.com/Asmory/Asmory/actions/workflows/ci.yml/badge.svg)](https://github.com/Asmory/Asmory/actions/workflows/ci.yml)
[![Pages](https://github.com/Asmory/Asmory/actions/workflows/pages.yml/badge.svg)](https://github.com/Asmory/Asmory/actions/workflows/pages.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Why Asmory?

For decades, Assembly had an obvious trade-off:

**maximum control, maximum human cost.**

You get direct control over instructions, registers, memory layout, calling
conventions, SIMD, cache behavior and the exact machine code that runs - but
traditionally you pay for that control with slower development, harder
debugging and a much heavier maintenance burden.

High-level languages won for good reasons: humans needed abstraction.

**AI changes that equation.**

Modern coding models can generate, rewrite and tune small low-level kernels
surprisingly well. Assembly also gives an AI something unusually concrete to
optimize:

```text
instructions
register pressure
dependency chains
memory access
SIMD width
branch structure
cache behavior
cycles
```

There is very little distance between the generated code and the hardware
behavior being measured.

That makes the optimization loop unusually direct:

```text
idea
  -> generate Assembly
  -> assemble
  -> run tests
  -> benchmark
  -> inspect instructions / counters
  -> rewrite
  -> benchmark again
```

### The build loop is tiny

This matters a lot for AI-driven iteration.

A high-level-language build can involve parsing, type checking, generic or
template expansion, IR generation, optimization passes, machine-code
generation, object generation and finally linking.

Assembly starts much closer to the destination:

```text
Assembly source
    -> assembler
    -> object file
    -> linker
```

The assembler and linker still do real work, of course. Assembly does not
magically skip those stages. But for small kernels and machine-level packages,
the edit -> assemble -> run -> benchmark loop can be extremely short.

That is exactly the kind of feedback loop an automated coding agent can exploit.

Instead of making one expensive attempt, an agent can iterate aggressively:

```text
edit
-> assemble
-> test
-> benchmark
-> inspect
-> edit again
```

The faster the loop, the more experiments become practical.

### Vibe coding makes the old trade-off look different

There is another reason Assembly becomes interesting now.

A lot of AI-assisted development already works like this:

```text
describe intent
-> let the model implement it
-> run the program
-> inspect the result
-> ask for another iteration
```

The developer is not necessarily reasoning about every generated line by hand.

That is very close to the way low-level code can be developed with an AI agent:
specify the contract, test the output, benchmark it, inspect the machine
behavior, then iterate.

If AI is carrying much of the implementation burden, one of the classic
reasons for avoiding Assembly - that every low-level detail must be managed
manually by a human - becomes less absolute.

This does **not** mean high-level languages are obsolete.

Rust, C++, C and other systems languages still provide enormously valuable
features:

- type systems;
- memory safety;
- portability;
- mature ecosystems;
- application frameworks;
- complex abstractions;
- developer tooling.

Asmory is not trying to replace them.

But when those abstractions are not the thing you need - when you simply want
a small, reusable, aggressively optimized machine-level building block - the
economics start to look different.

### The missing piece is an ecosystem

Today, Assembly is still often shared as:

```text
a code snippet
a gist
a random .S file
a kernel buried inside a larger project
```

That makes reuse unnecessarily difficult.

Asmory asks a simple question:

> **What if Assembly had the same "find a package, add it, use it" workflow
> that developers expect from Cargo, PyPI or npm?**

Imagine:

```bash
asmory add fast-memcpy
asmory add simd-json-scan
asmory add avx2-dot
asmory add sha256-x86
```

and let the package manager understand the machine contract:

```text
architecture
ISA baseline
ISA version
ISA extensions
ABI
calling convention
object format
operating system
assembler requirements
microarchitecture tuning
```

A package can ship several machine Variants:

```text
fast-memcpy 1.4.0
├── x86_64-sse2
├── x86_64-avx2
├── x86_64-avx512
├── aarch64-neon
└── aarch64-sve2
```

The resolver selects what the machine can legally execute.

The linker discards what the program never uses.

And an AI agent can operate one level higher:

```text
understand task
  -> search Asmory
  -> inspect machine contracts
  -> select compatible packages
  -> generate glue code
  -> assemble
  -> benchmark
  -> tune or replace
  -> repeat
```

Traditional package ecosystems primarily help **humans reuse abstractions**.

Asmory can also help **AI reuse machine-level building blocks**.

Instead of regenerating every memcpy loop, hash primitive, parser kernel, DSP
routine or SIMD building block from scratch, an agent can search for existing
implementations with explicit ISA and ABI contracts and compose them like
libraries in higher-level languages.

That is the idea behind Asmory.

> **AI changes the economics of low-level programming.**

If AI reduces the human cost of writing and tuning Assembly, and Assembly
offers an exceptionally short build-test-benchmark loop, then one of its
largest historical disadvantages starts to shrink.

At that point, the absence of a modern package ecosystem starts looking
strange.

**In the AI era, Assembly may finally deserve one.**

Asmory exists to find out how far that idea can go.


## Registry positioning

Asmory is **not** trying to be GitHub for Assembly.

Use GitHub, GitLab, Forgejo or another forge for source history, branches,
pull requests and collaboration.

Asmory is the package-distribution layer, closer in role to crates.io or PyPI:

```text
source repository
      -> publish
Asmory Project
      -> Release
      -> Variant
      -> Artifact
resolver / build / linker
```

The important unit is an immutable, versioned package Release with
machine-readable compatibility metadata and content-verified Artifacts.

See [spec/REGISTRY_MODEL.md](spec/REGISTRY_MODEL.md) and
[docs/PUBLISHING.md](docs/PUBLISHING.md).

## Working today

The repository already contains two static Linux x86-64 ELF programs written
in Assembly:

- `asmory-registry` — syscall-only HTTP registry prototype;
- `asmory` — package-manager CLI bootstrap.

Build everything:

```bash
make clean && make -j"$(nproc)" && make check && make smoke && make cli-smoke
```

Inspect the current machine:

```bash
./build/asmory target
```

Example output:

```text
Asmory host target

Target
  arch         x86_64
  os           linux
  object       elf64
  abi          sysv64
  cpu_vendor   AuthenticAMD

ISA
  baseline     x86-64-v3

  features
    sse2       yes
    sse4.2     yes
    avx        yes
    avx2       yes
    fma        yes
    bmi1       yes
    bmi2       yes
    avx512f    no
```

The CLI uses `CPUID` and `XGETBV` directly. AVX-family instructions are only
reported as usable when the operating system has enabled the required extended
register state.

## Bootstrap CLI

```bash
asmory init
asmory target
asmory search simd
asmory info simd-dot
asmory acquire simd-dot ./simd-dot-0.1.0.tar.gz
asmory cache simd-dot
asmory add simd-dot
asmory status
asmory restore simd-dot
asmory patch simd-dot
asmory reapply simd-dot
asmory --version
```

Install the locally built CLI:

```bash
make install-user
```

## Package model

A software version can contain several machine Variants:

```text
simd-dot 0.1.0
├── x86_64 / SSE2
├── x86_64 / AVX2 + FMA
├── x86_64 / AVX-512
├── aarch64 / NEON
├── aarch64 / SVE2
└── riscv64 / RVV
```

The package version describes the software release. The Variant describes a
machine implementation.

## Example manifest

```toml
[package]
name = "simd-dot"
version = "0.1.0"
license = "MIT"

[target]
arch = "x86_64"
os = "linux"
object = "elf64"
abi = "sysv64"

[target.isa]
baseline = "x86-64-v3"
required = ["avx2", "fma"]

[toolchain]
assembler = "gas"
min_version = "2.40"
```

## Design principles

### ISA is resolver input

ISA requirements are not search tags. They determine whether a Variant is
legal to execute.

### Runnable != optimal

Asmory separates correctness compatibility from performance preference. A
future resolver may choose between several compatible implementations using
microarchitecture information or benchmark profiles.

### Let the linker collect garbage

Packages should expose independently collectable sections where practical, so
normal linker mechanisms such as `--gc-sections` can eliminate unused code.

### Machine code + machine-readable contract

The goal is not to rebuild a high-level language around Assembly. The goal is
to make low-level code reusable by giving humans and coding agents a precise,
machine-readable interface and target contract.

<!-- ASMORY_SEMANTIC_MODEL_BEGIN -->
## Semantic compatibility model

Asmory deliberately avoids treating a named standard as permanent authority.

```text
Capability
    -> Semantic Facets
    -> optional Profile / Contract
    -> Implementation
    -> Machine Variant
    -> Evidence
```

**Semantic Facets are the source of truth.** A Profile / Contract is only an
immutable, reusable name for a common Facet bundle — closer to a `typedef` than
a constitution.

This lets the community reuse compatible implementations without forcing future
work to obey an old design forever.

> **Contracts define compatibility islands, not the boundaries of innovation.**

The resolver first checks semantic and machine compatibility, then trust, and
only then uses comparable Performance Evidence to rank surviving Variants.

See [`docs/DESIGN_PHILOSOPHY.md`](docs/DESIGN_PHILOSOPHY.md).

Asmory is also **local-first**: resolved packages are cached globally for reuse
but materialized into the project by default so humans and AI agents can inspect,
modify, test and benchmark the actual Assembly instead of treating dependencies
as opaque remote blobs.

Local dependencies have two explicit integrity states: **Exact** dependencies are
reconstructible from the lockfile and normally stay out of Git; **Modified**
dependencies must be captured as vendored source, deterministic patches, a fork,
or restored before release. Asmory v1 is also **leaf-first**: direct
machine-level dependencies are preferred over arbitrary recursive dependency
graphs.

Security findings should also be easy to report: reports bind to exact Artifact
or Delta identities, confirmed Advisories propagate independently of lockfiles,
and AI-assisted review can prefill evidence without turning an AI judgment into
an automatic verdict.

Artifact integrity and security are separate: an **Exact** Artifact only proves
that the bytes match the published identity. It may still be unreviewed or
dangerous. Asmory uses Reviewed Anchors plus deterministic Delta review to make
AI-assisted incremental security review efficient without treating a clean
baseline as automatically safe.
<!-- ASMORY_SEMANTIC_MODEL_END -->

## Repository

```text
registry/   Assembly HTTP registry
cli/        Assembly package-manager CLI
docs/       architecture, CLI and roadmap
spec/       package / ISA / ABI specifications
examples/   example Assembly packages
site/       GitHub Pages project site
org/        Organization profile source
tests/      integration tests
scripts/    development / publish / release helpers
```

## Roadmap

The immediate path is:

```text
host detection
    -> remote registry protocol
    -> Variant compatibility resolver
    -> asmory add
    -> lockfile/cache
    -> build/link pipeline
    -> signed publishing
```

See [docs/ROADMAP.md](docs/ROADMAP.md).

## Contributing

Asmory is especially interested in contributors familiar with:

- x86/x86-64, AArch64 or RISC-V ISA modeling;
- SIMD and optimized kernels;
- SysV AMD64, Win64 and AAPCS64 ABIs;
- ELF, COFF and Mach-O;
- GNU as, NASM and LLVM MC;
- linkers and section garbage collection;
- host feature detection and dispatch;
- dependency resolution and package registries;
- high-performance computing.

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT.
