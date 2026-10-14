param([string]$StateDirectory = '')
$ErrorActionPreference = 'Stop'
$executable = Join-Path $PSScriptRoot 'OpenCommander.exe'
if (-not (Test-Path -LiteralPath $executable)) { throw 'Run this script inside the extracted application package.' }
$arguments = ''
if ($StateDirectory) {
    $StateDirectory = (Resolve-Path -LiteralPath $StateDirectory).Path
    if (-not (Test-Path -LiteralPath $StateDirectory -PathType Container)) { throw 'StateDirectory must be an existing profile directory.' }
    $arguments = '--state-dir "' + $StateDirectory + '"'
}
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'OpenCommander.lnk'))
$shortcut.TargetPath = $executable
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.IconLocation = $executable
$shortcut.Arguments = $arguments
$shortcut.Save()
foreach ($kind in @('Directory', 'Drive')) {
    $key = "HKCU:\Software\Classes\$kind\shell\OpenCommander"
    New-Item -Path "$key\command" -Force | Out-Null
    Set-Item -LiteralPath $key -Value 'OpenCommander'
    Set-Item -LiteralPath "$key\command" -Value ('"' + $executable + '" ' + $arguments + ' "%1"')
}
Write-Output 'Start menu shortcut and OpenCommander context menu installed for the current user.'
