if (isServer) then {
    [] spawn {
        while {true} do {
            private _active = missionNamespace getVariable ["A3YTR_activeVehicles", []];
            _active = _active select {!isNull _x && {alive _x} && {count ((_x getVariable ["A3YTR_state", [[],0,70,0,0,0]]) select 0) > 0}};
            {
                private _state = _x getVariable ["A3YTR_state", [[],0,70,0,0,0]];
                private _updated = [_state, missionNamespace getVariable ["A3YTR_requireEngine", true], isEngineOn _x,
                    _x getVariable ["A3YTR_loop", false], serverTime, _x getVariable ["A3YTR_manualPause", false]] call A3YTR_fnc_tick;
                if (_updated isNotEqualTo _state) then {
                    _x setVariable ["A3YTR_state", _updated, true];
                };
            } forEach _active;
            missionNamespace setVariable ["A3YTR_activeVehicles", _active];
            sleep 0.5;
        };
    };
};

if (hasInterface) then {
    ["YouTube Player Music", "vehicleRadio", [localize "STR_A3YTR_KEY", localize "STR_A3YTR_TITLE"], {
        [] call A3YTR_fnc_open
    }, "", [0x13, [false, true, true]]] call CBA_fnc_addKeybind;
    if (isClass (configFile >> "CfgPatches" >> "ace_interact_menu")) then {
        [] spawn {
            waitUntil {!isNil "ace_interact_menu_fnc_createAction" && {!isNil "ace_interact_menu_fnc_addActionToClass"}};
            private _action = ["A3YTR_open", localize "STR_A3YTR_ACE_OPEN", "", {
                [] call A3YTR_fnc_open;
            }, {
                private _vehicle = objectParent player;
                !isNull _vehicle && {alive _vehicle} &&
                    {_vehicle isKindOf "LandVehicle" || {_vehicle isKindOf "Air"} || {_vehicle isKindOf "Ship"}}
            }, {}, [], [0,0,0], 2, [false,true,false,false,false]] call ace_interact_menu_fnc_createAction;
            ["CAManBase", 1, ["ACE_SelfActions"], _action, true] call ace_interact_menu_fnc_addActionToClass;
        };
    };
    [] spawn {
        waitUntil {!isNull player && {time > 0}};
        [] call A3YTR_fnc_listener;
    };
};
