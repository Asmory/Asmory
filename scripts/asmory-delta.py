#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import tomllib

DELTA_SCHEMA = 1
DELTA_FORMAT = "asmory-delta-v1"
TREE_SCHEMA = "asmory-tree-v1"


class DeltaError(RuntimeError):
    pass


def canonical_json_bytes(value: dict) -> bytes:
    return (
        json.dumps(
            value,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
        )
        + "\n"
    ).encode("utf-8")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def workspace_root() -> Path:
    root = Path.cwd()

    if not (root / "asm.toml").is_file() or not (root / "asm.lock").is_file():
        raise DeltaError("no initialized Asmory workspace; run 'asmory init' first")

    if not (root / ".asmory" / "deps").is_dir():
        raise DeltaError("workspace dependency root is missing")

    return root


def load_lock(root: Path) -> dict:
    try:
        data = tomllib.loads((root / "asm.lock").read_text())
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise DeltaError(f"cannot read asm.lock: {exc}") from exc

    if data.get("schema") != 1 or data.get("resolver_policy") != "asmory-v1":
        raise DeltaError("unsupported asm.lock format")

    deps = data.get("dependency", [])
    if not isinstance(deps, list):
        raise DeltaError("asm.lock dependency records are malformed")

    if data.get("dependency_count") != len(deps):
        raise DeltaError("asm.lock dependency_count does not match records")

    return data


def find_dependency(data: dict, name: str) -> dict:
    for dep in data.get("dependency", []):
        if dep.get("name") == name:
            return dep

    raise DeltaError(f"dependency not found in asm.lock: {name}")


def validate_locked_dependency(dep: dict) -> None:
    name = dep.get("name")
    source_kind = dep.get("source_kind", "registry")

    if source_kind != "registry":
        raise DeltaError(
            f"{name}: vendored dependency is project-owned; patch/reapply apply only to registry materializations"
        )

    release = dep.get("release")
    artifact = dep.get("artifact_sha256")
    tree_schema = dep.get("tree_hash_schema")
    base_tree = dep.get("materialized_tree_sha256")
    local_path = dep.get("materialized_path")

    if not isinstance(name, str) or re.fullmatch(r"[a-z0-9][a-z0-9._-]*", name) is None:
        raise DeltaError("locked dependency has invalid name")

    if not isinstance(release, str) or not release:
        raise DeltaError(f"{name}: locked release missing")

    if not isinstance(artifact, str) or re.fullmatch(r"[0-9a-f]{64}", artifact) is None:
        raise DeltaError(f"{name}: invalid locked Artifact SHA-256")

    if tree_schema != TREE_SCHEMA:
        raise DeltaError(f"{name}: unsupported tree hash schema")

    if not isinstance(base_tree, str) or re.fullmatch(r"[0-9a-f]{64}", base_tree) is None:
        raise DeltaError(f"{name}: invalid locked base tree hash")

    if local_path != f".asmory/deps/{name}":
        raise DeltaError(f"{name}: non-canonical materialized path")


