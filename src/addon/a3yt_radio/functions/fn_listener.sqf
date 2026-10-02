private _channels = createHashMap;
while {hasInterface} do {
    private _seen = [];
    private _vehicles = nearestObjects [player, ["LandVehicle", "Air", "Ship"], 50];
    {
        private _vehicle = _x;
        private _state = _vehicle getVariable ["A3YTR_state", [[],0,70,0,0,0]];
        _state params ["_queue", "_index", "_volume", "_started", "_generation"];
        private _radius = 50 * ((_volume max 0) min 100) / 100;
        private _inside = (objectParent player) isEqualTo _vehicle;
        if (isEngineOn _vehicle && {alive _vehicle} && {_index < count _queue} && {_radius > 0} && {_inside || {player distance _vehicle < _radius}}) then {
            private _id = (netId _vehicle splitString ":") joinString "_";
            private _url = _queue select _index;
            private _old = _channels getOrDefault [_id, [-1, "", false, false, -10]];
            if (_old select 0 isNotEqualTo _generation || {(_old select 1) isNotEqualTo _url}) then {
                private _offset = round (((serverTime - _started) max 0) * 1000);
                private _playResult = ["radioplay", [_id, _url, str _offset]] call A3YT_fnc_callExtension;
                if ((_playResult param [0, ""]) isEqualTo "ok|radio_queued") then {
                    _channels set [_id, [_generation, _url, false, false, diag_tickTime]];
                };
            };
            private _distance = player distance _vehicle;
            private _attenuation = if (_inside) then {1} else {(1 - _distance / _radius) ^ 2};
            private _localVolume = profileNamespace getVariable ["A3YTR_localVolume", 100];
            if !(_localVolume isEqualType 0) then {_localVolume = 100};
            private _broadcastVolume = ((_volume max 0) min 100);
            private _listenerVolume = ((_localVolume max 0) min 100);
            private _gain = round (_broadcastVolume * _listenerVolume * _attenuation / 100);
            private _pan = if (_inside) then {0} else {round (100 * sin ((player getDir _vehicle) - getDirVisual player))};
            ["radiovolume", [_id, str _gain, str _pan]] call A3YT_fnc_callExtension;
            private _status = ["radiostatus", [_id]] call A3YT_fnc_callExtension;
            private _statusParts = (_status param [0, ""]) splitString "|";
            if ((_statusParts param [2, ""]) isEqualTo "playing" && {_id in (keys _channels)} && {(_state param [5,0]) isEqualTo 0}) then {
                private _duration = parseNumber (_statusParts param [3, "0"]);
                private _channel = _channels get _id;
                if (_duration > 1000 && {!(_channel select 3)}) then {
                    [_vehicle, "duration", [_generation, _duration]] remoteExecCall ["A3YTR_fnc_command", 2];
                    _channels set [_id, [_generation, _url, _channel select 2, true, _channel select 4]];
                };
            };
            if ((_statusParts param [2, ""]) isEqualTo "ended" && {_id in (keys _channels)} && {!((_channels get _id) select 2)}) then {
                private _channel = _channels get _id;
                _channels set [_id, [_generation, _url, true, _channel select 3, _channel select 4]];
                [_vehicle, "finished", [_generation]] remoteExecCall ["A3YTR_fnc_command", 2];
            };
            if ((_statusParts param [2, ""]) isEqualTo "error" && {_id in (keys _channels)}) then {
                private _channel = _channels get _id;
                if (diag_tickTime - (_channel select 4) > 10) then {
                    _channels deleteAt _id;
                };
            };
            _seen pushBack _id;
        };
    } forEach _vehicles;
    {
        if !(_x in _seen) then {
            ["radiostop", [_x]] call A3YT_fnc_callExtension;
            _channels deleteAt _x;
        };
    } forEach (keys _channels);
    sleep 0.25;
};
{["radiostop", [_x]] call A3YT_fnc_callExtension} forEach (keys _channels);
