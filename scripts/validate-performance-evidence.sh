#!/usr/bin/env bash
set -euo pipefail

evidence="${1:-build/performance/simd-dot-variants.json}"
artifact="${2:-build/packages/simd-dot-0.1.0.tar.gz}"
contract="${3:-examples/simd-dot/performance.toml}"

python3 - "$evidence" "$artifact" "$contract" <<'PY'
import hashlib
import json
from pathlib import Path
import sys
import tomllib

evidence_path = Path(sys.argv[1])
artifact_path = Path(sys.argv[2])
contract_path = Path(sys.argv[3])

d = json.loads(evidence_path.read_text())
cfg = tomllib.loads(contract_path.read_text())

artifact_sha = hashlib.sha256(artifact_path.read_bytes()).hexdigest()
contract_sha = hashlib.sha256(contract_path.read_bytes()).hexdigest()

assert d["schema"] == "asmory-performance-evidence-v2"
assert d["status"] == "local-candidate"
assert d["package"] == "simd-dot"
assert d["version"] == "0.1.0"
assert d["artifact"]["sha256"] == artifact_sha
assert d["benchmark"]["id"] == cfg["benchmark_id"]
assert d["benchmark"]["contract_sha256"] == contract_sha
assert d["correctness"]["state"] == "pass"

minimum = int(cfg["minimum_samples"])
assert d["correctness"]["samples"] >= minimum
assert len(d["raw_samples"]) >= minimum

orders = {row["order"] for row in d["raw_samples"]}
assert "ab" in orders and "ba" in orders

assert "x86_64-avx2-generic" in d["variants"]
assert "x86_64-avx2-fma-4acc" in d["variants"]
assert d["observation"]["scope"] == "this-machine-only"
assert d["observation"]["eligible_for_global_ranking"] is False
assert cfg["evidence"]["cross_machine_ranking"] is False

print("performance-evidence: valid local candidate")
print("artifact:", artifact_sha)
print("contract:", contract_sha)
print("samples:", len(d["raw_samples"]))
print("orders:", ",".join(sorted(orders)))
print("global ranking: forbidden by this evidence record")
PY
