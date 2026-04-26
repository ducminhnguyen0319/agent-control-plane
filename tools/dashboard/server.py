#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import os
import subprocess
from pathlib import Path
from functools import partial

from aiohttp import web, WSMsgType
from aiohttp_cors import setup as cors_setup, ResourceOptions

from dashboard_snapshot import build_snapshot

ROOT_DIR = Path(__file__).resolve().parents[2]
TOOLS_BIN_DIR = ROOT_DIR / "tools" / "bin"
DASHBOARD_DIR = Path(__file__).resolve().parent

# Store connected WebSocket clients
ws_clients: set[web.WebSocketResponse] = set()


async def broadcast_snapshot():
    """Broadcast current snapshot to all connected WebSocket clients."""
    if not ws_clients:
        return
    payload = build_snapshot()
    encoded = json.dumps(payload, indent=2).encode("utf-8")
    disconnected = set()
    for ws in ws_clients:
        try:
            await ws.send_bytes(encoded)
        except Exception:
            disconnected.add(ws)
    for ws in disconnected:
        ws_clients.discard(ws)


async def snapshot_handler(request: web.Request) -> web.Response:
    """HTTP endpoint: GET /api/snapshot.json"""
    payload = build_snapshot()
    encoded = json.dumps(payload, indent=2).encode("utf-8")
    return web.Response(
        body=encoded,
        content_type="application/json; charset=utf-8",
        headers={"Cache-Control": "no-store"},
    )


