if (!hasInterface) exitWith {
    ""
};

private _sourceVolume = missionNamespace getVariable ["A3YT_localQueueVolume", -1];
if !(_sourceVolume isEqualType 0) then {
    _sourceVolume = -1;
};
if (_sourceVolume < 0) exitWith {
    ""
};

private _effectiveVolume = [_sourceVolume] call A3YT_fnc_getEffectiveVolume;
missionNamespace setVariable ["A3YT_localQueueEffectiveVolume", _effectiveVolume];

if ((missionNamespace getVariable ["A3YT_localQueueWorkerRunning", false]) || {(count (missionNamespace getVariable ["A3YT_localQueue", []])) > 0}) then {
    private _volumeResult = ["volume", [str _effectiveVolume]] call A3YT_fnc_callExtension;
    diag_log format [
        "[A3YT] local_volume_settings_applied sourceVolume=%1 effectiveVolume=%2 result=%3",
        _sourceVolume,
        _effectiveVolume,
        _volumeResult
    ];
};

"ok|local_volume_settings_applied"
