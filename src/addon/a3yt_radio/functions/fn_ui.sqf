disableSerialization;
params [["_mode", "load", [""]], ["_display", displayNull, [displayNull]]];
if (isNull _display) exitWith {};

private _vehicle = if (_mode isEqualTo "load") then {objectParent player} else {_display getVariable ["A3YTR_vehicle", objNull]};
if (isNull _vehicle) exitWith {closeDialog 0};

if (_mode isEqualTo "load") then {
    _display setVariable ["A3YTR_vehicle", _vehicle];
    private _name = getText (configFile >> "CfgVehicles" >> (typeOf _vehicle) >> "displayName");
    if (_name isEqualTo "") then {_name = typeOf _vehicle};
    (_display displayCtrl 2611944) ctrlSetText _name;

    private _initial = _vehicle getVariable ["A3YTR_state", [[],0,70,0,0,0]];
    private _initialVolume = _initial param [2, 70];
    (_display displayCtrl 2611943) ctrlSetText str _initialVolume;
    _display setVariable ["A3YTR_shownVolume", _initialVolume];

    [_display, _vehicle] spawn {
        params ["_display", "_vehicle"];
        private _previous = [];
        private _formatTime = {
            params ["_seconds"];
            private _minutes = floor (_seconds / 60);
            private _remainder = floor (_seconds mod 60);
            format ["%1:%2%3", _minutes, if (_remainder < 10) then {"0"} else {""}, _remainder]
        };

        while {!isNull _display && {!isNull _vehicle}} do {
            if (objectParent player isNotEqualTo _vehicle) exitWith {_display closeDisplay 2};

            private _state = _vehicle getVariable ["A3YTR_state", [[],0,70,0,0,0]];
            private _queue = _state param [0, []];
            private _index = _state param [1, 0];
            private _broadcastVolume = _state param [2, 70];
            private _started = _state param [3, 0];
            private _duration = _state param [5, 0];
            private _playing = count _queue > 0 && {_index >= 0} && {_index < count _queue};

            if (_state isNotEqualTo _previous) then {
                private _list = _display displayCtrl 2611942;
                private _selected = lbCurSel _list;
                lbClear _list;
                {
                    private _title = if (_x isEqualType []) then {_x param [1, _x param [0, ""]]} else {_x};
                    private _row = _list lbAdd format ["%1. %2", _forEachIndex + 1, _title];
                    _list lbSetTooltip [_row, if (_x isEqualType []) then {_x param [0, ""]} else {_x}];
                } forEach _queue;
                if (count _queue isEqualTo 0) then {_list lbAdd localize "STR_A3YTR_QUEUE_EMPTY"};
                if (count _queue > 0) then {
                    _list lbSetCurSel (if (_selected >= 0 && {_selected < count _queue}) then {_selected} else {_index});
                };
                (_display displayCtrl 2611949) ctrlSetText format [localize "STR_A3YTR_TRACKS", count _queue];

                private _volume = _display displayCtrl 2611943;
                private _shownVolume = _display getVariable ["A3YTR_shownVolume", _broadcastVolume];
                if (ctrlText _volume isEqualTo str _shownVolume) then {
                    _volume ctrlSetText str _broadcastVolume;
                    _display setVariable ["A3YTR_shownVolume", _broadcastVolume];
                };
                _previous = +_state;
            };

            private _entry = if (_playing) then {_queue select _index} else {""};
            private _url = if (_entry isEqualType []) then {_entry param [0, ""]} else {_entry};
            private _now = if (_playing) then {
                if (_entry isEqualType []) then {_entry param [1, _url]} else {_url}
            } else {localize "STR_A3YTR_NOTHING"};
            private _nowControl = _display displayCtrl 2611946;
            _nowControl ctrlSetText _now;
            _nowControl ctrlSetTooltip _now;
            private _urlControl = _display displayCtrl 2611952;
            _urlControl ctrlSetText _url;
            _urlControl ctrlSetTooltip _url;

            private _progress = "0:00 / --:--";
            private _fraction = 0;
            if (_playing) then {
                private _pausedAt = _state param [6, -1];
                private _elapsed = ((if (_pausedAt >= 0) then {_pausedAt} else {serverTime}) - _started) max 0;
                if (_duration > 0) then {
                    _elapsed = _elapsed min (_duration / 1000);
                    _fraction = (_elapsed * 1000 / _duration) min 1;
                };
                _progress = format [
                    "%1 / %2",
                    [_elapsed] call _formatTime,
                    if (_duration > 0) then {[_duration / 1000] call _formatTime} else {"--:--"}
                ];
            };
            (_display displayCtrl 2611947) ctrlSetText _progress;
            private _bar = _display displayCtrl 2611953;
            _bar ctrlSetPosition [safeZoneX + safeZoneW * 0.5 - 0.435, safeZoneY + safeZoneH * 0.5 - 0.17, 0.87 * _fraction, 0.006];
            _bar ctrlCommit 0;
            sleep 0.3;
        };
    };
};

