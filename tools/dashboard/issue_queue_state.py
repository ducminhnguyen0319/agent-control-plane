#!/usr/bin/env python3
from __future__ import annotations

import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def split_key_value_text(text: str) -> list[str]:
    return [line.strip() for line in re.split(r"(?:\r?\n|\\n)+", text) if line.strip()]


def normalize_value(raw: str) -> str:
    value = raw.strip()
    if value in {"''", '""'}:
        return ""
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def parse_key_value_text(text: str) -> dict[str, str]:
    data: dict[str, str] = {}
    for line in split_key_value_text(text):
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = normalize_value(value)
    return data


def read_env_file(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    return parse_key_value_text(path.read_text(encoding="utf-8", errors="replace"))


def file_mtime_iso(path: Path) -> str:
    return datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_issue_queue_filename(path: Path) -> tuple[str, str]:
    name = path.name
    if name.endswith(".env"):
        name = name[:-4]
    if not name.startswith("issue-"):
        return "", ""

    payload = name[len("issue-") :]
    if "." not in payload:
        return payload, ""

    issue_id, remainder = payload.split(".", 1)
    remainder_parts = remainder.split(".")
    if len(remainder_parts) >= 2:
        return issue_id, ".".join(remainder_parts[:-1])
    return issue_id, remainder


def is_pending_queue_file(path: Path) -> bool:
    return path.is_file() and path.name.startswith("issue-") and path.name.endswith(".env") and ".tmp." not in path.name


def is_claim_queue_file(path: Path) -> bool:
    return path.is_file() and path.name.startswith("issue-") and ".tmp." not in path.name


def collect_queue_items(root: Path, kind: str) -> list[dict[str, Any]]:
    if not root.is_dir():
        return []

    matcher = is_pending_queue_file if kind == "pending" else is_claim_queue_file
    items: list[dict[str, Any]] = []
    for path in sorted((item for item in root.iterdir() if matcher(item)), key=lambda item: item.stat().st_mtime, reverse=True):
        env = read_env_file(path)
        issue_id_from_name, claimer_from_name = parse_issue_queue_filename(path)
        claim_file = env.get("CLAIM_FILE", "")
        state_kind = env.get("STATE_KIND", "")
        items.append(
            {
                "issue_id": env.get("ISSUE_ID", "") or issue_id_from_name,
                "session": env.get("SESSION", "") or claimer_from_name,
                "claim_file": claim_file or (str(path) if kind == "claims" else ""),
                "queued_by": env.get("QUEUED_BY", ""),
                "claimed_by": env.get("CLAIMED_BY", "") or claimer_from_name,
                "state_kind": state_kind or ("claim" if kind == "claims" else "pending"),
                "state_format_version": env.get("STATE_FORMAT_VERSION", ""),
                "updated_at": env.get("UPDATED_AT", "") or env.get("CLAIMED_AT", "") or env.get("QUEUED_AT", "") or file_mtime_iso(path),
                "state_file": str(path),
            }
        )
    return items


def collect_issue_queue(state_root: Path) -> dict[str, list[dict[str, Any]]]:
    queue_root = state_root / "resident-workers" / "issue-queue"
    return {
        "pending": collect_queue_items(queue_root / "pending", "pending"),
        "claims": collect_queue_items(queue_root / "claims", "claims"),
    }
