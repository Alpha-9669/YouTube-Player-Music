# Playback regression checks (0.7.3)

## Vehicle radio metadata and power regression (2026-10-12)

Radio Add now uses `radioload`, `radioloadstatus`, `radioloaditem` and
`radioloadrelease`. The resolver runs in a native worker; SQF `spawn` alone
does not make synchronous `callExtension` network requests nonblocking.
Each request owns its result, independent of the Zeus playlist cache.
There are at most four outstanding imports. Closing the dialog or pressing
Stop discards the pending import; a 90-second UI timeout restores the Add button.

After `build.ps1`, run `python tools/test_radio_async.py` against the built DLL.
It checks concurrent video titles and a 32-track playlist, request isolation,
cancellation, invalid tokens, and a 250 ms upper limit for every radio API call.
Run `python tools/test_radio_native.py` for two independent audio channels.
Run `python tools/test_radio_state.py` (requires sqflint in `build/test-deps`)
to execute the actual SQF clock/advance functions and test power pause/resume,
engine bypass, queue retention, repeat and completed/idle states.

Both mod folders must be updated: the radio PBO requires the main mod's new
0.7.3 extension API. Restart Arma after updating.
In a hosted multiplayer mission, verify these remaining integration checks:

- With and without ACE3, open the radio through the CBA keybind.
- With ACE3, open through self-interaction while inside land, air and sea vehicles;
  disable/re-enable the action in the personal CBA settings.
- With Require running engine enabled (default), switch off the engine:
  music pauses, the queue stays, and the timestamp resumes when restarted.
- Disable Require running engine in the server CBA settings and play while off.
- Test two clients, a late joiner, repeated Next on the last track, and repeat
  enabled/disabled (default disabled). With repeat off, completion keeps the list.
- Add while Stop is pressed or the dialog is closed: the pending import must
  not repopulate the queue.

The standalone tests do not verify ACE integration or hosted multiplayer in Arma.

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


## Vehicle radio HTML interface (2026-10-12)

The production interface is `src/addon/a3yt_radio/radio.html`, packaged inside
`mod/@YouTube Player Vehicle Radio/addons/a3yt_radio.pbo`. Arma 3 2.20+ is
required. Open it through the existing CBA keybind or enabled ACE self action;
`preview_radio_faceplate.sqf` remains a separate mockup and is not the addon UI.

Automated checks completed for this integration:

- Production HTML commands exercised through a mock A3API in the browser:
  play selected, move, volume, mute, loop, and Base64 URL transfer.
- `tools/test_radio_state.py` executes the production SQF engine pause/resume,
  duration advance, queue retention and loop functions.
- `tools/test_radio_reorder.py` executes the production move branch in all 64
  source/target/playing-index combinations. Adapters provide primitives missing
  from the older SQF interpreter; the move algorithm is read from the source.
- SQF parsing, JavaScript syntax, CfgConvert compilation, PBO prefix and exact
  HTML/SQF file contents, plus DSCheckSignatures on the installed signed PBO.

After restarting Arma with the rebuilt addon, verify in-game:

1. Open/close via CBA; repeat through ACE if installed. Close with power or Esc.
2. Expand/collapse the queue repeatedly. Only the track list should scroll;
   the radio must not clip or acquire a page scrollbar/background.
3. Add a video and playlist. Confirm resolved titles appear and the host remains
   responsive during metadata loading. Failure should appear in the UI.
4. Play by double-click or PLAY; check PREV/NEXT, UP/DOWN, drag reorder and DEL.
   Reordering must preserve the currently playing track for every listener.
5. Turn the knob, use +/- and MUTE, then unmute to restore the previous volume.
6. Toggle LOOP. Repeat is controlled only on this vehicle; another vehicle
   retains its own LOOP value (off by default). Verify natural completion and NEXT at the end.
7. Confirm engine settings still pause/resume without erasing the queue.
8. With a second client, verify shared playback, volume and loop state updates,
   and that leaving/destroying the vehicle closes its interface.

These in-game checks require the actual Arma runtime and are not implied by the
browser/standalone checks above.


URL input follow-up: the URL rectangle is rendered by an Arma RscEdit overlay,
positioned from normalized HTML bounds after queue expansion. Input is handled
by Arma, including clipboard paste and Enter. The HTML Add button and native
Enter key both use the existing asynchronous metadata loader. Verify typing,
Ctrl+V, Enter/Add, repeated collapse/expand, and disabled input while loading.
The browser fixture checked input/inputHide/Add bridge messages and coordinate
bounds; actual Arma keyboard input still requires an in-game acceptance check.


PAUSE/Add follow-up: PREV/PLAY/PAUSE/NEXT/STOP now form the top row;
MUTE/LOOP/UP/DOWN/DEL form the lower row. Manual pause is stored per vehicle,
combined with the engine requirement by the shared server clock transition.
PLAY on the paused current track resumes its existing offset. Engine-off still
prevents playback when required; resuming manually does not bypass this setting.
The HTML queue Add button now calls its handler directly, with no form submission
and no native button overlay. A sandboxed iframe with only allow-scripts verified
its add and pause bridge messages. Native input and Enter remain supported, with
blur and periodic draft synchronization. In-game confirmation is still required.


Seek/settings follow-up: repeat and ACE interaction no longer have CBA settings.
LOOP is per vehicle, off by default; ACE self interaction is always registered
when ACE is installed. The progress handle supports pointer drag and arrow keys.
Seek is committed after release, validated against track generation and bounded
by known duration on the server. All listeners restart at the shared clock
position; seeking while paused preserves pause. Verify this with two clients,
including an engine-off vehicle, stale track changes during dragging, unknown
video duration, and start/end boundaries. Pure SQF tests cover running and paused
seek, duration bounds, unknown-duration guard and generation changes.
