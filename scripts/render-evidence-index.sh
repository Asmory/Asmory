#!/usr/bin/env bash
set -euo pipefail

artifact="${1:?artifact required}"
contract="${2:?performance contract required}"
output="${3:?output required}"

python3 - "$artifact" "$contract" "$output" <<'PY'
import hashlib
import json
from pathlib import Path
import sys
import tomllib

artifact = Path(sys.argv[1])
contract = Path(sys.argv[2])
output = Path(sys.argv[3])

artifact_bytes = artifact.read_bytes()
contract_bytes = contract.read_bytes()
cfg = tomllib.loads(contract_bytes.decode())

data = {
    "registry": "Asmory",
    "schema": 1,
    "project": "simd-dot",
    "release": "0.1.0",
    "artifact": {
        "kind": "source",
        "sha256": hashlib.sha256(artifact_bytes).hexdigest(),
        "size": len(artifact_bytes),
    },
    "benchmark_contract": {
        "id": cfg["benchmark_id"],
        "sha256": hashlib.sha256(contract_bytes).hexdigest(),
        "primary_metric": cfg["primary_metric"],
        "direction": cfg["direction"],
        "minimum_samples": cfg["minimum_samples"],
        "power_policy": {
            "policy": cfg["measurement"]["power"]["policy"],
            "required_mode": cfg["measurement"]["power"]["required_mode"],
            "fallback": cfg["measurement"]["power"]["fallback"],
            "restore_after_measurement": cfg["measurement"]["power"]["restore_after_measurement"],
        },
    },
    "policy": {
        "cross_machine_ranking": bool(cfg["evidence"]["cross_machine_ranking"]),
        "selection_order": [
            "semantic-compatibility",
            "machine-compatibility",
            "trust-policy",
            "comparable-performance-evidence",
        ],
    },
    "status": "no-accepted-current-artifact-evidence",
    "accepted_records": [],
}

output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(data, separators=(",", ":")) + "\n")
print("evidence-index:", output)
print("artifact:", data["artifact"]["sha256"])
print("contract:", data["benchmark_contract"]["sha256"])
PY
