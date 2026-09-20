#!/usr/bin/env python3
from __future__ import annotations

import argparse
import http.client
import json
import os
from pathlib import Path
import re
import socket
import ssl
import subprocess
import sys
import tomllib
from urllib.parse import quote, urlencode, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
from semantic_model import canonical_semantics, match  # noqa: E402

CAPABILITY_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,255}")
SHA_RE = re.compile(r"[0-9a-f]{64}")
BASELINE_ORDER = {
    "x86-64-v1": 1,
    "x86-64-v2": 2,
    "x86-64-v3": 3,
    "x86-64-v4": 4,
}
MAX_RESPONSE = 8 * 1024 * 1024


class SemanticResolverError(RuntimeError):
    pass


def run(args: list[str]) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            args,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        detail = ""
        if isinstance(exc, subprocess.CalledProcessError):
            detail = (exc.stderr or exc.stdout or "").strip()
        suffix = f": {detail}" if detail else f": {exc}"
        raise SemanticResolverError(
            f"command failed: {' '.join(args)}{suffix}"
        ) from exc


def loopback_host(host: str) -> bool:
    if host.lower() == "localhost":
        return True

    try:
        infos = socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)
    except socket.gaierror:
        return False

    if not infos:
        return False

    for info in infos:
        address = info[4][0]
        if address == "::1" or address.startswith("127."):
            continue
        return False

    return True


def endpoint() -> tuple[str, str, int, str]:
    raw = os.environ.get(
        "ASMORY_REGISTRY_URL",
        "http://127.0.0.1:18081",
    ).strip()
    parsed = urlsplit(raw)

    if parsed.scheme not in ("http", "https"):
        raise SemanticResolverError(
            "ASMORY_REGISTRY_URL must use http or https"
        )
    if parsed.username is not None or parsed.password is not None:
        raise SemanticResolverError(
            "credentials must not be embedded in ASMORY_REGISTRY_URL"
        )
    if not parsed.hostname:
        raise SemanticResolverError("ASMORY_REGISTRY_URL has no host")
    if parsed.query or parsed.fragment:
        raise SemanticResolverError(
            "ASMORY_REGISTRY_URL must not contain query/fragment"
        )
    if parsed.scheme == "http" and not loopback_host(parsed.hostname):
        raise SemanticResolverError(
            "plaintext HTTP registry access is allowed only for "
            "loopback development endpoints"
        )

    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    return parsed.scheme, parsed.hostname, port, parsed.path.rstrip("/")


def connection(
    scheme: str,
    host: str,
    port: int,
) -> http.client.HTTPConnection:
    timeout = float(os.environ.get("ASMORY_REGISTRY_TIMEOUT", "15"))

    if timeout <= 0 or timeout > 300:
        raise SemanticResolverError(
            "ASMORY_REGISTRY_TIMEOUT must be in (0, 300]"
        )

    if scheme == "https":
        return http.client.HTTPSConnection(
            host,
            port,
            timeout=timeout,
            context=ssl.create_default_context(),
        )

    return http.client.HTTPConnection(host, port, timeout=timeout)


def get_json(
    path: str,
    query: dict[str, str | list[str]] | None = None,
) -> dict:
    scheme, host, port, base = endpoint()
    request_path = f"{base}{path}" if base else path

    if query:
        request_path += "?" + urlencode(query, doseq=True)

    conn = connection(scheme, host, port)

    try:
        conn.request(
            "GET",
            request_path,
            headers={
                "Accept": "application/json",
                "Connection": "close",
            },
        )
        response = conn.getresponse()
        body = response.read(MAX_RESPONSE + 1)
    except (OSError, http.client.HTTPException) as exc:
        raise SemanticResolverError(
            f"Registry transport failed: {exc}"
        ) from exc
    finally:
        conn.close()

    if len(body) > MAX_RESPONSE:
        raise SemanticResolverError("Registry response exceeds 8 MiB")

    try:
        data = json.loads(body) if body else {}
    except json.JSONDecodeError as exc:
        raise SemanticResolverError(
            f"Registry returned non-JSON response ({response.status})"
        ) from exc

    if response.status != 200:
        message = (
            data.get("error", "Registry request failed")
            if isinstance(data, dict)
            else "Registry request failed"
        )
        raise SemanticResolverError(
            f"Registry request failed ({response.status}): {message}"
        )

    if not isinstance(data, dict):
        raise SemanticResolverError(
            "Registry response JSON is not an object"
        )

    return data


def require_capability(capability: str) -> str:
    if CAPABILITY_RE.fullmatch(capability) is None:
        raise SemanticResolverError("invalid Capability")
    return capability


