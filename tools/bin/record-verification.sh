#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  record-verification.sh --command <shell command> [--status pass|fail] [--run-dir <path>] [--note <text>]

Append one structured verification entry to verification.jsonl for the current
worker run. Defaults to the sandbox run directory exposed by the worker env.
EOF
}

run_dir="${ACP_RUN_DIR:-${F_LOSNING_RUN_DIR:-${AGENT_PROJECT_RUN_DIR:-}}}"
status="pass"
command_text=""
note=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) run_dir="${2:-}"; shift 2 ;;
    --status) status="${2:-}"; shift 2 ;;
    --command) command_text="${2:-}"; shift 2 ;;
    --note) note="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$run_dir" || -z "$command_text" ]]; then
  usage >&2
  exit 1
fi

case "$status" in
  pass|fail) ;;
  *)
    echo "Unsupported status: $status" >&2
    exit 1
    ;;
esac

mkdir -p "$run_dir"

RUN_DIR="$run_dir" STATUS="$status" COMMAND_TEXT="$command_text" NOTE="$note" node <<'EOF'
const fs = require('fs');
const path = require('path');

const runDir = process.env.RUN_DIR;
const status = process.env.STATUS;
const command = process.env.COMMAND_TEXT;
const note = process.env.NOTE || '';

const entry = {
  timestamp: new Date().toISOString(),
  status,
  command,
};

if (note) {
  entry.note = note;
}

const file = path.join(runDir, 'verification.jsonl');
fs.appendFileSync(file, `${JSON.stringify(entry)}\n`);
process.stdout.write(`${file}\n`);
EOF
