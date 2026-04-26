# ACP Demo Flows

Quick-start demos for common ACP workflows. Each flow shows the commands, expected output, and what to verify.

## Flow 1: First-Time Setup

**Goal**: Set up ACP with a new repo in one command.

```bash
# 1. Create a test repo
mkdir -p /tmp/demo-repo && cd /tmp/demo-repo
git init && git commit --allow-empty -m "init"

# 2. Run setup wizard
npx agent-control-plane@latest setup \
  --repo-root /tmp/demo-repo \
  --profile-id demo \
  --non-interactive \
  --no-start-runtime

# 3. Verify
ls ~/.agent-runtime/control-plane/profiles/demo/control-plane.yaml
cat ~/.agent-runtime/control-plane/profiles/demo/control-plane.yaml

# Expected: Profile created with correct repo-slug, worker backend, etc.
```

**Verify**:
- [x] Profile YAML exists
- [x] `worker_backend` is set
- [x] `runtime_home` is configured

---

## Flow 2: Doctor Check

**Goal**: Verify ACP installation health.

```bash
# Run doctor
npx agent-control-plane@latest doctor

# Expected output:
# CONTROL_PLANE_NAME=agent-control-plane
# FLOW_SKILL_DIR=/path/to/skill#
# PROFILE_ID=demo#
# DOCTOR_STATUS=ok#
```

**Verify**:
- [x] `DOCTOR_STATUS=ok`
- [x] No errors about missing binaries or configs

---

## Flow 3: Runtime Status

**Goal**: Check if workers are running.

```bash
# Check runtime status
npx agent-control-plane@latest runtime status --profile-id demo

# Expected output shows:
# PROFILE_ID=demo#
# RUNTIME_STATUS=stopped|running#
# ACTIVE_RUNS=0#
```

**Verify**:
- [x] Status is `ok` or `stopped`
- [x] No stale sessions or errors

---

## Flow 4: Dashboard Quick View

**Goal**: Launch dashboard and see live state (WebSocket updates).

```bash
# Start dashboard (background)
npx agent-control-plane@latest dashboard --host 127.0.0.1 --port 8765 &

# Open in browser:
# http://localhost:8765

# Expected: Dashboard shows:
# - Profiles card (1+ profiles)
# - Run sessions card
# - Implemented runs card
# - Alerts card (0+)
# - Real-time WebSocket updates (no more 5s polling!)
```
**Verify**:
- [x] Dashboard loads in browser
- [x] Cards show correct counts
- [x] Polling updates every 5s

---

## Flow 5: Worker Session (Simple)

**Goal**: Run a simple worker session.

```bash
# Start runtime (background)
npx agent-control-plane@latest runtime start --profile-id demo --wait-seconds 1

# Expected: Worker session starts in tmux
# Check: tmux ls | grep agent-
```

**Verify**:
- [x] `tmux` session created
- [x] Worker process running
- [x] `runtime status` shows `running`

---

## Flow 6: Multi-Backend Swap

**Goal**: Switch between worker backends.

```bash
# 1. Check available backends
ls tools/bin/agent-project-run-*.sh

# 2. Edit profile to switch backend
# (edit ~/.agent-runtime/control-plane/profiles/demo/control-plane.yaml)
# Change: worker_backend: claude → worker_backend: codex

# 3. Restart runtime
npx agent-control-plane@latest runtime stop --profile-id demo
npx agent-control-plane@latest runtime start --profile-id demo

# Expected: Worker now uses Codex instead of Claude
```

**Verify**:
- [x] Backend switched without rebuilding runtime
- [x] New worker session uses correct CLI

---

## Screenshots Needed

To strengthen public docs, add screenshots of:

1. **Setup wizard** - terminal output showing setup completion
2. **Doctor output** - clean doctor check with `DOCTOR_STATUS=ok`
3. **Dashboard** - browser view showing all cards/metrics
4. **Runtime status** - terminal output with profile info
5. **tmux sessions** - `tmux ls` showing agent sessions
6. **Multi-backend** - side-by-side config comparison

Add these to `assets/readme/` and reference in README.md.
