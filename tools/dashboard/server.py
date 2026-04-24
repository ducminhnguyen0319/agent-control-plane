#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
from functools import partial
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

from dashboard_snapshot import build_snapshot

ROOT_DIR = Path(__file__).resolve().parents[2]
TOOLS_BIN_DIR = ROOT_DIR / "tools" / "bin"


DASHBOARD_DIR = Path(__file__).resolve().parent


class DashboardHandler(SimpleHTTPRequestHandler):
    server_version = "ACPDashboard/1.0"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/snapshot.json":
            payload = build_snapshot()
            encoded = json.dumps(payload, indent=2).encode("utf-8")
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(encoded)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(encoded)
            return
        if parsed.path == "/api/doctor":
            query = parse_qs(parsed.query)
            profile_id = (query.get("profile_id") or [""])[0]
            if not profile_id:
                self.send_response(HTTPStatus.BAD_REQUEST)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "profile_id is required"}).encode("utf-8"))
                return
            doctor_script = TOOLS_BIN_DIR / "flow-runtime-doctor.sh"
            if not doctor_script.is_file():
                self.send_response(HTTPStatus.NOT_FOUND)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "doctor script not found"}).encode("utf-8"))
                return
            try:
                env = os.environ.copy()
                env["ACP_PROJECT_ID"] = profile_id
                output = subprocess.check_output(
                    ["bash", str(doctor_script)],
                    cwd=str(ROOT_DIR),
                    env=env,
                    text=True,
                    stderr=subprocess.STDOUT,
                    timeout=120,
                )
                payload = {"output": output}
                encoded = json.dumps(payload).encode("utf-8")
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(encoded)))
                self.end_headers()
                self.wfile.write(encoded)
            except subprocess.TimeoutExpired:
                self.send_response(HTTPStatus.GATEWAY_TIMEOUT)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "doctor timed out"}).encode("utf-8"))
            except subprocess.CalledProcessError as exc:
                payload = {"error": exc.returncode, "output": exc.output}
                encoded = json.dumps(payload).encode("utf-8")
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(encoded)))
                self.end_headers()
                self.wfile.write(encoded)
            return
        if parsed.path == "/api/profile/export":
            query = parse_qs(parsed.query)
            profile_id = (query.get("profile_id") or [""])[0]
            if not profile_id:
                self.send_response(HTTPStatus.BAD_REQUEST)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "profile_id is required"}).encode("utf-8"))
                return
            registry_root = Path(os.environ.get("ACP_PROFILE_REGISTRY_ROOT", str(Path.home() / ".agent-runtime" / "control-plane" / "profiles")))
            profile_dir = registry_root / profile_id
            config_file = profile_dir / "control-plane.yaml"
            if not config_file.is_file():
                self.send_response(HTTPStatus.NOT_FOUND)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "profile config not found"}).encode("utf-8"))
                return
            try:
                config = config_file.read_text(encoding="utf-8")
                payload = {"profile_id": profile_id, "config": config, "config_file": str(config_file)}
                encoded = json.dumps(payload).encode("utf-8")
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(encoded)))
                self.end_headers()
                self.wfile.write(encoded)
            except Exception as exc:
                self.send_response(HTTPStatus.INTERNAL_SERVER_ERROR)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(exc)}).encode("utf-8"))
            return
        return super().do_GET()

    def end_headers(self) -> None:
        if self.path != "/api/snapshot.json":
            self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Serve the ACP worker dashboard.")
    parser.add_argument("--host", default="127.0.0.1", help="Bind host. Default: 127.0.0.1")
    parser.add_argument("--port", type=int, default=8765, help="Bind port. Default: 8765")
    parser.add_argument(
        "--registry-root",
        default="",
        help="Override ACP profile registry root for dashboard snapshot generation.",
    )
    args = parser.parse_args(argv)

    if args.registry_root:
        os.environ["ACP_PROFILE_REGISTRY_ROOT"] = args.registry_root

    handler = partial(DashboardHandler, directory=str(DASHBOARD_DIR))
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"ACP_DASHBOARD_URL=http://{args.host}:{args.port}", flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
