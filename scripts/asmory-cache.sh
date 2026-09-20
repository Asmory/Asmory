#!/usr/bin/env bash
set -euo pipefail

print_object=0
if [[ "$#" -eq 4 && "$4" == "--print-object" ]]; then
  print_object=1
elif [[ "$#" -ne 3 ]]; then
  echo "usage: asmory-cache <package> <version> <expected-sha256> [--print-object]" >&2
  exit 2
fi

package="$1"
version="$2"
expected="$3"

[[ "$package" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || {
  echo "cache: invalid package identity" >&2
  exit 2
}
[[ "$version" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]*$ ]] || {
  echo "cache: invalid release identity" >&2
  exit 2
}
[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || {
  echo "cache: invalid expected SHA-256" >&2
  exit 2
}

command -v sha256sum >/dev/null 2>&1 || {
  echo "cache: bootstrap verification requires sha256sum" >&2
  exit 10
}
command -v asmory-acquire >/dev/null 2>&1 || {
  echo "cache: bootstrap acquisition backend unavailable" >&2
  exit 10
}

if [[ -n "${ASMORY_CACHE_HOME:-}" ]]; then
  cache_root="$ASMORY_CACHE_HOME"
elif [[ -n "${XDG_CACHE_HOME:-}" ]]; then
  cache_root="$XDG_CACHE_HOME/asmory"
elif [[ -n "${HOME:-}" ]]; then
  cache_root="$HOME/.cache/asmory"
else
  echo "cache: HOME/XDG_CACHE_HOME unavailable and ASMORY_CACHE_HOME not set" >&2
  exit 10
fi

parent="$cache_root/objects/sha256"
object="$parent/$expected"
mkdir -p -- "$parent"

verify_object() {
  local path="$1"
  [[ -f "$path" && ! -L "$path" ]] || return 1
  local actual
  actual="$(sha256sum "$path" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]]
}

if [[ -e "$object" || -L "$object" ]]; then
  if ! verify_object "$object"; then
    echo "cache: corruption detected at content-addressed path" >&2
    echo "  expected  $expected" >&2
    echo "  path      $object" >&2
    echo "cache: refusing silent repair or overwrite" >&2
    exit 13
  fi

  if (( print_object )); then
    printf '%s\n' "$object"
  else
    echo "Cache hit"
    echo
    echo "  package      $package"
    echo "  release      $version"
    echo "  sha256       $expected"
    echo "  verification exact"
    echo "  object       $object"
  fi
  exit 0
fi

stage="$(mktemp -d --tmpdir="$parent" ".asmory-cache.${expected}.XXXXXX")"
cleanup() {
  rm -rf -- "$stage"
}
trap cleanup EXIT INT TERM

asmory-acquire "$package" "$version" "$expected" "$stage/artifact" >/dev/null

# Atomic, no-clobber publication on the same filesystem.
if ln -- "$stage/artifact" "$object" 2>/dev/null; then
  chmod 0444 "$object"
else
  # A concurrent writer may have won. Reuse only if independently verified.
  if ! verify_object "$object"; then
    echo "cache: publication race produced a non-verifiable object" >&2
    exit 13
  fi
fi

rm -rf -- "$stage"
trap - EXIT INT TERM

if ! verify_object "$object"; then
  echo "cache: post-publication verification failed" >&2
  exit 13
fi

if (( print_object )); then
  printf '%s\n' "$object"
else
  echo "Cache populated"
  echo
  echo "  package      $package"
  echo "  release      $version"
  echo "  sha256       $expected"
  echo "  verification exact"
  echo "  object       $object"
fi
