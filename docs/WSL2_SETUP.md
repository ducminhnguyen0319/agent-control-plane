# ACP on Windows via WSL2

Pragmatic Windows support: run ACP inside WSL2 (Windows Subsystem for Linux) where it behaves like a Linux machine.

## Prerequisites

1. **Windows 10 version 2004+ or Windows 11**
2. **WSL2 with Ubuntu** (recommended distro)

```powershell
# In PowerShell (Admin)
wsl --install -d Ubuntu
```

3. **Inside WSL2 Ubuntu**, verify systemd is enabled:

```bash
# In WSL2 terminal
cat /etc/wsl.conf
```

If missing, create it:

```bash
sudo tee /etc/wsl.conf > /dev/null << 'EOF'
[boot]
systemd=true
EOF
```

Then restart WSL2 from PowerShell: `wsl --shutdown`

## Install ACP in WSL2

```bash
# Inside WSL2 Ubuntu
npx agent-control-plane@latest setup
```

The setup wizard detects Linux and offers systemd service installation.

## Project Service Setup (WSL2 + systemd)

Since WSL2 with systemd works like Linux, use the existing systemd scripts:

```bash
# Inside your project (in WSL2)
cd /path/to/your/project

# Bootstrap systemd service for ACP worker
agent-control-plane project systemd-bootstrap \
  --project-dir . \
  --repo-url https://github.com/your-org/your-repo.git \
  --worker-type claude \
  --schedule "*/30 * * * *" \
  --issues "1,2,3"
```

This creates:
- `~/.config/systemd/user/agent-control-plane@<project>.service`
- Timer unit for scheduled execution

Start the service:

```bash
systemctl --user daemon-reload
systemctl --user enable --now agent-control-plane@$(basename $(pwd)).timer
systemctl --user status agent-control-plane@$(basename $(pwd)).timer
```

## Path Translation

When working with Windows paths from WSL2:

```bash
# Windows: C:\Users\YourName\Projects\my-repo
# WSL2:    /mnt/c/Users/YourName/Projects/my-repo

cd /mnt/c/Users/YourName/Projects/my-repo
npx agent-control-plane@latest setup
```

## Docker in WSL2

If using Docker (e.g., for f-losning's `pnpm db:up`):

1. Install Docker Desktop for Windows
2. Enable "WSL2 integration" in Docker Desktop settings
3. Select your Ubuntu distro

Verify in WSL2:

```bash
docker --version
docker compose version
```

## Known Limitations

- **No native Windows agent** — ACP runs inside WSL2, not PowerShell
- **Path confusion** — Be careful with Windows vs WSL2 paths
- **WSL2 must be running** — Services stop when all WSL2 instances exit
- **systemd in WSL2** — Requires Windows 11 22H2+ or manual enable

## Troubleshooting

### WSL2 doesn't have systemd

```bash
# Check
ps -p 1 -o comm=

# Should print "systemd"
# If not, edit /etc/wsl.conf as shown above and run: wsl --shutdown
```

### npm/npx not found in WSL2

```bash
# Install Node.js via nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install --lts
nvm use --lts
```

### Permission denied on scripts

```bash
chmod +x ~/.local/share/agent-control-plane/tools/bin/*.sh
```

## Next Steps

- See [README.md](README.md) for full ACP documentation
- See [SYSTEMD.md](SYSTEMD.md) for service management
- File issues at: https://github.com/hyrup-digital/agent-control-plane/issues
