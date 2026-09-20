#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys
import tarfile
import tempfile

MAX_MEMBERS = 10_000
MAX_TOTAL_BYTES = 256 * 1024 * 1024
MAX_FILE_BYTES = 128 * 1024 * 1024
AT_FDCWD = -100
RENAME_NOREPLACE = 1


class MaterializeError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def validate_member(package: str, member: tarfile.TarInfo, seen: set[str]) -> int:
    name = member.name

    if not name or "\x00" in name:
        raise MaterializeError("archive contains an empty/NUL path")
    if name.startswith("/"):
        raise MaterializeError(f"absolute archive path rejected: {name!r}")

    path = PurePosixPath(name)
    parts = path.parts

    if not parts or parts[0] != package:
        raise MaterializeError(
            f"archive member must stay under top-level {package!r}: {name!r}"
        )
    if any(part in (".", "..") for part in parts):
        raise MaterializeError(f"path traversal component rejected: {name!r}")

    normalized = str(path)
    if normalized in seen:
        raise MaterializeError(f"duplicate archive path rejected: {name!r}")
    seen.add(normalized)

    if member.issym():
        raise MaterializeError(f"symbolic link rejected in MVP: {name!r}")
    if member.islnk():
        raise MaterializeError(f"hard link rejected in MVP: {name!r}")
    if member.ischr() or member.isblk() or member.isfifo():
        raise MaterializeError(f"special file rejected: {name!r}")
    if not (member.isdir() or member.isreg()):
        raise MaterializeError(f"unsupported tar member type rejected: {name!r}")

    if member.size < 0 or member.size > MAX_FILE_BYTES:
        raise MaterializeError(f"member size limit exceeded: {name!r}")

    return member.size if member.isreg() else 0


def secure_members(tf: tarfile.TarFile, package: str) -> list[tarfile.TarInfo]:
    members = tf.getmembers()
    if len(members) > MAX_MEMBERS:
        raise MaterializeError(
            f"archive member count exceeds limit ({len(members)} > {MAX_MEMBERS})"
        )

    seen: set[str] = set()
    total = 0
    has_package_content = False

    for member in members:
        total += validate_member(package, member, seen)
        if total > MAX_TOTAL_BYTES:
            raise MaterializeError(
                f"archive expanded size exceeds {MAX_TOTAL_BYTES} bytes"
            )
        parts = PurePosixPath(member.name).parts
        if parts and parts[0] == package:
            has_package_content = True

    if not has_package_content:
        raise MaterializeError(f"archive has no {package!r} package root")

    return members


def extract_regular_tree(
    tf: tarfile.TarFile,
    members: list[tarfile.TarInfo],
    package: str,
    extract_root: Path,
) -> Path:
    for member in members:
        rel = PurePosixPath(member.name)
        dest = extract_root.joinpath(*rel.parts)

        if member.isdir():
            dest.mkdir(mode=0o755, parents=True, exist_ok=True)
            if dest.is_symlink():
                raise MaterializeError(f"directory became symlink: {member.name!r}")
            continue

        dest.parent.mkdir(mode=0o755, parents=True, exist_ok=True)

        if dest.exists() or dest.is_symlink():
            raise MaterializeError(f"archive destination collision: {member.name!r}")

        source = tf.extractfile(member)
        if source is None:
            raise MaterializeError(f"cannot read regular member: {member.name!r}")

        try:
            with source, dest.open("xb") as out:
                shutil.copyfileobj(source, out, length=1024 * 1024)
        except OSError as exc:
            raise MaterializeError(
                f"cannot extract {member.name!r}: {exc}"
            ) from exc

    package_root = extract_root / package
    if not package_root.is_dir() or package_root.is_symlink():
        raise MaterializeError("extracted package root is missing or invalid")

    roots = list(extract_root.iterdir())
    if len(roots) != 1 or roots[0] != package_root:
        names = ", ".join(sorted(x.name for x in roots))
        raise MaterializeError(f"unexpected top-level archive entries: {names}")

    return package_root


