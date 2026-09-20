#!/usr/bin/env python3
from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import fcntl
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
from urllib.parse import urlsplit

NAME_RE = re.compile(r"[a-z0-9][a-z0-9._-]*")
VERSION_RE = re.compile(r"[0-9]+(?:\.[0-9]+){2}(?:[-+][0-9A-Za-z.-]+)?")
SHA_RE = re.compile(r"[0-9a-f]{64}")
OWNER_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
MAX_CANDIDATE = 1024 * 1024
DEFAULT_MAX_ARTIFACT = 8 * 1024 * 1024 * 1024


class RegistryError(RuntimeError):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def canonical_json(value: dict) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode()


def fsync_dir(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def atomic_write(path: Path, data: bytes, mode: int = 0o444) -> None:
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
        fsync_dir(path.parent)
    finally:
        tmp.unlink(missing_ok=True)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


class RegistryState:
    def __init__(self, data_dir: Path, auth_file: Path, max_artifact: int):
        self.data_dir = data_dir
        self.auth_file = auth_file
        self.max_artifact = max_artifact
        self.objects = data_dir / "objects" / "sha256"
        self.projects = data_dir / "projects"
        self.locks = data_dir / "locks"
        self.incoming = data_dir / "incoming"
        for path in (self.objects, self.projects, self.locks, self.incoming):
            path.mkdir(parents=True, exist_ok=True)

    def auth_owner(self, header: str | None) -> str:
        if not header or not header.startswith("Bearer "):
            raise RegistryError(401, "missing Bearer publication token")

        token = header[7:].strip()
        if not (32 <= len(token) <= 512) or any(c.isspace() for c in token):
            raise RegistryError(401, "invalid publication token")

        try:
            st = self.auth_file.lstat()
        except OSError as exc:
            raise RegistryError(503, f"auth database unavailable: {exc}") from exc

        if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode):
            raise RegistryError(503, "auth database must be a regular non-symlink file")

        if stat.S_IMODE(st.st_mode) & 0o077:
            raise RegistryError(503, "auth database permissions are too broad")

        try:
            data = json.loads(self.auth_file.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            raise RegistryError(503, f"auth database invalid: {exc}") from exc

        if data.get("schema") != 1 or not isinstance(data.get("tokens"), list):
            raise RegistryError(503, "unsupported auth database")

        digest = hashlib.sha256(token.encode()).hexdigest()
        owner = None
        for record in data["tokens"]:
            stored = record.get("sha256")
            if not isinstance(stored, str):
                continue
            if hmac.compare_digest(stored, digest) and record.get("enabled") is True:
                candidate = record.get("owner")
                if isinstance(candidate, str) and OWNER_RE.fullmatch(candidate):
                    owner = candidate
                break

        if owner is None:
            raise RegistryError(401, "publication token is not authorized")

        return owner

    def project_lock(self, package: str):
        path = self.locks / f"{package}.lock"
        file = path.open("a+b")
        fcntl.flock(file.fileno(), fcntl.LOCK_EX)
        return file

    def object_path(self, digest: str) -> Path:
        return self.objects / digest

    def owner_path(self, package: str) -> Path:
        return self.projects / package / "owner.json"

    def candidate_path(self, package: str, version: str) -> Path:
        return self.projects / package / "candidates" / f"{version}.json"

    def validate_candidate(self, raw: bytes) -> dict:
        if len(raw) > MAX_CANDIDATE:
            raise RegistryError(413, "candidate exceeds 1 MiB")

        try:
            obj = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise RegistryError(400, f"candidate JSON invalid: {exc}") from exc

        if not isinstance(obj, dict):
            raise RegistryError(400, "candidate must be a JSON object")

        if canonical_json(obj) != raw:
            raise RegistryError(400, "candidate JSON must use canonical Asmory encoding")

        if obj.get("schema") != 1 or obj.get("kind") != "asmory-release-candidate":
            raise RegistryError(400, "unsupported release candidate")

        package = obj.get("package")
        source = obj.get("source")
        artifact = obj.get("artifact")
        boundary = obj.get("boundary")

        if not isinstance(package, dict):
            raise RegistryError(400, "candidate package identity missing")

        name = package.get("name")
        version = package.get("version")
        if not isinstance(name, str) or NAME_RE.fullmatch(name) is None:
            raise RegistryError(400, "candidate package name invalid")
        if not isinstance(version, str) or VERSION_RE.fullmatch(version) is None:
            raise RegistryError(400, "candidate package version invalid")

        if not isinstance(source, dict):
            raise RegistryError(400, "candidate source provenance missing")
        if source.get("kind") != "git":
            raise RegistryError(400, "candidate source provenance must be git")
        if source.get("worktree_dirty") is not False:
            raise RegistryError(400, "dirty source provenance cannot be staged")
        if not isinstance(source.get("repository"), str) or not source["repository"]:
            raise RegistryError(400, "candidate repository provenance missing")
        commit = source.get("commit")
        if not isinstance(commit, str) or re.fullmatch(r"[0-9a-f]{40}", commit) is None:
            raise RegistryError(400, "candidate Git commit invalid")
        subdir = source.get("subdir")
        if not isinstance(subdir, str) or not subdir or ".." in subdir.split("/"):
            raise RegistryError(400, "candidate Git subdir invalid")

        if not isinstance(artifact, dict):
            raise RegistryError(400, "candidate Artifact missing")
        digest = artifact.get("sha256")
        size = artifact.get("size")
        filename = artifact.get("filename")
        if artifact.get("kind") != "source":
            raise RegistryError(400, "candidate Artifact kind must be source")
        if not isinstance(digest, str) or SHA_RE.fullmatch(digest) is None:
            raise RegistryError(400, "candidate Artifact digest invalid")
        if not isinstance(size, int) or size < 0 or size > self.max_artifact:
            raise RegistryError(400, "candidate Artifact size invalid")
        if filename != f"{name}-{version}.tar.gz":
            raise RegistryError(400, "candidate Artifact filename does not match Package identity")

        if boundary != {
            "self_contained": True,
            "package_manifest_in_artifact": False,
        }:
            raise RegistryError(400, "candidate Package boundary declaration invalid")

        origin = obj.get("origin")
        if origin is not None and not isinstance(origin, dict):
            raise RegistryError(400, "candidate origin must be null or object")

        return obj

    def verify_object(self, digest: str, size: int | None = None) -> Path:
        path = self.object_path(digest)
        if not path.is_file() or path.is_symlink():
            raise RegistryError(409, "candidate references Artifact that has not been uploaded")
        if size is not None and path.stat().st_size != size:
            raise RegistryError(500, "stored Artifact size mismatch")
        if sha256_file(path) != digest:
            raise RegistryError(500, "stored Artifact digest mismatch")
        return path

    def read_owner(self, package: str) -> str | None:
        path = self.owner_path(package)
        if not path.exists():
            return None
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            raise RegistryError(500, f"project ownership record invalid: {exc}") from exc
        owner = data.get("owner")
        if data.get("schema") != 1 or data.get("package") != package or not isinstance(owner, str):
            raise RegistryError(500, "project ownership record invalid")
        return owner

    def claim_owner(self, package: str, owner: str) -> bool:
        path = self.owner_path(package)
        existing = self.read_owner(package)
        if existing is not None:
            if existing != owner:
                raise RegistryError(403, f"Package is owned by another publisher: {existing}")
            return False

        data = {
            "schema": 1,
            "package": package,
            "owner": owner,
        }
        atomic_write(path, canonical_json(data), 0o444)
        return True

    def rollback_owner_claim(self, package: str, owner: str) -> None:
        path = self.owner_path(package)
        try:
            current = self.read_owner(package)
            candidates = self.projects / package / "candidates"
            has_candidates = candidates.is_dir() and any(candidates.iterdir())
            if current == owner and not has_candidates:
                path.unlink(missing_ok=True)
                fsync_dir(path.parent)
        except OSError:
            pass


class Handler(BaseHTTPRequestHandler):
    server_version = "AsmoryWrite/0.1"
    protocol_version = "HTTP/1.1"

    @property
    def state(self) -> RegistryState:
        return self.server.state  # type: ignore[attr-defined]

    def log_message(self, fmt: str, *args) -> None:
        # Never log Authorization headers; BaseHTTPRequestHandler does not by
        # default, and this compact log keeps publication identities visible.
        sys.stderr.write(
            f"{self.client_address[0]} {self.command} {self.path} - {fmt % args}\n"
        )

    def send_json(self, status: int, value: dict) -> None:
        body = canonical_json(value)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def fail(self, exc: RegistryError) -> None:
        self.send_json(exc.status, {"error": exc.message})

    def require_owner(self) -> str:
        return self.state.auth_owner(self.headers.get("Authorization"))

    def content_length(self, maximum: int) -> int:
        raw = self.headers.get("Content-Length")
        if raw is None or not raw.isdigit():
            raise RegistryError(411, "Content-Length is required")
        length = int(raw)
        if length > maximum:
            raise RegistryError(413, "request body too large")
        return length

    def read_exact(self, length: int) -> bytes:
        data = self.rfile.read(length)
        if len(data) != length:
            raise RegistryError(400, "request body truncated")
        return data

    def do_GET(self) -> None:
        try:
            path = urlsplit(self.path).path
            if path == "/healthz":
                self.send_json(200, {"status": "ok", "service": "asmory-registry-write"})
                return

            owner = self.require_owner()

            m = re.fullmatch(
                r"/api/v1/staging/packages/([a-z0-9][a-z0-9._-]*)/"
                r"([0-9]+(?:\.[0-9]+){2}(?:[-+][0-9A-Za-z.-]+)?)(/download)?",
                path,
            )
            if not m:
                raise RegistryError(404, "staging resource not found")

            package, version, download = m.groups()
            project_owner = self.state.read_owner(package)
            if project_owner is None:
                raise RegistryError(404, "staged Package not found")
            if project_owner != owner:
                raise RegistryError(403, "publisher does not own staged Package")

            candidate_path = self.state.candidate_path(package, version)
            if not candidate_path.is_file():
                raise RegistryError(404, "staged version not found")

            record = json.loads(candidate_path.read_text())

            if download:
                candidate = record["candidate"]
                artifact = candidate["artifact"]
                obj = self.state.verify_object(artifact["sha256"], artifact["size"])
                size = obj.stat().st_size
                self.send_response(200)
                self.send_header("Content-Type", "application/gzip")
                self.send_header(
                    "Content-Disposition",
                    f'attachment; filename="{artifact["filename"]}"',
                )
                self.send_header("Content-Length", str(size))
                self.send_header("Cache-Control", "no-store")
                self.send_header("Connection", "close")
                self.end_headers()
                with obj.open("rb") as f:
                    for block in iter(lambda: f.read(1024 * 1024), b""):
                        self.wfile.write(block)
                self.close_connection = True
                return

            self.send_json(200, record)
        except RegistryError as exc:
            self.fail(exc)
        except OSError as exc:
            self.fail(RegistryError(500, f"storage failure: {exc}"))

    def do_PUT(self) -> None:
        temp = None
        try:
            owner = self.require_owner()
            path = urlsplit(self.path).path
            m = re.fullmatch(
                r"/api/v1/staging/artifacts/sha256/([0-9a-f]{64})",
                path,
            )
            if not m:
                raise RegistryError(404, "Artifact staging endpoint not found")

            digest = m.group(1)
            length = self.content_length(self.state.max_artifact)
            final = self.state.object_path(digest)

            if final.exists():
                obj = self.state.verify_object(digest, length)
                self.send_json(
                    200,
                    {
                        "state": "reused",
                        "sha256": digest,
                        "size": obj.stat().st_size,
                        "owner": owner,
                    },
                )
                return

            fd, name = tempfile.mkstemp(
                prefix=f"{digest}.",
                dir=self.state.incoming,
            )
            temp = Path(name)

            h = hashlib.sha256()
            remaining = length

            try:
                with os.fdopen(fd, "wb", closefd=True) as out:
                    while remaining:
                        block = self.rfile.read(min(1024 * 1024, remaining))
                        if not block:
                            raise RegistryError(400, "Artifact upload truncated")
                        out.write(block)
                        h.update(block)
                        remaining -= len(block)
                    out.flush()
                    os.fsync(out.fileno())

                if h.hexdigest() != digest:
                    raise RegistryError(422, "Artifact SHA-256 mismatch")

                os.chmod(temp, 0o444)

                try:
                    os.link(temp, final)
                    fsync_dir(final.parent)
                    state = "stored"
                    status = 201
                except FileExistsError:
                    self.state.verify_object(digest, length)
                    state = "reused"
                    status = 200

                self.send_json(
                    status,
                    {
                        "state": state,
                        "sha256": digest,
                        "size": length,
                        "owner": owner,
                    },
                )
            finally:
                temp.unlink(missing_ok=True)
                temp = None
        except RegistryError as exc:
            self.fail(exc)
        except OSError as exc:
            self.fail(RegistryError(500, f"storage failure: {exc}"))
        finally:
            if temp is not None:
                temp.unlink(missing_ok=True)

    def do_POST(self) -> None:
        try:
            owner = self.require_owner()
            path = urlsplit(self.path).path
            if path != "/api/v1/staging/releases":
                raise RegistryError(404, "candidate staging endpoint not found")

            length = self.content_length(MAX_CANDIDATE)
            raw = self.read_exact(length)
            candidate = self.state.validate_candidate(raw)

            package = candidate["package"]["name"]
            version = candidate["package"]["version"]
            artifact = candidate["artifact"]

            self.state.verify_object(artifact["sha256"], artifact["size"])
            candidate_sha = hashlib.sha256(raw).hexdigest()

            with self.state.project_lock(package):
                claimed = self.state.claim_owner(package, owner)
                record_path = self.state.candidate_path(package, version)

                record = {
                    "schema": 1,
                    "kind": "asmory-staged-release",
                    "state": "staged",
                    "resolvable": False,
                    "owner": owner,
                    "package": package,
                    "version": version,
                    "candidate_sha256": candidate_sha,
                    "artifact_sha256": artifact["sha256"],
                    "candidate": candidate,
                }
                body = canonical_json(record)

                try:
                    if record_path.exists():
                        existing = record_path.read_bytes()
                        if existing != body:
                            raise RegistryError(
                                409,
                                "immutable staged Package version already exists with different candidate",
                            )
                        status = 200
                        state = "reused"
                    else:
                        atomic_write(record_path, body, 0o444)
                        status = 201
                        state = "stored"
                except Exception:
                    if claimed:
                        self.state.rollback_owner_claim(package, owner)
                    raise

            self.send_json(
                status,
                {
                    "state": state,
                    "package": package,
                    "version": version,
                    "owner": owner,
                    "candidate_sha256": candidate_sha,
                    "artifact_sha256": artifact["sha256"],
                    "resolvable": False,
                },
            )
        except RegistryError as exc:
            self.fail(exc)
        except OSError as exc:
            self.fail(RegistryError(500, f"storage failure: {exc}"))


def parse_args():
    import argparse

    parser = argparse.ArgumentParser(prog="asmory-registry-write")
    parser.add_argument(
        "--host",
        default=os.environ.get("ASMORY_WRITE_HOST", "127.0.0.1"),
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("ASMORY_WRITE_PORT", "18081")),
    )
    parser.add_argument(
        "--data-dir",
        default=os.environ.get("ASMORY_WRITE_DATA_DIR", "build/write-registry"),
    )
    parser.add_argument(
        "--auth-file",
        default=os.environ.get("ASMORY_WRITE_AUTH_FILE", "build/write-registry-auth.json"),
    )
    parser.add_argument(
        "--max-artifact-bytes",
        type=int,
        default=int(os.environ.get("ASMORY_WRITE_MAX_ARTIFACT_BYTES", str(DEFAULT_MAX_ARTIFACT))),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if not (1 <= args.port <= 65535):
        raise SystemExit("invalid port")
    if args.max_artifact_bytes <= 0:
        raise SystemExit("max Artifact size must be positive")

    state = RegistryState(
        Path(args.data_dir).resolve(),
        Path(args.auth_file).resolve(),
        args.max_artifact_bytes,
    )

    class Server(ThreadingHTTPServer):
        daemon_threads = True
        allow_reuse_address = True

    server = Server((args.host, args.port), Handler)
    server.state = state  # type: ignore[attr-defined]

    print(
        f"asmory-registry-write listening on {args.host}:{args.port} "
        f"data={state.data_dir}",
        flush=True,
    )

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
