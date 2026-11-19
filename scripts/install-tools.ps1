param([string]$Destination = (Join-Path $PSScriptRoot '../.tools'))
$ErrorActionPreference = 'Stop'
$headers = @{ 'User-Agent'='Aether-Isles-build'; 'Accept'='application/vnd.github+json' }
if ($env:GITHUB_TOKEN) { $headers.Authorization = "Bearer $env:GITHUB_TOKEN" }
New-Item -ItemType Directory -Force $Destination | Out-Null
foreach ($tool in @(@{name='lune';repo='lune-org/lune';version='0.11.1'},@{name='rojo';repo='rojo-rbx/rojo';version='7.7.1'})) {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$($tool.repo)/releases/tags/v$($tool.version)" -Headers $headers
    $assets = @($release.assets | Where-Object { $_.name -match 'windows' -and $_.name -match '(x86_64|x64)' -and $_.name -match '\.zip$' })
    if ($assets.Count -ne 1) { throw "Expected one Windows x64 archive for $($tool.name)." }
    $asset = $assets[0]
    if ($asset.digest -notmatch '^sha256:([a-f0-9]{64})$') { throw 'Release asset lacks a SHA256 digest; verify upstream before changing this installer.' }
    $expected = $Matches[1]
    $archive = Join-Path $Destination "$($tool.name).zip"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archive
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'Downloaded tool checksum mismatch.' }
    $unpacked = Join-Path $Destination $tool.name
    Expand-Archive -LiteralPath $archive -DestinationPath $unpacked -Force
    $binary = @(Get-ChildItem -LiteralPath $unpacked -Filter "$($tool.name).exe" -Recurse)
    if ($binary.Count -ne 1) { throw 'Expected one tool executable.' }
    Copy-Item -LiteralPath $binary[0].FullName -Destination (Join-Path $Destination "$($tool.name).exe") -Force
    & (Join-Path $Destination "$($tool.name).exe") --version
    if ($LASTEXITCODE -ne 0) { throw 'Installed tool failed to run.' }
}
