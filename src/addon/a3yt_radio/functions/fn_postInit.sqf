if (isServer) then {
    [] spawn {
        while {true} do {
            private _active = missionNamespace getVariable ["A3YTR_activeVehicles", []];
            _active = _active select {!isNull _x && {alive _x} && {count ((_x getVariable ["A3YTR_state", [[],0,70,0,0,0]]) select 0) > 0}};
            {
                private _state = _x getVariable ["A3YTR_state", [[],0,70,0,0,0]];
                if !(isEngineOn _x) then {
                    _x setVariable ["A3YTR_state", [[],0,_state param [2,70],0,(_state param [4,0]) + 1,0], true];
                } else {
                    private _duration = _state param [5, 0, [0]];
                    if (_duration > 0 && {serverTime - (_state param [3,0]) > _duration / 1000 + 1}) then {
                        private _queue = _state param [0, []];
                        private _index = (_state param [1, 0]) + 1;
                        if (_index >= count _queue) then {_queue = []; _index = 0};
                        _x setVariable ["A3YTR_state", [_queue,_index,_state param [2,70],serverTime,(_state param [4,0]) + 1,0], true];
                    };
                };
            } forEach _active;
            missionNamespace setVariable ["A3YTR_activeVehicles", _active];
            sleep 0.5;
        };
    };
};

if (hasInterface) then {
    ["YouTube Player Music", "vehicleRadio", [localize "STR_A3YTR_KEY", localize "STR_A3YTR_TITLE"], {
        if (isNull objectParent player) exitWith {false};
        if !(isEngineOn (objectParent player)) exitWith {systemChat localize "STR_A3YTR_ENGINE"; true};
        createDialog "A3YTR_RscRadio";
        true
    }, "", [0x13, [false, true, true]]] call CBA_fnc_addKeybind;
    [] spawn {
        waitUntil {!isNull player && {time > 0}};
        [] call A3YTR_fnc_listener;
    };
};