def profile_document(path_text: str) -> tuple[Path, dict, dict]:
    path = Path(path_text).expanduser().resolve()

    if not path.is_file() or path.is_symlink():
        raise SemanticResolverError(
            f"Profile path must be a regular file: {path}"
        )

    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise SemanticResolverError(
            f"cannot read Profile: {path}: {exc}"
        ) from exc

    if len(raw) > 1024 * 1024:
        raise SemanticResolverError("Profile exceeds 1 MiB")

    try:
        doc = tomllib.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, tomllib.TOMLDecodeError) as exc:
        raise SemanticResolverError(
            f"Profile TOML is invalid: {exc}"
        ) from exc

    if doc.get("schema") != 1 or not isinstance(doc.get("profile"), dict):
        raise SemanticResolverError(
            "Profile must use schema 1 and contain [profile]"
        )

    try:
        canonical = canonical_semantics(doc)
    except (KeyError, TypeError, ValueError) as exc:
        raise SemanticResolverError(
            f"Profile semantics cannot be canonicalized: {exc}"
        ) from exc

    capability = canonical.get("capability")
    if not isinstance(capability, str):
        raise SemanticResolverError("Profile has no Capability")

    require_capability(capability)
    return path, doc, canonical


def exact_prefilter_facets(canonical: dict) -> list[str]:
    interface = canonical.get("interface", {})
    if not isinstance(interface, dict):
        return []

    facets = []
    for key in (
        "shape",
        "logical_export",
        "calling_convention",
    ):
        if key not in interface:
            continue
        value = json.dumps(
            interface[key],
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
        )
        facets.append(f"interface.{key}={value}")

    return facets


def parse_target() -> dict:
    out = run(["asmory", "target"]).stdout
    target: dict[str, object] = {"features": set()}

    in_features = False

    for raw in out.splitlines():
        line = raw.rstrip()
        stripped = line.strip()

        if stripped == "features":
            in_features = True
            continue

        if stripped in ("Target", "ISA"):
            in_features = False
            continue

        m = re.match(
            r"^\s{2}(arch|os|object|abi|baseline)\s+(\S+)\s*$",
            line,
        )
        if m:
            target[m.group(1)] = m.group(2)
            continue

        if in_features:
            m = re.match(
                r"^\s{4}([A-Za-z0-9._+-]+)\s+(yes|no)\s*$",
                line,
            )
            if m and m.group(2) == "yes":
                target["features"].add(m.group(1).lower())

    missing = [
        key
        for key in ("arch", "os", "object", "abi", "baseline")
        if key not in target
    ]

    if missing:
        raise SemanticResolverError(
            "cannot parse local Asmory host target: "
            + ", ".join(missing)
        )

    return target


def compatible_variant(
    variant: dict,
    host: dict,
) -> tuple[bool, str]:
    target = variant.get("target")
    if not isinstance(target, dict):
        return False, "Variant target metadata missing"

    for key in ("arch", "os", "object", "abi"):
        required = target.get(key)
        actual = host.get(key)
        if required != actual:
            return (
                False,
                f"{key} requires {required}, host is {actual}",
            )

    isa = target.get("isa")
    if not isinstance(isa, dict):
        return False, "Variant ISA metadata missing"

    baseline = isa.get("baseline")
    host_baseline = host.get("baseline")

    if baseline in BASELINE_ORDER and host_baseline in BASELINE_ORDER:
        if BASELINE_ORDER[host_baseline] < BASELINE_ORDER[baseline]:
            return (
                False,
                f"baseline requires {baseline}, host is {host_baseline}",
            )
    elif baseline != host_baseline:
        return (
            False,
            f"baseline requires {baseline}, host is {host_baseline}",
        )

    required = isa.get("required", [])
    if not (
        isinstance(required, list)
        and all(isinstance(x, str) for x in required)
    ):
        return False, "Variant required ISA list invalid"

    features = host["features"]
    missing = sorted(
        {x.lower() for x in required} - features
    )

    if missing:
        return False, "missing ISA: " + ", ".join(missing)

    return True, "compatible"


def select_variant(
    record: dict,
    host: dict,
) -> tuple[dict | None, list[tuple[str, str]]]:
    release = record.get("release")
    if not isinstance(release, dict):
        raise SemanticResolverError(
            "active Release payload is malformed"
        )

    variants = release.get("variants")
    if not isinstance(variants, list) or not variants:
        raise SemanticResolverError("active Release has no Variants")

    accepted = []
    rejected: list[tuple[str, str]] = []

    for variant in variants:
        if not isinstance(variant, dict):
            continue

        ok, reason = compatible_variant(variant, host)
        variant_id = str(variant.get("id", "<unknown>"))

        if ok:
            accepted.append(variant)
        else:
            rejected.append((variant_id, reason))

    accepted.sort(
        key=lambda item: (
            0 if item.get("stability") == "stable" else 1,
            str(item.get("id", "")),
        )
    )

    return (accepted[0] if accepted else None), rejected


