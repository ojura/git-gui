# git-gui-pyggy one-line web installer.
#
# Fetches the latest release zip, unpacks it to a temp folder, and runs the
# bundled install.ps1 (which drops git-gui into Git for Windows and sets up
# Python 3 + Pygments). Meant to be piped straight into PowerShell:
#
#     irm https://raw.githubusercontent.com/ojura/git-gui/diff-syntax-highlight/packaging/windows/web-install.ps1 | iex

$ErrorActionPreference = 'Stop'
$repo = 'ojura/git-gui'

Write-Host "Looking up the latest git-gui-pyggy release..."
$release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" `
    -Headers @{ 'User-Agent' = 'git-gui-pyggy-installer' }
$asset = $release.assets |
    Where-Object { $_.name -like 'git-gui-pyggy-windows-*.zip' } |
    Select-Object -First 1
if (-not $asset) { throw "the latest release of $repo has no git-gui-pyggy-windows zip" }

$work = Join-Path $env:TEMP ("git-gui-pyggy-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$zip = Join-Path $work $asset.name
Write-Host "Downloading $($asset.name) ..."
Invoke-WebRequest $asset.browser_download_url -OutFile $zip `
    -Headers @{ 'User-Agent' = 'git-gui-pyggy-installer' }
Expand-Archive -Path $zip -DestinationPath $work -Force

# The zip contains a single git-gui-pyggy-windows/ folder; run its installer,
# which self-elevates and installs from this temp copy.
& (Join-Path $work 'git-gui-pyggy-windows\install.ps1')
