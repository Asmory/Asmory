#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$HOME/asm/Asmory}"
cd "$ROOT"

echo '===== [1/7] build ====='
make clean
make -j"$(nproc)"

echo '===== [2/7] checks ====='
make check
make smoke
make cli-smoke

echo '===== [3/7] CLI target ====='
./build/asmory target

echo '===== [4/7] commit ====='
git add .
if ! git diff --cached --quiet; then
  git commit -m 'feat: add Assembly CLI target detection and release pipeline'
else
  echo 'no new changes to commit'
fi

echo '===== [5/7] push ====='
git push origin main

echo '===== [6/7] organization profile ====='
./scripts/publish-org-profile.sh

echo '===== [7/7] GitHub status ====='
gh run list --repo Asmory/Asmory --limit 10

echo
echo 'CLI binary: ./build/asmory'
echo 'Install locally: make install-user'
echo 'Organization: https://github.com/Asmory'
echo 'Repository:   https://github.com/Asmory/Asmory'
echo 'Pages:        https://asmory.github.io/Asmory/'
