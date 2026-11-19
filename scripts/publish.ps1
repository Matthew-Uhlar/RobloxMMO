param(
    [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,15}$')][string]$UniverseId,
    [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,15}$')][string]$PlaceId,
    [string]$PlaceFile = (Join-Path $PSScriptRoot '../Aether-Isles.rbxl'),
    [switch]$DryRun,
    [string]$OperationId,
    [string]$ReceiptPath = (Join-Path $PSScriptRoot '../publish-receipt.json')
)
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$file = Get-Item -LiteralPath $PlaceFile
if ($file.Extension -notin @('.rbxl','.rbxlx') -or $file.Length -le 0 -or $file.Length -gt 104857600) { throw 'Expected a nonempty .rbxl/.rbxlx file up to 100 MiB.' }
$hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$mime = if ($file.Extension -eq '.rbxl') { 'application/octet-stream' } else { 'application/xml' }
if ($OperationId -and $OperationId -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid operation ID.' }
if ($OperationId) {
    if (-not (Test-Path -LiteralPath $ReceiptPath)) { throw 'Resuming requires the original publish receipt; retain it with the uploaded file.' }
    $prior=Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json
    if ($prior.operationId -cne $OperationId -or $prior.universeId -cne $UniverseId -or $prior.placeId -cne $PlaceId -or $prior.sha256 -cne $hash) {
        throw 'Resume target, operation or file hash differs from the original receipt.'
    }
}
Write-Host "Target universe $UniverseId / place $PlaceId; $($file.Length) bytes; SHA256 $hash"
if ($DryRun) { Write-Host "Dry run: validated local file/IDs. Would verify destination, PATCH multipart $mime, then poll operation. No network request made."; return }
if (-not $env:ROBLOX_API_KEY) { throw 'Set ROBLOX_API_KEY in the process environment or GitHub environment secret.' }
Add-Type -AssemblyName System.Net.Http
$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(120)
$client.DefaultRequestHeaders.Add('x-api-key',$env:ROBLOX_API_KEY)
function Read-Api([string]$Url) {
    for ($attempt=1; $attempt -le 4; $attempt++) {
        try { $response=$client.GetAsync($Url).GetAwaiter().GetResult() }
        catch { if ($attempt -eq 4) { throw 'Roblox read failed after four attempts; network/timeout.' }; Start-Sleep -Seconds (2*$attempt); continue }
        try {
            $status=[int]$response.StatusCode
            if (($status -eq 429 -or $status -ge 500) -and $attempt -lt 4) { Start-Sleep -Seconds (2*$attempt); continue }
            if (-not $response.IsSuccessStatusCode) { throw "Roblox read failed with HTTP $status. Check destination, scopes and account access." }
            return ($response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json)
        } finally { $response.Dispose() }
    }
}
try {
    $place=Read-Api "https://apis.roblox.com/cloud/v2/universes/$UniverseId/places/$PlaceId"
    if ($place.path -ne "universes/$UniverseId/places/$PlaceId") { throw 'Destination verification returned a different place.' }
    if (-not $OperationId) {
        $form=[System.Net.Http.MultipartFormDataContent]::new()
        $request=$null
        try {
            $metadata=@{assetId=[long]$PlaceId;assetType='Place';published=$true} | ConvertTo-Json -Compress
            $form.Add([System.Net.Http.StringContent]::new($metadata),'request')
            $binary=[System.Net.Http.ByteArrayContent]::new([IO.File]::ReadAllBytes($file.FullName))
            $binary.Headers.ContentType=[System.Net.Http.Headers.MediaTypeHeaderValue]::new($mime)
            $form.Add($binary,'fileContent',$file.Name)
            $request=[System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new('PATCH'),"https://apis.roblox.com/assets/v1/assets/$PlaceId")
            $request.Content=$form
            try { $response=$client.SendAsync($request).GetAwaiter().GetResult() }
            catch { throw 'Upload acknowledgement unknown. Check Creator Dashboard before retrying; the write is deliberately not replayed automatically.' }
            try {
                if (-not $response.IsSuccessStatusCode) { throw "Upload returned HTTP $([int]$response.StatusCode). Check API permissions/account limits; verify version history before retrying." }
                $accepted=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
                if ($accepted.path -notmatch '^operations/([A-Za-z0-9_-]+)$') { throw 'Upload accepted but operation identifier missing. Check Creator Dashboard before retrying.' }
                $OperationId=$Matches[1]
            } finally { $response.Dispose() }
        } finally { if ($request) { $request.Dispose() } else { $form.Dispose() } }
    }
    $receipt=@{universeId=$UniverseId;placeId=$PlaceId;sha256=$hash;operationId=$OperationId;status='pending'}
    $receipt | ConvertTo-Json | Set-Content -LiteralPath $ReceiptPath
    Write-Host "Publish operation $OperationId; receipt saved."
    for ($poll=0; $poll -lt 60; $poll++) {
        $operation=Read-Api "https://apis.roblox.com/assets/v1/operations/$OperationId"
        if ($operation.done) {
            if ($operation.error) { throw "Publish operation failed (code $($operation.error.code)). Inspect operation in Roblox; no successful release recorded." }
            if ($operation.response.isPublished -ne $true -or $operation.response.path -ne "assets/$PlaceId" -or -not $operation.response.revisionId) { throw 'Operation completed without confirmed published target/version.' }
            $receipt.status='published'; $receipt.revisionId=$operation.response.revisionId
            $receipt | ConvertTo-Json | Set-Content -LiteralPath $ReceiptPath
            Write-Host "Published place $PlaceId revision $($receipt.revisionId). Public audience access is configured separately."
            return
        }
        Start-Sleep -Seconds 5
    }
    throw "Operation is still pending. Resume with -OperationId $OperationId; do not upload again."
} finally { $client.Dispose(); $handler.Dispose() }
