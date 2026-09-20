#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$HOME/asm/Asmory}"
cd "$ROOT"

echo "===== [1/8] update Why Asmory messaging ====="

python3 - <<'PY'
from pathlib import Path

README = Path("README.md")
SITE = Path("site/index.html")
SITE_CSS = Path("site/style.css")
REG = Path("registry/static/index.html")
REG_CSS = Path("registry/static/app.css")

why_readme = r'''## Why Asmory?

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
'''

readme = README.read_text()
start = readme.find("## The idea")
if start == -1:
    start = readme.find("## Why Asmory?")
end = readme.find("## Working today")
if start == -1 or end == -1 or end <= start:
    raise SystemExit("README anchors not found")
readme = readme[:start] + why_readme + "\n\n" + readme[end:]
README.write_text(readme)

why_site = r'''
<section class="section why" id="why">
  <div class="kicker">Why Asmory · Why now?</div>
  <h2>AI changes the economics of low-level programming.</h2>
  <p class="why-lead">Assembly used to trade maximum control for maximum human cost. AI weakens that trade-off: coding models can generate and tune low-level kernels, while Assembly gives them a brutally short path from edit to benchmark.</p>

  <div class="why-grid">
    <article class="why-card">
      <span class="why-num">01</span>
      <h3>Concrete optimization targets</h3>
      <p>Instructions, register pressure, dependency chains, memory access, SIMD width, branches and cycles are directly visible. The distance between generated code and measured hardware behavior is small.</p>
    </article>

    <article class="why-card">
      <span class="why-num">02</span>
      <h3>A tiny feedback loop</h3>
      <p>For small kernels, the path can be as short as <code>edit → assemble → run → benchmark → inspect → repeat</code>. Fewer high-level compilation stages means more experiments per minute.</p>
    </article>

    <article class="why-card">
      <span class="why-num">03</span>
      <h3>Vibe coding meets machine code</h3>
      <p>If developers already describe intent, let AI implement it, then validate the result, the old requirement to manually manage every Assembly detail becomes less absolute.</p>
    </article>
  </div>

  <div class="why-thesis">
    <div>
      <span class="why-label">The missing layer</span>
      <h3>Assembly still has no modern package ecosystem.</h3>
      <p>Today, optimized kernels are often scattered across snippets, gists and larger projects. Asmory wants the same <strong>find → add → reuse</strong> workflow developers expect from Cargo, PyPI and npm - without hiding the machine contract.</p>
    </div>
    <pre><span class="gold">$</span> asmory add fast-memcpy
<span class="gold">$</span> asmory add simd-json-scan
<span class="gold">$</span> asmory add avx2-dot

<span class="ok">resolve</span> ISA + ABI + object + OS
<span class="ok">select</span> compatible Variant
<span class="ok">link</span> only what survives</pre>
  </div>

  <blockquote class="manifesto">
    <strong>In the AI era, Assembly may finally deserve a modern package ecosystem.</strong>
    <span>Asmory exists to find out how far that idea can go.</span>
  </blockquote>
</section>
'''

site = SITE.read_text()
anchor = '<section class="section" id="cli">'
if anchor not in site:
    raise SystemExit("site CLI anchor not found")
if 'id="why"' not in site:
    site = site.replace(anchor, why_site + "\n\n" + anchor, 1)
if 'href="#why"' not in site:
    site = site.replace(
        '<a class="chip hide" href="#cli">CLI</a>',
        '<a class="chip hide" href="#why">Why</a>\n    <a class="chip hide" href="#cli">CLI</a>',
        1
    )
SITE.write_text(site)

site_css = SITE_CSS.read_text()
site_marker = "/* ASMORY_WHY_V1 */"
site_block = r'''
/* ASMORY_WHY_V1 */
.why{padding-top:96px}
.why-lead{font-size:20px!important;max-width:850px!important}
.why-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:15px;margin-top:32px}
.why-card{padding:24px;border:1px solid var(--line);border-radius:16px;background:linear-gradient(180deg,var(--panel),var(--panel2));box-shadow:0 10px 30px var(--shadow)}
.why-card h3{font-size:18px;margin:24px 0 8px}
.why-card p{color:var(--muted);margin:0}
.why-num{font:700 11px ui-monospace,SFMono-Regular,Consolas,monospace;color:var(--accent);letter-spacing:.12em}
.why-thesis{display:grid;grid-template-columns:1fr 1fr;gap:22px;margin-top:22px;padding:28px;border:1px solid var(--line);border-radius:18px;background:var(--panel)}
.why-thesis h3{font-size:28px;line-height:1.08;letter-spacing:-.035em;margin:8px 0 12px}
.why-thesis p{color:var(--muted);margin:0}
.why-label{font:700 11px ui-monospace,SFMono-Regular,Consolas,monospace;text-transform:uppercase;letter-spacing:.15em;color:var(--accent)}
.why-thesis pre{margin:0;background:var(--terminal);color:#eef2f6;border:1px solid #303842;border-radius:14px;padding:22px;overflow:auto;font:13px/1.8 ui-monospace,SFMono-Regular,Consolas,monospace}
.manifesto{margin:22px 0 0;padding:28px;border-left:3px solid var(--accent);background:color-mix(in srgb,var(--panel) 86%,transparent);border-radius:0 14px 14px 0}
.manifesto strong{display:block;font-size:22px;letter-spacing:-.025em}
.manifesto span{display:block;color:var(--muted);margin-top:5px}
@media(max-width:800px){.why-grid,.why-thesis{grid-template-columns:1fr}}
'''
if site_marker in site_css:
    site_css = site_css[:site_css.find(site_marker)].rstrip()
