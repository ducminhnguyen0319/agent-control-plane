# install-windows-service.ps1
# Install ACP as a Windows Service using NSSM (recommended) or sc.exe

[CmdletBinding()]
param(
    [string]$ServiceName = "ACP_Dashboard",
    [string]$PythonPath = "",
    [string]$ACPRoot = "",
    [string]$HostName = "127.0.0.1",
    [int]$Port = 8765,
    [switch]$UseNSSM,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param($Message)
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -ForegroundColor Cyan
}

function Test-CommandExists {
    param($Command)
    try { Get-Command $Command -ErrorAction Stop | Out-Null; return $true }
    catch { return $false }
}

# Uninstall mode
if ($Uninstall) {
    Write-Log "Uninstalling service '$ServiceName'..."
    if (Test-CommandExists "nssm.exe") {
        & nssm stop $ServiceName confirm
        & nssm remove $ServiceName confirm
    } elseif (Test-CommandExists "sc.exe") {
        & sc.exe stop $ServiceName
        & sc.exe delete $ServiceName
    } else {
        Write-Error "Neither nssm nor sc.exe found. Cannot uninstall service."
        exit 1
    }
    Write-Log "Service '$ServiceName' uninstalled successfully."
    exit 0
}

# Detect Python
if (-not $PythonPath) {
    $PythonPath = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
    if (-not $PythonPath) {
        $PythonPath = (Get-Command py.exe -ErrorAction SilentlyContinue).Source
    }
    if (-not $PythonPath) {
        Write-Error "Python not found in PATH. Please install Python 3.8+ or specify -PythonPath."
        exit 1
    }
}
Write-Log "Using Python: $PythonPath"

# Detect ACP root
if (-not $ACPRoot) {
    $ACPRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ACPRoot = Split-Path -Parent $ACPRoot  # Go up to repo root
}
$ServerScript = Join-Path $ACPRoot "tools\dashboard\server.py"
if (-not (Test-Path $ServerScript)) {
    Write-Error "Server script not found: $ServerScript"
    exit 1
}
Write-Log "ACP Root: $ACPRoot"
Write-Log "Server Script: $ServerScript"

# Build arguments
$ServiceArgs = @(
    $PythonPath,
    $ServerScript,
    "--host", $HostName,
    "--port", $Port.ToString()
)

# Install using NSSM (recommended)
if ($UseNSSM -or (Test-CommandExists "nssm.exe")) {
    Write-Log "Installing service using NSSM..."
    & nssm install $ServiceName $ServiceArgs[0] $ServiceArgs[1..($ServiceArgs.Count-1)]
    if ($LASTEXITCODE -ne 0) {
        Write-Error "NSSM install failed with exit code $LASTEXITCODE"
        exit 1
    }
    & nssm set $ServiceName Description "Agent Control Plane Dashboard"
    & nssm set $ServiceName AppDirectory $ACPRoot
    Write-Log "Starting service..."
    & nssm start $ServiceName
    Write-Log "Service '$ServiceName' installed and started successfully using NSSM."
    Write-Log "Dashboard URL: http://${HostName}:$Port"
    exit 0
}

# Install using sc.exe (built-in)
if (Test-CommandExists "sc.exe") {
    Write-Log "Installing service using sc.exe..."
    $BinPath = '"{0}" "{1}"' -f $ServiceArgs[0], ($ServiceArgs[1..($ServiceArgs.Count-1)] -join ' '
    & sc.exe create $ServiceName binPath= $BinPath start= auto
    if ($LASTEXITCODE -ne 0) {
        Write-Error "sc.exe create failed with exit code $LASTEXITCODE"
        exit 1
    }
    & sc.exe description $ServiceName "Agent Control Plane Dashboard"
    Write-Log "Starting service..."
    & sc.exe start $ServiceName
    Write-Log "Service '$ServiceName' installed and started successfully using sc.exe."
    Write-Log "Dashboard URL: http://${HostName}:$Port"
    exit 0
}

Write-Error "Neither NSSM nor sc.exe available. Please install NSSM from https://nssm.cc/download"
exit 1
