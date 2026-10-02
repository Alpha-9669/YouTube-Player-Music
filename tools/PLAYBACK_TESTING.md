# Playback regression checks (0.7.2)

## Reproduction and fix

The 2026-09-07 RPT contains videos `f50r2QKdkus` and `S3izA5BA-gE`.
With 0.7.1, both resolved successfully but MFPlay emitted Play and Ended at
position zero. Downloading the direct fragmented M4A files did not fix playback.
The same audio delivered as packed AAC from the audio-only HLS rendition played
and supported seeking in the isolated MFPlay probe.

0.7.2 prepares that HLS rendition into an atomic local AAC cache file before
starting MFPlay. It does not ship or invoke yt-dlp, FFmpeg, or another player.
Unsupported/encrypted/live HLS playlists fail explicitly. Resolver attempts still
fall back across YouTube client profiles.

The cache is under `%LOCALAPPDATA%\Arma 3\A3YT\audio-cache`, capped at 256 MiB
and 16 files. Cleanup runs during preparation; entries expire after 24 hours.
Under capacity pressure, idle files can be evicted after a short handoff grace.
Native read leases protect active playback. Temporary or incomplete downloads
are never returned to the player.

## Repeatable checks

From the repository root on Windows with .NET 8 and MSVC installed:

1. Run `dotnet run --project tools/HlsCache.Tests/HlsCache.Tests.csproj`.
   This tests manifest parsing, audio validation, rejected formats and cache
   pressure rules without accessing the network or the user's cache.
   Optional command-line file arguments validate real packed-AAC fixtures too.
2. Run `.\build.ps1` to build the extension and signed addon.
3. Compile `tools/smoke_native.cpp` from an x64 MSVC developer terminal:
   `cl /nologo /EHsc /std:c++17 /O2 /MT tools\smoke_native.cpp /Fo:build\smoke_native.obj /Fe:tools\smoke_native.exe /link kernel32.lib`.
4. Run `.\tools\test_playback_regression.ps1`.
   This loads the actual exported extension ABI, runs muted, and checks both
   reproduction URLs, next-track prefetch, advancing time, pause/resume, seeking
   and end-of-track status. An assertion failure makes the script fail.
   Pass `-ExtensionDirectory` to test an installed mod instead of `tools`.
5. For an unseeked completion check, run:

   ```powershell
   .\tools\smoke_native.exe .\tools 'debug|1' `
       'play|https://www.youtube.com/watch?v=S3izA5BA-gE|0' `
       'sleep:10000' 'timeline' 'sleep:150000' 'status' 'stop'
   ```

   Expect a playing timeline followed by `ok|status|ended`. On the reproduction
   machine, the natural Play-to-Ended interval was about 146 seconds. MFPlay's
   AAC duration estimate was about 144 seconds; queue completion must use the
   actual Ended event, not that estimate.

The native debug log is `%LOCALAPPDATA%\Arma 3\A3YT_extension.log`.
The standalone checks do not exercise Arma's multiplayer/Zeus UI. After copying
the DLL and addon into an installed mod, restart Arma and check the two-item
queue in-game. Keep the old installed files backed up for rollback.

## Custom audio output and volume regression (2026-09-21)

MFPlay's SetVolume can report success while leaving a custom renderer at unity
gain. The extension now controls IMFAudioStreamVolume on its own renderer,
including initial gain before Play. It does not set endpoint or session volume.

From an x64 MSVC developer terminal, compile and run against a local audio-only
AAC fixture (no resolver/network dependency):

```powershell
cl /nologo /EHsc /std:c++17 /W4 /WX /O2 /MT tools\audio_output_tests.cpp /Fo:build\audio_output_tests.obj /Fe:build\audio_output_tests.exe /link mfplat.lib mfplay.lib mf.lib mfuuid.lib ole32.lib shlwapi.lib propsys.lib
.\build\audio_output_tests.exe .\build\probe-f50r2QKdkus.aac
```

This test reads actual renderer channel gains, not MFPlay's cached GetVolume.
It covers initial mute, 0/25/100%, bounds, paused changes, seek/recovery, a new
track's initial volume, and unchanged host-session/endpoint volume and mute.
The synthetic host session belongs to the test process; no Arma session is
modified. With two active output devices it also exercises non-default routing;
with one device that portion is explicitly skipped. Some checks briefly play
audible music; run with an appropriate system output level.

In-game acceptance checks (not covered by the standalone executable):

1. Start music and vary Zeus playlist volume through 0/25/100.
2. In Esc -> local music settings, disable override, set Zeus to 70 and local
   to 50, then Apply. Effective music volume should be 35.
3. Enable local override and Apply: local 50 should give 50, independently of
   Zeus. Local 0 must mute music in either mode.
4. Repeat while paused, then resume; advance to the next track and seek.
5. Confirm game effects/voices and Windows endpoint/session volume are unchanged.
6. With separate default and Arma output devices, confirm music follows Arma.