async def doctor_handler(request: web.Request) -> web.Response:
    """HTTP endpoint: GET /api/doctor?profile_id=xxx"""
    profile_id = request.query.get("profile_id", "")
    if not profile_id:
        return web.Response(
            body=json.dumps({"error": "profile_id is required"}),
            status=400,
            content_type="application/json",
        )
    doctor_script = TOOLS_BIN_DIR / "flow-runtime-doctor.sh"
    if not doctor_script.is_file():
        return web.Response(
            body=json.dumps({"error": "doctor script not found"}),
            status=404,
            content_type="application/json",
        )
    try:
        env = os.environ.copy()
        env["ACP_PROJECT_ID"] = profile_id
        proc = await asyncio.create_subprocess_exec(
            "bash",
            str(doctor_script),
            cwd=str(ROOT_DIR),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        output, _ = await asyncio.wait_for(proc.communicate(), timeout=120)
        payload = {"output": output.decode("utf-8", errors="replace")}
        return web.Response(
            body=json.dumps(payload),
            content_type="application/json; charset=utf-8",
        )
    except asyncio.TimeoutError:
        return web.Response(
            body=json.dumps({"error": "doctor timed out"}),
            status=504,
            content_type="application/json",
        )
    except subprocess.CalledProcessError as exc:
        payload = {"error": exc.returncode, "output": exc.output}
        return web.Response(
            body=json.dumps(payload),
            content_type="application/json; charset=utf-8",
        )


async def scheduler_status_handler(request: web.Request) -> web.Response:
    """HTTP endpoint: GET /api/scheduler-status"""
    
    # Check if scheduler is running
    state_dir = Path.home() / ".agent-runtime" / "control-plane" / "kick-scheduler"
    pid_file = state_dir / "pid"
    log_file = state_dir / "kick-scheduler.log"
    
    is_running = False
    pid = None
    if pid_file.is_file():
        pid = pid_file.read_text().strip()
        if pid:
            try:
                os.kill(int(pid), 0)  # Check if process exists
                is_running = True
            except (ProcessLookupError, PermissionError):
                is_running = False
    
    # Read last few lines of log
    last_log_lines = []
    if log_file.is_file():
        try:
            lines = log_file.read_text().strip().split("\n")
            last_log_lines = lines[-5:] if len(lines) > 5 else lines
        except Exception:
            pass
    
    payload = {
        "is_running": is_running,
        "pid": pid if is_running else None,
        "state_dir": str(state_dir),
        "last_log_lines": last_log_lines,
        "message": "Scheduler status from real state",
    }
    return web.Response(
        body=json.dumps(payload, indent=2),
        content_type="application/json; charset=utf-8",
    )


async def profile_export_handler(request: web.Request) -> web.Response:
    """HTTP endpoint: GET /api/profile/export?profile_id=xxx"""
    profile_id = request.query.get("profile_id", "")
    if not profile_id:
        return web.Response(
            body=json.dumps({"error": "profile_id is required"}),
            status=400,
            content_type="application/json",
        )
    registry_root = Path(
        os.environ.get(
            "ACP_PROFILE_REGISTRY_ROOT",
            str(Path.home() / ".agent-runtime" / "control-plane" / "profiles"),
        )
    )
    config_file = registry_root / profile_id / "control-plane.yaml"
    if not config_file.is_file():
        return web.Response(
            body=json.dumps({"error": "profile config not found"}),
            status=404,
            content_type="application/json",
        )
    try:
        config = config_file.read_text(encoding="utf-8")
        payload = {"profile_id": profile_id, "config": config, "config_file": str(config_file)}
        return web.Response(
            body=json.dumps(payload),
            content_type="application/json; charset=utf-8",
        )
    except Exception as exc:
        return web.Response(
            body=json.dumps({"error": str(exc)}),
            status=500,
            content_type="application/json",
        )


async def profile_import_handler(request: web.Request) -> web.Response:
    """HTTP endpoint: POST /api/profile/import"""
    if request.method != "POST":
        return web.Response(
            body=json.dumps({"error": "POST required"}),
            status=405,
            content_type="application/json",
        )
    try:
        data = await request.json()
        profile_id = data.get("profile_id", "")
        config = data.get("config", "")
        if not profile_id or not config:
            return web.Response(
                body=json.dumps({"error": "profile_id and config required"}),
                status=400,
                content_type="application/json",
            )
        registry_root = Path(
            os.environ.get(
                "ACP_PROFILE_REGISTRY_ROOT",
                str(Path.home() / ".agent-runtime" / "control-plane" / "profiles"),
            )
        )
        profile_dir = registry_root / profile_id
        config_file = profile_dir / "control-plane.yaml"
        profile_dir.mkdir(parents=True, exist_ok=True)
        config_file.write_text(config, encoding="utf-8")
        payload = {"status": "ok", "profile_id": profile_id, "config_file": str(config_file)}
        return web.Response(
            body=json.dumps(payload),
            content_type="application/json; charset=utf-8",
        )
    except Exception as exc:
        return web.Response(
            body=json.dumps({"error": str(exc)}),
            status=500,
            content_type="application/json",
        )


async def websocket_handler(request: web.Request) -> web.WebSocketResponse:
    """WebSocket endpoint: GET /ws"""
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    ws_clients.add(ws)
    try:
        # Send initial snapshot
        payload = build_snapshot()
        encoded = json.dumps(payload, indent=2).encode("utf-8")
        await ws.send_bytes(encoded)
        # Keep connection alive, listen for client messages (ping/pong)
        async for msg in ws:
            if msg.type == WSMsgType.TEXT:
                # Echo back or handle commands if needed
                await ws.send_str(msg.data)
            elif msg.type == WSMsgType.ERROR:
                break
    except Exception:
        pass
    finally:
        ws_clients.discard(ws)
    return ws


def build_app() -> web.Application:
    app = web.Application()
    # Routes
    app.router.add_get("/api/snapshot.json", snapshot_handler)
    app.router.add_get("/api/doctor", doctor_handler)
    app.router.add_get("/api/profile/export", profile_export_handler)
    app.router.add_get("/api/scheduler-status", scheduler_status_handler)
    app.router.add_post("/api/profile/import", profile_import_handler)
    app.router.add_get("/ws", websocket_handler)
    # Static files (dashboard HTML/CSS/JS)
    app.router.add_static("/", path=str(DASHBOARD_DIR), show_index=True)
    # CORS setup
    cors = cors_setup(
        app,
        defaults={
            "*": ResourceOptions(
                allow_credentials=True,
                expose_headers="*",
                allow_headers="*",
                allow_methods=["GET", "POST", "OPTIONS"],
            )
        },
    )
    return app


async def poll_snapshot_changes(interval: int = 5):
    """Periodically check for snapshot changes and broadcast to WS clients."""
    last_snapshot = None
    while True:
        try:
            current = build_snapshot()
            if current != last_snapshot:
                await broadcast_snapshot()
                last_snapshot = current
        except Exception:
            pass
        await asyncio.sleep(interval)


async def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Serve the ACP worker dashboard with WebSocket support.")
    parser.add_argument("--host", default="127.0.0.1", help="Bind host. Default: 127.0.0.1")
    parser.add_argument("--port", type=int, default=8765, help="Bind port. Default: 8765")
    parser.add_argument(
        "--registry-root",
        default="",
        help="Override ACP profile registry root for dashboard snapshot generation.",
    )
    parser.add_argument(
        "--no-poll",
        action="store_true",
        help="Disable snapshot polling (manual refresh only)",
    )
    args = parser.parse_args(argv)

    if args.registry_root:
        os.environ["ACP_PROFILE_REGISTRY_ROOT"] = args.registry_root

    app = build_app()

    # Start background task for polling if not disabled
    if not args.no_poll:
        asyncio.create_task(poll_snapshot_changes())

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, args.host, args.port)
    await site.start()

    print(f"ACP_DASHBOARD_URL=http://{args.host}:{args.port}", flush=True)
    print(f"WebSocket endpoint: ws://{args.host}:{args.port}/ws", flush=True)

    # Run forever
    try:
        await asyncio.Event().wait()
    except (KeyboardInterrupt, SystemExit):
        pass
    finally:
        await runner.cleanup()
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
