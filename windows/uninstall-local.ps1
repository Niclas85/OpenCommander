$ErrorActionPreference = 'Stop'
$directoryKey = 'HKCU:\Software\Classes\Directory\shell'
if (Test-Path -LiteralPath $directoryKey) {
    if ((Get-Item -LiteralPath $directoryKey).GetValue('') -eq 'OpenCommander') {
        $previous = ''
        if (Test-Path -LiteralPath 'HKCU:\Software\OpenCommander') {
            $previous = (Get-Item -LiteralPath 'HKCU:\Software\OpenCommander').GetValue('PreviousDirectoryVerb', '')
        }
        Set-Item -LiteralPath $directoryKey -Value $previous
    }
}
foreach ($kind in @('Directory', 'Drive')) {
    $key = "HKCU:\Software\Classes\$kind\shell\OpenCommander"
    if (Test-Path -LiteralPath "$key\command") { Remove-Item -LiteralPath "$key\command" }
    if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key }
}
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'OpenCommander.lnk'
if (Test-Path -LiteralPath $shortcut) { Remove-Item -LiteralPath $shortcut }
Write-Output 'Shell integration removed. Application files, settings, credentials and recovery data retained.'
