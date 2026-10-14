param([string]$Python = 'python', [switch]$SkipTests, [switch]$RequirePublisherGoogle)
$ErrorActionPreference = 'Stop'
$env:PYTHONUTF8 = '1'
$taskRoot = $PSScriptRoot
$repo = Split-Path $taskRoot
$venv = Join-Path $taskRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $venv)) {
    & $Python -m venv (Join-Path $taskRoot '.venv')
    if ($LASTEXITCODE -ne 0) { throw 'Python 3.12+ x64 is required.' }
}
& $venv -m pip install -r (Join-Path $taskRoot 'requirements-dev.txt')
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
$buildArguments = @()
if ($SkipTests) { $buildArguments += '--skip-tests' }
if ($RequirePublisherGoogle) { $buildArguments += '--require-publisher-google' }
& $venv (Join-Path $taskRoot 'build.py') @buildArguments
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