site_css = site_css.rstrip() + "\n\n" + site_block.strip() + "\n"
SITE_CSS.write_text(site_css)

why_registry = r'''
<section class="shell section why-now">
  <div class="section-head">
    <div>
      <span class="eyebrow">Why Asmory · Why now?</span>
      <h2 style="margin-top:14px">AI changes the economics of low-level programming.</h2>
      <p class="intro">Assembly used to trade maximum control for maximum human cost. AI lowers that cost, and Assembly gives an agent an unusually short path from generated code to measurable machine behavior.</p>
    </div>
  </div>

  <div class="grid3">
    <article class="feature">
      <span class="num">01 / DIRECT</span>
      <h3>Concrete optimization targets</h3>
      <p>Instructions, register pressure, dependency chains, SIMD width, memory access and cycles are directly visible to the tuning loop.</p>
    </article>
    <article class="feature">
      <span class="num">02 / FAST LOOP</span>
      <h3>Edit → assemble → benchmark</h3>
      <p>For small kernels, fewer high-level compilation stages make aggressive AI iteration practical.</p>
    </article>
    <article class="feature">
      <span class="num">03 / ECOSYSTEM</span>
      <h3>Stop regenerating every kernel</h3>
      <p>Give humans and agents a registry of reusable machine-level building blocks with explicit ISA and ABI contracts.</p>
    </article>
  </div>

  <div class="registry-manifesto">
    <strong>In the AI era, Assembly may finally deserve a modern package ecosystem.</strong>
    <span>Asmory exists to find out how far that idea can go.</span>
  </div>
</section>
'''

reg = REG.read_text()
reg_anchor = '<section class="shell section"><div class="section-head"><div><h2>Compatibility is a dependency.</h2>'
if reg_anchor not in reg:
    raise SystemExit("registry compatibility anchor not found")
if 'class="shell section why-now"' not in reg:
    reg = reg.replace(reg_anchor, why_registry + "\n" + reg_anchor, 1)
REG.write_text(reg)

reg_css = REG_CSS.read_text()
reg_marker = "/* ASMORY_WHY_V1 */"
reg_block = r'''
/* ASMORY_WHY_V1 */
.why-now{padding-top:78px}
.registry-manifesto{
  margin-top:20px;padding:22px 24px;border-left:3px solid var(--accent);
  background:var(--panel-2);border-radius:0 12px 12px 0
}
.registry-manifesto strong{display:block;font-size:19px;letter-spacing:-.02em}
.registry-manifesto span{display:block;color:var(--muted);margin-top:4px}
'''
if reg_marker in reg_css:
    reg_css = reg_css[:reg_css.find(reg_marker)].rstrip()
reg_css = reg_css.rstrip() + "\n\n" + reg_block.strip() + "\n"
REG_CSS.write_text(reg_css)

print("Why Asmory content updated.")
PY

echo "===== [2/8] content checks ====="
grep -q "AI changes the economics of low-level programming" README.md
grep -q 'id="why"' site/index.html
grep -q "ASMORY_WHY_V1" site/style.css
grep -q "In the AI era, Assembly may finally deserve" registry/static/index.html
grep -q "ASMORY_WHY_V1" registry/static/app.css
echo "content checks: ok"

echo "===== [3/8] build ====="
make clean
make -j"$(nproc)"

echo "===== [4/8] checks ====="
make check
make smoke
make cli-smoke

echo "===== [5/8] commit ====="
git add \
  README.md \
  site/index.html \
  site/style.css \
  registry/static/index.html \
  registry/static/app.css \
  scripts/update-why-asmory.sh

if ! git diff --cached --quiet; then
  git commit -m "docs: sharpen Why Asmory AI-era thesis"
else
  echo "No changes to commit."
fi

echo "===== [6/8] push ====="
git push

echo "===== [7/8] Pages / CI ====="
gh run list --repo Asmory/Asmory --limit 8

echo "===== [8/8] done ====="
echo "Repository: https://github.com/Asmory/Asmory"
echo "Pages:      https://asmory.github.io/Asmory/"
