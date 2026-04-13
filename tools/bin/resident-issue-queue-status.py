#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[1]
DASHBOARD_DIR = ROOT_DIR / "dashboard"
if str(DASHBOARD_DIR) not in sys.path:
    sys.path.insert(0, str(DASHBOARD_DIR))

from issue_queue_state import collect_issue_queue


def main() -> int:
    parser = argparse.ArgumentParser(description="Render resident issue queue state as JSON.")
    parser.add_argument("--state-root", default=os.environ.get("ACP_STATE_ROOT", "").strip(), help="ACP runtime state root")
    parser.add_argument("--pretty", action="store_true", help="Pretty-print JSON output")
    args = parser.parse_args()

    if not args.state_root:
        parser.error("--state-root is required")

    payload = collect_issue_queue(Path(args.state_root).expanduser())
    json.dump(payload, sys.stdout, indent=2 if args.pretty else None, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
