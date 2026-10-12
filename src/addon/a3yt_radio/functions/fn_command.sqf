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
private _requireEngine = missionNamespace getVariable ["A3YTR_requireEngine", true];
private _loop = _vehicle getVariable ["A3YTR_loop", false];
private _manualPause = _vehicle getVariable ["A3YTR_manualPause", false];
_state = [_state, _requireEngine, isEngineOn _vehicle, _loop, serverTime, _manualPause] call A3YTR_fnc_tick;
_state params ["_queue", "_index", "_volume", "_started", "_generation"];
private _duration = _state param [5, 0, [0]];
private _pausedAt = _state param [6, -1, [0]];
if !(_queue isEqualType []) then {_queue = []};
if !(_index isEqualType 0) then {_index = 0};
if !(_volume isEqualType 0) then {_volume = 70};
if !(_generation isEqualType 0) then {_generation = 0};

if (_action isEqualTo "finished") exitWith {
    if (_owner > 2 && {_requester distance _vehicle > 50}) exitWith {};
    if (count _queue isEqualTo 0 || {_index < 0} || {_pausedAt >= 0} || {serverTime - _started < 0.5}) exitWith {};
    if ((_payload param [0, -1, [0]]) isNotEqualTo _generation) exitWith {};
    _vehicle setVariable ["A3YTR_state", [_state, _loop, serverTime] call A3YTR_fnc_advance, true];
};

if (_action isEqualTo "duration") exitWith {
    if (_owner > 2 && {_requester distance _vehicle > 50}) exitWith {};
    if (count _queue isEqualTo 0 || {_index < 0} || {_pausedAt >= 0} || {(_payload param [0,-1,[0]]) isNotEqualTo _generation}) exitWith {};
    private _reported = _payload param [1, 0, [0]];
    if (_reported > 1000 && {_reported <= 86400000} && {_duration isEqualTo 0}) then {
        _vehicle setVariable ["A3YTR_state", [_queue, _index, _volume, _started, _generation, round _reported, _pausedAt], true];
    };
};

if !(_action in ["add", "volume", "next", "stop", "play", "move", "remove", "loop", "pause", "resume", "seek"]) exitWith {};
if (_action in ["play","move","remove","seek"]) then {
    private _expected = _payload param [if (_action isEqualTo "move") then {2} else {1}, _generation, [0]];
    if (_expected isNotEqualTo _generation) then {_action = ""};
};
if (_action isEqualTo "") exitWith {};
private _lastCommand = _vehicle getVariable ["A3YTR_lastCommand", -10];
if (_action isNotEqualTo "stop" && {serverTime - _lastCommand < 0.15}) exitWith {};
_vehicle setVariable ["A3YTR_lastCommand", serverTime];

switch (_action) do {
    case "add": {
        private _oldCount = count _queue;
        private _new = _payload param [0, [], [[]]];
        {
            private _entry = _x;
            private _url = if (_entry isEqualType []) then {_entry param [0, "", [""]]} else {_entry};
            private _title = if (_entry isEqualType []) then {_entry param [1, "", [""]]} else {""};
            if (_url isEqualType "" && {count _url <= 2048}) then {
                private _lower = toLower (trim _url);
                if (count _queue < 32 && {
                    (_lower find "https://www.youtube.com/") isEqualTo 0 ||
                    {(_lower find "https://youtube.com/") isEqualTo 0} ||
                    {(_lower find "https://music.youtube.com/") isEqualTo 0} ||
                    {(_lower find "https://youtu.be/") isEqualTo 0}
                }) then {
                    _url = trim _url;
                    _title = trim _title;
                    if (_title isEqualTo "") then {_title = _url};
                    _queue pushBack [_url, _title select [0, 160]];
                };
            };
        } forEach (_new select [0, 32]);
        if (count _queue > _oldCount && {_oldCount isEqualTo 0 || {_index < 0}}) then {
            _index = _oldCount;
            _started = serverTime;
            _generation = _generation + 1;
            _duration = 0;
            _pausedAt = -1;
        };
    };
    case "seek": {
        private _sought = [_state, _payload param [0,0,[0]], serverTime] call A3YTR_fnc_seek;
        _started = _sought select 3;
        _generation = _sought select 4;
    };
    case "pause": {if (count _queue > 0 && {_index >= 0}) then {_manualPause = true}};
    case "resume": {_manualPause = false};
    case "loop": {
        _loop = (_payload param [0,0,[0]]) > 0;
        _vehicle setVariable ["A3YTR_loop", _loop, true];
    };
    case "volume": {
        private _requested = _payload param [0, _volume, [0]];
        _volume = round ((_requested max 0) min 100);
    };
    case "next": {
        if (count _queue > 0) then {
            private _advanced = [_state, _loop, serverTime] call A3YTR_fnc_advance;
            _index = _advanced select 1;
            _started = _advanced select 3;
            _generation = _advanced select 4;
            _duration = 0;
            _pausedAt = -1;
        };
    };
    case "play": {
        _manualPause = false;
        private _requested = _payload param [0, -1, [0]];
        if (_requested >= 0 && {_requested < count _queue}) then {
            _index = _requested;
            _started = serverTime;
            _generation = _generation + 1;
            _duration = 0;
            _pausedAt = -1;
        };
    };
    case "move": {
        private _from = _payload param [0, -1, [0]];
        private _delta = _payload param [1, 0, [0]];
        private _to = _from + _delta;
        if (abs _delta >= 1 && {abs _delta <= 31} && {_from >= 0} && {_from < count _queue} && {_to >= 0} && {_to < count _queue}) then {
            private _entry = _queue deleteAt _from;
            _queue insert [_to, [_entry]];
            if (_index isEqualTo _from) then {_index = _to} else {
                if (_from < _index && {_to >= _index}) then {_index = _index - 1};
                if (_from > _index && {_to <= _index}) then {_index = _index + 1};
            };
        };
    };
    case "remove": {
        private _removed = _payload param [0, -1, [0]];
        if (_removed >= 0 && {_removed < count _queue}) then {
            _queue deleteAt _removed;
            if (count _queue isEqualTo 0) then {
                _index = 0;
                _started = 0;
                _generation = _generation + 1;
                _duration = 0;
                _pausedAt = -1;
            } else {
                if (_removed isEqualTo _index) then {
                    _index = _removed min (count _queue - 1);
                    _started = serverTime;
                    _generation = _generation + 1;
                    _duration = 0;
                    _pausedAt = -1;
                } else {
                    if (_removed < _index) then {_index = _index - 1};
                };
            };
        };
    };
    case "stop": {
        _manualPause = false;
        _queue = [];
        _index = 0;
        _started = 0;
        _generation = _generation + 1;
        _duration = 0;
        _pausedAt = -1;
    };
};

private _updated = [[_queue, _index, _volume, _started, _generation, _duration, _pausedAt],
    _requireEngine, isEngineOn _vehicle, _loop, serverTime, _manualPause] call A3YTR_fnc_tick;
_vehicle setVariable ["A3YTR_manualPause", _manualPause, true];
_vehicle setVariable ["A3YTR_state", _updated, true];
if (count _queue > 0) then {
    private _active = missionNamespace getVariable ["A3YTR_activeVehicles", []];
    _active pushBackUnique _vehicle;
    missionNamespace setVariable ["A3YTR_activeVehicles", _active];
};
