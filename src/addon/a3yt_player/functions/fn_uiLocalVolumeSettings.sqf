params [["_mode", "onLoad"], ["_display", displayNull]];

if (_mode isEqualType []) then {
    _display = _mode param [0, displayNull];
    _mode = "onLoad";
};

if (isNull _display) exitWith {
    false
};

private _volumeCtrl = _display displayCtrl 2611931;
private _overrideCtrl = _display displayCtrl 2611932;
private _effectiveCtrl = _display displayCtrl 2611933;

private _fnc_readVolume = {
    private _volumeText = trim ctrlText _volumeCtrl;
    private _volume = parseNumber _volumeText;
    if (_volumeText isEqualTo "" || {(_volume isEqualTo 0) && !(_volumeText isEqualTo "0")}) then {
        _volume = missionNamespace getVariable ["A3YT_localVolume", 100];
    };

    round ((_volume max 0) min 100)
};

private _fnc_updatePreview = {
    private _localVolume = call _fnc_readVolume;
    private _sourceVolume = missionNamespace getVariable ["A3YT_localQueueVolume", 70];
    private _effectiveVolume = if (cbChecked _overrideCtrl) then {
        _localVolume
    } else {
        round (((_sourceVolume max 0) min 100) * _localVolume / 100)
    };

    _effectiveCtrl ctrlSetText str _effectiveVolume;
};

switch (toLower _mode) do {
    case "onload": {
        _volumeCtrl ctrlSetText str (missionNamespace getVariable ["A3YT_localVolume", 100]);
        _overrideCtrl cbSetChecked (missionNamespace getVariable ["A3YT_localVolumeOverride", false]);

        _volumeCtrl ctrlAddEventHandler ["KeyUp", {
            ["preview", ctrlParent (_this select 0)] call A3YT_fnc_uiLocalVolumeSettings;
        }];

        _overrideCtrl ctrlAddEventHandler ["CheckedChanged", {
            ["preview", ctrlParent (_this select 0)] call A3YT_fnc_uiLocalVolumeSettings;
        }];

        call _fnc_updatePreview;
    };

    case "preview": {
        call _fnc_updatePreview;
    };

    case "apply": {
        private _localVolume = call _fnc_readVolume;
        private _override = cbChecked _overrideCtrl;

        missionNamespace setVariable ["A3YT_localVolume", _localVolume];
        missionNamespace setVariable ["A3YT_localVolumeOverride", _override];
        profileNamespace setVariable ["A3YT_localVolume", _localVolume];
        profileNamespace setVariable ["A3YT_localVolumeOverride", _override];
        saveProfileNamespace;

        _volumeCtrl ctrlSetText str _localVolume;
        call _fnc_updatePreview;
        [] call A3YT_fnc_applyLocalVolumeSettings;

        systemChat localize "STR_A3YT_CHAT_LOCAL_VOLUME_APPLIED";
    };
};

true
