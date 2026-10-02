param(
    [switch]$AllowPython,
    [double]$PollSeconds = 3
)

$ErrorActionPreference = "Stop"

$env:BLENDER_REMOTE_REPO = "francesco-bufalini/VTT"
$env:BLENDER_REMOTE_ISSUE = "2"
$env:BLENDER_REMOTE_ALLOWED = "francesco-bufalini"
$env:BLENDER_REMOTE_POLL_SECONDS = [string]$PollSeconds
$env:BLENDER_REMOTE_ALLOW_PYTHON = $(if ($AllowPython) { "1" } else { "0" })

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI not found. Install it with: winget install --id GitHub.cli"
}

& gh auth status
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not authenticated. Run: gh auth login"
}

$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
    & $python.Source "$PSScriptRoot\daemon.py"
    exit $LASTEXITCODE
}

$py = Get-Command py -ErrorAction SilentlyContinue
if ($py) {
    & $py.Source -3 "$PSScriptRoot\daemon.py"
    exit $LASTEXITCODE
}

throw "Python 3 was not found in PATH."
