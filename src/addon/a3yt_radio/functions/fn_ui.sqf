params [["_mode", "load", [""]], ["_display", displayNull, [displayNull]]];
if (isNull _display) exitWith {};
private _vehicle = if (_mode isEqualTo "load") then {objectParent player} else {_display getVariable ["A3YTR_vehicle", objNull]};
if (isNull _vehicle) exitWith {closeDialog 0};
if (_mode isEqualTo "load") then {
    _display setVariable ["A3YTR_vehicle", _vehicle];
    [_display, _vehicle] spawn {
        params ["_display", "_vehicle"];
        private _previous = [];
        while {!isNull _display && {!isNull _vehicle}} do {
            private _state = _vehicle getVariable ["A3YTR_state", [[],0,70,0,0]];
            if (_state isNotEqualTo _previous) then {
                private _list = _display displayCtrl 2611942;
                lbClear _list;
                {_list lbAdd _x} forEach (_state param [0, []]);
                if (count (_state param [0, []]) > 0) then {_list lbSetCurSel (_state param [1, 0])};
                _previous = +_state;
            };
            if (objectParent player isNotEqualTo _vehicle) exitWith {_display closeDisplay 2};
            sleep 0.3;
        };
    };
};
private _state = _vehicle getVariable ["A3YTR_state", [[],0,70,0,0]];
private _list = _display displayCtrl 2611942;
private _volume = _display displayCtrl 2611943;

switch (_mode) do {
    case "load": {_volume ctrlSetText str (_state param [2,70])};
    case "add": {
        if !(isEngineOn _vehicle) exitWith {systemChat localize "STR_A3YTR_ENGINE"};
        private _url = trim ctrlText (_display displayCtrl 2611941);
        private _lower = toLower _url;
        if !(((_lower find "https://www.youtube.com/") isEqualTo 0) || {(_lower find "https://youtube.com/") isEqualTo 0} || {(_lower find "https://music.youtube.com/") isEqualTo 0} || {(_lower find "https://youtu.be/") isEqualTo 0}) exitWith {
            systemChat localize "STR_A3YTR_INVALID";
        };
        private _urls = [_url];
        if ((_lower find "list=") >= 0 && {(_lower find "v=") < 0}) then {
            _urls = [];
            private _response = ["playlistload", [_url]] call A3YT_fnc_callExtension;
            private _parts = (_response param [0, ""]) splitString "|";
            if ((_parts param [0, ""]) isEqualTo "ok" && {(_parts param [1, ""]) isEqualTo "playlistload"}) then {
                private _token = _parts param [2, "0"];
                private _count = (parseNumber (_parts param [3,"0"])) min 32;
                for "_i" from 0 to (_count - 1) do {
                    private _item = (["playlistitem", [_token, str _i]] call A3YT_fnc_callExtension) param [0, ""];
                    private _fields = _item splitString "|";
                    if ((_fields param [0, ""]) isEqualTo "ok") then {_urls pushBack (_fields param [2, ""])};
                };
            };
            if (count _urls isEqualTo 0) then {systemChat localize "STR_A3YTR_INVALID"};
        };
        if (count _urls > 0) then {[_vehicle, "add", [_urls]] remoteExecCall ["A3YTR_fnc_command", 2]};
        (_display displayCtrl 2611941) ctrlSetText "";
    };
    case "volume": {
        private _value = round (((parseNumber ctrlText _volume) max 0) min 100);
        _volume ctrlSetText str _value;
        [_vehicle, "volume", [_value]] remoteExecCall ["A3YTR_fnc_command", 2];
    };
    case "next": {[_vehicle, "next", []] remoteExecCall ["A3YTR_fnc_command", 2]};
    case "stop": {[_vehicle, "stop", []] remoteExecCall ["A3YTR_fnc_command", 2]};
};

lbClear _list;
{_list lbAdd _x} forEach (_state param [0, []]);
_list lbSetCurSel (_state param [1, 0]);
