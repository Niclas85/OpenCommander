param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AppArguments)
$ErrorActionPreference = 'Stop'
$python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    python -m venv (Join-Path $PSScriptRoot '.venv')
    if ($LASTEXITCODE -ne 0) { throw 'Python 3.12+ x64 is required.' }
    & $python -m pip install -r (Join-Path $PSScriptRoot 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
}
& $python (Join-Path $PSScriptRoot 'launcher.py') @AppArguments
exit $LASTEXITCODE
