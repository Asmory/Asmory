#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import tomllib

base = Path("examples/simd-dot")
cap = tomllib.loads((base / "capability.toml").read_text())
contract = tomllib.loads((base / "contracts/core-v1.toml").read_text())
variants = tomllib.loads((base / "variants.toml").read_text())

cap_id = cap["capability"]["id"]
c = contract["contract"]
contract_ref = f'{c["id"]}@{c["version"]}'

assert cap["capability"]["authority"] == "none"
assert c["capability"] == cap_id

matched = 0
for variant in variants.get("variant", []):
    if variant.get("contract") == contract_ref:
        assert variant.get("capability") == cap_id
        assert variant.get("provider")
        assert variant.get("conformance_suite") == "core-v1-basic"
        matched += 1

if matched < 2:
    raise SystemExit(
        f"expected at least 2 Variants of {contract_ref}, found {matched}"
    )

print("contract-model: ok")
print("capability:", cap_id)
print("contract:", contract_ref)
print("variant candidates:", matched)
PY
