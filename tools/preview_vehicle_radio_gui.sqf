// Copy this whole file into the Arma 3 debug console and press LOCAL EXEC.
// Visual preview only: the radio and PBOs are not changed.
[] spawn {
    disableSerialization;
    private _parent = if (is3DEN) then {findDisplay 313} else {findDisplay 46};
    if (isNull _parent) exitWith {systemChat "Open the preview in a mission or Eden."};
    private _d = _parent createDisplay "RscDisplayEmpty";
    if (isNull _d) exitWith {};
    private _x = safeZoneX + safeZoneW * 0.5 - 0.46;
    private _y = safeZoneY + safeZoneH * 0.5 - 0.47;
    private _white = [0.92,0.92,0.90,1];
    private _muted = [0.64,0.64,0.62,1];
    private _amber = [0.93,0.70,0.33,1];
    private _clear = [0,0,0,0];
    private _add = {
        params ["_class","_text","_p","_bg","_fg",["_size",0]];
        private _c = _d ctrlCreate [_class,-1];
        _c ctrlSetPosition [_x + (_p select 0),_y + (_p select 1),_p select 2,_p select 3];
        _c ctrlSetBackgroundColor _bg;
        _c ctrlSetTextColor _fg;
        _c ctrlSetText _text;
        if (_size > 0) then {_c ctrlSetFontHeight _size};
        _c ctrlCommit 0;
        _c
    };
    ["RscText","",[0,0,0.92,0.94],[0,0,0,0.91],_white] call _add;
    ["RscText","",[0,0,0.92,0.055],[0.34,0.29,0.16,0.98],_white] call _add;
    ["RscText",localize "STR_A3YTR_TITLE",[0.025,0.006,0.65,0.043],_clear,_white,0.034] call _add;

    private _vehicle = objectParent player;
    private _state = if (isNull _vehicle) then {[[],0,70,0,0,0]} else {
        _vehicle getVariable ["A3YTR_state",[[],0,70,0,0,0]]
    };
    private _queue = +(_state param [0,[]]);
    private _index = _state param [1,0];
    private _volume = _state param [2,70];
    private _started = _state param [3,0];
    private _duration = _state param [5,0];
    private _playing = _index >= 0 && {_index < count _queue};
    private _name = if (isNull _vehicle) then {"Vehicle preview"} else {
        getText (configFile >> "CfgVehicles" >> (typeOf _vehicle) >> "displayName")
    };
    ["RscText",_name,[0.025,0.073,0.62,0.032],_clear,_white,0.028] call _add;

    ["RscText","",[0.025,0.116,0.87,0.001],[0.32,0.32,0.29,1],_white] call _add;
    ["RscText",localize "STR_A3YTR_NOW",[0.025,0.133,0.80,0.028],_clear,_muted,0.026] call _add;
    private _titleCtrl = ["RscTextMulti",if (_playing) then {"Loading track title..."} else {
        localize "STR_A3YTR_NOTHING"
    },[0.025,0.166,0.87,0.078],_clear,_white,0.035] call _add;
    private _url = if (_playing) then {_queue select _index} else {""};
    private _urlCtrl = ["RscText",_url,[0.025,0.250,0.87,0.030],_clear,_muted,0.023] call _add;
    _urlCtrl ctrlSetTooltip _url;
    ["RscText","",[0.025,0.300,0.87,0.006],[0.23,0.23,0.21,1],_white] call _add;
    private _bar = ["RscText","",[0.025,0.300,0,0.006],[0.58,0.52,0.31,1],_white] call _add;
    private _clock = ["RscText","",[0.025,0.322,0.30,0.033],_clear,_muted,0.026] call _add;

    ["RscText",localize "STR_A3YTR_QUEUE",[0.025,0.345,0.48,0.030],_clear,_white,0.030] call _add;
    private _countCtrl = ["RscText",format [localize "STR_A3YTR_TRACKS",count _queue],
        [0.68,0.345,0.21,0.030],_clear,_muted,0.026] call _add;
    private _list = ["RscListBox","",[0.025,0.380,0.87,0.285],
        [0.045,0.045,0.045,0.88],_white] call _add;
    private _play = ["RscButton","Play selected",[0.025,0.675,0.20,0.039],
        [0.12,0.12,0.12,1],_white] call _add;
    private _up = ["RscButton","Up",[0.235,0.675,0.14,0.039],
        [0.12,0.12,0.12,1],_white] call _add;
    private _down = ["RscButton","Down",[0.385,0.675,0.14,0.039],
        [0.12,0.12,0.12,1],_white] call _add;
    private _remove = ["RscButton","Remove",[0.735,0.675,0.16,0.039],
        [0.12,0.12,0.12,1],_white] call _add;

    ["RscText",localize "STR_A3YTR_URL",[0.025,0.728,0.87,0.028],_clear,_muted,0.026] call _add;
    private _urlInput = ["RscEdit","",[0.025,0.760,0.705,0.043],[0.06,0.06,0.06,1],_white] call _add;
    private _addButton = ["RscButton",localize "STR_A3YTR_ADD",[0.742,0.760,0.153,0.043],
        [0.30,0.31,0.24,1],_white] call _add;
    ["RscText",localize "STR_A3YTR_VOLUME",[0.025,0.820,0.33,0.043],
        _clear,_white,0.028] call _add;
    private _minus = ["RscButton","-",[0.575,0.820,0.065,0.043],[0.12,0.12,0.12,1],_white] call _add;
    private _volumeInput = ["RscEdit",str _volume,[0.65,0.820,0.075,0.043],
        [0.06,0.06,0.06,1],_white] call _add;
    private _plus = ["RscButton","+",[0.735,0.820,0.065,0.043],[0.12,0.12,0.12,1],_white] call _add;
    private _apply = ["RscButton",localize "STR_A3YTR_APPLY",[0.81,0.820,0.085,0.043],
        [0.12,0.12,0.12,1],_white] call _add;
    ["RscText","",[0.025,0.875,0.87,0.001],[0.32,0.32,0.29,1],_white] call _add;
    private _next = ["RscButton",localize "STR_A3YTR_NEXT",[0.025,0.890,0.17,0.039],
        [0.12,0.12,0.12,1],_white] call _add;
    private _stop = ["RscButton",localize "STR_A3YTR_STOP",[0.205,0.890,0.17,0.039],
        [0.12,0.12,0.12,1],_white] call _add;
    private _close = ["RscButton",localize "STR_A3YT_UI_CLOSE",
        [0.725,0.890,0.17,0.039],[0.12,0.12,0.12,1],_white] call _add;
    _close ctrlAddEventHandler ["ButtonClick",{(ctrlParent (_this select 0)) closeDisplay 2}];

    _d setVariable ["previewQueue",_queue];
    _d setVariable ["previewCurrent",_url];
    _d setVariable ["previewStarted",_started];
    _d setVariable ["previewDuration",_duration];
    _d setVariable ["previewTitles",createHashMap];
    _d setVariable ["previewList",_list];
    _d setVariable ["previewCount",_countCtrl];
    _d setVariable ["previewTitle",_titleCtrl];
    _d setVariable ["previewUrl",_urlCtrl];
    _d setVariable ["previewInput",_urlInput];
    _d setVariable ["previewVolume",_volumeInput];
    private _refresh = {
        params ["_d",["_selection",-1]];
        private _queue = _d getVariable ["previewQueue",[]];
        private _current = _d getVariable ["previewCurrent",""];
        private _titles = _d getVariable ["previewTitles",createHashMap];
        private _list = _d getVariable "previewList";
        lbClear _list;
        if (count _queue isEqualTo 0) then {
            _list lbAdd "Queue is empty";
        } else {
            {_list lbAdd format ["%1.  %2",_forEachIndex + 1,
                _titles getOrDefault [_x,_x]]} forEach _queue;
            if (_selection < 0) then {_selection = _queue find _current};
            _list lbSetCurSel ((_selection max 0) min (count _queue - 1));
        };
        (_d getVariable "previewCount") ctrlSetText
            format [localize "STR_A3YTR_TRACKS",count _queue];
        private _title = localize "STR_A3YTR_NOTHING";
        if !(_current isEqualTo "") then {
            _title = _titles getOrDefault [_current,""];
            if (_title isEqualTo "") then {
                _title = _current;
                if !(isNil "A3YT_fnc_callExtension") then {
                    private _response = ["title",[_current]] call A3YT_fnc_callExtension;
                    private _parts = (_response param [0,""]) splitString "|";
                    if ((_parts param [0,""]) isEqualTo "ok" &&
                        {(_parts param [1,""]) isEqualTo "title"}) then {
                        _title = _parts param [2,_current];
                    };
                };
                _titles set [_current,_title];
            };
        };
        private _titleCtrl = _d getVariable "previewTitle";
        _titleCtrl ctrlSetText _title;
        _titleCtrl ctrlSetTooltip _title;
        private _urlCtrl = _d getVariable "previewUrl";
        _urlCtrl ctrlSetText _current;
        _urlCtrl ctrlSetTooltip _current;
        if (count _queue > 0) then {
            private _i = _queue find _current;
            if (_i >= 0) then {_list lbSetText [_i,format ["%1.  %2",_i + 1,_title]]};
        };
    };
    _d setVariable ["previewRefresh",_refresh];
    [_d,_index] call _refresh;

    private _queueAction = {
        params ["_button","_action"];
        private _d = ctrlParent _button;
        private _queue = +(_d getVariable ["previewQueue",[]]);
        private _list = _d getVariable "previewList";
        private _selected = lbCurSel _list;
        private _current = _d getVariable ["previewCurrent",""];
        if (_action isEqualTo "add") then {
            private _input = _d getVariable "previewInput";
            private _url = trim ctrlText _input;
            if (_url isEqualTo "") exitWith {};
            _queue pushBack _url;
            _input ctrlSetText "";
            _selected = count _queue - 1;
            if (_current isEqualTo "") then {_current = _url};
        };
        if (_action isEqualTo "play" && {_selected >= 0} &&
            {_selected < count _queue}) then {_current = _queue select _selected};
        if (_action isEqualTo "up" && {_selected > 0} &&
            {_selected < count _queue}) then {
            private _item = _queue deleteAt _selected;
            _selected = _selected - 1;
            _queue insert [_selected,[_item]];
        };
        if (_action isEqualTo "down" && {_selected >= 0} &&
            {_selected < count _queue - 1}) then {
            private _item = _queue deleteAt _selected;
            _selected = _selected + 1;
            _queue insert [_selected,[_item]];
        };
        if (_action isEqualTo "remove" && {_selected >= 0} &&
            {_selected < count _queue}) then {
            private _removed = _queue deleteAt _selected;
            if (_removed isEqualTo _current) then {
                _current = _queue param [_selected,_queue param [0,""]];
            };
        };
        if (_action isEqualTo "next") then {
            private _nextIndex = (_queue find _current) + 1;
            _current = _queue param [_nextIndex,""];
            _selected = _nextIndex;
        };
        if (_action isEqualTo "stop") then {
            _queue = [];
            _current = "";
        };
        if (_action in ["play","next","stop","remove"]) then {
            _d setVariable ["previewStarted",serverTime];
            _d setVariable ["previewDuration",0];
        };
        _d setVariable ["previewQueue",_queue];
        _d setVariable ["previewCurrent",_current];
        [_d,_selected] call (_d getVariable "previewRefresh");
    };
    _d setVariable ["previewAction",_queueAction];
    {
        _x params ["_button","_action"];
        _button setVariable ["previewActionName",_action];
        _button ctrlAddEventHandler ["ButtonClick",{
            private _button = _this select 0;
            [_button,_button getVariable "previewActionName"] spawn {
                disableSerialization;
                _this call ((ctrlParent (_this select 0)) getVariable "previewAction");
            };
        }];
    } forEach [
        [_play,"play"],[_up,"up"],[_down,"down"],[_remove,"remove"],
        [_addButton,"add"],[_next,"next"],[_stop,"stop"]
    ];
    {
        _x params ["_button","_step"];
        _button setVariable ["previewStep",_step];
        _button ctrlAddEventHandler ["ButtonClick",{
            private _button = _this select 0;
            private _input = (ctrlParent _button) getVariable "previewVolume";
            _input ctrlSetText str (round ((((parseNumber ctrlText _input) +
                (_button getVariable "previewStep")) max 0) min 100));
        }];
    } forEach [[_minus,-10],[_plus,10]];
    _apply ctrlAddEventHandler ["ButtonClick",{
        private _input = (ctrlParent (_this select 0)) getVariable "previewVolume";
        _input ctrlSetText str (round (((parseNumber ctrlText _input) max 0) min 100));
    }];

    private _time = {
        params ["_seconds"];
        private _m = floor (_seconds / 60);
        private _s = floor (_seconds mod 60);
        format ["%1:%2%3",_m,if (_s < 10) then {"0"} else {""},_s]
    };
    while {!isNull _d} do {
        private _current = _d getVariable ["previewCurrent",""];
        private _started = _d getVariable ["previewStarted",0];
        private _duration = _d getVariable ["previewDuration",0];
        private _elapsed = if (_current isNotEqualTo "") then {
            (serverTime - _started) max 0
        } else {0};
        if (_duration > 0) then {_elapsed = _elapsed min (_duration / 1000)};
        _clock ctrlSetText format ["%1 / %2",[_elapsed] call _time,
            if (_duration > 0) then {[_duration / 1000] call _time} else {"--:--"}];
        private _fraction = if (_duration > 0) then {_elapsed / (_duration / 1000)} else {0};
        _bar ctrlSetPosition [_x + 0.025,_y + 0.300,0.87 * _fraction,0.006];
        _bar ctrlCommit 0;
        sleep 0.5;
    };
};
