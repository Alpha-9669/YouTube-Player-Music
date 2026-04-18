if (isServer) then {
    [] spawn A3YT_fnc_monitorCurators;
};

if (hasInterface) then {
    addMissionEventHandler ["Ended", {
        ["mission_ended"] call A3YT_fnc_forceStopLocalPlayback;
    }];

    addMissionEventHandler ["MPEnded", {
        ["mission_mpended"] call A3YT_fnc_forceStopLocalPlayback;
    }];

    [] spawn {
        waitUntil {!isNull findDisplay 46};

        private _missionDisplay = findDisplay 46;
        if (isNull _missionDisplay) exitWith {};
        if (_missionDisplay getVariable ["A3YT_unloadHookAttached", false]) exitWith {};

        _missionDisplay setVariable ["A3YT_unloadHookAttached", true];
        _missionDisplay displayAddEventHandler ["Unload", {
            ["mission_display_unload"] call A3YT_fnc_forceStopLocalPlayback;
        }];

        diag_log "[A3YT] mission unload hook attached";
    };

    [] spawn {
        waitUntil {time > 0};
        sleep 0.2;
        private _warmupResult = ["warmup", []] call A3YT_fnc_callExtension;
        diag_log format ["[A3YT] warmup result=%1", _warmupResult];
    };
};
