params [["_sourceVolume", 70, [0]]];

private _zeusVolume = (_sourceVolume max 0) min 100;
private _localVolume = (missionNamespace getVariable ["A3YT_localVolume", 100]) max 0 min 100;

if (missionNamespace getVariable ["A3YT_localVolumeOverride", false]) exitWith {
    round _localVolume
};

round ((_zeusVolume * _localVolume) / 100)
