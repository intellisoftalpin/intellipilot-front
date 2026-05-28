# PowerShell shim for Windows shells that don't have bash.
#
# Tries Git Bash first (handles the heavy lifting of run-web.sh); falls back
# to a minimal direct `flutter run -d chrome` invocation if no bash is on
# PATH. Mirrors the bash script's most-used flags.
#
# Usage:
#   .\scripts\run-web.ps1
#   .\scripts\run-web.ps1 -Port 5173
#   .\scripts\run-web.ps1 -Host 0.0.0.0
#   .\scripts\run-web.ps1 -Mode release
#   .\scripts\run-web.ps1 -Build

[CmdletBinding()]
param(
  [int]    $Port    = $(if ($env:INTELLIPILOT_PORT) { [int]$env:INTELLIPILOT_PORT } else { 8080 }),
  [string] $Host_   = $(if ($env:INTELLIPILOT_HOST) { $env:INTELLIPILOT_HOST } else { '127.0.0.1' }),
  [ValidateSet('debug','profile','release')]
  [string] $Mode    = 'debug',
  [switch] $Build,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $Extra = @()
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
Set-Location $repoRoot

# Prefer running the canonical bash script under Git Bash if it's available —
# that path has the full feature set and a single place to maintain.
$bash = Get-Command bash -ErrorAction SilentlyContinue
if ($bash) {
  $bashArgs = @('./scripts/run-web.sh', '--port', "$Port", '--host', $Host_, '--mode', $Mode)
  if ($Build) { $bashArgs += '--build' }
  if ($Extra.Count -gt 0) {
    $bashArgs += '--'
    $bashArgs += $Extra
  }
  & $bash.Source @bashArgs
  exit $LASTEXITCODE
}

Write-Host "→ Running without bash (fallback path; install Git Bash for full features)."

# Resolve a Flutter command (fvm first, then PATH).
$flutter = $null
if (Get-Command fvm -ErrorAction SilentlyContinue) {
  $flutter = @('fvm', 'flutter')
} elseif (Get-Command flutter -ErrorAction SilentlyContinue) {
  $flutter = @('flutter')
} else {
  Write-Error 'Flutter not found. Install fvm (recommended) or add flutter to PATH.'
  exit 1
}

if ($Build) {
  $buildArgs = @('build', 'web', '--release') + $Extra
  & $flutter[0] @($flutter[1..($flutter.Length - 1)] + $buildArgs)
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  Write-Host "→ Serving build/web on http://$Host_:$Port (Ctrl+C to stop)"
  $py = Get-Command python -ErrorAction SilentlyContinue
  if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
  if (-not $py) {
    Write-Error 'No Python on PATH. Install Python 3 or run: dart pub global activate dhttpd'
    exit 1
  }
  Push-Location 'build/web'
  & $py.Source '-m' 'http.server' "$Port" '--bind' $Host_
  Pop-Location
  exit $LASTEXITCODE
}

$runArgs = @('run', '-d', 'chrome', "--web-port=$Port", "--web-hostname=$Host_")
switch ($Mode) {
  'profile' { $runArgs += '--profile' }
  'release' { $runArgs += '--release' }
}
$runArgs += $Extra
& $flutter[0] @($flutter[1..($flutter.Length - 1)] + $runArgs)
exit $LASTEXITCODE
