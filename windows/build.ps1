param([string]$Python = 'python', [switch]$SkipTests)
$ErrorActionPreference = 'Stop'
$taskRoot = $PSScriptRoot
$repo = Split-Path $taskRoot
$venv = Join-Path $taskRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $venv)) {
    & $Python -m venv (Join-Path $taskRoot '.venv')
    if ($LASTEXITCODE -ne 0) { throw 'Python 3.12+ x64 is required.' }
}
& $venv -m pip install -r (Join-Path $taskRoot 'requirements-dev.txt')
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
& $venv (Join-Path $taskRoot 'build.py') $(if ($SkipTests) { '--skip-tests' })
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
