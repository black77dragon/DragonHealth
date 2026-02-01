#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys

VERSION_PATH = "Docs/version.json"
SEMVER_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
RELEASE_LABELS = {"release"}


def fail(message: str) -> None:
    print(f"ERROR: {message}")
    sys.exit(1)


def read_json(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        fail(f"Missing {path}")
    except json.JSONDecodeError as exc:
        fail(f"Invalid JSON in {path}: {exc}")


def validate_payload(data: dict, source: str) -> None:
    if "marketing_version" not in data:
        fail(f"{source} missing marketing_version")
    if "build_number" not in data:
        fail(f"{source} missing build_number")

    marketing_version = data["marketing_version"]
    build_number = data["build_number"]

    if not isinstance(marketing_version, str):
        fail(f"{source} marketing_version must be a string")
    if not SEMVER_RE.match(marketing_version):
        fail(f"{source} marketing_version must be SemVer (x.y.z)")

    if not isinstance(build_number, int):
        fail(f"{source} build_number must be an integer")
    if build_number < 0:
        fail(f"{source} build_number must be >= 0")


def git_show(ref: str, path: str) -> str | None:
    try:
        return subprocess.check_output(["git", "show", f"{ref}:{path}"], text=True).strip()
    except subprocess.CalledProcessError:
        return None


def file_changed(base_ref: str, path: str) -> bool:
    try:
        output = subprocess.check_output(
            ["git", "diff", "--name-only", f"{base_ref}...HEAD", "--", path],
            text=True,
        )
    except subprocess.CalledProcessError:
        return False
    return bool(output.strip())


def parse_labels_from_event() -> set[str]:
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path or not os.path.exists(event_path):
        return set()
    try:
        with open(event_path, "r", encoding="utf-8") as handle:
            event = json.load(handle)
    except json.JSONDecodeError:
        return set()

    labels = set()
    pr = event.get("pull_request")
    if pr and isinstance(pr, dict):
        for label in pr.get("labels", []) or []:
            name = label.get("name") if isinstance(label, dict) else None
            if name:
                labels.add(name)
    return labels


def semver_tuple(version: str) -> tuple[int, int, int]:
    major, minor, patch = version.split(".")
    return (int(major), int(minor), int(patch))


def resolve_base_ref() -> str | None:
    base_ref = os.environ.get("GITHUB_BASE_REF")
    if base_ref:
        return f"origin/{base_ref}"

    for candidate in ("origin/main", "origin/master", "main", "master"):
        try:
            subprocess.check_output(["git", "rev-parse", "--verify", candidate])
            return candidate
        except subprocess.CalledProcessError:
            continue
    return None


def main() -> None:
    current = read_json(VERSION_PATH)
    validate_payload(current, VERSION_PATH)

    base_ref = resolve_base_ref()
    if not base_ref:
        print("No base ref detected; validated current version only.")
        return

    changed = file_changed(base_ref, VERSION_PATH)
    labels = parse_labels_from_event()
    release_requested = bool(RELEASE_LABELS & labels)

    if release_requested and not changed:
        fail(f"{VERSION_PATH} must be updated when release label is applied")

    base_contents = git_show(base_ref, VERSION_PATH)
    if base_contents is None:
        print(f"{VERSION_PATH} not found on {base_ref}; treating as initial version.")
        return

    try:
        base = json.loads(base_contents)
    except json.JSONDecodeError as exc:
        fail(f"Invalid JSON in {VERSION_PATH} at {base_ref}: {exc}")

    validate_payload(base, f"{VERSION_PATH} at {base_ref}")

    if changed:
        if current["build_number"] <= base["build_number"]:
            fail(
                f"build_number must increase (current {current['build_number']}, "
                f"base {base['build_number']})"
            )

        current_version = semver_tuple(current["marketing_version"])
        base_version = semver_tuple(base["marketing_version"])

        if current_version < base_version:
            fail(
                f"marketing_version must not decrease "
                f"(current {current['marketing_version']}, base {base['marketing_version']})"
            )

        if release_requested and current_version <= base_version:
            fail(
                f"marketing_version must increase for release label "
                f"(current {current['marketing_version']}, base {base['marketing_version']})"
            )

    print("Versioning validation passed.")


if __name__ == "__main__":
    main()
