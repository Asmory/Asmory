#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fcntl
import hashlib
import os
from pathlib import Path
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import tomllib

TREE_SCHEMA = "asmory-tree-v1"


class StateError(RuntimeError):
    pass


def _feed_field(h, data: bytes) -> None:
    h.update(struct.pack(">Q", len(data)))
    h.update(data)


def _entry_kind(mode: int) -> bytes:
    if stat.S_ISREG(mode):
        return b"F"
    if stat.S_ISDIR(mode):
        return b"D"
    if stat.S_ISLNK(mode):
        return b"L"
    if stat.S_ISFIFO(mode):
        return b"P"
    if stat.S_ISCHR(mode):
        return b"C"
    if stat.S_ISBLK(mode):
        return b"B"
    if stat.S_ISSOCK(mode):
        return b"S"
    return b"?"


def tree_hash(root: Path) -> str:
    root = root.absolute()

    if not root.exists() or not root.is_dir() or root.is_symlink():
        raise StateError(f"tree root is missing or invalid: {root}")

    h = hashlib.sha256()
    h.update(TREE_SCHEMA.encode("ascii") + b"\0")

    def walk(directory: Path, rel_prefix: Path) -> None:
        try:
            entries = sorted(os.scandir(directory), key=lambda e: os.fsencode(e.name))
        except OSError as exc:
            raise StateError(f"cannot scan tree: {directory}: {exc}") from exc

        for entry in entries:
            rel = rel_prefix / entry.name
            rel_bytes = os.fsencode(rel.as_posix())

            try:
                st = entry.stat(follow_symlinks=False)
            except OSError as exc:
                raise StateError(f"cannot stat tree entry: {rel}: {exc}") from exc

            kind = _entry_kind(st.st_mode)
            h.update(kind)
            _feed_field(h, rel_bytes)
            h.update(struct.pack(">I", stat.S_IMODE(st.st_mode)))

            path = Path(entry.path)

            if kind == b"F":
                h.update(struct.pack(">Q", st.st_size))
                fh = hashlib.sha256()
                try:
                    with path.open("rb") as f:
                        for block in iter(lambda: f.read(1024 * 1024), b""):
                            fh.update(block)
                except OSError as exc:
                    raise StateError(f"cannot read tree file: {rel}: {exc}") from exc
                h.update(fh.digest())

            elif kind == b"D":
                walk(path, rel)

            elif kind == b"L":
                try:
                    target = os.readlink(path)
                except OSError as exc:
                    raise StateError(f"cannot read symlink: {rel}: {exc}") from exc
                _feed_field(h, os.fsencode(target))

            else:
                h.update(struct.pack(">Q", getattr(st, "st_rdev", 0)))

    walk(root, Path())
    return h.hexdigest()


def workspace_root() -> Path:
    root = Path.cwd()

    if not (root / "asm.toml").is_file() or not (root / "asm.lock").is_file():
        raise StateError("no initialized Asmory workspace; run 'asmory init' first")

    if not (root / ".asmory" / "deps").is_dir():
        raise StateError("workspace dependency root is missing")

    return root


def load_lock(root: Path) -> dict:
    try:
        data = tomllib.loads((root / "asm.lock").read_text())
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise StateError(f"cannot read asm.lock: {exc}") from exc

    if data.get("schema") != 1:
        raise StateError("unsupported asm.lock schema")

    if data.get("resolver_policy") != "asmory-v1":
        raise StateError("unsupported resolver policy")

    deps = data.get("dependency", [])
    if not isinstance(deps, list):
        raise StateError("asm.lock dependency records are malformed")

    if data.get("dependency_count") != len(deps):
        raise StateError("asm.lock dependency_count does not match records")

    seen: set[str] = set()

    for dep in deps:
        if not isinstance(dep, dict):
            raise StateError("asm.lock dependency entry is malformed")

        name = dep.get("name")
        if not isinstance(name, str) or not name:
            raise StateError("dependency is missing a name")

        if name in seen:
            raise StateError(f"duplicate dependency in asm.lock: {name}")

        seen.add(name)

    return data


def canonical_local_path(root: Path, dep: dict) -> Path:
    name = dep["name"]
    declared = dep.get("materialized_path")
    expected_rel = f".asmory/deps/{name}"

    if declared != expected_rel:
        raise StateError(
            f"unsafe/non-canonical materialized path for {name}: {declared!r}"
        )

    deps_root = (root / ".asmory" / "deps").resolve()
    local = (root / declared).absolute()

    try:
        parent = local.parent.resolve()
    except OSError as exc:
        raise StateError(f"cannot resolve dependency parent for {name}: {exc}") from exc

    if parent != deps_root:
        raise StateError(f"dependency path escapes .asmory/deps: {name}")

    return local


def dependency_state(root: Path, dep: dict) -> tuple[str, str | None]:
    local = canonical_local_path(root, dep)
    baseline = dep.get("materialized_tree_sha256")
    schema = dep.get("tree_hash_schema")

    if schema != TREE_SCHEMA or not isinstance(baseline, str) or len(baseline) != 64:
        return ("Unknown", None)

    if not local.exists() and not local.is_symlink():
        return ("Missing", None)

    if local.is_symlink() or not local.is_dir():
        return ("Modified", None)

    try:
        actual = tree_hash(local)
    except StateError:
        return ("Modified", None)

    return ("Exact" if actual == baseline else "Modified", actual)


