$ErrorActionPreference = 'Stop'
$functions = Join-Path $PSScriptRoot '../src/addon/a3yt_player/functions'
function Assert-Source([string]$File, [string]$Text, [string]$Label) {
    $source = Get-Content -LiteralPath (Join-Path $functions $File) -Raw
    if (!$source.Contains($Text)) { throw "FAIL: $Label" }
    Write-Output "PASS: $Label"
}
# Static wiring checks, not an SQF interpreter or GUI simulation.
Assert-Source 'fn_moduleYoutube.sqf' '["volume", _clampedVolume, _currentGeneration] remoteExec ["A3YT_fnc_handleLocalPlayback", 0, false]' 'Zeus broadcasts volume to client playback'
Assert-Source 'fn_handleLocalPlayback.sqf' 'private _effectiveVolume = [_clampedVolume] call A3YT_fnc_getEffectiveVolume;' 'Zeus applies local volume rules'
Assert-Source 'fn_handleLocalPlayback.sqf' '["volume", [str _effectiveVolume]] call A3YT_fnc_callExtension' 'Zeus sends effective volume to DLL'
Assert-Source 'fn_uiLocalVolumeSettings.sqf' '[] call A3YT_fnc_applyLocalVolumeSettings;' 'Esc Apply updates playing music'
Assert-Source 'fn_applyLocalVolumeSettings.sqf' 'private _effectiveVolume = [_sourceVolume] call A3YT_fnc_getEffectiveVolume;' 'Esc uses shared volume rules'
Assert-Source 'fn_applyLocalVolumeSettings.sqf' '["volume", [str _effectiveVolume]] call A3YT_fnc_callExtension' 'Esc sends effective volume to DLL'
Assert-Source 'fn_getEffectiveVolume.sqf' 'round ((_zeusVolume * _localVolume) / 100)' 'Normal mode multiplies Zeus and local levels'
Assert-Source 'fn_getEffectiveVolume.sqf' 'if (missionNamespace getVariable ["A3YT_localVolumeOverride", false]) exitWith {' 'Local override bypasses Zeus level'
Assert-Source 'fn_getEffectiveVolume.sqf' 'round _localVolume' 'Override returns local level'
Assert-Source 'fn_handleLocalPlayback.sqf' 'private _volume = [_sourceVolume] call A3YT_fnc_getEffectiveVolume;' 'Next track recalculates effective volume'
Write-Output 'PASS: 10 SQF source-contract checks (no Arma runtime required).'
