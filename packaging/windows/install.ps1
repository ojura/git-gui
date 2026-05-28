# git-gui-pyggy installer for Windows.
#
# Installs this git-gui (diff syntax highlighting) into your Git for Windows,
# and sets up Python 3 + Pygments, which power the highlighting (Git for Windows
# ships no Python). git-gui works without them, just without colour.
#
# Usage, in a PowerShell prompt:
#     powershell -ExecutionPolicy Bypass -File install.ps1
#
# It will prompt for administrator rights, since Git for Windows usually lives
# under Program Files.

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSCommandPath

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git not found on PATH. Install Git for Windows first: https://git-scm.com/download/win"
}
$execPath = (& git --exec-path).Trim()
$share    = (Resolve-Path (Join-Path $execPath '..\..\share')).Path

# Copying into Git for Windows generally needs administrator rights; re-launch
# elevated if we are not already.
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
    [Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Re-launching as administrator to write into $execPath ..."
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    return
}

Write-Host "Installing git-gui-pyggy into Git for Windows..."
Copy-Item -Force (Join-Path $here 'git-gui') (Join-Path $execPath 'git-gui')
$libDst = Join-Path $share 'git-gui\lib'
New-Item -ItemType Directory -Force -Path $libDst | Out-Null
Copy-Item -Force -Recurse (Join-Path $here 'lib\*') $libDst
Write-Host "  git-gui -> $execPath"
Write-Host "  lib     -> $libDst"

# Python 3 + Pygments for the highlighting.
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
if (-not $py -and (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "Python not found; installing it via winget..."
    winget install -e --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
}
if ($py) {
    Write-Host "Installing Pygments..."
    & $py.Source -m pip install --upgrade pygments
    Write-Host ""
    Write-Host "Done. Launch with:  git gui"
} else {
    Write-Warning ("git-gui is installed and works, but highlighting needs Python 3 + Pygments. " +
        "Install Python from https://python.org , then run: pip install pygments")
}
