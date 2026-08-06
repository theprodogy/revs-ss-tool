# Launcher
# UI

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$local = if ($PSScriptRoot) { Join-Path $PSScriptRoot "REVS-SS-TOOL.ps1" } else { $null }
$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$dst = Join-Path $env:TEMP ("REVS-SS-TOOL-{0}.ps1" -f $stamp)
$wrapperLog = Join-Path $env:TEMP "REVS-SS-TOOL-wrapper.log"
$startupLog = Join-Path $env:TEMP "REVS-SS-TOOL-startup.log"

if ($PSScriptRoot -and (Test-Path -LiteralPath $local)) {
    Write-Host "Launching local REVS SS TOOL..." -ForegroundColor Yellow
    $dst = $local
} else {
    $raw = "https://github.com/theprodogy/revs-ss-tool/raw/refs/heads/main/REVS-SS-TOOL.ps1?cb=$stamp"
    Write-Host "Downloading REVS SS TOOL..." -ForegroundColor Yellow
    Remove-Item -LiteralPath $wrapperLog -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $startupLog -Force -ErrorAction SilentlyContinue
    Invoke-RestMethod -Uri $raw -OutFile $dst
    $downloaded = Get-Content -LiteralPath $dst -Raw
    if ($downloaded -notmatch 'REVS SS TOOL') {
        throw "Downloaded script is stale or incomplete. Try again in a new PowerShell window."
    }
}

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$quotedDst = '"' + $dst + '"'
$args = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',$quotedDst)
if ($isAdmin) { Start-Process powershell.exe -ArgumentList $args }
else          { Start-Process powershell.exe -Verb RunAs -ArgumentList $args }
