#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$HOME/asm/Asmory}"
cd "$ROOT"

echo "===== [1/7] patch light-theme contrast ====="

python3 - <<'PY'
from pathlib import Path

APP = Path("registry/static/app.css")
SITE = Path("site/style.css")
DOC = Path("docs/THEMING.md")

APP_MARK = "/* ASMORY_LIGHT_CONTRAST_V2 */"
SITE_MARK = "/* ASMORY_PAGES_LIGHT_CONTRAST_V2 */"
DOC_MARK = "## Light-theme contrast policy"

app_block = r'''
/* ASMORY_LIGHT_CONTRAST_V2 */

/*
 * Light-theme readability pass.
 * Ordinary page text must use dark semantic colors.
 * Light foregrounds are reserved for deliberately dark surfaces.
 */
:root[data-theme="light"]{
  --text:#171c22;
  --muted:#525d68;
  --soft:#303944;
  --accent:#8f5b00;
  --accent-strong:#704600;
  --chip-text:#4c5761;
  --line:#d3ccbf;
  --line-strong:#aea390;
}

:root[data-theme="light"] body,
:root[data-theme="light"] .brand,
:root[data-theme="light"] .btn,
:root[data-theme="light"] .pkg-name,
:root[data-theme="light"] .result-name,
:root[data-theme="light"] .pkg-title,
:root[data-theme="light"] .side-row span:last-child,
:root[data-theme="light"] .variant-row,
:root[data-theme="light"] .symbol{
  color:var(--text);
}

:root[data-theme="light"] .navlinks,
:root[data-theme="light"] .navcta,
:root[data-theme="light"] .lede,
:root[data-theme="light"] .stat span,
:root[data-theme="light"] .section p.intro,
:root[data-theme="light"] .feature .num,
:root[data-theme="light"] .feature p,
:root[data-theme="light"] .pkg-desc,
:root[data-theme="light"] .pkg-foot,
:root[data-theme="light"] .page-head p,
:root[data-theme="light"] .result-desc,
:root[data-theme="light"] .result-meta,
:root[data-theme="light"] .empty,
:root[data-theme="light"] .crumbs,
:root[data-theme="light"] .pkg-sub,
:root[data-theme="light"] .content p,
:root[data-theme="light"] .sidebox h3,
:root[data-theme="light"] .side-row span:first-child,
:root[data-theme="light"] .toc a,
:root[data-theme="light"] .prose p,
:root[data-theme="light"] .prose li,
:root[data-theme="light"] .footer,
:root[data-theme="light"] .copy{
  color:var(--muted);
}

:root[data-theme="light"] .chip{
  color:var(--chip-text);
}

:root[data-theme="light"] .chip.hot,
:root[data-theme="light"] .eyebrow,
:root[data-theme="light"] .prompt,
:root[data-theme="light"] .symbol code,
:root[data-theme="light"] .text-link:hover,
:root[data-theme="light"] .navlinks a:hover,
:root[data-theme="light"] .toc a:hover{
  color:var(--accent);
}

/* Explicit bronze surface for light text. */
:root[data-theme="light"] .btn.primary{
  background:#956000;
  border-color:#956000;
  color:#fffdf8;
}

:root[data-theme="light"] .btn.primary:hover{
  background:#784c00;
  border-color:#784c00;
  color:#fffdf8;
}

/* Terminals remain intentionally dark in both themes. */
:root[data-theme="light"] .terminal,
:root[data-theme="light"] .terminal .termcode{
  color:#dce3ec;
}

:root[data-theme="light"] .terminal .dim{color:#8995a4}
:root[data-theme="light"] .terminal .key{color:#9dbbff}
:root[data-theme="light"] .terminal .value{color:#e2bd72}
:root[data-theme="light"] .terminal .ok{color:#75d9a0}

/* System-light mode before a user explicitly chooses a theme. */
@media(prefers-color-scheme:light){
  :root:not([data-theme]){
    --text:#171c22;
    --muted:#525d68;
    --soft:#303944;
    --accent:#8f5b00;
    --accent-strong:#704600;
    --chip-text:#4c5761;
    --line:#d3ccbf;
    --line-strong:#aea390;
  }

  :root:not([data-theme]) body,
  :root:not([data-theme]) .brand,
  :root:not([data-theme]) .btn,
  :root:not([data-theme]) .pkg-name,
  :root:not([data-theme]) .result-name,
  :root:not([data-theme]) .pkg-title,
  :root:not([data-theme]) .side-row span:last-child,
  :root:not([data-theme]) .variant-row,
  :root:not([data-theme]) .symbol{
    color:var(--text);
  }

  :root:not([data-theme]) .navlinks,
  :root:not([data-theme]) .navcta,
  :root:not([data-theme]) .lede,
  :root:not([data-theme]) .stat span,
  :root:not([data-theme]) .section p.intro,
  :root:not([data-theme]) .feature .num,
  :root:not([data-theme]) .feature p,
  :root:not([data-theme]) .pkg-desc,
  :root:not([data-theme]) .pkg-foot,
  :root:not([data-theme]) .page-head p,
  :root:not([data-theme]) .result-desc,
  :root:not([data-theme]) .result-meta,
  :root:not([data-theme]) .empty,
  :root:not([data-theme]) .crumbs,
  :root:not([data-theme]) .pkg-sub,
  :root:not([data-theme]) .content p,
  :root:not([data-theme]) .sidebox h3,
  :root:not([data-theme]) .side-row span:first-child,
  :root:not([data-theme]) .toc a,
  :root:not([data-theme]) .prose p,
  :root:not([data-theme]) .prose li,
  :root:not([data-theme]) .footer,
  :root:not([data-theme]) .copy{
    color:var(--muted);
  }

  :root:not([data-theme]) .chip{color:var(--chip-text)}

  :root:not([data-theme]) .btn.primary{
    background:#956000;
    border-color:#956000;
    color:#fffdf8;
  }

  :root:not([data-theme]) .terminal,
  :root:not([data-theme]) .terminal .termcode{
    color:#dce3ec;
  }
}
'''

