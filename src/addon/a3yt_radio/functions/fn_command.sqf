// Only the server may change a vehicle's public radio state.
params [
    ["_vehicle", objNull, [objNull]],
    ["_action", "", [""]],
    ["_payload", [], [[]]]
];
if (!isServer || {isNull _vehicle} || {!(_vehicle isKindOf "LandVehicle" || {_vehicle isKindOf "Air"} || {_vehicle isKindOf "Ship"})}) exitWith {};

private _owner = if (isNil "remoteExecutedOwner") then {2} else {remoteExecutedOwner};
private _requester = objNull;
if (_owner > 2) then {
    {if (owner _x isEqualTo _owner) exitWith {_requester = _x}} forEach allPlayers;
};
if (_owner > 2 && {isNull _requester}) exitWith {};
if (_owner > 2 && {!(_action in ["finished", "duration"])} && {!(_requester in crew _vehicle)}) exitWith {};

private _state = _vehicle getVariable ["A3YTR_state", [[], 0, 70, 0, 0, 0]];
_state params ["_queue", "_index", "_volume", "_started", "_generation"];
private _duration = _state param [5, 0, [0]];
if !(_queue isEqualType []) then {_queue = []};
if !(_index isEqualType 0) then {_index = 0};
if !(_volume isEqualType 0) then {_volume = 70};
if !(_generation isEqualType 0) then {_generation = 0};

if (_action isEqualTo "finished") exitWith {
    if (_owner > 2 && {_requester distance _vehicle > 50}) exitWith {};
    if (count _queue isEqualTo 0 || {serverTime - _started < 0.5}) exitWith {};
    if ((_payload param [0, -1, [0]]) isNotEqualTo _generation) exitWith {};
    _index = _index + 1;
    _generation = _generation + 1;
    _duration = 0;
    if (_index >= count _queue) then {_queue = []; _index = 0};
    _vehicle setVariable ["A3YTR_state", [_queue, _index, _volume, serverTime, _generation, _duration], true];
};

if (_action isEqualTo "duration") exitWith {
    if (_owner > 2 && {_requester distance _vehicle > 50}) exitWith {};
    if (count _queue isEqualTo 0 || {(_payload param [0,-1,[0]]) isNotEqualTo _generation}) exitWith {};
    private _reported = _payload param [1, 0, [0]];
    if (_reported > 1000 && {_reported <= 86400000} && {_duration isEqualTo 0}) then {
        _vehicle setVariable ["A3YTR_state", [_queue, _index, _volume, _started, _generation, round _reported], true];
    };
};

if !(_action in ["add", "volume", "next", "stop"]) exitWith {};
if !(isEngineOn _vehicle) exitWith {};
private _lastCommand = _vehicle getVariable ["A3YTR_lastCommand", -10];
if (_action isNotEqualTo "stop" && {serverTime - _lastCommand < 0.15}) exitWith {};
_vehicle setVariable ["A3YTR_lastCommand", serverTime];

switch (_action) do {
    case "add": {
        private _new = _payload param [0, [], [[]]];
        {
            if (_x isEqualType "" && {count _x <= 2048}) then {
                private _url = toLower (trim _x);
                if (count _queue < 32 && {
                    (_url find "https://www.youtube.com/") isEqualTo 0 ||
                    {(_url find "https://youtube.com/") isEqualTo 0} ||
                    {(_url find "https://music.youtube.com/") isEqualTo 0} ||
                    {(_url find "https://youtu.be/") isEqualTo 0}
                }) then {_queue pushBack (trim _x)};
            };
        } forEach (_new select [0, 32]);
        if (count _queue > 0 && {_started isEqualTo 0}) then {
            _index = 0;
            _started = serverTime;
            _generation = _generation + 1;
            _duration = 0;
        };
    };
    case "volume": {
        private _requested = _payload param [0, _volume, [0]];
        _volume = round ((_requested max 0) min 100);
    };
    case "next": {
        if (count _queue > 0) then {
            _index = _index + 1;
            if (_index >= count _queue) then {_queue = []; _index = 0};
            _generation = _generation + 1;
            _started = serverTime;
            _duration = 0;
        };
    };
    case "stop": {
        _queue = [];
        _index = 0;
        _started = 0;
        _generation = _generation + 1;
        _duration = 0;
    };
};

_vehicle setVariable ["A3YTR_state", [_queue, _index, _volume, _started, _generation, _duration], true];
if (count _queue > 0) then {
    private _active = missionNamespace getVariable ["A3YTR_activeVehicles", []];
    _active pushBackUnique _vehicle;
    missionNamespace setVariable ["A3YTR_activeVehicles", _active];
};