private _volume = _display displayCtrl 2611943;
switch (_mode) do {
    case "add": {
        if (_display getVariable ["A3YTR_loading", false]) exitWith {};
        private _urlControl = _display displayCtrl 2611941;
        private _url = trim ctrlText _urlControl;
        private _lower = toLower _url;
        if !(((_lower find "https://www.youtube.com/") isEqualTo 0) || {(_lower find "https://youtube.com/") isEqualTo 0} || {(_lower find "https://music.youtube.com/") isEqualTo 0} || {(_lower find "https://youtu.be/") isEqualTo 0}) exitWith {
            systemChat localize "STR_A3YTR_INVALID";
            ["notice",_display,[localize "STR_A3YTR_INVALID"]] call A3YTR_fnc_html;
        };
        private _playlist = (_lower find "list=") >= 0 && {(_lower find "v=") < 0};
        private _response = (["radioload", [_url, if (_playlist) then {"1"} else {"0"}]] call A3YT_fnc_callExtension) param [0, ""];
        private _parts = _response splitString "|";
        if ((_parts param [1, ""]) isNotEqualTo "radioloadqueued") exitWith {
            diag_log format ["[A3YTR] metadata start failed: %1", _response];
            systemChat localize "STR_A3YTR_LOAD_FAILED";
            ["notice",_display,[localize "STR_A3YTR_LOAD_FAILED"]] call A3YTR_fnc_html;
        };
        private _token = _parts param [2, "0"];
        _display setVariable ["A3YTR_loading", true];
        _display setVariable ["A3YTR_loadToken", _token];
        private _addButton = _display displayCtrl 2611958;
        _addButton ctrlEnable false;
        _addButton ctrlSetText localize "STR_A3YTR_LOADING";
        private _deadline = diag_tickTime + 90;
        private _result = [];
        waitUntil {
            sleep 0.2;
            _response = (["radioloadstatus", [_token]] call A3YT_fnc_callExtension) param [0, ""];
            _result = _response splitString "|";
            isNull _display || {objectParent player isNotEqualTo _vehicle} || {diag_tickTime >= _deadline} ||
                {(_display getVariable ["A3YTR_loadToken", ""]) isNotEqualTo _token} ||
                {(_result param [0, "err"]) isEqualTo "err"} || {(_result param [2, ""]) isEqualTo "ready"}
        };
        private _cancelled = isNull _display || {(_display getVariable ["A3YTR_loadToken", ""]) isNotEqualTo _token};
        private _urls = [];
        if (!_cancelled && {objectParent player isEqualTo _vehicle} && {(_result param [2, ""]) isEqualTo "ready"}) then {
            private _count = (parseNumber (_result param [3, "0"])) min 32;
            for "_i" from 0 to (_count - 1) do {
                private _item = (["radioloaditem", [_token, str _i]] call A3YT_fnc_callExtension) param [0, ""];
                private _fields = _item splitString "|";
                if ((_fields param [1, ""]) isEqualTo "radioloaditem") then {
                    _urls pushBack [_fields param [2, ""], _fields param [3, ""]];
                };
            };
        };
        ["radioloadrelease", [_token]] call A3YT_fnc_callExtension;
        if (isNull _display) exitWith {};
        _display setVariable ["A3YTR_loading", false];
        _display setVariable ["A3YTR_loadToken", ""];
        _addButton ctrlEnable true;
        _addButton ctrlSetText localize "STR_A3YTR_ADD";
        if (_cancelled || {objectParent player isNotEqualTo _vehicle}) exitWith {};
        if (count _urls > 0) then {
            [_vehicle, "add", [_urls]] remoteExecCall ["A3YTR_fnc_command", 2];
            _urlControl ctrlSetText "";
            ["notice",_display,["Added to queue.",true]] call A3YTR_fnc_html;
        } else {
            diag_log format ["[A3YTR] metadata failed or timed out: %1", _response];
            systemChat localize "STR_A3YTR_LOAD_FAILED";
            ["notice",_display,[localize "STR_A3YTR_LOAD_FAILED"]] call A3YTR_fnc_html;
        };
    };
    case "quieter";
    case "louder";
    case "volume": {
        private _value = if (_mode isEqualTo "volume") then {
            parseNumber ctrlText _volume
        } else {
            private _step = if (_mode isEqualTo "louder") then {10} else {-10};
            (parseNumber ctrlText _volume) + _step
        };
        _value = round ((_value max 0) min 100);
        _volume ctrlSetText str _value;
        _display setVariable ["A3YTR_shownVolume", _value];
        [_vehicle, "volume", [_value]] remoteExecCall ["A3YTR_fnc_command", 2];
    };
    case "next": {[_vehicle, "next", []] remoteExecCall ["A3YTR_fnc_command", 2]};
    case "stop": {
        _display setVariable ["A3YTR_loadToken", ""];
        [_vehicle, "stop", []] remoteExecCall ["A3YTR_fnc_command", 2];
    };
    case "playSelected";
    case "moveUp";
    case "moveDown";
    case "remove": {
        private _selected = lbCurSel (_display displayCtrl 2611942);
        private _queue = (_vehicle getVariable ["A3YTR_state", [[],0,70,0,0,0]]) param [0, []];
        if (_selected < 0 || {_selected >= count _queue}) exitWith {};
        private _action = switch (_mode) do {
            case "playSelected": {"play"};
            case "remove": {"remove"};
            default {"move"};
        };
        private _payload = if (_action isEqualTo "move") then {
            [_selected, if (_mode isEqualTo "moveUp") then {-1} else {1}]
        } else {[_selected]};
        if (_action isEqualTo "move") then {
            private _target = _selected + (_payload select 1);
            if (_target < 0 || {_target >= count _queue}) exitWith {};
            (_display displayCtrl 2611942) lbSetCurSel _target;
        };
        [_vehicle, _action, _payload] remoteExecCall ["A3YTR_fnc_command", 2];
    };
};
