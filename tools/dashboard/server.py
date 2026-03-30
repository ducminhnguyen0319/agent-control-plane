#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from functools import partial
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from dashboard_snapshot import build_snapshot


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
