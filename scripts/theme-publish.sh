#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$HOME/asm/Asmory}"
cd "$ROOT"

echo "===== [1/7] patch Registry pages ====="
python3 - <<'PY'
from pathlib import Path

for name in ("index.html", "packages.html", "package-simd-dot.html", "design.html"):
    p = Path("registry/static") / name
    text = p.read_text()

    # Ensure browser toolbar theme can be updated.
    if 'name="theme-color"' not in text:
        text = text.replace(
            '<meta name="viewport" content="width=device-width,initial-scale=1">',
            '<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="theme-color" content="#090a0d">',
            1
        )

    # Prevent a flash when a user explicitly selected a theme previously.
    boot = """<script>try{const t=localStorage.getItem('asmory-theme');if(t==='light'||t==='dark')document.documentElement.dataset.theme=t}catch(_){}</script>"""
    if "asmory-theme" not in text.split("</head>", 1)[0]:
        text = text.replace("</head>", boot + "</head>", 1)

    # design.html previously did not load shared JS.
    if '/static/app.js' not in text:
        text = text.replace("</body>", '<script src="/static/app.js"></script></body>', 1)

    p.write_text(text)
PY

echo "===== [2/7] build ====="
make clean
make -j"$(nproc)"

echo "===== [3/7] checks ====="
make check
make smoke
make cli-smoke

echo "===== [4/7] verify theme assets ====="
grep -q 'data-theme="light"' registry/static/app.css
grep -q 'asmory-theme' registry/static/app.js
grep -q 'data-theme-toggle' site/index.html
grep -q 'asmory-theme' site/theme.js
echo "theme assets: ok"

echo "===== [5/7] commit ====="
git add \
  registry/static/app.css \
  registry/static/app.js \
  registry/static/index.html \
  registry/static/packages.html \
  registry/static/package-simd-dot.html \
  registry/static/design.html \
  site/index.html \
  site/style.css \
  site/theme.js \
  docs/THEMING.md \
  scripts/theme-publish.sh

if ! git diff --cached --quiet; then
  git commit -m "feat: add persistent dark and light website themes"
else
  echo "No changes to commit."
fi

echo "===== [6/7] push ====="
git push

echo "===== [7/7] GitHub Actions ====="
gh run list --repo Asmory/Asmory --limit 8

echo
echo "Registry local: make run"
echo "Pages: https://asmory.github.io/Asmory/"
