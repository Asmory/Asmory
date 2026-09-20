#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from copy import deepcopy
from pathlib import Path
import sys
import tomllib

sys.path.insert(0, str(Path("scripts").resolve()))
from semantic_model import match

impl = tomllib.loads(Path("examples/simd-dot/semantics.toml").read_text())
core = tomllib.loads(Path("examples/simd-dot/profiles/core-v1.toml").read_text())
strict = tomllib.loads(Path("examples/simd-dot/profiles/strict-v1.toml").read_text())

m = match(core, impl)
assert m["compatible"]
assert m["exact_semantic_identity"]

m = match(strict, impl)
assert not m["compatible"]
paths = {x["path"] for x in m["rejections"]}
assert "numeric.bit_exact" in paths
assert "numeric.absolute_error_max" in paths
assert "determinism.level" in paths

# Directional alignment:
# A consumer promising 64-byte alignment satisfies an implementation requiring 32.
impl32 = deepcopy(impl)
impl32["requires"]["memory"]["alignment_min_bytes"] = 32
consumer64 = deepcopy(core)
consumer64["semantics"]["guarantees"]["memory"]["alignment_min_bytes"] = 64
assert match(consumer64, impl32)["compatible"]

# But a caller promising only byte alignment cannot satisfy the same implementation.
consumer1 = deepcopy(core)
consumer1["semantics"]["guarantees"]["memory"]["alignment_min_bytes"] = 1
assert not match(consumer1, impl32)["compatible"]

# Stronger numeric guarantee satisfies a looser consumer maximum.
consumer_loose = deepcopy(core)
consumer_loose["semantics"]["requires"] = {
    "numeric": {
        "absolute_error_max": 0.0001,
        "relative_error_max": 0.001,
        "bit_exact": False,
    },
    "side_effects": {"allowed": []},
}
assert match(consumer_loose, impl)["compatible"]

# A tighter maximum than the implementation promises is rejected.
consumer_tight = deepcopy(core)
consumer_tight["semantics"]["requires"] = {
    "numeric": {
        "absolute_error_max": 0.0000001,
        "relative_error_max": 0.000001,
        "bit_exact": False,
    },
    "side_effects": {"allowed": []},
}
assert not match(consumer_tight, impl)["compatible"]

print("semantic-matching: ok")
print("  exact fingerprint identity: pass")
print("  minimum relation:            pass")
print("  maximum relation:            pass")
print("  subset relation:             pass")
print("  semantic alternative reject: pass")
PY