def normalize_modes(root: Path) -> None:
    root.chmod(0o755)

    for path in root.rglob("*"):
        st = path.lstat()

        if stat.S_ISLNK(st.st_mode):
            raise MaterializeError(f"symlink appeared after extraction: {path}")

        if path.is_dir():
            path.chmod(0o755)
        elif path.is_file():
            old = stat.S_IMODE(st.st_mode)
            path.chmod(0o644 | (old & 0o111))
        else:
            raise MaterializeError(f"special file appeared after extraction: {path}")


def rename_noreplace(src: Path, dst: Path) -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    func = getattr(libc, "renameat2", None)

    if func is None:
        if dst.exists() or dst.is_symlink():
            raise FileExistsError(dst)
        os.rename(src, dst)
        return

    func.argtypes = [
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_uint,
    ]
    func.restype = ctypes.c_int

    rc = func(
        AT_FDCWD,
        os.fsencode(src),
        AT_FDCWD,
        os.fsencode(dst),
        RENAME_NOREPLACE,
    )
    if rc == 0:
        return

    err = ctypes.get_errno()

    if err == errno.ENOSYS:
        if dst.exists() or dst.is_symlink():
            raise FileExistsError(dst)
        os.rename(src, dst)
        return

    raise OSError(err, os.strerror(err), str(dst))


def materialize(
    package: str,
    expected: str,
    cache_object: Path,
    deps_root: Path,
) -> Path:
    if re.fullmatch(r"[a-z0-9][a-z0-9._-]*", package) is None:
        raise MaterializeError("invalid package name")
    if re.fullmatch(r"[0-9a-f]{64}", expected) is None:
        raise MaterializeError("invalid SHA-256")

    deps_root = deps_root.resolve()
    cache_object = cache_object.resolve()

    if not deps_root.is_dir():
        raise MaterializeError(f"dependency root does not exist: {deps_root}")
    if not cache_object.is_file():
        raise MaterializeError(f"cache object missing: {cache_object}")

    final = deps_root / package
    if final.exists() or final.is_symlink():
        raise MaterializeError(f"dependency destination already exists: {final}")

    workspace_local = deps_root.parent
    staging_root = workspace_local / ".staging"
    staging_root.mkdir(mode=0o700, parents=True, exist_ok=True)

    stage = Path(
        tempfile.mkdtemp(
            prefix=f"materialize-{package}-",
            dir=staging_root,
        )
    )

    try:
        # Snapshot before verification. Hashing and extraction then operate on the
        # exact same private bytes, rather than on a cache pathname that another
        # local process could mutate between the two operations.
        snapshot = stage / "artifact.snapshot"
        shutil.copyfile(cache_object, snapshot)

        actual = sha256_file(snapshot)
        if actual != expected:
            raise MaterializeError(
                f"cache snapshot SHA-256 mismatch: expected {expected}, got {actual}"
            )

        extract_root = stage / "extract"
        extract_root.mkdir(mode=0o700)

        try:
            with tarfile.open(snapshot, mode="r:gz") as tf:
                members = secure_members(tf, package)
                package_root = extract_regular_tree(
                    tf,
                    members,
                    package,
                    extract_root,
                )
        except (tarfile.TarError, OSError) as exc:
            raise MaterializeError(f"cannot read source Artifact: {exc}") from exc

        normalize_modes(package_root)

        # Publish only a completely validated and extracted tree.
        rename_noreplace(package_root, final)
        return final
    finally:
        shutil.rmtree(stage, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="asmory-materialize",
        description="Safely materialize a verified Asmory source Artifact",
    )
    parser.add_argument("package")
    parser.add_argument("expected_sha256")
    parser.add_argument("cache_object")
    parser.add_argument("deps_root")
    args = parser.parse_args()

    try:
        final = materialize(
            args.package,
            args.expected_sha256,
            Path(args.cache_object),
            Path(args.deps_root),
        )
    except (MaterializeError, FileExistsError, OSError, tarfile.TarError) as exc:
        print(f"materialize: {exc}", file=sys.stderr)
        return 16

    print(final)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
