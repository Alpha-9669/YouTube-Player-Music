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

$headers = @{
    "User-Agent" = "A3YTPlayer-BuildScript"
    "Accept" = "application/vnd.github+json"
}

$ytDlpTarget = Join-Path $Destination "yt-dlp.exe"
Invoke-WebRequest -Uri "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -OutFile $ytDlpTarget

$zipPath = $null
$extractDir = $null

try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest" -Headers $headers
    $asset = $release.assets |
        Where-Object { $_.name -like "*win64-gpl*.zip" } |
        Sort-Object name |
        Select-Object -First 1

    if (-not $asset) {
        throw "Could not find a matching FFmpeg Windows asset in the latest BtbN release."
    }

    $zipPath = Join-Path $env:TEMP $asset.name
    $extractDir = Join-Path $env:TEMP ("a3yt_ffmpeg_" + [guid]::NewGuid().ToString("N"))

    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -Headers $headers
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    $ffplay = Get-ChildItem -Path $extractDir -Recurse -Filter "ffplay.exe" | Select-Object -First 1
    if (-not $ffplay) {
        throw "ffplay.exe not found inside downloaded FFmpeg archive."
    }

    Copy-Item $ffplay.FullName (Join-Path $Destination "ffplay.exe") -Force
} finally {
    if ($zipPath -and (Test-Path -LiteralPath $zipPath)) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    }

    if ($extractDir -and (Test-Path -LiteralPath $extractDir)) {
        Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Downloaded yt-dlp.exe and ffplay.exe to $Destination"