def provider_summaries(
    capability: str,
    facets: list[str] | None = None,
) -> list[dict]:
    query: dict[str, str | list[str]] = {
        "capability": require_capability(capability),
        "limit": "100",
    }
    if facets:
        query["facet"] = facets

    data = get_json("/api/v1/semantic/providers", query)
    providers = data.get("providers")

    if not isinstance(providers, list):
        raise SemanticResolverError(
            "Registry semantic provider response is malformed"
        )

    return [
        item
        for item in providers
        if isinstance(item, dict)
    ]


def provider_record(summary: dict) -> dict:
    release_path = summary.get("release")
    if not isinstance(release_path, str) or not release_path.startswith("/"):
        raise SemanticResolverError(
            "provider candidate has invalid Release endpoint"
        )

    record = get_json(release_path)

    package = summary.get("package")
    version = summary.get("version")

    if (
        record.get("project") != package
        or not isinstance(record.get("release"), dict)
        or record["release"].get("version") != version
        or record.get("resolvable") is not True
    ):
        raise SemanticResolverError(
            "provider Release identity mismatches semantic index"
        )

    return record


def evaluate_profile(
    path_text: str,
) -> tuple[Path, dict, dict, list[dict], list[dict]]:
    path, profile, canonical = profile_document(path_text)
    capability = canonical["capability"]
    facets = exact_prefilter_facets(canonical)
    summaries = provider_summaries(capability, facets)

    host = parse_target()
    accepted = []
    rejected = []

    for summary in summaries:
        record = provider_record(summary)
        release = record["release"]
        implementation = release.get("canonical_semantics")

        if not isinstance(implementation, dict):
            rejected.append(
                {
                    "summary": summary,
                    "stage": "semantic",
                    "reasons": [
                        "active Release has no canonical semantics"
                    ],
                }
            )
            continue

        result = match(profile, implementation)

        if not result["compatible"]:
            rejected.append(
                {
                    "summary": summary,
                    "stage": "semantic",
                    "result": result,
                    "reasons": [
                        item["path"]
                        for item in result["rejections"]
                    ],
                }
            )
            continue

        variant, variant_rejections = select_variant(record, host)

        if variant is None:
            rejected.append(
                {
                    "summary": summary,
                    "stage": "machine",
                    "reasons": [
                        f"{variant_id}: {reason}"
                        for variant_id, reason in variant_rejections
                    ],
                }
            )
            continue

        accepted.append(
            {
                "summary": summary,
                "record": record,
                "variant": variant,
                "semantic_result": result,
            }
        )

    accepted.sort(
        key=lambda item: (
            str(item["summary"].get("package", "")),
            str(item["summary"].get("version", "")),
        )
    )
    rejected.sort(
        key=lambda item: (
            str(item["summary"].get("package", "")),
            str(item["summary"].get("version", "")),
        )
    )

    return path, profile, canonical, accepted, rejected


def install_resolved(
    record: dict,
    variant: dict,
) -> int:
    package = record.get("project")
    release = record.get("release")

    if not isinstance(package, str) or not isinstance(release, dict):
        raise SemanticResolverError(
            "resolved provider identity is malformed"
        )

    artifacts = release.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        raise SemanticResolverError(
            "active Release has no Artifact"
        )

    artifact = artifacts[0]
    digest = artifact.get("sha256")
    semantic = release.get("semantic_fingerprint")

    if not isinstance(digest, str) or SHA_RE.fullmatch(digest) is None:
        raise SemanticResolverError(
            "active Release Artifact digest is invalid"
        )
    if (
        not isinstance(semantic, str)
        or SHA_RE.fullmatch(semantic) is None
    ):
        raise SemanticResolverError(
            "active Release semantic fingerprint is invalid"
        )

    provider = record.get("owner")
    review = release.get("review", {}).get("state", "unknown")
    safety = release.get("safety", {}).get("state", "unknown")

    fields = (
        release.get("version"),
        release.get("capability"),
        release.get("profile"),
        provider,
        variant.get("id"),
        review,
        safety,
    )

    if not all(isinstance(value, str) and value for value in fields):
        raise SemanticResolverError(
            "resolved provider metadata is incomplete"
        )

    proc = subprocess.run(
        [
            "asmory-add",
            package,
            str(release["version"]),
            str(release["capability"]),
            semantic,
            str(release["profile"]),
            str(provider),
            str(variant["id"]),
            digest,
            str(review),
            str(safety),
        ]
    )

    return proc.returncode