def tree_hash(path: Path) -> str:
    try:
        proc = subprocess.run(
            ["asmory-state", "tree-hash", str(path)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise DeltaError(f"cannot compute tree hash for {path}: {exc}") from exc

    value = proc.stdout.strip()

    if re.fullmatch(r"[0-9a-f]{64}", value) is None:
        raise DeltaError(f"state helper returned invalid tree hash for {path}")

    return value


def cache_object(dep: dict) -> Path:
    try:
        proc = subprocess.run(
            [
                "asmory-cache",
                dep["name"],
                dep["release"],
                dep["artifact_sha256"],
                "--print-object",
            ],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise DeltaError(f"cannot obtain locked Artifact: {exc}") from exc

    path = Path(proc.stdout.strip())

    if not path.is_file() or path.is_symlink():
        raise DeltaError("cache helper returned invalid object")

    return path


def materialize_base(dep: dict, deps_root: Path) -> Path:
    object_path = cache_object(dep)

    try:
        subprocess.run(
            [
                "asmory-materialize",
                dep["name"],
                dep["artifact_sha256"],
                str(object_path),
                str(deps_root),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise DeltaError(f"cannot materialize locked base Artifact: {exc}") from exc

    base = deps_root / dep["name"]
    actual = tree_hash(base)

    if actual != dep["materialized_tree_sha256"]:
        raise DeltaError(
            f"locked base tree mismatch: {actual} != {dep['materialized_tree_sha256']}"
        )

    return base


def captured_mode(mode: int, path: str) -> int:
    bits = stat.S_IMODE(mode)

    if bits & ~0o777:
        raise DeltaError(
            f"patch capture v1 rejects special permission bits: {path}"
        )

    return bits


def scan_tree(root: Path) -> dict[str, dict]:
    if not root.is_dir() or root.is_symlink():
        raise DeltaError(f"cannot capture non-directory tree: {root}")

    result: dict[str, dict] = {}

    def walk(directory: Path, prefix: PurePosixPath) -> None:
        entries = sorted(os.scandir(directory), key=lambda entry: os.fsencode(entry.name))

        for entry in entries:
            rel = prefix / entry.name
            rel_text = rel.as_posix()
            st = entry.stat(follow_symlinks=False)

            if stat.S_ISDIR(st.st_mode):
                result[rel_text] = {
                    "kind": "dir",
                    "mode": captured_mode(st.st_mode, rel_text),
                }
                walk(Path(entry.path), rel)
                continue

            if stat.S_ISREG(st.st_mode):
                path = Path(entry.path)
                result[rel_text] = {
                    "kind": "file",
                    "mode": captured_mode(st.st_mode, rel_text),
                    "size": st.st_size,
                    "sha256": sha256_file(path),
                    "source_path": str(path),
                }
                continue

            if stat.S_ISLNK(st.st_mode):
                raise DeltaError(
                    f"patch capture v1 rejects symlinks: {rel_text}; use vendor/fork later"
                )

            raise DeltaError(
                f"patch capture v1 rejects special file: {rel_text}"
            )

    walk(root, PurePosixPath())
    return result


def collapse_removed(paths: list[str]) -> list[str]:
    selected: list[str] = []

    for path in sorted(paths, key=lambda p: (len(PurePosixPath(p).parts), p)):
        parts = PurePosixPath(path).parts
        covered = False

        for parent in selected:
            parent_parts = PurePosixPath(parent).parts
            if len(parent_parts) <= len(parts) and parts[: len(parent_parts)] == parent_parts:
                covered = True
                break

        if not covered:
            selected.append(path)

    return sorted(selected)


def build_delta(base: Path, target: Path, blob_stage: Path, dep: dict) -> tuple[dict, str]:
    base_map = scan_tree(base)
    target_map = scan_tree(target)

    remove_candidates = [
        path
        for path in base_map
        if path not in target_map
        or base_map[path]["kind"] != target_map[path]["kind"]
    ]
    remove = collapse_removed(remove_candidates)

    put: list[dict] = []
    blob_stage.mkdir(parents=True, exist_ok=True)

    for path in sorted(target_map):
        target_entry = target_map[path]
        base_entry = base_map.get(path)

        same = False
        if base_entry and base_entry["kind"] == target_entry["kind"]:
            if target_entry["kind"] == "dir":
                same = base_entry["mode"] == target_entry["mode"]
            else:
                same = (
                    base_entry["mode"] == target_entry["mode"]
                    and base_entry["sha256"] == target_entry["sha256"]
                )

        if same:
            continue

        if target_entry["kind"] == "dir":
            put.append(
                {
                    "path": path,
                    "kind": "dir",
                    "mode": target_entry["mode"],
                }
            )
            continue

        blob_sha = target_entry["sha256"]
        blob_path = blob_stage / blob_sha

        if not blob_path.exists():
            shutil.copyfile(target_entry["source_path"], blob_path)

        if sha256_file(blob_path) != blob_sha:
            raise DeltaError(f"blob verification failed while capturing {path}")

        put.append(
            {
                "path": path,
                "kind": "file",
                "mode": target_entry["mode"],
                "size": target_entry["size"],
                "blob_sha256": blob_sha,
            }
        )

    target_tree = tree_hash(target)

    manifest = {
        "schema": DELTA_SCHEMA,
        "format": DELTA_FORMAT,
        "package": dep["name"],
        "base_artifact_sha256": dep["artifact_sha256"],
        "base_tree_sha256": dep["materialized_tree_sha256"],
        "target_tree_sha256": target_tree,
        "remove": remove,
        "put": put,
    }

    manifest_bytes = canonical_json_bytes(manifest)
    delta_sha = sha256_bytes(manifest_bytes)

    return manifest, delta_sha


def validate_relpath(text: str) -> PurePosixPath:
    path = PurePosixPath(text)

    if path.is_absolute() or not path.parts:
        raise DeltaError(f"invalid delta path: {text!r}")

    if any(part in ("", ".", "..") for part in path.parts):
        raise DeltaError(f"unsafe delta path: {text!r}")

    return path


def remove_path(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    elif path.exists() or path.is_symlink():
        path.unlink()


def apply_manifest(tree: Path, manifest: dict, blob_root: Path) -> None:
    remove = manifest.get("remove")
    put = manifest.get("put")

    if not isinstance(remove, list) or not isinstance(put, list):
        raise DeltaError("delta operations malformed")

    for text in sorted(remove, key=lambda p: (-len(validate_relpath(p).parts), p)):
        rel = validate_relpath(text)
        remove_path(tree.joinpath(*rel.parts))

    dir_ops = [op for op in put if isinstance(op, dict) and op.get("kind") == "dir"]
    file_ops = [op for op in put if isinstance(op, dict) and op.get("kind") == "file"]

    if len(dir_ops) + len(file_ops) != len(put):
        raise DeltaError("delta contains unsupported put operation")

    for op in sorted(dir_ops, key=lambda x: (len(validate_relpath(x["path"]).parts), x["path"])):
        rel = validate_relpath(op["path"])
        dest = tree.joinpath(*rel.parts)
        mode = op.get("mode")

        if not isinstance(mode, int) or not (0 <= mode <= 0o777):
            raise DeltaError(f"invalid directory mode for {op['path']}")

        if dest.exists() or dest.is_symlink():
            if not dest.is_dir() or dest.is_symlink():
                remove_path(dest)
                dest.mkdir(parents=True, mode=0o755)
        else:
            dest.mkdir(parents=True, mode=0o755)

    for op in sorted(file_ops, key=lambda x: x["path"]):
        rel = validate_relpath(op["path"])
        dest = tree.joinpath(*rel.parts)
        mode = op.get("mode")
        blob_sha = op.get("blob_sha256")
        size = op.get("size")

        if not isinstance(mode, int) or not (0 <= mode <= 0o777):
            raise DeltaError(f"invalid file mode for {op['path']}")

        if not isinstance(blob_sha, str) or re.fullmatch(r"[0-9a-f]{64}", blob_sha) is None:
            raise DeltaError(f"invalid blob identity for {op['path']}")

        if not isinstance(size, int) or size < 0:
            raise DeltaError(f"invalid file size for {op['path']}")

        blob = blob_root / blob_sha
        if not blob.is_file() or blob.is_symlink():
            raise DeltaError(f"delta blob missing: {blob_sha}")

        if blob.stat().st_size != size or sha256_file(blob) != blob_sha:
            raise DeltaError(f"delta blob verification failed: {blob_sha}")

        dest.parent.mkdir(parents=True, exist_ok=True)

        if dest.exists() or dest.is_symlink():
            remove_path(dest)

        shutil.copyfile(blob, dest)
        dest.chmod(mode)

    for op in sorted(
        dir_ops,
        key=lambda x: (-len(validate_relpath(x["path"]).parts), x["path"]),
    ):
        rel = validate_relpath(op["path"])
        tree.joinpath(*rel.parts).chmod(op["mode"])


def verify_manifest(manifest_path: Path, expected_delta: str, dep: dict) -> dict:
    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise DeltaError("active delta manifest missing")

    raw = manifest_path.read_bytes()

    if sha256_bytes(raw) != expected_delta:
        raise DeltaError("active delta manifest digest mismatch")

    try:
        manifest = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise DeltaError(f"active delta manifest is invalid JSON: {exc}") from exc

    if canonical_json_bytes(manifest) != raw:
        raise DeltaError("active delta manifest is not canonical")

    if manifest.get("schema") != DELTA_SCHEMA or manifest.get("format") != DELTA_FORMAT:
        raise DeltaError("unsupported delta format")

    checks = {
        "package": dep["name"],
        "base_artifact_sha256": dep["artifact_sha256"],
        "base_tree_sha256": dep["materialized_tree_sha256"],
    }

    for key, expected in checks.items():
        if manifest.get(key) != expected:
            raise DeltaError(f"delta {key} does not match lockfile")

    target = manifest.get("target_tree_sha256")
    if not isinstance(target, str) or re.fullmatch(r"[0-9a-f]{64}", target) is None:
        raise DeltaError("delta target tree hash invalid")

    return manifest


def patch_paths(root: Path, name: str) -> tuple[Path, Path, Path]:
    package_root = root / ".asmory" / "patches" / name
    return (
        package_root,
        package_root / "deltas",
        package_root / "blobs",
    )


def active_delta(root: Path, dep: dict) -> tuple[str, dict, Path]:
    package_root, deltas_root, blobs_root = patch_paths(root, dep["name"])
    active_path = package_root / "active"

    try:
        delta_sha = active_path.read_text().strip()
    except OSError as exc:
        raise DeltaError(f"no captured patch for {dep['name']}") from exc

    if re.fullmatch(r"[0-9a-f]{64}", delta_sha) is None:
        raise DeltaError("active patch pointer is invalid")

    manifest = verify_manifest(deltas_root / f"{delta_sha}.json", delta_sha, dep)
    return delta_sha, manifest, blobs_root


def atomic_publish_file(src: Path, dst: Path, expected_sha: str) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)

    if dst.exists() or dst.is_symlink():
        if not dst.is_file() or dst.is_symlink() or sha256_file(dst) != expected_sha:
            raise DeltaError(f"existing captured blob conflicts: {dst}")
        return

    try:
        os.link(src, dst)
    except FileExistsError:
        if sha256_file(dst) != expected_sha:
            raise DeltaError(f"captured blob race mismatch: {dst}")


def capture(root: Path, dep: dict) -> int:
    validate_locked_dependency(dep)
    name = dep["name"]
    local = root / dep["materialized_path"]

    if not local.is_dir() or local.is_symlink():
        raise DeltaError(f"{name}: local dependency tree is missing or invalid")

    actual = tree_hash(local)
    baseline = dep["materialized_tree_sha256"]

    if actual == baseline:
        raise DeltaError(f"{name}: tree is Exact; there is no local divergence to capture")

    lock_path = root / ".asmory" / "workspace.lock"

    with lock_path.open("a+b") as lock_file:
        try:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise DeltaError("another Asmory workspace mutation is in progress") from exc

        # Recompute after acquiring the lock.
        actual = tree_hash(local)
        if actual == baseline:
            raise DeltaError(f"{name}: tree became Exact; nothing to capture")

        runtime = root / ".asmory" / ".delta"
        runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
        stage = Path(tempfile.mkdtemp(prefix=f"capture-{name}-", dir=runtime))

        try:
            base_deps = stage / "base-deps"
            base_deps.mkdir()
            base = materialize_base(dep, base_deps)

            staged_blobs = stage / "blobs"
            manifest, delta_sha = build_delta(base, local, staged_blobs, dep)
            manifest_bytes = canonical_json_bytes(manifest)

            # Validate the delta by replaying it onto a second exact base before
            # exposing any captured record to the project.
            verify_deps = stage / "verify-deps"
            verify_deps.mkdir()
            candidate = materialize_base(dep, verify_deps)
            apply_manifest(candidate, manifest, staged_blobs)

            replay_hash = tree_hash(candidate)
            if replay_hash != actual:
                raise DeltaError(
                    f"captured delta replay mismatch: {replay_hash} != {actual}"
                )

            package_root, deltas_root, blobs_root = patch_paths(root, name)
            deltas_root.mkdir(parents=True, exist_ok=True)
            blobs_root.mkdir(parents=True, exist_ok=True)

            for blob in sorted(staged_blobs.iterdir(), key=lambda p: p.name):
                atomic_publish_file(blob, blobs_root / blob.name, blob.name)

            manifest_path = deltas_root / f"{delta_sha}.json"
            if manifest_path.exists() or manifest_path.is_symlink():
                if (
                    not manifest_path.is_file()
                    or manifest_path.is_symlink()
                    or manifest_path.read_bytes() != manifest_bytes
                ):
                    raise DeltaError("existing delta identity conflicts with captured manifest")
            else:
                tmp_manifest = deltas_root / f".{delta_sha}.tmp-{os.getpid()}"
                tmp_manifest.write_bytes(manifest_bytes)
                tmp_manifest.chmod(0o644)
                try:
                    os.link(tmp_manifest, manifest_path)
                except FileExistsError:
                    if manifest_path.read_bytes() != manifest_bytes:
                        raise DeltaError("delta publication race mismatch")
                finally:
                    tmp_manifest.unlink(missing_ok=True)

            active_tmp = package_root / f".active-{os.getpid()}"
            active_tmp.write_text(delta_sha + "\n")
            active_tmp.chmod(0o644)
            os.replace(active_tmp, package_root / "active")

        finally:
            shutil.rmtree(stage, ignore_errors=True)

    print("Local divergence captured")
    print()
    print(f"  package      {name}")
    print("  kind         deterministic-patch")
    print(f"  delta        {delta_sha}")
    print(f"  base tree    {baseline}")
    print(f"  target tree  {actual}")
    print(f"  tracked      .asmory/patches/{name}/")
    return 0


def transactional_publish(root: Path, dep: dict, candidate: Path, expected_tree: str) -> None:
    local = root / dep["materialized_path"]
    runtime = root / ".asmory" / ".delta"
    backup = runtime / f"reapply-backup-{dep['name']}-{os.getpid()}"
    verified = False

    def cleanup_path(path: Path) -> None:
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        elif path.exists() or path.is_symlink():
            path.unlink()

    had_old = local.exists() or local.is_symlink()

    if backup.exists() or backup.is_symlink():
        cleanup_path(backup)

    if had_old:
        os.rename(local, backup)

    try:
        os.rename(candidate, local)

        if tree_hash(local) != expected_tree:
            raise DeltaError("post-publication patched tree verification failed")

        verified = True

        if had_old and (backup.exists() or backup.is_symlink()):
            cleanup_path(backup)

    finally:
        if not verified and (backup.exists() or backup.is_symlink()):
            cleanup_path(local)
            os.rename(backup, local)


def reapply(root: Path, dep: dict) -> int:
    validate_locked_dependency(dep)
    name = dep["name"]
    local = root / dep["materialized_path"]
    baseline = dep["materialized_tree_sha256"]

    delta_sha, manifest, blobs_root = active_delta(root, dep)
    target = manifest["target_tree_sha256"]

    if local.exists() or local.is_symlink():
        if not local.is_dir() or local.is_symlink():
            raise DeltaError(f"{name}: local dependency root is invalid")

        actual = tree_hash(local)

        if actual == target:
            print(f"{name}: captured patch already applied")
            return 0

        if actual != baseline:
            raise DeltaError(
                f"{name}: refusing to overwrite uncaptured Modified work; "
                "restore or capture it first"
            )

    lock_path = root / ".asmory" / "workspace.lock"

    with lock_path.open("a+b") as lock_file:
        try:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise DeltaError("another Asmory workspace mutation is in progress") from exc

        runtime = root / ".asmory" / ".delta"
        runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
        stage = Path(tempfile.mkdtemp(prefix=f"reapply-{name}-", dir=runtime))

        try:
            deps_stage = stage / "deps"
            deps_stage.mkdir()
            candidate = materialize_base(dep, deps_stage)
            apply_manifest(candidate, manifest, blobs_root)

            actual = tree_hash(candidate)
            if actual != target:
                raise DeltaError(
                    f"patched tree verification failed: {actual} != {target}"
                )

            transactional_publish(root, dep, candidate, target)

        finally:
            shutil.rmtree(stage, ignore_errors=True)

    print("Captured patch reapplied")
    print()
    print(f"  package      {name}")
    print(f"  delta        {delta_sha}")
    print(f"  state        Modified")
    print("  capture      captured-patch")
    print(f"  target tree  {target}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="asmory-delta")
    sub = parser.add_subparsers(dest="command", required=True)

    capture_p = sub.add_parser("capture")
    capture_p.add_argument("package")

    reapply_p = sub.add_parser("reapply")
    reapply_p.add_argument("package")

    args = parser.parse_args()

    try:
        root = workspace_root()
        data = load_lock(root)
        dep = find_dependency(data, args.package)

        if args.command == "capture":
            return capture(root, dep)

        if args.command == "reapply":
            return reapply(root, dep)

        raise DeltaError("unknown command")

    except DeltaError as exc:
        print(f"delta: {exc}", file=sys.stderr)
        return 19


if __name__ == "__main__":
    raise SystemExit(main())
