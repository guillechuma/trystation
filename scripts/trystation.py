#!/usr/bin/env python3
"""Filesystem adapter for TryStation.

Tobi Lütke's `try` directory remains the source of truth. This helper only reads that
folder and stores optional presentation metadata in XDG state.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Any

DATE_PREFIX = re.compile(r"^(\d{4}-\d{2}-\d{2})-(.+)$")
SAFE_NAME = re.compile(r"[^A-Za-z0-9._-]+")


def expand(path: str) -> Path:
    expanded = os.path.expandvars(os.path.expanduser(path))
    return Path(os.path.abspath(expanded))


def state_path() -> Path:
    state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    return state_home / "trystation" / "metadata.json"


def load_metadata() -> dict[str, dict[str, Any]]:
    path = state_path()
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def save_metadata(value: dict[str, dict[str, Any]]) -> None:
    path = state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="metadata.", suffix=".json", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


@contextmanager
def locked_metadata():
    path = state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_suffix(".lock")
    with lock_path.open("a+") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        data = load_metadata()
        yield data
        save_metadata(data)


def identity(path: Path) -> str:
    stat = path.stat()
    return f"{stat.st_dev}:{stat.st_ino}"


def run_git(path: Path, *args: str) -> str:
    try:
        proc = subprocess.run(
            ["git", "-C", str(path), *args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=2,
            check=False,
        )
        return proc.stdout.strip() if proc.returncode == 0 else ""
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return ""


def project_kind(path: Path) -> tuple[str, str]:
    signatures = [
        ("flake.nix", "Nix", "󱄅"),
        ("Cargo.toml", "Rust", ""),
        ("go.mod", "Go", ""),
        ("package.json", "JavaScript", ""),
        ("pyproject.toml", "Python", ""),
        ("requirements.txt", "Python", ""),
        ("Gemfile", "Ruby", ""),
        ("pom.xml", "Java", ""),
        ("CMakeLists.txt", "C/C++", ""),
    ]
    for filename, label, icon in signatures:
        if path.joinpath(filename).exists():
            return label, icon
    if any(path.glob("*.qml")):
        return "QML", "󰖯"
    return "Folder", "󰉋"


def read_readme(path: Path) -> str:
    for name in ("README.md", "README", "readme.md"):
        candidate = path / name
        try:
            if candidate.is_file():
                text = candidate.read_text(errors="replace")[:1200]
                text = re.sub(r"^#{1,6}\s*", "", text, flags=re.MULTILINE)
                text = re.sub(r"[`*_>#]", "", text)
                return " ".join(text.split())[:360]
        except OSError:
            pass
    return ""


def describe(path: Path, metadata: dict[str, dict[str, Any]]) -> dict[str, Any]:
    stat = path.stat()
    match = DATE_PREFIX.match(path.name)
    created = match.group(1) if match else ""
    title = match.group(2) if match else path.name
    title = title.replace("-", " ").replace("_", " ").strip()
    title = " ".join(word.capitalize() for word in title.split())

    git_marker = path / ".git"
    is_git = git_marker.exists()
    branch = run_git(path, "branch", "--show-current") if is_git else ""
    if is_git and not branch:
        branch = run_git(path, "rev-parse", "--short", "HEAD")
        if branch:
            branch = "detached@" + branch
    status_lines = run_git(path, "status", "--porcelain", "--untracked-files=normal").splitlines() if is_git else []
    remote = run_git(path, "remote", "get-url", "origin") if is_git else ""
    language, icon = project_kind(path)
    key = identity(path)
    meta = metadata.get(key, {})

    return {
        "id": key,
        "name": path.name,
        "title": title or path.name,
        "path": str(path),
        "created": created,
        "modified": int(stat.st_mtime),
        "git": is_git,
        "worktree": git_marker.is_file(),
        "branch": branch,
        "changes": len(status_lines),
        "remote": remote,
        "language": language,
        "icon": icon,
        "readme": read_readme(path),
        "group": str(meta.get("group", "")),
        "note": str(meta.get("note", "")),
        "pinned": bool(meta.get("pinned", False)),
        "graduated": path.is_symlink(),
        "target": str(path.resolve()) if path.is_symlink() else "",
    }


def command_list(args: argparse.Namespace) -> int:
    root = expand(args.path)
    metadata = load_metadata()
    rows: list[dict[str, Any]] = []
    if root.is_dir():
        for path in root.iterdir():
            try:
                if path.name.startswith(".") or not path.is_dir():
                    continue
                rows.append(describe(path, metadata))
            except (OSError, subprocess.SubprocessError):
                continue
    rows.sort(key=lambda row: (not row["pinned"], -row["modified"], row["name"]))
    print(json.dumps({"path": str(root), "exists": root.is_dir(), "sessions": rows}))
    return 0


def clean_name(value: str) -> str:
    value = "-".join(value.strip().split())
    value = SAFE_NAME.sub("-", value).strip("-.")
    return value


def command_create(args: argparse.Namespace) -> int:
    root = expand(args.path)
    name = clean_name(args.name)
    if not name:
        raise ValueError("Enter a name using letters or numbers")
    root.mkdir(parents=True, exist_ok=True)
    prefix = dt.date.today().isoformat()
    stem = f"{prefix}-{name}"
    candidate = root / stem
    suffix = 2
    while candidate.exists():
        candidate = root / f"{stem}-{suffix}"
        suffix += 1
    candidate.mkdir()
    print(json.dumps({"ok": True, "path": str(candidate), "name": candidate.name}))
    return 0


def require_child(root_value: str, child_value: str) -> tuple[Path, Path]:
    root = expand(root_value)
    child = expand(child_value)
    if child.parent != root or child.name.startswith("."):
        raise ValueError("Session must be an immediate child of the try directory")
    if not child.exists() or not child.is_dir():
        raise ValueError("Try session does not exist")
    return root, child


def command_meta(args: argparse.Namespace) -> int:
    _, child = require_child(args.root, args.session)
    key = identity(child)
    group = args.group.strip()[:80]
    note = args.note.strip()[:1000]
    with locked_metadata() as data:
        entry = dict(data.get(key, {}))
        entry["group"] = group
        entry["note"] = note
        if args.pinned is not None:
            entry["pinned"] = args.pinned == "true"
        pinned = bool(entry.get("pinned", False))
        if group or note or pinned:
            entry["pinned"] = pinned
            data[key] = entry
        else:
            data.pop(key, None)
    print(json.dumps({"ok": True, "id": key}))
    return 0


def command_pin(args: argparse.Namespace) -> int:
    _, child = require_child(args.root, args.session)
    key = identity(child)
    with locked_metadata() as data:
        entry = dict(data.get(key, {}))
        entry["pinned"] = args.pinned == "true"
        if entry.get("group") or entry.get("note") or entry["pinned"]:
            data[key] = entry
        else:
            data.pop(key, None)
    print(json.dumps({"ok": True, "id": key, "pinned": entry["pinned"]}))
    return 0


def command_trash(args: argparse.Namespace) -> int:
    _, child = require_child(args.root, args.session)
    key = identity(child)
    if child.is_symlink():
        child.unlink()
    else:
        proc = subprocess.run(["gio", "trash", str(child)], check=False)
        if proc.returncode != 0:
            raise RuntimeError("Could not move the session to trash")
    with locked_metadata() as metadata:
        metadata.pop(key, None)
    print(json.dumps({"ok": True}))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="TryStation filesystem adapter")
    sub = parser.add_subparsers(dest="command", required=True)

    listing = sub.add_parser("list")
    listing.add_argument("--path", required=True)
    listing.set_defaults(handler=command_list)

    create = sub.add_parser("create")
    create.add_argument("--path", required=True)
    create.add_argument("--name", required=True)
    create.set_defaults(handler=command_create)

    meta = sub.add_parser("set-meta")
    meta.add_argument("--root", required=True)
    meta.add_argument("--session", required=True)
    meta.add_argument("--group", default="")
    meta.add_argument("--note", default="")
    meta.add_argument("--pinned", choices=("true", "false"), default=None)
    meta.set_defaults(handler=command_meta)

    pin = sub.add_parser("set-pin")
    pin.add_argument("--root", required=True)
    pin.add_argument("--session", required=True)
    pin.add_argument("--pinned", choices=("true", "false"), required=True)
    pin.set_defaults(handler=command_pin)

    trash = sub.add_parser("trash")
    trash.add_argument("--root", required=True)
    trash.add_argument("--session", required=True)
    trash.set_defaults(handler=command_trash)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.handler(args)
    except (ValueError, RuntimeError, OSError) as error:
        print(json.dumps({"ok": False, "error": str(error)}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
