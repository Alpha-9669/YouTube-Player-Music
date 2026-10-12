// HTML faceplate preview. No calls to A3YTR_fnc_command or the audio extension.
// Put this and radio_faceplate_preview.html beside the mission.sqm, then run:
// [] execVM "preview_radio_faceplate.sqf";
[] spawn {
    disableSerialization;
    if !(isClass (configFile >> "RscWebBrowser")) exitWith {
        systemChat "This preview needs Arma 3 2.20+ (RscWebBrowser).";
    };
    private _html = loadFile "radio_faceplate_preview.html";
    if (_html isEqualTo "") exitWith {systemChat "radio_faceplate_preview.html is missing from the mission folder."};
    private _parent = if (is3DEN) then {findDisplay 313} else {findDisplay 46};
    if (isNull _parent) exitWith {};
    private _old = uiNamespace getVariable ["A3YTR_previewDisplay", displayNull];
    if (!isNull _old) then {_old closeDisplay 2};
    private _display = _parent createDisplay "RscDisplayEmpty";
    uiNamespace setVariable ["A3YTR_previewDisplay", _display];
    if !(isClass (missionConfigFile >> "A3YTRPreviewWebBrowser")) exitWith {
        _display closeDisplay 2;
        systemChat "Reload the test.VR mission to load the preview browser config.";
    };
    // Mark the actual HTML before loading: ExecJS can run in the sandbox host,
    // whereas the page stylesheet lives inside its local-content iframe.
    private _headEnd = _html find "</head>";
    if (_headEnd >= 0) then {
        _html = (_html select [0, _headEnd]) + "<style>:root{color-scheme:normal!important}html,body{background:transparent!important;margin:0!important;padding:0!important}body{min-height:0!important}html,body{height:100%;overflow:hidden!important}.assembly{width:100%!important;margin:0!important;box-shadow:inset 0 1px 1px #686868,inset 0 -1px 2px #080808!important}.assembly{max-height:100vh}.queue-list{height:clamp(80px,calc(100vh - 25cqw - 155px),270px)!important}</style>" + (_html select [_headEnd]);
    };
    private _browser = _display ctrlCreate ["A3YTRPreviewWebBrowser", 2611990];
    _browser ctrlSetBackgroundColor [0,0,0,0];
    // Keep the CEF viewport stable while the HTML drawer animates.
    private _width = safeZoneW * 0.62;
    _browser ctrlSetPosition [safeZoneX + (safeZoneW - _width) / 2, safeZoneY + safeZoneH * 0.18, _width, safeZoneH * 0.78];
    _browser ctrlCommit 0;
    _display displayAddEventHandler ["KeyDown", {
        params ["_display", "_key"];
        if (_key isEqualTo 1) exitWith {_display closeDisplay 2; true};
        false
    }];
    _browser ctrlAddEventHandler ["JSDialog", {
        params ["_control", "_confirm", "_message"];
        if (_message isEqualTo "A3YTR_PREVIEW|close") then {
            [_control] spawn {
                disableSerialization;
                params ["_control"];
                sleep 0.01;
                if (!isNull _control) then {(ctrlParent _control) closeDisplay 2};
            };
        };
        true // Reply immediately: leaving JSDialog unanswered freezes the browser.
    }];
    private _js = "document.body.classList.add('in-arma');document.documentElement.classList.add('in-arma');";
    private _vehicle = objectParent player;
    if (!isNull _vehicle) then {
        private _state = _vehicle getVariable ["A3YTR_state", [[],0,70,0,0,0,-1]];
        private _queue = _state param [0, []];
        if (count _queue > 0) then {
            // SQF string escaping is not JSON escaping. Base64 transfers Unicode,
            // quotes, backslashes and arbitrary track titles without executing them.
            private _encode = {
                params ["_text"];
                format ["A3YTDecode('%1')", controlNull ctrlWebBrowserAction ["ToBase64", _text]]
            };
            private _items = _queue apply {
                private _url = if (_x isEqualType []) then {_x param [0, ""]} else {_x};
                private _title = if (_x isEqualType []) then {_x param [1, _url]} else {_url};
                format ["[%1,%2]", [_url] call _encode, [_title] call _encode]
            };
            private _pausedAt = _state param [6, -1];
            private _elapsed = ((if (_pausedAt >= 0) then {_pausedAt} else {serverTime}) - (_state param [3, 0])) max 0;
            private _vehicleName = getText (configFile >> "CfgVehicles" >> typeOf _vehicle >> "displayName");
            _js = _js + "var A3YTDecode=function(s){return new TextDecoder().decode(Uint8Array.from(atob(s),function(c){return c.charCodeAt(0)}))};";
            _js = _js + format [
                "window.A3YTRPreview.setState([[%1],%2,%3,%4,%5,%6,%7,%8]);",
                _items joinString ",", _state param [1,0], _state param [2,70], _elapsed,
                (_state param [5,0]) / 1000, if (_pausedAt >= 0) then {"true"} else {"false"},
                [_vehicleName] call _encode, if (missionNamespace getVariable ["A3YTR_loopQueue",false]) then {"true"} else {"false"}
            ];
        };
    };
    _browser setVariable ["A3YTR_previewScript", _js];
    _browser ctrlAddEventHandler ["PageLoaded", {
        params ["_control"];
        _control ctrlWebBrowserAction ["ExecJS", _control getVariable ["A3YTR_previewScript", ""]];
    }];
    _browser ctrlWebBrowserAction ["OpenDataAsURL", _html];
};
