$ErrorActionPreference = 'Stop'
foreach ($script in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1') {
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count) { throw "PowerShell parse errors in $($script.Name): $($parseErrors.Message -join ', ')" }
}
& "$PSScriptRoot/publish.ps1" -UniverseId 1 -PlaceId 2 -DryRun
$rejected=$false
try { & "$PSScriptRoot/publish.ps1" -UniverseId invalid -PlaceId 2 -DryRun } catch { $rejected=$true }
if (-not $rejected) { throw 'Invalid target was accepted.' }
$rejected=$false
try { & "$PSScriptRoot/publish.ps1" -UniverseId 1 -PlaceId 2 -PlaceFile "$PSScriptRoot/publish.ps1" -DryRun } catch { $rejected=$true }
if (-not $rejected) { throw 'Non-place file was accepted.' }
$receiptFile=Join-Path ([IO.Path]::GetTempPath()) ('aether-receipt-'+[guid]::NewGuid()+'.json')
try {
    $placeFile=Join-Path $PSScriptRoot '../Aether-Isles.rbxl'
    $hash=(Get-FileHash -LiteralPath $placeFile -Algorithm SHA256).Hash.ToLowerInvariant()
    @{operationId='test-operation';universeId='1';placeId='2';sha256=$hash} | ConvertTo-Json | Set-Content -LiteralPath $receiptFile
    & "$PSScriptRoot/publish.ps1" -UniverseId 1 -PlaceId 2 -OperationId test-operation -ReceiptPath $receiptFile -DryRun
    $rejected=$false
    try { & "$PSScriptRoot/publish.ps1" -UniverseId 1 -PlaceId 3 -OperationId test-operation -ReceiptPath $receiptFile -DryRun } catch { $rejected=$true }
    if (-not $rejected) { throw 'Mismatched resume target was accepted.' }
    $rejected=$false
    try { & "$PSScriptRoot/publish.ps1" -UniverseId 1 -PlaceId 2 -OperationId different-operation -ReceiptPath $receiptFile -DryRun } catch { $rejected=$true }
    if (-not $rejected) { throw 'Mismatched resume operation was accepted.' }
} finally { Remove-Item -LiteralPath $receiptFile -ErrorAction SilentlyContinue }
Write-Host 'Release checks passed: PowerShell syntax, offline dry run, invalid target/file rejection.'
