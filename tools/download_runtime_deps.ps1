[CmdletBinding()]
param(
    [string]$Destination = (Join-Path $PSScriptRoot "..\\build\\runtime")
)

$ErrorActionPreference = "Stop"

function Ensure-Directory {
    param([string]$Path)

    if (!(Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

Ensure-Directory $Destination
$Destination = (Resolve-Path -LiteralPath $Destination).Path

$headers = @{
    "User-Agent" = "A3YTPlayer-BuildScript"
    "Accept" = "application/vnd.github+json"
}

$downloadRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("a3yt_runtime_" + [guid]::NewGuid().ToString("N"))
$ytDlpTemp = Join-Path $downloadRoot "yt-dlp.exe"
$zipPath = Join-Path $downloadRoot "ffmpeg.zip"
$extractDir = Join-Path $downloadRoot "ffmpeg"

try {
    Ensure-Directory $downloadRoot
    Invoke-WebRequest -Uri "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -OutFile $ytDlpTemp -Headers $headers
    if ((Get-Item -LiteralPath $ytDlpTemp).Length -le 0) {
        throw "Downloaded yt-dlp.exe is empty."
    }

    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest" -Headers $headers
    $asset = $release.assets |
        Where-Object { $_.name -like "*win64-gpl*.zip" } |
        Sort-Object name |
        Select-Object -First 1

    if (-not $asset) {
        throw "Could not find a matching FFmpeg Windows asset in the latest BtbN release."
    }

    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -Headers $headers
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    $ffplay = Get-ChildItem -Path $extractDir -Recurse -Filter "ffplay.exe" | Select-Object -First 1
    if (-not $ffplay) {
        throw "ffplay.exe not found inside downloaded FFmpeg archive."
    }

    if ($ffplay.Length -le 0) {
        throw "Downloaded ffplay.exe is empty."
    }

    Move-Item -LiteralPath $ytDlpTemp -Destination (Join-Path $Destination "yt-dlp.exe") -Force
    Copy-Item -LiteralPath $ffplay.FullName -Destination (Join-Path $Destination "ffplay.exe") -Force
} finally {
    if (Test-Path -LiteralPath $downloadRoot) {
        Remove-Item -LiteralPath $downloadRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Downloaded yt-dlp.exe and ffplay.exe to $Destination"
