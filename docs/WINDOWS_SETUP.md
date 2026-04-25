# Windows Service Setup for agent-control-plane

This guide explains how to run ACP as a native Windows Service.

## Prerequisites

- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1+ (or PowerShell Core 6+)
- Python 3.8+ installed and in PATH
- Git for Windows (optional, for cloning)

## Option 1: Using NSSM (Recommended)

NSSM (Non-Sucking Service Manager) is a great tool for running any executable as a Windows Service.

### Install NSSM

Download from: https://nssm.cc/download

Or using Chocolatey:
```powershell
choco install nssm
```

### Install ACP Service

```powershell
# Clone or download ACP
git clone https://github.com/ducminhnguyen0319/agent-control-plane.git
cd agent-control-plane

# Install the service
nssm install "ACP_Dashboard" "C:\Path\To\python.exe" "C:\Path\To\agent-control-plane\tools\dashboard\server.py --host 127.0.0.1 --port 8765"

# Set service description
nssm set "ACP_Dashboard" Description "Agent Control Plane Dashboard"

# Set startup directory
nssm set "ACP_Dashboard" AppDirectory "C:\Path\To\agent-control-plane"

# Start the service
nssm start "ACP_Dashboard"
```

### Manage Service

```powershell
# Check status
nssm status "ACP_Dashboard"

# Stop service
nssm stop "ACP_Dashboard"

# Restart service
nssm restart "ACP_Dashboard"

# Remove service
nssm remove "ACP_Dashboard" confirm
```

## Option 2: Using sc.exe (Built-in)

```powershell
# Create service
sc create "ACP_Dashboard" binPath= "C:\Path\To\python.exe C:\Path\To\agent-control-plane\tools\dashboard\server.py --host 127.0.0.1 --port 8765" start= auto

# Set description
sc description "ACP_Dashboard" "Agent Control Plane Dashboard"

# Start service
sc start "ACP_Dashboard"

# Check status
sc query "ACP_Dashboard"
```

## Option 3: Using PowerShell Cmdlets

```powershell
# Create service
$service = New-Service -Name "ACP_Dashboard" `
    -BinaryPathName "C:\Path\To\python.exe C:\Path\To\agent-control-plane\tools\dashboard\server.py --host 127.0.0.1 --port 8765" `
    -DisplayName "ACP Dashboard" `
    -Description "Agent Control Plane Dashboard" `
    -StartupType Automatic

# Start service
Start-Service -Name "ACP_Dashboard"

# Check status
Get-Service -Name "ACP_Dashboard"
```

## Verifying Installation

1. Open browser to: http://127.0.0.1:8765
2. Check service status in Windows Services MMC (services.msc)
3. View logs at: `%USERPROFILE%\.agent-runtime\logs\`

## Troubleshooting

### Service won't start
- Check Python is in system PATH
- Verify all dependencies installed: `pip install -r tools\dashboard\requirements.txt`
- Check Windows Event Viewer for service errors

### Port already in use
- Change port: Edit service parameters to use different `--port`
- Or stop conflicting services

### Permission issues
- Run PowerShell as Administrator
- Grant "Log on as a service" right to the service account

## Uninstall

```powershell
# Using NSSM
nssm stop "ACP_Dashboard"
nssm remove "ACP_Dashboard" confirm

# Using sc.exe
sc stop "ACP_Dashboard"
sc delete "ACP_Dashboard"
```

## Notes

- ACP worker sessions may need additional setup for Git/SSH keys
- Windows paths use backslashes (`\`) in PowerShell, forward slashes (`/`) in Git Bash
- For production use, consider running as a dedicated service account (not your user account)
