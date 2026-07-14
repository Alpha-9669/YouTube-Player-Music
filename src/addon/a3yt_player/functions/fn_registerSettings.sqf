private _storedVolume = profileNamespace getVariable ["A3YT_localVolume", 100];
private _storedOverride = profileNamespace getVariable ["A3YT_localVolumeOverride", false];

if !(_storedVolume isEqualType 0) then {
    _storedVolume = 100;
};
if !(_storedOverride isEqualType true) then {
    _storedOverride = false;
};

missionNamespace setVariable ["A3YT_localVolume", (round ((_storedVolume max 0) min 100))];
missionNamespace setVariable ["A3YT_localVolumeOverride", _storedOverride isEqualTo true];

if (isNil "CBA_fnc_addPauseMenuOption") exitWith {
    diag_log "[A3YT] CBA pause menu is not available";
};

[
    [
        localize "STR_A3YT_PAUSE_LOCAL_VOLUME_MENU",
        localize "STR_A3YT_PAUSE_LOCAL_VOLUME_TOOLTIP"
    ],
    "A3YT_RscDisplayLocalVolumeSettings"
] call CBA_fnc_addPauseMenuOption;