def print_status(root: Path, data: dict) -> int:
    deps = data["dependency"]

    print("Workspace dependency status")
    print()

    if not deps:
        print("  dependencies  0")
        return 0

    for index, dep in enumerate(deps):
        state, actual = dependency_state(root, dep)

        if index:
            print()

        print(f"{dep['name']} {dep.get('release', '?')}")
        print(f"  state       {state}")
        print(f"  artifact    {dep.get('artifact_sha256', '?')}")
        print(f"  base tree   {dep.get('materialized_tree_sha256', 'unknown')}")
        print(f"  local tree  {actual if actual is not None else '-'}")
        print(f"  profile     {dep.get('profile', '?')}")
        print(f"  variant     {dep.get('variant', '?')}")
        print(f"  path        {dep.get('materialized_path', '?')}")

    return 0


def _find_dependency(data: dict, name: str) -> dict:
    for dep in data["dependency"]:
        if dep.get("name") == name:
            return dep

    raise StateError(f"dependency not found in asm.lock: {name}")


def _cache_object(dep: dict) -> Path:
    for key in ("name", "release", "artifact_sha256"):
        value = dep.get(key)

        if not isinstance(value, str) or not value:
            raise StateError(f"locked dependency is missing {key}")

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
        raise StateError(f"cannot obtain locked Artifact from cache: {exc}") from exc

    value = proc.stdout.strip()

    if not value:
        raise StateError("cache helper returned no object path")

    path = Path(value)

    if not path.is_file() or path.is_symlink():
        raise StateError("cache helper returned an invalid object")

    return path


def restore_dependency(root: Path, data: dict, name: str) -> int:
    dep = _find_dependency(data, name)
    local = canonical_local_path(root, dep)

    baseline = dep.get("materialized_tree_sha256")
    schema = dep.get("tree_hash_schema")

    if schema != TREE_SCHEMA or not isinstance(baseline, str) or len(baseline) != 64:
        raise StateError(
            f"{name}: lockfile lacks a supported materialization baseline; re-add is required"
        )

    state, _ = dependency_state(root, dep)

    if state == "Exact":
        print(f"{name}: already Exact")
        return 0

    if state == "Unknown":
        raise StateError(f"{name}: local integrity is Unknown; refusing restore")

    lock_path = root / ".asmory" / "workspace.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)

    with lock_path.open("a+b") as lock_file:
        try:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise StateError("another Asmory workspace mutation is in progress") from exc

        state, _ = dependency_state(root, dep)

        if state == "Exact":
            print(f"{name}: already Exact")
            return 0

        cache_object = _cache_object(dep)

        restore_root = root / ".asmory" / ".restore"
        restore_root.mkdir(mode=0o700, parents=True, exist_ok=True)
        stage = Path(tempfile.mkdtemp(prefix=f"restore-{name}-", dir=restore_root))
        deps_stage = stage / "deps"
        deps_stage.mkdir(mode=0o700)

        backup = restore_root / f"backup-{name}-{os.getpid()}"
        candidate = deps_stage / name
        restore_verified = False

        def remove_path(path: Path) -> None:
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
            elif path.exists() or path.is_symlink():
                path.unlink()

        try:
            try:
                subprocess.run(
                    [
                        "asmory-materialize",
                        name,
                        dep["artifact_sha256"],
                        str(cache_object),
                        str(deps_stage),
                    ],
                    check=True,
                    stdout=subprocess.DEVNULL,
                )
            except (OSError, subprocess.CalledProcessError) as exc:
                raise StateError(f"{name}: cannot materialize locked Artifact: {exc}") from exc

            new_hash = tree_hash(candidate)

            if new_hash != baseline:
                raise StateError(
                    f"{name}: restored tree does not match locked baseline "
                    f"({new_hash} != {baseline})"
                )

            had_old = local.exists() or local.is_symlink()

            if backup.exists() or backup.is_symlink():
                remove_path(backup)

            if had_old:
                os.rename(local, backup)

            try:
                os.rename(candidate, local)
            except Exception:
                if had_old and backup.exists() and not local.exists():
                    os.rename(backup, local)
                raise

            final_hash = tree_hash(local)

            if final_hash != baseline:
                raise StateError(f"{name}: post-restore verification failed")

            restore_verified = True

            if had_old and (backup.exists() or backup.is_symlink()):
                remove_path(backup)

        finally:
            shutil.rmtree(stage, ignore_errors=True)

            if backup.exists() or backup.is_symlink():
                if not restore_verified:
                    remove_path(local)
                    os.rename(backup, local)
                else:
                    remove_path(backup)

    print("Dependency restored")
    print()
    print(f"  package      {name}")
    print("  state        Exact")
    print(f"  artifact     {dep['artifact_sha256']}")
    print(f"  tree         {baseline}")
    print(f"  local        {dep['materialized_path']}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="asmory-state")
    sub = parser.add_subparsers(dest="command", required=True)

    tree = sub.add_parser("tree-hash")
    tree.add_argument("path")

    sub.add_parser("status")

    restore = sub.add_parser("restore")
    restore.add_argument("package")

    args = parser.parse_args()

    try:
        if args.command == "tree-hash":
            print(tree_hash(Path(args.path)))
            return 0

        root = workspace_root()
        data = load_lock(root)

        if args.command == "status":
            return print_status(root, data)

        if args.command == "restore":
            return restore_dependency(root, data, args.package)

        raise StateError("unknown command")

    except StateError as exc:
        print(f"state: {exc}", file=sys.stderr)
        return 17


if __name__ == "__main__":
    raise SystemExit(main())
