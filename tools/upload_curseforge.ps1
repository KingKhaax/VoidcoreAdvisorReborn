<#
Uploads the addon zip to CurseForge with the upload API.

  The token is read from the CURSEFORGE_API_TOKEN environment variable and is never written
  anywhere. By default this only shows what WOULD be uploaded (a dry run); add -Upload to
  really publish the file. A published file is public and goes through CurseForge's review.

  powershell -File tools/upload_curseforge.ps1                 # dry run
  powershell -File tools/upload_curseforge.ps1 -Upload         # publish
  powershell -File tools/upload_curseforge.ps1 -Upload -ReleaseType beta

  The changelog is the latest section of CHANGELOG.md (everything above the first "---").
#>
param(
    [switch]$Upload,
    [ValidateSet("alpha", "beta", "release")][string]$ReleaseType = "release",
    [string]$Zip = "$env:USERPROFILE\Desktop\VoidcoreAdvisor Reborn.zip",
    [string]$ProjectId = "1757601"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$token = $env:CURSEFORGE_API_TOKEN
if (-not $token) { $token = [Environment]::GetEnvironmentVariable("CURSEFORGE_API_TOKEN", "User") } # set after this terminal was opened
if (-not $token) { throw "CURSEFORGE_API_TOKEN is not set." }
$headers = @{ "X-Api-Token" = $token }
$base = "https://wow.curseforge.com/api"

# Version from the .toc
$toc = Get-Content (Join-Path $root "VoidcoreAdvisorReborn.toc")
$version = ($toc | Where-Object { $_ -match '^## Version:' }) -replace '^## Version:\s*', ''
$interfaces = (($toc | Where-Object { $_ -match '^## Interface:' }) -replace '^## Interface:\s*', '') -split ',\s*'

# Game versions: 120107 -> "12.1.7"
$wanted = $interfaces | ForEach-Object {
    $n = [int]$_
    "{0}.{1}.{2}" -f [math]::Floor($n / 10000), [math]::Floor(($n % 10000) / 100), ($n % 100)
}
$all = Invoke-RestMethod -Uri "$base/game/versions" -Headers $headers
$ids = @(); foreach ($name in $wanted) {
    $hit = $all | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if ($hit) { $ids += [int]$hit.id } else { Write-Warning "Game version $name was not found on CurseForge; skipped." }
}
if ($ids.Count -eq 0) { throw "No matching game versions." }

# Changelog: the first section of CHANGELOG.md
$text = (Get-Content (Join-Path $root "CHANGELOG.md") -Raw -Encoding UTF8) -replace "`r`n", "`n"
$changelog = ($text -split "\n---\n")[0].Trim()

if (-not (Test-Path $Zip)) { throw "Zip not found: $Zip" }
$zipInfo = Get-Item $Zip

$metadata = @{
    changelog     = $changelog
    changelogType = "markdown"
    displayName   = "VoidcoreAdvisor Reborn $version"
    gameVersions  = $ids
    releaseType   = $ReleaseType
} | ConvertTo-Json -Depth 5

Write-Host "Project:       $ProjectId"
Write-Host "Version:       $version ($ReleaseType)"
Write-Host "Game versions: $($wanted -join ', ')  ->  $($ids -join ', ')"
Write-Host "File:          $($zipInfo.FullName) ($([math]::Round($zipInfo.Length / 1KB)) KB)"
Write-Host "Changelog:     $($changelog.Length) characters"
if (-not $Upload) {
    Write-Host "`nDry run: nothing was uploaded. Add -Upload to publish."
    return
}

# Multipart upload with curl.exe (ships with Windows 10/11)
$metaFile = New-TemporaryFile
try {
    [IO.File]::WriteAllText($metaFile.FullName, $metadata, (New-Object Text.UTF8Encoding($false)))
    $response = & curl.exe -sS -X POST "$base/projects/$ProjectId/upload-file" `
        -H "X-Api-Token: $token" `
        -F "metadata=<$($metaFile.FullName);type=application/json" `
        -F "file=@$($zipInfo.FullName)"
    Write-Host "Response: $response"
} finally {
    Remove-Item $metaFile.FullName -Force -ErrorAction SilentlyContinue
}