site_block = r'''
/* ASMORY_PAGES_LIGHT_CONTRAST_V2 */

:root[data-theme="light"]{
  --text:#171c22;
  --muted:#525d68;
  --accent:#8f5b00;
  --accent-strong:#704600;
  --line:#d3ccbf;
}

:root[data-theme="light"] body,
:root[data-theme="light"] .brand,
:root[data-theme="light"] .chip,
:root[data-theme="light"] .theme-toggle,
:root[data-theme="light"] .btn.alt,
:root[data-theme="light"] .card h3,
:root[data-theme="light"] .flow div{
  color:var(--text);
}

:root[data-theme="light"] .lead,
:root[data-theme="light"] .card p,
:root[data-theme="light"] .section>p,
:root[data-theme="light"] footer{
  color:var(--muted);
}

:root[data-theme="light"] .btn:not(.alt){
  background:#956000;
  color:#fffdf8;
}

:root[data-theme="light"] .btn:not(.alt):hover{
  background:#784c00;
  color:#fffdf8;
}

/* Dark terminal is a deliberate contrast island. */
:root[data-theme="light"] .terminal,
:root[data-theme="light"] .terminal pre{
  color:#eef2f6;
}

:root[data-theme="light"] .terminal .gold{color:#f2b84b}
:root[data-theme="light"] .terminal .ok{color:#72dca3}

@media(prefers-color-scheme:light){
  :root:not([data-theme]){
    --text:#171c22;
    --muted:#525d68;
    --accent:#8f5b00;
    --accent-strong:#704600;
    --line:#d3ccbf;
  }

  :root:not([data-theme]) body,
  :root:not([data-theme]) .brand,
  :root:not([data-theme]) .chip,
  :root:not([data-theme]) .theme-toggle,
  :root:not([data-theme]) .btn.alt,
  :root:not([data-theme]) .card h3,
  :root:not([data-theme]) .flow div{
    color:var(--text);
  }

  :root:not([data-theme]) .lead,
  :root:not([data-theme]) .card p,
  :root:not([data-theme]) .section>p,
  :root:not([data-theme]) footer{
    color:var(--muted);
  }

  :root:not([data-theme]) .btn:not(.alt){
    background:#956000;
    color:#fffdf8;
  }

  :root:not([data-theme]) .terminal,
  :root:not([data-theme]) .terminal pre{
    color:#eef2f6;
  }
}
'''

doc_block = r'''
## Light-theme contrast policy

Asmory follows a stricter contrast rule for the light theme:

- ordinary text on light surfaces always uses dark semantic colors;
- secondary text uses graphite gray rather than pale gray;
- light foreground colors are only allowed on deliberately dark surfaces;
- terminals remain dark in both themes for stable syntax/terminal contrast;
- bronze primary buttons explicitly pair a dark-enough surface with light text.

This prevents dark-theme hardcoded foreground colors from leaking onto light
surfaces.
'''

def replace_tail_block(text: str, marker: str, block: str) -> str:
    pos = text.find(marker)
    if pos >= 0:
        text = text[:pos].rstrip()
    return text.rstrip() + "\n\n" + block.strip() + "\n"

app = replace_tail_block(APP.read_text(), APP_MARK, app_block)
site = replace_tail_block(SITE.read_text(), SITE_MARK, site_block)

APP.write_text(app)
SITE.write_text(site)

doc = DOC.read_text() if DOC.exists() else "# Asmory theming\n"
if DOC_MARK in doc:
    doc = doc[:doc.find(DOC_MARK)].rstrip()
doc = doc.rstrip() + "\n\n" + doc_block.strip() + "\n"
DOC.write_text(doc)
PY

echo "===== [2/7] static contrast audit ====="

python3 - <<'PY'
from pathlib import Path

checks = {
    "registry/static/app.css": [
        "ASMORY_LIGHT_CONTRAST_V2",
        ':root[data-theme="light"] .lede',
        ':root[data-theme="light"] .terminal',
        '--text:#171c22',
        'background:#956000',
    ],
    "site/style.css": [
        "ASMORY_PAGES_LIGHT_CONTRAST_V2",
        ':root[data-theme="light"] .lead',
        ':root[data-theme="light"] .terminal',
        '--text:#171c22',
        'background:#956000',
    ],
}

for filename, needles in checks.items():
    text = Path(filename).read_text()
    for needle in needles:
        assert needle in text, f"{filename}: missing {needle}"

print("contrast audit: ok")
PY

echo "===== [3/7] build ====="
make clean
make -j"$(nproc)"

echo "===== [4/7] smoke ====="
make check
make smoke
make cli-smoke

echo "===== [5/7] commit ====="
git add registry/static/app.css site/style.css docs/THEMING.md scripts/theme-contrast-fix.sh

if ! git diff --cached --quiet; then
  git commit -m "fix: improve light theme text contrast"
else
  echo "No changes to commit."
fi

echo "===== [6/7] push ====="
git push

echo "===== [7/7] status ====="
gh run list --repo Asmory/Asmory --limit 8

echo
echo "Pages: https://asmory.github.io/Asmory/"
echo "Local registry: make run"
