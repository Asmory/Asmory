#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import stat
import sys
import tempfile

OWNER_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")


class AuthError(RuntimeError):
    pass


def canonical_json(value: dict) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode()


def load(path: Path) -> dict:
    if not path.exists():
        return {"schema": 1, "tokens": []}

    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise AuthError(f"cannot read auth database: {exc}") from exc

    if data.get("schema") != 1 or not isinstance(data.get("tokens"), list):
        raise AuthError("unsupported auth database")

    return data


def atomic_write(path: Path, data: bytes, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    tmp = Path(tmp_name)

    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "wb", closefd=True) as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def issue(auth_file: Path, owner: str, token_file: Path) -> int:
    if OWNER_RE.fullmatch(owner) is None:
        raise AuthError("owner must match [A-Za-z0-9][A-Za-z0-9._-]{0,63}")

    if token_file.exists() or token_file.is_symlink():
        raise AuthError(f"token output already exists: {token_file}")

    data = load(auth_file)
    token = secrets.token_urlsafe(48)
    digest = hashlib.sha256(token.encode()).hexdigest()

    for record in data["tokens"]:
        if record.get("sha256") == digest:
            raise AuthError("generated token collision")

    data["tokens"].append(
        {
            "owner": owner,
            "sha256": digest,
            "enabled": True,
        }
    )
    data["tokens"].sort(key=lambda x: (x["owner"], x["sha256"]))

    atomic_write(auth_file, canonical_json(data), 0o600)
    atomic_write(token_file, (token + "\n").encode(), 0o600)

    print("Registry publication token issued")
    print()
    print(f"  owner        {owner}")
    print(f"  auth db      {auth_file}")
    print(f"  token file   {token_file}")
    print(f"  token sha256 {digest}")
    print("  plaintext    token file only")
    return 0


def revoke(auth_file: Path, token_sha256: str) -> int:
    if re.fullmatch(r"[0-9a-f]{64}", token_sha256) is None:
        raise AuthError("token SHA-256 is invalid")

    data = load(auth_file)
    found = False

    for record in data["tokens"]:
        if record.get("sha256") == token_sha256:
            record["enabled"] = False
            found = True

    if not found:
        raise AuthError("token digest not found")

    atomic_write(auth_file, canonical_json(data), 0o600)
    print(f"revoked: {token_sha256}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="asmory-registry-auth")
    sub = parser.add_subparsers(dest="command", required=True)

    issue_p = sub.add_parser("issue")
    issue_p.add_argument("auth_file")
    issue_p.add_argument("owner")
    issue_p.add_argument("token_file")

    revoke_p = sub.add_parser("revoke")
    revoke_p.add_argument("auth_file")
    revoke_p.add_argument("token_sha256")

    args = parser.parse_args()

    try:
        if args.command == "issue":
            return issue(Path(args.auth_file), args.owner, Path(args.token_file))
        if args.command == "revoke":
            return revoke(Path(args.auth_file), args.token_sha256)
        raise AuthError("unknown command")
    except AuthError as exc:
        print(f"registry-auth: {exc}", file=sys.stderr)
        return 25


if __name__ == "__main__":
    raise SystemExit(main())
