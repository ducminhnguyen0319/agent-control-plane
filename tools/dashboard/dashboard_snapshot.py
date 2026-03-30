#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT_DIR = Path(__file__).resolve().parents[2]
TOOLS_BIN_DIR = ROOT_DIR / "tools" / "bin"
RENDER_FLOW_CONFIG = TOOLS_BIN_DIR / "render-flow-config.sh"
WORKER_STATUS_TOOL = TOOLS_BIN_DIR / "agent-project-worker-status"


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def profile_registry_root() -> Path:
    override = os.environ.get("ACP_PROFILE_REGISTRY_ROOT", "").strip()
    if override:
        return Path(override).expanduser()
    return Path.home() / ".agent-runtime" / "control-plane" / "profiles"


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


def parse_simple_yaml(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.is_file():
        return data

    stack: list[tuple[int, str]] = []
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.endswith(":"):
            key = stripped[:-1].strip()
            while stack and stack[-1][0] >= indent:
                stack.pop()
            stack.append((indent, key))
            continue
        if ":" not in stripped:
            continue
        key, value = stripped.split(":", 1)
        key = key.strip()
        value = normalize_value(value)
        path_parts = [entry[1] for entry in stack]
        path_parts.append(key)
        data[".".join(path_parts)] = value
    return data


def run_key_value_script(script: Path, env: dict[str, str], *args: str) -> dict[str, str]:
    output = subprocess.check_output(
        ["bash", str(script), *args],
        cwd=str(ROOT_DIR),
        env=env,
        text=True,
        stderr=subprocess.DEVNULL,
        timeout=30,
    )
    return parse_key_value_text(output)


def list_profile_ids(registry_root: Path) -> list[str]:
    if not registry_root.is_dir():
        return []
    profile_ids: list[str] = []
    for entry in sorted(registry_root.iterdir()):
        if not entry.is_dir():
            continue
        if (entry / "control-plane.yaml").is_file():
            profile_ids.append(entry.name)
    return profile_ids


def env_with_profile(profile_id: str, registry_root: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["ACP_PROJECT_ID"] = profile_id
    env["ACP_PROFILE_REGISTRY_ROOT"] = str(registry_root)
    return env


def safe_int(value: str | None) -> int | None:
    if not value:
        return None
    try:
        return int(str(value).strip())
    except ValueError:
        return None


def pid_alive(value: str | None) -> bool:
    pid = safe_int(value)
    if not pid or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def file_mtime_iso(path: Path) -> str:
    return datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def classify_run_result(status: str, outcome: str, failure_reason: str) -> tuple[str, str]:
    normalized_status = (status or "").strip().upper()
    normalized_outcome = (outcome or "").strip()
    normalized_failure = (failure_reason or "").strip()

    if normalized_status == "RUNNING":
        return ("running", "In progress")
    if normalized_status == "FAILED":
        if normalized_failure:
            return ("failed", f"Failed: {normalized_failure}")
        return ("failed", "Failed")
    if normalized_status == "SUCCEEDED":
        if normalized_outcome == "implemented":
            return ("implemented", "Implemented")
        if normalized_outcome == "reported":
            return ("reported", "Reported")
        if normalized_outcome == "blocked":
            return ("blocked", "Blocked")
        if normalized_outcome:
            return ("completed", normalized_outcome)
        return ("completed", "Completed")
    return ("unknown", normalized_status or "Unknown")


def collect_runs(runs_root: Path) -> list[dict[str, Any]]:
    if not runs_root.is_dir():
        return []

    runs: list[dict[str, Any]] = []
    for run_dir in sorted(
        [entry for entry in runs_root.iterdir() if entry.is_dir()],
        key=lambda item: item.stat().st_mtime,
        reverse=True,
    ):
        run_env = read_env_file(run_dir / "run.env")
        session = run_env.get("SESSION", run_dir.name)
        try:
            status_env = run_key_value_script(
                WORKER_STATUS_TOOL,
                os.environ.copy(),
                "--runs-root",
                str(runs_root),
                "--session",
                session,
            )
        except subprocess.CalledProcessError:
            status_env = {}

        runner_env = read_env_file(run_dir / "runner.env")
        result_env = read_env_file(run_dir / "result.env")
        lifecycle_status = status_env.get("STATUS", "UNKNOWN")
        outcome = result_env.get("OUTCOME", "")
        failure_reason = status_env.get("FAILURE_REASON", runner_env.get("LAST_FAILURE_REASON", ""))
        result_kind, result_label = classify_run_result(lifecycle_status, outcome, failure_reason)
        item = {
            "session": session,
            "task_kind": run_env.get("TASK_KIND", ""),
            "task_id": run_env.get("TASK_ID", ""),
            "mode": run_env.get("MODE", ""),
            "status": lifecycle_status,
            "lifecycle_status": lifecycle_status,
            "started_at": run_env.get("STARTED_AT", ""),
            "updated_at": runner_env.get("UPDATED_AT", "") or result_env.get("UPDATED_AT", "") or file_mtime_iso(run_dir),
            "coding_worker": run_env.get("CODING_WORKER", ""),
            "branch": run_env.get("BRANCH", ""),
            "worktree": run_env.get("WORKTREE", ""),
            "thread_id": status_env.get("THREAD_ID", runner_env.get("THREAD_ID", "")),
            "failure_reason": failure_reason,
            "outcome": outcome,
            "action": result_env.get("ACTION", ""),
            "result_only_completion": status_env.get("RESULT_ONLY_COMPLETION", "no"),
            "result_kind": result_kind,
            "result_label": result_label,
            "resident_worker_key": run_env.get("RESIDENT_WORKER_KEY", ""),
            "provider_model": run_env.get("OPENCLAW_MODEL", "") or run_env.get("CLAUDE_MODEL", ""),
            "provider_pool_name": run_env.get("ACTIVE_PROVIDER_POOL_NAME", ""),
            "run_dir": str(run_dir),
        }
        runs.append(item)
    return runs


def collect_resident_controllers(state_root: Path) -> list[dict[str, Any]]:
    controllers_root = state_root / "resident-workers" / "issues"
    if not controllers_root.is_dir():
        return []

    items: list[dict[str, Any]] = []
    for path in sorted(controllers_root.glob("*/controller.env"), key=lambda item: item.stat().st_mtime, reverse=True):
        env = read_env_file(path)
        controller_pid = env.get("CONTROLLER_PID", "")
        items.append(
            {
                "issue_id": env.get("ISSUE_ID", path.parent.name),
                "session": env.get("SESSION", ""),
                "controller_pid": controller_pid,
                "controller_live": pid_alive(controller_pid),
                "mode": env.get("CONTROLLER_MODE", ""),
                "loop_count": safe_int(env.get("CONTROLLER_LOOP_COUNT")),
                "state": env.get("CONTROLLER_STATE", ""),
                "reason": env.get("CONTROLLER_REASON", ""),
                "next_wake_at": env.get("NEXT_WAKE_AT", ""),
                "updated_at": env.get("UPDATED_AT", "") or file_mtime_iso(path),
                "worker_key": env.get("ACTIVE_RESIDENT_WORKER_KEY", ""),
                "lane_kind": env.get("ACTIVE_RESIDENT_LANE_KIND", ""),
                "lane_value": env.get("ACTIVE_RESIDENT_LANE_VALUE", ""),
                "provider_pool_name": env.get("ACTIVE_PROVIDER_POOL_NAME", ""),
                "provider_backend": env.get("ACTIVE_PROVIDER_BACKEND", ""),
                "provider_model": env.get("ACTIVE_PROVIDER_MODEL", ""),
                "provider_key": env.get("ACTIVE_PROVIDER_KEY", ""),
                "provider_switch_count": safe_int(env.get("PROVIDER_SWITCH_COUNT")) or 0,
                "provider_failover_count": safe_int(env.get("PROVIDER_FAILOVER_COUNT")) or 0,
                "provider_wait_count": safe_int(env.get("PROVIDER_WAIT_COUNT")) or 0,
                "provider_wait_total_seconds": safe_int(env.get("PROVIDER_WAIT_TOTAL_SECONDS")) or 0,
                "provider_last_wait_seconds": safe_int(env.get("PROVIDER_LAST_WAIT_SECONDS")) or 0,
                "last_provider_switch_at": env.get("LAST_PROVIDER_SWITCH_AT", ""),
                "last_provider_switch_reason": env.get("LAST_PROVIDER_SWITCH_REASON", ""),
                "last_provider_from_backend": env.get("LAST_PROVIDER_FROM_BACKEND", ""),
                "last_provider_from_model": env.get("LAST_PROVIDER_FROM_MODEL", ""),
                "last_provider_to_backend": env.get("LAST_PROVIDER_TO_BACKEND", ""),
                "last_provider_to_model": env.get("LAST_PROVIDER_TO_MODEL", ""),
                "controller_file": str(path),
            }
        )
    return items


def collect_resident_workers(state_root: Path) -> list[dict[str, Any]]:
    resident_root = state_root / "resident-workers" / "issues"
    if not resident_root.is_dir():
        return []

    items: list[dict[str, Any]] = []
    for path in sorted(resident_root.glob("*/metadata.env"), key=lambda item: item.stat().st_mtime, reverse=True):
        env = read_env_file(path)
        items.append(
            {
                "key": env.get("RESIDENT_WORKER_KEY", path.parent.name),
                "scope": env.get("RESIDENT_WORKER_SCOPE", "issue"),
                "kind": env.get("RESIDENT_WORKER_KIND", ""),
                "issue_id": env.get("ISSUE_ID", ""),
                "coding_worker": env.get("CODING_WORKER", ""),
                "task_count": safe_int(env.get("TASK_COUNT")) or 0,
                "last_status": env.get("LAST_STATUS", ""),
                "last_started_at": env.get("LAST_STARTED_AT", ""),
                "last_finished_at": env.get("LAST_FINISHED_AT", ""),
                "last_run_session": env.get("LAST_RUN_SESSION", ""),
                "last_outcome": env.get("LAST_OUTCOME", ""),
                "last_action": env.get("LAST_ACTION", ""),
                "last_failure_reason": env.get("LAST_FAILURE_REASON", ""),
                "worktree": env.get("WORKTREE", ""),
                "metadata_file": str(path),
            }
        )
    return items


def collect_provider_cooldowns(state_root: Path) -> list[dict[str, Any]]:
    providers_root = state_root / "retries" / "providers"
    if not providers_root.is_dir():
        return []

    now_epoch = int(datetime.now(timezone.utc).timestamp())
    items: list[dict[str, Any]] = []
    for path in sorted(providers_root.glob("*.env"), key=lambda item: item.stat().st_mtime, reverse=True):
        env = read_env_file(path)
        next_attempt_epoch = safe_int(env.get("NEXT_ATTEMPT_EPOCH"))
        items.append(
            {
                "provider_key": path.stem,
                "attempts": safe_int(env.get("ATTEMPTS")) or 0,
                "next_attempt_epoch": next_attempt_epoch,
                "next_attempt_at": env.get("NEXT_ATTEMPT_AT", ""),
                "last_reason": env.get("LAST_REASON", ""),
                "updated_at": env.get("UPDATED_AT", "") or file_mtime_iso(path),
                "active": bool(next_attempt_epoch and next_attempt_epoch > now_epoch),
                "state_file": str(path),
            }
        )
    return items


def collect_scheduled_issues(state_root: Path) -> list[dict[str, Any]]:
    scheduled_root = state_root / "scheduled-issues"
    if not scheduled_root.is_dir():
        return []

    items: list[dict[str, Any]] = []
    for path in sorted(scheduled_root.glob("*.env"), key=lambda item: item.stat().st_mtime, reverse=True):
        env = read_env_file(path)
        items.append(
            {
                "issue_id": path.stem,
                "interval_seconds": safe_int(env.get("INTERVAL_SECONDS")) or 0,
                "last_started_at": env.get("LAST_STARTED_AT", ""),
                "next_due_at": env.get("NEXT_DUE_AT", ""),
                "updated_at": env.get("UPDATED_AT", "") or file_mtime_iso(path),
                "state_file": str(path),
            }
        )
    return items


def collect_issue_queue(state_root: Path) -> dict[str, list[dict[str, Any]]]:
    queue_root = state_root / "resident-workers" / "issue-queue"
    pending_root = queue_root / "pending"
    claims_root = queue_root / "claims"

    def collect_files(root: Path) -> list[dict[str, Any]]:
        if not root.is_dir():
            return []
        items: list[dict[str, Any]] = []
        for path in sorted(root.glob("*.env"), key=lambda item: item.stat().st_mtime, reverse=True):
            env = read_env_file(path)
            items.append(
                {
                    "issue_id": env.get("ISSUE_ID", path.stem.removeprefix("issue-")),
                    "session": env.get("SESSION", ""),
                    "claim_file": env.get("CLAIM_FILE", ""),
                    "updated_at": env.get("UPDATED_AT", "") or file_mtime_iso(path),
                    "state_file": str(path),
                }
            )
        return items

    return {
        "pending": collect_files(pending_root),
        "claims": collect_files(claims_root),
    }


def build_profile_snapshot(profile_id: str, registry_root: Path) -> dict[str, Any]:
    env = env_with_profile(profile_id, registry_root)
    render_env = run_key_value_script(RENDER_FLOW_CONFIG, env)
    config_yaml = Path(render_env.get("CONFIG_YAML", registry_root / profile_id / "control-plane.yaml"))
    yaml_env = parse_simple_yaml(config_yaml)

    runs_root = Path(render_env.get("EFFECTIVE_RUNS_ROOT", ""))
    state_root = Path(render_env.get("EFFECTIVE_STATE_ROOT", ""))
    runs = collect_runs(runs_root)
    controllers = collect_resident_controllers(state_root)
    resident_workers = collect_resident_workers(state_root)
    cooldowns = collect_provider_cooldowns(state_root)
    scheduled = collect_scheduled_issues(state_root)
    queue = collect_issue_queue(state_root)

    return {
        "id": profile_id,
        "repo_slug": yaml_env.get("repo.slug", ""),
        "repo_root": render_env.get("EFFECTIVE_REPO_ROOT", ""),
        "runs_root": str(runs_root),
        "state_root": str(state_root),
        "issue_prefix": yaml_env.get("session_naming.issue_prefix", ""),
        "pr_prefix": yaml_env.get("session_naming.pr_prefix", ""),
        "coding_worker": render_env.get("EFFECTIVE_CODING_WORKER", ""),
        "provider_pool": {
            "order": render_env.get("EFFECTIVE_PROVIDER_POOL_ORDER", ""),
            "name": render_env.get("EFFECTIVE_PROVIDER_POOL_NAME", ""),
            "backend": render_env.get("EFFECTIVE_PROVIDER_POOL_BACKEND", ""),
            "model": render_env.get("EFFECTIVE_PROVIDER_POOL_MODEL", ""),
            "key": render_env.get("EFFECTIVE_PROVIDER_POOL_KEY", ""),
            "selection_reason": render_env.get("EFFECTIVE_PROVIDER_POOL_SELECTION_REASON", ""),
            "next_attempt_at": render_env.get("EFFECTIVE_PROVIDER_POOL_NEXT_ATTEMPT_AT", ""),
            "last_reason": render_env.get("EFFECTIVE_PROVIDER_POOL_LAST_REASON", ""),
            "pools_exhausted": render_env.get("EFFECTIVE_PROVIDER_POOLS_EXHAUSTED", ""),
        },
        "counts": {
            "active_runs": len(runs),
            "running_runs": sum(1 for item in runs if item["status"] == "RUNNING"),
            "failed_runs": sum(1 for item in runs if item["status"] == "FAILED"),
            "succeeded_runs": sum(1 for item in runs if item["status"] == "SUCCEEDED"),
            "implemented_runs": sum(1 for item in runs if item["result_kind"] == "implemented"),
            "reported_runs": sum(1 for item in runs if item["result_kind"] == "reported"),
            "blocked_runs": sum(1 for item in runs if item["result_kind"] == "blocked"),
            "completed_runs": sum(
                1 for item in runs if item["status"] == "SUCCEEDED" and item["result_kind"] not in {"implemented", "reported", "blocked"}
            ),
            "resident_controllers": len(controllers),
            "live_resident_controllers": sum(1 for item in controllers if item["state"] != "stopped" and item["controller_live"]),
            "resident_workers": len(resident_workers),
            "queued_issues": len(queue["pending"]),
            "claimed_issues": len(queue["claims"]),
            "provider_cooldowns": sum(1 for item in cooldowns if item["active"]),
            "scheduled_issues": len(scheduled),
        },
        "runs": runs,
        "resident_controllers": controllers,
        "resident_workers": resident_workers,
        "provider_cooldowns": cooldowns,
        "scheduled_issues": scheduled,
        "issue_queue": queue,
    }


def build_snapshot() -> dict[str, Any]:
    registry_root = profile_registry_root()
    profiles = [build_profile_snapshot(profile_id, registry_root) for profile_id in list_profile_ids(registry_root)]
    return {
        "generated_at": utc_now_iso(),
        "flow_skill_dir": str(ROOT_DIR),
        "profile_registry_root": str(registry_root),
        "profile_count": len(profiles),
        "profiles": profiles,
    }


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Render an ACP worker dashboard snapshot as JSON.")
    parser.add_argument("--pretty", action="store_true", help="Pretty-print JSON output.")
    args = parser.parse_args(argv)

    snapshot = build_snapshot()
    json.dump(snapshot, sys.stdout, indent=2 if args.pretty else None, sort_keys=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
