disableSerialization;
params [["_mode", "load", [""]], ["_display", displayNull, [displayNull]], ["_fields", [], [[]]]];
if (isNull _display) exitWith {};
private _browser = _display displayCtrl 2611990;
private _vehicle = _display getVariable ["A3YTR_vehicle", objNull];
if (_mode isEqualTo "load") exitWith {
    _vehicle = objectParent player;
    if (isNull _vehicle) exitWith {_display closeDisplay 2};
    _display setVariable ["A3YTR_vehicle", _vehicle];
    (_display displayCtrl 2611941) ctrlShow false;
    (_display displayCtrl 2611958) ctrlShow false;
    ctrlSetFocus _browser;
    _browser ctrlAddEventHandler ["MouseEnter", {ctrlSetFocus (_this select 0)}];
    _browser ctrlAddEventHandler ["JSDialog", {
        params ["_control", "_confirm", "_message"];
        if ((_message find "A3YTR|") isEqualTo 0 && {count _message < 4096}) then {
            ["command", ctrlParent _control, _message splitString "|"] spawn A3YTR_fnc_html;
        };
        true
    }];
    _browser ctrlAddEventHandler ["PageLoaded", {
        (ctrlParent (_this select 0)) setVariable ["A3YTR_htmlReady", true];
        ctrlSetFocus (_this select 0);
    }];
    _browser ctrlWebBrowserAction ["OpenDataAsURL", loadFile "\a3yt_radio\radio.html"];
    [_display, _vehicle] spawn {
        disableSerialization;
        params ["_display", "_vehicle"];
        private _browser = _display displayCtrl 2611990;
        private _name = getText (configFile >> "CfgVehicles" >> typeOf _vehicle >> "displayName");
        private _encode = {
            params ["_text"];
            format ["decode('%1')", controlNull ctrlWebBrowserAction ["ToBase64", _text]]
        };
        while {!isNull _display && {!isNull _vehicle}} do {
            if (objectParent player isNotEqualTo _vehicle || {!alive _vehicle}) exitWith {_display closeDisplay 2};
            if (_display getVariable ["A3YTR_htmlReady", false]) then {
                private _state = _vehicle getVariable ["A3YTR_state", [[],0,70,0,0,0,-1]];
                private _items = (_state select 0) apply {
                    private _url = if (_x isEqualType []) then {_x param [0, ""]} else {_x};
                    private _title = if (_x isEqualType []) then {_x param [1, _url]} else {_url};
                    format ["[%1,%2]", [_url] call _encode, [_title] call _encode]
                };
                private _paused = _state param [6, -1];
                private _elapsed = ((if (_paused >= 0) then {_paused} else {serverTime}) - (_state param [3,0])) max 0;
                private _loop = _vehicle getVariable ["A3YTR_loop", false];
                private _input = _display displayCtrl 2611941;
                private _enabled = !(_display getVariable ["A3YTR_loading",false]);
                if (ctrlEnabled _input isNotEqualTo _enabled) then {_input ctrlEnable _enabled};
                private _snapshot = format ["[[%1],%2,%3,%4,%5,%6,%7,%8,%9,%10,%11]",
                    _items joinString ",", _state select 1, _state select 2, _elapsed, (_state param [5,0])/1000,
                    str (_paused >= 0), [_name] call _encode, str _loop,
                    str (_display getVariable ["A3YTR_loading",false]), _state select 4, [ctrlText _input] call _encode];
                // Supports both direct ExecJS and the local-content sandbox host.
                private _js = "(function(){var decode=function(s){return new TextDecoder().decode(Uint8Array.from(atob(s),function(c){return c.charCodeAt(0)}))};var s=" + _snapshot + ";if(window.A3YTRRadio)window.A3YTRRadio.setState(s);document.querySelectorAll('iframe').forEach(function(f){f.contentWindow.postMessage({a3ytrState:s},'*')})})()";
                _browser ctrlWebBrowserAction ["ExecJS", _js];
            };
            sleep 0.3;
        };
    };
};
if (_mode isEqualTo "draft") exitWith {
    private _encoded = controlNull ctrlWebBrowserAction ["ToBase64", ctrlText (_display displayCtrl 2611941)];
    _browser ctrlWebBrowserAction ["ExecJS", format ["(function(){var t=new TextDecoder().decode(Uint8Array.from(atob('%1'),function(c){return c.charCodeAt(0)}));if(window.A3YTRRadio)window.A3YTRRadio.setDraft(t);document.querySelectorAll('iframe').forEach(function(f){f.contentWindow.postMessage({a3ytrDraft:t},'*')})})()", _encoded]];
};
if (_mode isEqualTo "notice") exitWith {
    private _message = _fields param [0, ""];
    private _encoded = controlNull ctrlWebBrowserAction ["ToBase64", _message];
    _browser ctrlWebBrowserAction ["ExecJS", format ["(function(){var t=new TextDecoder().decode(Uint8Array.from(atob('%1'),function(c){return c.charCodeAt(0)}));if(window.A3YTRRadio)window.A3YTRRadio.notice(t,%2);document.querySelectorAll('iframe').forEach(function(f){f.contentWindow.postMessage({a3ytrNotice:t,clear:%2},'*')})})()", _encoded, str (_fields param [1,false])]];
};
if (isNull _vehicle || {objectParent player isNotEqualTo _vehicle}) exitWith {_display closeDisplay 2};
private _action = _fields param [1, ""];
if (_action isEqualTo "ready") exitWith {_display setVariable ["A3YTR_htmlReady", true]};
if (_action isEqualTo "close") exitWith {_display closeDisplay 2};
if (_action isEqualTo "inputHide") exitWith {
    (_display displayCtrl 2611941) ctrlShow false;
    (_display displayCtrl 2611958) ctrlShow false;
    ctrlSetFocus _browser;
};
if (_action isEqualTo "input") exitWith {
    // HTML supplies normalized bounds; Arma handles keyboard/clipboard input.
    private _rect = (_fields param [2, ""]) splitString ",";
    if (count _rect isNotEqualTo 4) exitWith {};
    _rect = _rect apply {parseNumber _x};
    if ((_rect select 0) < 0 || {(_rect select 1) < 0} || {(_rect select 2) <= 0} || {(_rect select 3) <= 0} ||
        {(_rect select 0) + (_rect select 2) > 1.001} || {(_rect select 1) + (_rect select 3) > 1.001}) exitWith {};
    private _bounds = ctrlPosition _browser;
    private _input = _display displayCtrl 2611941;
    _input ctrlSetPosition [(_bounds select 0) + (_rect select 0) * (_bounds select 2),
        (_bounds select 1) + (_rect select 1) * (_bounds select 3),
        (_rect select 2) * (_bounds select 2), (_rect select 3) * (_bounds select 3)];
    _input ctrlSetFontHeight (13 * pixelH);
    _input ctrlCommit 0;
    _input ctrlShow true;
    _input ctrlEnable !(_display getVariable ["A3YTR_loading",false]);
    _display setVariable ["A3YTR_nativeInput", true];
    if ((_fields param [3, "0"]) isEqualTo "1") then {ctrlSetFocus _input};
};
if (_action isEqualTo "add") exitWith {
    if (_display getVariable ["A3YTR_loading",false]) exitWith {};
    private _url = if (_display getVariable ["A3YTR_nativeInput", false]) then {
        ctrlText (_display displayCtrl 2611941)
    } else {
        controlNull ctrlWebBrowserAction ["FromBase64", _fields param [2, ""]]
    };
    if (count _url > 2048) exitWith {};
    (_display displayCtrl 2611941) ctrlSetText _url;
    ["add", _display] call A3YTR_fnc_ui;
};
if !(_action in ["play","move","remove","next","stop","volume","loop","pause","resume","seek"]) exitWith {};
private _payload = switch (_action) do {
    case "next";
    case "pause";
    case "resume";
    case "stop": {[]};
    case "move": {[parseNumber (_fields param [2,"-1"]), parseNumber (_fields param [3,"0"])]};
    default {[parseNumber (_fields param [2,"-1"])]};
};
if (_action isEqualTo "stop") then {_display setVariable ["A3YTR_loadToken", ""]};
// Queue indices from a stale screen must not change a newer track generation.
if (_action in ["play","move","remove","seek"]) then {_payload pushBack parseNumber (_fields param [4,"-1"])};
[_vehicle, _action, _payload] remoteExecCall ["A3YTR_fnc_command", 2];
