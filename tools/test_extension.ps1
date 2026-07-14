[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Url,
    [int]$Volume = 70,
    [Nullable[int]]$LiveVolume = $null,
    [int]$PlaySeconds = 10,
    [Nullable[int]]$SeekMs = $null,
    [int]$SeekDelaySeconds = 2,
    [switch]$EnableDebug,
    [int]$TailLogLines = 40,
    [ValidateSet("x86", "x64")]
    [string]$Architecture = "x64"
)

$ErrorActionPreference = "Stop"

$runner = if ($Architecture -eq "x86") {
    Join-Path $PSScriptRoot "callExtension.exe"
} else {
    Join-Path $PSScriptRoot "callExtension_x64.exe"
}

$extensionDll = if ($Architecture -eq "x86") {
    "youtube_player_music.dll"
} else {
    "youtube_player_music_x64.dll"
}

if (!(Test-Path $runner)) {
    throw "Runner was not found: $runner"
}

if (!(Test-Path (Join-Path $PSScriptRoot $extensionDll))) {
    throw "$extensionDll was not found in tools\\. Run .\\build.ps1 first."
}

$extensionLog = Join-Path $env:LOCALAPPDATA "Arma 3\\A3YT_extension.log"
$existingLogLineCount = if ($EnableDebug -and (Test-Path $extensionLog)) {
    @(Get-Content -LiteralPath $extensionLog).Count
} else {
    0
}

$existingRunnerIds = @(
    Get-Process callExtension,callExtension_x64 -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Id
)

$escapedUrl = $Url.Replace('"', '""')
$scriptName = "a3yt_test_" + [guid]::NewGuid().ToString("N") + ".sqf"
$scriptPath = Join-Path $PSScriptRoot $scriptName

$lines = @(
    '#define freeExtension comment',
    '',
    '"youtube_player_music" callExtension "status";',
    'sleep 1;'
)

if ($EnableDebug) {
    $lines += '"youtube_player_music" callExtension "debug|1";'
    $lines += 'sleep 1;'
}

$lines += '"youtube_player_music" callExtension "play|' + $escapedUrl + '|' + $Volume + '";'
$lines += 'sleep ' + $PlaySeconds + ';'
$lines += '"youtube_player_music" callExtension "status";'
$lines += '"youtube_player_music" callExtension "timeline";'

if ($LiveVolume -ne $null) {
    $lines += '"youtube_player_music" callExtension "volume|' + [string]$LiveVolume + '";'
    $lines += 'sleep 2;'
    $lines += '"youtube_player_music" callExtension "status";'
    $lines += '"youtube_player_music" callExtension "timeline";'
}

if ($SeekMs -ne $null) {
    $lines += '"youtube_player_music" callExtension "seek|' + [string]$SeekMs + '";'
    $lines += 'sleep ' + $SeekDelaySeconds + ';'
    $lines += '"youtube_player_music" callExtension "status";'
    $lines += '"youtube_player_music" callExtension "timeline";'
}

$lines += @(
    'sleep 1;',
    '"youtube_player_music" callExtension "stop";',
    'sleep 1;',
    '"youtube_player_music" callExtension "status";',
    'exit;'
)

$lines | Set-Content -Path $scriptPath -Encoding ASCII

Push-Location $PSScriptRoot
try {
    Start-Process -FilePath $runner -ArgumentList $scriptName -WorkingDirectory $PSScriptRoot -Wait
} finally {
    Get-Process callExtension,callExtension_x64 -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -notin $existingRunnerIds } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Pop-Location
    Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
}

if ($EnableDebug) {
    if (Test-Path $extensionLog) {
        Write-Host "--- A3YT_extension.log new lines ---"
        Get-Content -LiteralPath $extensionLog |
            Select-Object -Skip $existingLogLineCount |
            Select-Object -Last $TailLogLines
    } else {
        Write-Warning "Extension log was not created: $extensionLog"
    }
}