def command_providers(capability: str) -> int:
    capability = require_capability(capability)

    data = get_json(
        f"/api/v1/capabilities/{quote(capability, safe='._-')}/providers",
        {"limit": "100"},
    )
    providers = data.get("providers")

    if not isinstance(providers, list):
        raise SemanticResolverError(
            "Registry provider response is malformed"
        )

    print(f"Providers for {capability}")
    print()
    print(
        "PACKAGE              VERSION      PROFILE"
        "                              SEMANTICS"
    )

    for item in providers:
        if not isinstance(item, dict):
            continue
        print(
            f"{str(item.get('package','')):<20} "
            f"{str(item.get('version','')):<12} "
            f"{str(item.get('profile','')):<36} "
            f"{str(item.get('semantic_fingerprint',''))}"
        )

    print()
    print(f"providers: {len(providers)}")
    return 0


def command_match_profile(path_text: str) -> int:
    path, profile, canonical, accepted, rejected = evaluate_profile(
        path_text
    )
    profile_meta = profile["profile"]

    profile_id = (
        f"{profile_meta.get('id','')}@"
        f"{profile_meta.get('version','')}"
    )

    print("Semantic Provider Resolution")
    print()
    print(f"  profile      {profile_id}")
    print(f"  file         {path}")
    print(f"  capability   {canonical['capability']}")
    print(
        f"  candidates   {len(accepted) + len(rejected)}"
    )
    print()

    for item in accepted:
        summary = item["summary"]
        variant = item["variant"]
        result = item["semantic_result"]
        identity = (
            "exact"
            if result["exact_semantic_identity"]
            else "compatible"
        )
        print(
            "ACCEPT "
            f"{summary.get('package')}@{summary.get('version')} "
            f"semantic={identity} "
            f"variant={variant.get('id')}"
        )

    for item in rejected:
        summary = item["summary"]
        reasons = ", ".join(item.get("reasons", [])) or "rejected"
        print(
            "REJECT "
            f"{summary.get('package')}@{summary.get('version')} "
            f"{item.get('stage')}={reasons}"
        )

    print()
    print(f"accepted: {len(accepted)}")
    print(f"rejected: {len(rejected)}")

    return 0 if accepted else 5


def command_add_profile(path_text: str) -> int:
    path, profile, canonical, accepted, rejected = evaluate_profile(
        path_text
    )

    if not accepted:
        reasons = []
        for item in rejected[:5]:
            summary = item["summary"]
            why = ", ".join(item.get("reasons", [])) or "rejected"
            reasons.append(
                f"{summary.get('package')}@{summary.get('version')}: "
                f"{item.get('stage')} {why}"
            )

        detail = "; ".join(reasons)
        raise SemanticResolverError(
            "no active Provider satisfies Profile"
            + (f" ({detail})" if detail else "")
        )

    if len(accepted) != 1:
        names = ", ".join(
            f"{item['summary'].get('package')}@"
            f"{item['summary'].get('version')}"
            for item in accepted
        )
        raise SemanticResolverError(
            "semantic request is ambiguous across "
            f"{len(accepted)} compatible Providers: {names}. "
            "Choose an explicit Package until an accepted "
            "Evidence/trust ranking policy is available."
        )

    chosen = accepted[0]
    summary = chosen["summary"]

    print("Resolved semantic Provider")
    print()
    print(f"  profile      {path}")
    print(f"  capability   {canonical['capability']}")
    print(
        f"  package      "
        f"{summary.get('package')}@{summary.get('version')}"
    )
    print(f"  variant      {chosen['variant'].get('id')}")
    print()

    return install_resolved(
        chosen["record"],
        chosen["variant"],
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="asmory-semantic-resolver"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    providers = sub.add_parser("providers")
    providers.add_argument("capability")

    match_profile = sub.add_parser("match-profile")
    match_profile.add_argument("profile")

    add_profile = sub.add_parser("add-profile")
    add_profile.add_argument("profile")

    args = parser.parse_args()

    try:
        if args.command == "providers":
            return command_providers(args.capability)
        if args.command == "match-profile":
            return command_match_profile(args.profile)
        if args.command == "add-profile":
            return command_add_profile(args.profile)
        raise SemanticResolverError("unknown semantic resolver command")
    except SemanticResolverError as exc:
        print(f"semantic-resolver: {exc}", file=sys.stderr)
        return 28


if __name__ == "__main__":
    raise SystemExit(main())
