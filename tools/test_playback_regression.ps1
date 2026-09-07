[CmdletBinding()]
param(
    [string]$ExtensionDirectory = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'smoke_native.exe'
if (!(Test-Path -LiteralPath $runner)) { throw 'Build tools/smoke_native.cpp first.' }

# Public reproduction videos from the 2026-09-07 RPT. Run muted. Test the
# actual exported ABI, with both prefetch and playback in the same process.
$first = 'https://www.youtube.com/watch?v=f50r2QKdkus&list=RD00xxe5Dk4Zw&index=2'
$second = 'https://www.youtube.com/watch?v=S3izA5BA-gE&list=RD00xxe5Dk4Zw&index=3'
$commands = @(
    'debug|1', "prefetch|$first", 'sleep:1000', "play|$first|0",
    "prefetch|$second", 'sleep:18000', 'timeline', 'sleep:1200', 'timeline',
    'pause', 'sleep:500', 'timeline', 'sleep:1200', 'timeline',
    'resume', 'sleep:1500', 'timeline', 'seek|120000', 'sleep:3000', 'timeline',
    'seek|230000', 'sleep:4000', 'status',
    "play|$second|0", 'sleep:3000', 'timeline', 'sleep:1200', 'timeline',
    'seek|143000', 'sleep:4000', 'status', 'stop'
)
$output = & $runner $ExtensionDirectory @commands
if ($LASTEXITCODE -ne 0) { throw "Runner exited with $LASTEXITCODE" }
$output | Write-Output
$snapshots = @($output | ForEach-Object {
    if ($_ -match '^timeline => ok\|timeline\|([^|]+)\|(\d+)\|(\d+)') {
        [pscustomobject]@{ State = $Matches[1]; Position = [long]$Matches[2]; Duration = [long]$Matches[3] }
    }
})
if ($snapshots.Count -ne 8) { throw "Expected 8 timeline snapshots; got $($snapshots.Count)." }
foreach ($pair in @(@(0,1), @(6,7))) {
    $a = $snapshots[$pair[0]]; $b = $snapshots[$pair[1]]
    if ($a.State -ne 'playing' -or $b.State -ne 'playing' -or $b.Position - $a.Position -lt 700) {
        throw 'A reproduction track did not maintain advancing playback.'
    }
}
if ($snapshots[2].State -ne 'paused' -or $snapshots[3].State -ne 'paused' -or
    [Math]::Abs($snapshots[3].Position - $snapshots[2].Position) -gt 100) {
    throw 'Pause did not hold the timeline still.'
}
if ($snapshots[4].State -ne 'playing' -or $snapshots[4].Position -le $snapshots[3].Position) {
    throw 'Resume did not advance playback.'
}
if ($snapshots[5].State -ne 'playing' -or $snapshots[5].Position -lt 119000) {
    throw 'Seek to 120 seconds failed.'
}
if (@($output | Where-Object { $_ -eq 'status => ok|status|ended' }).Count -ne 2) {
    throw 'A track failed to report normal completion after a near-end seek.'
}
Write-Output 'PASS: both RPT tracks, next-track prefetch, advancing playback, pause/resume, seek and completion.'
