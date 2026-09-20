#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 4 ]]; then
  echo "usage: asmory-acquire <package> <version> <expected-sha256> <output>" >&2
  exit 2
fi

package="$1"
version="$2"
expected="$3"
output="$4"

[[ "$package" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || {
  echo "acquire: invalid package identity" >&2
  exit 2
}
[[ "$version" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]*$ ]] || {
  echo "acquire: invalid release identity" >&2
  exit 2
}
[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || {
  echo "acquire: invalid expected SHA-256" >&2
  exit 2
}

registry="${ASMORY_REGISTRY_URL:-http://127.0.0.1:18080}"
registry="${registry%/}"

case "$registry" in
  https://*) ;;
  http://127.0.0.1|http://127.0.0.1:*|http://localhost|http://localhost:*) ;;
  http://*)
    echo "acquire: refusing non-loopback plaintext HTTP registry: $registry" >&2
    exit 9
    ;;
  *)
    echo "acquire: registry URL must use HTTPS (or loopback HTTP for local development)" >&2
    exit 9
    ;;
esac

command -v curl >/dev/null 2>&1 || {
  echo "acquire: bootstrap transport requires curl" >&2
  exit 10
}
command -v sha256sum >/dev/null 2>&1 || {
  echo "acquire: bootstrap verification requires sha256sum" >&2
  exit 10
}

if [[ -e "$output" || -L "$output" ]]; then
  echo "acquire: refusing to overwrite existing destination: $output" >&2
  exit 12
fi

parent="$(dirname -- "$output")"
[[ -d "$parent" ]] || {
  echo "acquire: destination parent does not exist: $parent" >&2
  exit 12
}

tmp="$(mktemp --tmpdir="$parent" ".asmory-acquire.${package}.${version}.XXXXXX")"
cleanup() { rm -f -- "$tmp"; }
trap cleanup EXIT INT TERM

url="$registry/api/v1/packages/$package/$version/download"

curl \
  --fail \
  --location \
  --silent \
  --show-error \
  --connect-timeout 5 \
  --max-time 60 \
  --proto '=http,https' \
  --proto-redir '=http,https' \
  --output "$tmp" \
  "$url"

actual="$(sha256sum "$tmp" | awk '{print $1}')"

if [[ "$actual" != "$expected" ]]; then
  echo "acquire: SHA-256 mismatch" >&2
  echo "  expected  $expected" >&2
  echo "  actual    $actual" >&2
  exit 11
fi

# Publish atomically without clobbering a destination created during download.
chmod 0444 "$tmp"
if ! ln -- "$tmp" "$output"; then
  echo "acquire: destination appeared during acquisition; refusing overwrite" >&2
  exit 12
fi
rm -f -- "$tmp"
trap - EXIT INT TERM

echo "Artifact acquired"
echo
echo "  package      $package"
echo "  release      $version"
echo "  sha256       $actual"
echo "  verification exact"
echo "  output       $output"
