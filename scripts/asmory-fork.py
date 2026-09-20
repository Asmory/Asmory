#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fcntl
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import tomllib

NAME_RE = re.compile(r"[a-z0-9][a-z0-9._-]*")
SHA_RE = re.compile(r"[0-9a-f]{64}")
WORKSPACE_FILE = "asmory.workspace.toml"
PACKAGE_FILE = "asmory.package.toml"


class ForkError(RuntimeError):
    pass


def run(args: list[str], *, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            args,
            cwd=cwd,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ForkError(f"command failed: {' '.join(args)}: {exc}") from exc


def project_root() -> Path:
    root = Path.cwd().resolve()

    if not (root / "asm.toml").is_file() or not (root / "asm.lock").is_file():
        raise ForkError("no initialized Asmory project workspace; run 'asmory init' first")

    try:
        git_root = Path(
            run(["git", "rev-parse", "--show-toplevel"], cwd=root).stdout.strip()
        ).resolve()
    except ForkError as exc:
        raise ForkError("fork requires a Git working tree") from exc

    if git_root != root:
        raise ForkError(
            "fork MVP requires the Asmory project workspace to be the Git repository root"
        )

    return root


def load_lock(root: Path) -> dict:
    try:
        data = tomllib.loads((root / "asm.lock").read_text())
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise ForkError(f"cannot read asm.lock: {exc}") from exc

    if data.get("schema") != 1 or data.get("resolver_policy") != "asmory-v1":
        raise ForkError("unsupported asm.lock format")

    deps = data.get("dependency", [])
    if not isinstance(deps, list) or data.get("dependency_count") != len(deps):
        raise ForkError("asm.lock dependency records are malformed")

    return data


def find_dep(lock: dict, package: str) -> dict:
    matches = [
        dep for dep in lock.get("dependency", [])
        if isinstance(dep, dict) and dep.get("name") == package
    ]

    if len(matches) != 1:
        raise ForkError(f"dependency not found uniquely in asm.lock: {package}")

    dep = matches[0]

    for key in (
        "release",
        "artifact_sha256",
        "materialized_tree_sha256",
        "semantic_fingerprint",
        "profile",
        "provider",
        "variant",
    ):
        value = dep.get(key)
        if not isinstance(value, str) or not value:
            raise ForkError(f"{package}: locked dependency missing {key}")

    for key in ("artifact_sha256", "materialized_tree_sha256", "semantic_fingerprint"):
        if SHA_RE.fullmatch(dep[key]) is None:
            raise ForkError(f"{package}: invalid locked {key}")

    return dep


def active_source(root: Path, dep: dict) -> tuple[str, Path]:
    source_kind = dep.get("source_kind", "registry")
    name = dep["name"]

    if source_kind == "registry":
        expected = f".asmory/deps/{name}"
        if dep.get("materialized_path") != expected:
            raise ForkError(f"{name}: non-canonical registry materialized path")
        path = root / expected
    elif source_kind == "vendor":
        expected = f"vendor/{name}"
        if dep.get("vendor_path") != expected:
            raise ForkError(f"{name}: non-canonical vendor path")
        path = root / expected
    else:
        raise ForkError(f"{name}: unsupported source_kind {source_kind!r}")

    if not path.is_dir() or path.is_symlink():
        raise ForkError(f"{name}: active dependency tree is missing or invalid")

    return source_kind, path


def tree_hash(path: Path) -> str:
    proc = run(["asmory-state", "tree-hash", str(path)])
    value = proc.stdout.strip()

    if SHA_RE.fullmatch(value) is None:
        raise ForkError("state helper returned invalid tree hash")

    return value


def copy_tree(source: Path, destination: Path) -> None:
    destination.mkdir(mode=0o755)

    def walk(src: Path, dst: Path, *, root_level: bool = False) -> None:
        for entry in sorted(os.scandir(src), key=lambda e: os.fsencode(e.name)):
            if root_level and entry.name == PACKAGE_FILE:
                # The new fork receives a fresh identity manifest below.
                continue

            src_path = Path(entry.path)
            dst_path = dst / entry.name
            st = entry.stat(follow_symlinks=False)
            mode = stat.S_IMODE(st.st_mode)

            if mode & ~0o777:
                raise ForkError(f"fork rejects special permission bits: {src_path}")

            if stat.S_ISDIR(st.st_mode):
                dst_path.mkdir(mode=0o755)
                walk(src_path, dst_path)
                dst_path.chmod(mode)
                continue

            if stat.S_ISREG(st.st_mode):
                shutil.copyfile(src_path, dst_path, follow_symlinks=False)
                dst_path.chmod(mode)
                continue

            if stat.S_ISLNK(st.st_mode):
                raise ForkError(f"fork source v1 rejects symlink: {src_path}")

            raise ForkError(f"fork source v1 rejects special file: {src_path}")

    walk(source, destination, root_level=True)


def git_origin(root: Path) -> str:
    proc = run(["git", "remote", "get-url", "origin"], cwd=root)
    value = proc.stdout.strip()
    if not value:
        raise ForkError("Git origin remote is required to create repository workspace")
    return value


def parse_workspace(root: Path) -> tuple[str, list[str]] | None:
    path = root / WORKSPACE_FILE
    if not path.exists():
        return None

    try:
        data = tomllib.loads(path.read_text())
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise ForkError(f"cannot read {WORKSPACE_FILE}: {exc}") from exc

    if data.get("schema") != 1:
        raise ForkError("unsupported repository workspace schema")

    ws = data.get("workspace")
    if not isinstance(ws, dict):
        raise ForkError("repository workspace [workspace] table missing")

    # Refuse unsafe generic TOML rewriting. V1 only rewrites the canonical
    # shape it knows how to preserve exactly.
    if set(data) != {"schema", "workspace"}:
        raise ForkError("fork refuses non-canonical repository workspace top-level keys")
    if set(ws) != {"repository", "members"}:
        raise ForkError("fork refuses non-canonical repository workspace fields")

    repository = ws.get("repository")
    members = ws.get("members")

    if not isinstance(repository, str) or not repository:
        raise ForkError("repository workspace repository is invalid")

    if not isinstance(members, list) or not all(isinstance(x, str) for x in members):
        raise ForkError("repository workspace members are invalid")

    return repository, list(members)


def render_workspace(repository: str, members: list[str]) -> str:
    members = sorted(set(members))
    body = [
        "schema = 1",
        "",
        "[workspace]",
        f'repository = "{repository}"',
        "members = [",
    ]
    body.extend(f'    "{member}",' for member in members)
    body.append("]")
    body.append("")
    return "\n".join(body)


def toml_string(value: str) -> str:
    if any(c in value for c in ('"', "\\", "\n", "\r", "\t")):
        raise ForkError("fork metadata contains unsupported TOML string characters")
    return f'"{value}"'


def render_package_manifest(
    new_name: str,
    dep: dict,
    source_kind: str,
    source_tree: str,
) -> str:
    fields = [
        "schema = 1",
        "",
        "[package]",
        f"name = {toml_string(new_name)}",
        'version = "0.1.0"',
        "",
        "[origin]",
        'kind = "asmory-fork"',
        f"package = {toml_string(dep['name'])}",
        f"release = {toml_string(dep['release'])}",
        f"source_kind = {toml_string(source_kind)}",
        f"artifact_sha256 = {toml_string(dep['artifact_sha256'])}",
        f"base_tree_sha256 = {toml_string(dep['materialized_tree_sha256'])}",
        f"source_tree_sha256 = {toml_string(source_tree)}",
        f"semantic_fingerprint = {toml_string(dep['semantic_fingerprint'])}",
        f"profile = {toml_string(dep['profile'])}",
        f"provider = {toml_string(dep['provider'])}",
        f"variant = {toml_string(dep['variant'])}",
        "",
    ]
    return "\n".join(fields)


def ensure_runtime_ignores(root: Path) -> None:
    ignore = root / ".asmory" / ".gitignore"
    try:
        lines = ignore.read_text().splitlines()
    except OSError as exc:
        raise ForkError(f"cannot read .asmory/.gitignore: {exc}") from exc

    changed = False
    for item in (".fork/", ".publish/"):
        if item not in lines:
            lines.append(item)
            changed = True

    if changed:
        ignore.write_text("\n".join(lines) + "\n")


def fork_dependency(root: Path, package: str, new_name: str) -> int:
    if NAME_RE.fullmatch(package) is None or NAME_RE.fullmatch(new_name) is None:
        raise ForkError("package names must match [a-z0-9][a-z0-9._-]*")

    if package == new_name:
        raise ForkError("fork destination name must differ from source package")

    lock = load_lock(root)
    dep = find_dep(lock, package)
    source_kind, source = active_source(root, dep)
    source_tree = tree_hash(source)

    workspace = parse_workspace(root)
    if workspace is None:
        repository = git_origin(root)
        members: list[str] = []
    else:
        repository, members = workspace

    member = f"packages/{new_name}"
    destination = root / member

    if destination.exists() or destination.is_symlink():
        raise ForkError(f"fork destination already exists: {member}")

    if member in members:
        raise ForkError(f"repository workspace already contains member: {member}")

    # Prevent identity collision with another existing member.
    if (root / WORKSPACE_FILE).is_file():
        try:
            probe = run(["asmory-workspace", "list"], cwd=root).stdout
        except ForkError:
            probe = ""
        if re.search(rf"(?m)^{re.escape(new_name)}\s+", probe):
            raise ForkError(f"repository workspace already contains Package name: {new_name}")

    lock_path = root / ".asmory" / "workspace.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)

    with lock_path.open("a+b") as lock_file:
        try:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise ForkError("another Asmory workspace mutation is in progress") from exc

        # Recompute after lock acquisition so fork ancestry binds the bytes we
        # actually copy.
        if not source.is_dir() or source.is_symlink():
            raise ForkError(f"{package}: active source changed before fork")

        source_tree = tree_hash(source)

        runtime = root / ".asmory" / ".fork"
        runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
        stage = Path(tempfile.mkdtemp(prefix=f"fork-{new_name}-", dir=runtime))
        candidate = stage / new_name
        workspace_tmp = stage / WORKSPACE_FILE
        workspace_backup = stage / f"{WORKSPACE_FILE}.backup"
        workspace_path = root / WORKSPACE_FILE

        published_tree = False
        workspace_published = False
        committed = False

        try:
            copy_tree(source, candidate)

            copied_tree = tree_hash(candidate)
            if copied_tree != source_tree:
                raise ForkError(
                    f"fork copy verification failed: {copied_tree} != {source_tree}"
                )

            manifest = render_package_manifest(
                new_name,
                dep,
                source_kind,
                source_tree,
            )
            (candidate / PACKAGE_FILE).write_text(manifest)
            tomllib.loads(manifest)

            new_members = members + [member]
            workspace_tmp.write_text(render_workspace(repository, new_members))
            tomllib.loads(workspace_tmp.read_text())

            destination.parent.mkdir(parents=True, exist_ok=True)
            os.rename(candidate, destination)
            published_tree = True

            if workspace_path.exists():
                shutil.copyfile(workspace_path, workspace_backup)

            os.replace(workspace_tmp, workspace_path)
            workspace_published = True

            # The existing workspace checker is the final authority for member
            # boundaries and self-contained package roots.
            run(["asmory-workspace", "check"], cwd=root)

            # Artifact/source closure of the new Package must reproduce the
            # current source tree while excluding only the new control manifest.
            verify = stage / f"{new_name}-0.1.0.tar.gz"
            run(
                ["asmory-workspace", "pack", new_name, str(verify)],
                cwd=root,
            )

            listing = run(["tar", "-tzf", str(verify)]).stdout.splitlines()
            if f"{new_name}/{PACKAGE_FILE}" in listing:
                raise ForkError("fork identity manifest leaked into source Artifact payload")

            committed = True

        finally:
            if not committed:
                if workspace_published:
                    if workspace_backup.exists():
                        shutil.copyfile(workspace_backup, workspace_path)
                    else:
                        workspace_path.unlink(missing_ok=True)

                if published_tree:
                    shutil.rmtree(destination, ignore_errors=True)

            shutil.rmtree(stage, ignore_errors=True)

    ensure_runtime_ignores(root)

    print("Package fork created")
    print()
    print(f"  source       {package}@{dep['release']}")
    print(f"  source tree  {source_tree}")
    print(f"  new package  {new_name}@0.1.0")
    print(f"  member       {member}")
    print("  identity     independent")
    print("  repository   current Git repository only")
    print("  clone        not performed")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="asmory-fork")
    parser.add_argument("package")
    parser.add_argument("new_package")
    args = parser.parse_args()

    try:
        root = project_root()
        return fork_dependency(root, args.package, args.new_package)
    except (ForkError, OSError, tomllib.TOMLDecodeError) as exc:
        print(f"fork: {exc}", file=sys.stderr)
        return 22


if __name__ == "__main__":
    raise SystemExit(main())
