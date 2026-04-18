params ["_control"];

private _display = ctrlParent _control;
if (isNull _display) exitWith {};

private _logic = missionNamespace getVariable ["BIS_fnc_initCuratorAttributes_target", objNull];
if (isNull _logic) exitWith {
    _display closeDisplay 2;
};

private _urlCtrl = _display displayCtrl 2611901;
private _addCtrl = _display displayCtrl 2611902;
private _volumeCtrl = _display displayCtrl 2611903;
private _notifyCtrl = _display displayCtrl 2611904;
private _consumePlayedCtrl = _display displayCtrl 2611915;
private _loopQueueCtrl = _display displayCtrl 2611916;
private _pauseCtrl = _display displayCtrl 2611909;
private _stopCtrl = _display displayCtrl 2611910;
private _startCtrl = _display displayCtrl 2611911;
private _timelineSlider = _display displayCtrl 2611912;
private _timelineValueCtrl = _display displayCtrl 2611913;
private _queueGroup = _display displayCtrl 2611914;

if (isNull _urlCtrl || {isNull _addCtrl} || {isNull _volumeCtrl} || {isNull _notifyCtrl} || {isNull _consumePlayedCtrl} || {isNull _loopQueueCtrl} || {isNull _pauseCtrl} || {isNull _stopCtrl} || {isNull _startCtrl} || {isNull _timelineSlider} || {isNull _timelineValueCtrl} || {isNull _queueGroup}) exitWith {
    _display closeDisplay 2;
};

private _gridW = ((safeZoneW / safeZoneH) min 1.2) / 40;
private _gridH = (((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25;

private _fnc_logDebug = {
    params [["_message", "", [""]]];
    if !(missionNamespace getVariable ["A3YT_debugUi", false]) exitWith {};
    diag_log format ["[A3YT][UI] %1", _message];
};
uiNamespace setVariable ["A3YT_fnc_logDebugUi", _fnc_logDebug];

private _fnc_showTransientHint = {
    params [["_text", "", [""]], ["_duration", 4, [0]]];

    hint _text;
    private _token = (uiNamespace getVariable ["A3YT_hintToken", 0]) + 1;
    uiNamespace setVariable ["A3YT_hintToken", _token];

    [_token, _duration] spawn {
        params ["_token", "_duration"];
        sleep (_duration max 0);
        if ((uiNamespace getVariable ["A3YT_hintToken", 0]) isEqualTo _token) then {
            hintSilent "";
        };
    };
};
uiNamespace setVariable ["A3YT_fnc_showTransientHintUi", _fnc_showTransientHint];

private _fnc_normalizeQueueItem = {
    params [["_item", [], ["", []]]];

    if (_item isEqualType "") exitWith {
        private _url = trim _item;
        if (_url isEqualTo "") exitWith {[]};
        [_url, _url]
    };

    if !(_item isEqualType []) exitWith {[]};

    private _url = trim (_item param [0, ""]);
    if (_url isEqualTo "") exitWith {[]};

    private _title = trim (_item param [1, _url]);
    if (_title isEqualTo "") then {
        _title = _url;
    };

    [_url, _title]
};

private _fnc_normalizeQueue = {
    params [["_items", [], [[]]]];

    private _normalized = [];
    private _normalizeItem = uiNamespace getVariable ["A3YT_fnc_normalizeQueueItemUi", _fnc_normalizeQueueItem];
    {
        private _entry = [_x] call _normalizeItem;
        if ((count _entry) > 0) then {
            _normalized pushBack _entry;
        };
    } forEach _items;

    _normalized
};

private _fnc_formatTime = {
    params [["_milliseconds", 0, [0]]];

    private _fnc_pad2 = {
        params [["_value", 0, [0]]];
        if (_value < 10) exitWith {format ["0%1", _value]};
        str _value
    };

    private _totalSeconds = floor ((_milliseconds max 0) / 1000);
    private _hours = floor (_totalSeconds / 3600);
    private _minutes = floor ((_totalSeconds mod 3600) / 60);
    private _seconds = _totalSeconds mod 60;

    if (_hours > 0) exitWith {
        format ["%1:%2:%3", _hours, [_minutes] call _fnc_pad2, [_seconds] call _fnc_pad2]
    };

    format ["%1:%2", [_minutes] call _fnc_pad2, [_seconds] call _fnc_pad2]
};

private _fnc_isPlaylistUrl = {
    params [["_url", "", [""]]];

    private _lower = toLower (trim _url);
    if (_lower isEqualTo "") exitWith {false};
    if ((_lower find "/playlist") >= 0) exitWith {true};
    ((_lower find "list=") >= 0) && {(_lower find "v=") < 0}
};

private _fnc_cleanupRowControls = {
    params ["_display"];

    {
        {
            if (!isNull _x) then {
                ctrlDelete _x;
            };
        } forEach _x;
    } forEach (_display getVariable ["A3YT_queueRowControls", []]);

    _display setVariable ["A3YT_queueRowControls", []];
};

private _fnc_refreshActionButtons = {
    params ["_display"];

    private _pauseCtrl = _display displayCtrl 2611909;
    private _startCtrl = _display displayCtrl 2611911;
    if (isNull _pauseCtrl || {isNull _startCtrl}) exitWith {};

    private _isPaused = missionNamespace getVariable ["A3YT_queuePaused", false];
    private _queueItems = _display getVariable ["A3YT_queueItems", []];
    private _pendingUrl = trim ctrlText (_display displayCtrl 2611901);

    _pauseCtrl ctrlSetText localize (if (_isPaused) then {"STR_A3YT_UI_RESUME_PLAYLIST"} else {"STR_A3YT_UI_PAUSE_PLAYLIST"});
    _startCtrl ctrlEnable ((count _queueItems) > 0 || {!(_pendingUrl isEqualTo "")});
};

private _fnc_getSharedState = {
    private _hasDraft = !isNil { missionNamespace getVariable "A3YT_queueDraft" };
    private _queue = if (_hasDraft) then {
        missionNamespace getVariable ["A3YT_queueDraft", missionNamespace getVariable ["A3YT_queue", []]]
    } else {
        missionNamespace getVariable ["A3YT_queue", []]
    };
    private _volume = if (_hasDraft) then {
        missionNamespace getVariable ["A3YT_queueDraftVolume", missionNamespace getVariable ["A3YT_queueVolume", 70]]
    } else {
        missionNamespace getVariable ["A3YT_queueVolume", 70]
    };
    private _notify = if (_hasDraft) then {
        missionNamespace getVariable ["A3YT_queueDraftNotify", missionNamespace getVariable ["A3YT_queueNotify", false]]
    } else {
        missionNamespace getVariable ["A3YT_queueNotify", false]
    };
    private _consumePlayed = if (_hasDraft) then {
        missionNamespace getVariable ["A3YT_queueDraftConsumePlayed", missionNamespace getVariable ["A3YT_queueConsumePlayed", false]]
    } else {
        missionNamespace getVariable ["A3YT_queueConsumePlayed", false]
    };
    private _loopQueue = if (_hasDraft) then {
        missionNamespace getVariable ["A3YT_queueDraftLoop", missionNamespace getVariable ["A3YT_queueLoop", false]]
    } else {
        missionNamespace getVariable ["A3YT_queueLoop", false]
    };

    [_queue, _volume, _notify, _consumePlayed, _loopQueue]
};

private _fnc_publishDraft = {
    params ["_display"];

    if (isNull _display) exitWith {false};

    private _queue = +(_display getVariable ["A3YT_queueItems", []]);
    private _volumeText = trim ctrlText (_display displayCtrl 2611903);
    private _volume = parseNumber _volumeText;
    if (_volumeText isEqualTo "" || {(_volume isEqualTo 0) && !(_volumeText isEqualTo "0")}) then {
        _volume = 70;
    };
    _volume = (_volume max 0) min 100;

    private _notify = cbChecked (_display displayCtrl 2611904);
    private _loopQueue = cbChecked (_display displayCtrl 2611916);
    private _consumePlayed = if (_loopQueue) then {false} else {cbChecked (_display displayCtrl 2611915)};
    private _payload = ["draft", _queue, _volume, _notify, [], _consumePlayed, _loopQueue];

    [format [
        "publishDraft queueCount=%1 volume=%2 notify=%3 consume=%4 loop=%5",
        count _queue,
        _volume,
        _notify,
        _consumePlayed,
        _loopQueue
    ]] call (uiNamespace getVariable ["A3YT_fnc_logDebugUi", {}]);

    if (isServer) then {
        ["dispatch", _payload] call A3YT_fnc_moduleYoutube;
    } else {
        ["dispatch", _payload] remoteExecCall ["A3YT_fnc_moduleYoutube", 2, false];
    };

    true
};

private _fnc_syncSharedState = {
    params ["_display"];

    if (isNull _display || {_display getVariable ["A3YT_addBusy", false]}) exitWith {};

    private _sharedState = call (uiNamespace getVariable ["A3YT_fnc_getSharedStateUi", {[[], 70, false, false, false]}]);
    private _serverQueue = +(_sharedState param [0, []]);
    _serverQueue = [_serverQueue] call (uiNamespace getVariable ["A3YT_fnc_normalizeQueueDataUi", {_this param [0, []]}]);

    private _localQueue = +(_display getVariable ["A3YT_queueItems", []]);
    if !(_localQueue isEqualTo _serverQueue) then {
        [format ["syncSharedState localCount=%1 serverCount=%2", count _localQueue, count _serverQueue]] call (uiNamespace getVariable ["A3YT_fnc_logDebugUi", {}]);
        _display setVariable ["A3YT_queueItems", _serverQueue];
        [_display] call (uiNamespace getVariable ["A3YT_fnc_refreshQueueRowsUi", {}]);
    };

    private _volumeCtrl = _display displayCtrl 2611903;
    if !(isNull _volumeCtrl) then {
        private _serverVolumeText = str (round (_sharedState param [1, 70]));
        if !(_display getVariable ["A3YT_volumeHasFocus", false]) then {
            if ((ctrlText _volumeCtrl) isNotEqualTo _serverVolumeText) then {
                _volumeCtrl ctrlSetText _serverVolumeText;
            };
        };
    };

    private _notifyCtrl = _display displayCtrl 2611904;
    if !(isNull _notifyCtrl) then {
        private _serverNotify = _sharedState param [2, false];
        if ((cbChecked _notifyCtrl) isNotEqualTo _serverNotify) then {
            _notifyCtrl cbSetChecked _serverNotify;
        };
    };

    private _consumePlayedCtrl = _display displayCtrl 2611915;
    if !(isNull _consumePlayedCtrl) then {
        private _serverConsume = _sharedState param [3, false];
        if ((cbChecked _consumePlayedCtrl) isNotEqualTo _serverConsume) then {
            _consumePlayedCtrl cbSetChecked _serverConsume;
        };
    };

    private _loopQueueCtrl = _display displayCtrl 2611916;
    if !(isNull _loopQueueCtrl) then {
        private _serverLoop = _sharedState param [4, false];
        if ((cbChecked _loopQueueCtrl) isNotEqualTo _serverLoop) then {
            _loopQueueCtrl cbSetChecked _serverLoop;
        };
    };

    [_display] call (uiNamespace getVariable ["A3YT_fnc_refreshActionButtonsUi", {}]);
};

private _fnc_unregisterSharedStateHandlers = {
    params ["_display"];
    _display setVariable ["A3YT_sharedStateHandlerIds", []];
};

private _fnc_registerSharedStateHandlers = {
    params ["_display"];

    if (uiNamespace getVariable ["A3YT_sharedStateHandlersRegistered", false]) exitWith {};

    private _handlerRefs = [];
    {
        private _varName = _x;
        private _handlerId = _varName addPublicVariableEventHandler {
            private _display = uiNamespace getVariable ["A3YT_activeYoutubeDisplay", displayNull];
            if (isNull _display) exitWith {};
            if (missionNamespace getVariable ["A3YT_debugUi", false]) then {
                diag_log format ["[A3YT][UI] publicVariableEvent %1", _this param [0, "unknown"]];
            };
            [_display] call (uiNamespace getVariable ["A3YT_fnc_syncSharedStateUi", {}]);
        };
        _handlerRefs pushBack [_varName, _handlerId];
    } forEach [
        "A3YT_queueDraft",
        "A3YT_queueDraftVolume",
        "A3YT_queueDraftNotify",
        "A3YT_queueDraftConsumePlayed",
        "A3YT_queueDraftLoop",
        "A3YT_queuePaused"
    ];

    _display setVariable ["A3YT_sharedStateHandlerIds", _handlerRefs];
    uiNamespace setVariable ["A3YT_sharedStateHandlersRegistered", true];
};

private _fnc_updateTimelineText = {
    params ["_display", ["_positionMs", 0, [0]], ["_durationMs", 0, [0]]];

    private _timelineValueCtrl = _display displayCtrl 2611913;
    if (isNull _timelineValueCtrl) exitWith {};

    _timelineValueCtrl ctrlSetText format [
        "%1 / %2",
        [_positionMs] call (uiNamespace getVariable ["A3YT_fnc_formatTimeUi", {_this param [0, "00:00"]}]),
        [_durationMs] call (uiNamespace getVariable ["A3YT_fnc_formatTimeUi", {_this param [0, "00:00"]}])
    ];
};

private _fnc_refreshQueueRows = {
    params ["_display"];

    private _queueGroup = _display displayCtrl 2611914;
    if (isNull _queueGroup) exitWith {};

    [_display] call (uiNamespace getVariable ["A3YT_fnc_cleanupQueueRowsUi", {}]);

    private _items = +(_display getVariable ["A3YT_queueItems", []]);
    private _rowControls = [];
    private _gridW = _display getVariable ["A3YT_gridW", 0.03];
    private _gridH = _display getVariable ["A3YT_gridH", 0.04];
    private _rowHeight = 0.95 * _gridH;
    private _rowSpacing = 1.05 * _gridH;
    private _baseIdc = 2620000;

    if ((count _items) isEqualTo 0) exitWith {
        private _emptyCtrl = _display ctrlCreate ["RscText", _baseIdc, _queueGroup];
        _emptyCtrl ctrlSetPosition [0.4 * _gridW, 0.2 * _gridH, 25 * _gridW, _rowHeight];
        _emptyCtrl ctrlSetText localize "STR_A3YT_HINT_QUEUE_EMPTY";
        _emptyCtrl ctrlSetBackgroundColor [0, 0, 0, 0];
        _emptyCtrl ctrlCommit 0;
        _rowControls pushBack [_emptyCtrl];
        _display setVariable ["A3YT_queueRowControls", _rowControls];
        [_display] call (uiNamespace getVariable ["A3YT_fnc_refreshActionButtonsUi", {}]);
    };

    {
        private _rowIndex = _forEachIndex;
        private _url = _x param [0, ""];
        private _title = _x param [1, _url];
        private _y = _rowIndex * _rowSpacing;
        private _rowIdc = _baseIdc + (_rowIndex * 10);

        private _bgCtrl = _display ctrlCreate ["RscText", _rowIdc, _queueGroup];
        _bgCtrl ctrlSetPosition [0, _y, 34 * _gridW, _rowHeight];
        _bgCtrl ctrlSetBackgroundColor [0, 0, 0, 0.2];
        _bgCtrl ctrlCommit 0;

        private _titleCtrl = _display ctrlCreate ["RscText", _rowIdc + 1, _queueGroup];
        _titleCtrl ctrlSetPosition [0.3 * _gridW, _y, 22.6 * _gridW, _rowHeight];
        _titleCtrl ctrlSetText format ["%1. %2", _rowIndex + 1, _title];
        _titleCtrl ctrlSetTooltip _url;
        _titleCtrl ctrlSetBackgroundColor [0, 0, 0, 0];
        _titleCtrl ctrlCommit 0;

        private _deleteCtrl = _display ctrlCreate ["RscButton", _rowIdc + 2, _queueGroup];
        _deleteCtrl ctrlSetPosition [23.2 * _gridW, _y, 3.2 * _gridW, _rowHeight];
        _deleteCtrl ctrlSetText localize "STR_A3YT_UI_DELETE";
        _deleteCtrl setVariable ["A3YT_queueIndex", _rowIndex];
        _deleteCtrl ctrlCommit 0;
        _deleteCtrl ctrlAddEventHandler ["ButtonClick", {
            private _button = _this param [0, controlNull];
            private _display = ctrlParent _button;
            if (isNull _display) exitWith {};
            [_display, _button getVariable ["A3YT_queueIndex", -1]] call (uiNamespace getVariable ["A3YT_fnc_deleteQueueItemUi", {}]);
        }];

        private _upCtrl = _display ctrlCreate ["RscButton", _rowIdc + 3, _queueGroup];
        _upCtrl ctrlSetPosition [26.7 * _gridW, _y, 3.2 * _gridW, _rowHeight];
        _upCtrl ctrlSetText localize "STR_A3YT_UI_UP";
        _upCtrl setVariable ["A3YT_queueIndex", _rowIndex];
        _upCtrl ctrlCommit 0;
        _upCtrl ctrlAddEventHandler ["ButtonClick", {
            private _button = _this param [0, controlNull];
            private _display = ctrlParent _button;
            if (isNull _display) exitWith {};
            [_display, _button getVariable ["A3YT_queueIndex", -1], -1] call (uiNamespace getVariable ["A3YT_fnc_moveQueueItemUi", {}]);
        }];

        private _downCtrl = _display ctrlCreate ["RscButton", _rowIdc + 4, _queueGroup];
        _downCtrl ctrlSetPosition [30.2 * _gridW, _y, 3.2 * _gridW, _rowHeight];
        _downCtrl ctrlSetText localize "STR_A3YT_UI_DOWN";
        _downCtrl setVariable ["A3YT_queueIndex", _rowIndex];
        _downCtrl ctrlCommit 0;
        _downCtrl ctrlAddEventHandler ["ButtonClick", {
            private _button = _this param [0, controlNull];
            private _display = ctrlParent _button;
            if (isNull _display) exitWith {};
            [_display, _button getVariable ["A3YT_queueIndex", -1], 1] call (uiNamespace getVariable ["A3YT_fnc_moveQueueItemUi", {}]);
        }];

        _rowControls pushBack [_bgCtrl, _titleCtrl, _deleteCtrl, _upCtrl, _downCtrl];
    } forEach _items;

    _display setVariable ["A3YT_queueRowControls", _rowControls];
    [_display] call (uiNamespace getVariable ["A3YT_fnc_refreshActionButtonsUi", {}]);
};

private _fnc_deleteQueueItem = {
    params ["_display", ["_index", -1, [0]]];

    private _items = +(_display getVariable ["A3YT_queueItems", []]);
    if (_index < 0 || {_index >= count _items}) exitWith {};

    _items deleteAt _index;
    _display setVariable ["A3YT_queueItems", _items];
    [format ["deleteQueueItem index=%1 newCount=%2", _index, count _items]] call (uiNamespace getVariable ["A3YT_fnc_logDebugUi", {}]);
    [_display] call (uiNamespace getVariable ["A3YT_fnc_refreshQueueRowsUi", {}]);
    [_display] call (uiNamespace getVariable ["A3YT_fnc_publishDraftUi", {false}]);
};

private _fnc_moveQueueItem = {
    params ["_display", ["_index", -1, [0]], ["_direction", 0, [0]]];

    private _items = +(_display getVariable ["A3YT_queueItems", []]);
    private _target = _index + _direction;
    if (_index < 0 || {_target < 0} || {_index >= count _items} || {_target >= count _items}) exitWith {};

    private _current = _items param [_index, []];
    private _other = _items param [_target, []];
    _items set [_index, _other];
    _items set [_target, _current];

    _display setVariable ["A3YT_queueItems", _items];
    [format ["moveQueueItem index=%1 target=%2 count=%3", _index, _target, count _items]] call (uiNamespace getVariable ["A3YT_fnc_logDebugUi", {}]);
    [_display] call (uiNamespace getVariable ["A3YT_fnc_refreshQueueRowsUi", {}]);
    [_display] call (uiNamespace getVariable ["A3YT_fnc_publishDraftUi", {false}]);
};

private _fnc_dispatchAction = {
    params [
        ["_display", displayNull, [displayNull]],
        ["_action", "apply", [""]],
        ["_extra", [], [[], 0]]
    ];

    if (isNull _display) exitWith {false};

    private _queue = +(_display getVariable ["A3YT_queueItems", []]);
    private _volumeText = trim ctrlText (_display displayCtrl 2611903);
    private _volume = parseNumber _volumeText;
    if (_volumeText isEqualTo "" || {(_volume isEqualTo 0) && !(_volumeText isEqualTo "0")}) then {
        _volume = 70;
    };
    _volume = (_volume max 0) min 100;

    private _notify = cbChecked (_display displayCtrl 2611904);
    private _loopQueue = cbChecked (_display displayCtrl 2611916);
    private _consumePlayed = if (_loopQueue) then {false} else {cbChecked (_display displayCtrl 2611915)};
    private _payload = [_action, _queue, _volume, _notify, _extra, _consumePlayed, _loopQueue];

    [format [
        "dispatch action=%1 queueCount=%2 volume=%3 notify=%4 consume=%5 loop=%6 extra=%7",
        _action,
        count _queue,
        _volume,
        _notify,
        _consumePlayed,
        _loopQueue,
        _extra
    ]] call (uiNamespace getVariable ["A3YT_fnc_logDebugUi", {}]);

    if (isServer) then {
        ["dispatch", _payload] call A3YT_fnc_moduleYoutube;
    } else {
        ["dispatch", _payload] remoteExecCall ["A3YT_fnc_moduleYoutube", 2, false];
    };

    true
};

private _fnc_applyLiveVolume = {
    params ["_display"];

    if (isNull _display) exitWith {false};

    private _timelineState = _display getVariable ["A3YT_lastTimelineState", "idle"];
    private _activeQueue = missionNamespace getVariable ["A3YT_queue", []];
    if ((count _activeQueue) isEqualTo 0 && !(_timelineState in ["playing", "paused", "resolving"])) exitWith {false};

    [_display, "volume", []] call (uiNamespace getVariable ["A3YT_fnc_dispatchQueueActionUi", {false}]);
};

private _fnc_scheduleLiveVolume = {
    params ["_display", ["_delay", 0.35, [0]]];

    if (isNull _display) exitWith {false};

    private _token = (_display getVariable ["A3YT_volumeDebounceToken", 0]) + 1;
    _display setVariable ["A3YT_volumeDebounceToken", _token];

    [_display, _token, _delay] spawn {
        params ["_display", "_token", "_delay"];

        sleep _delay;
        if (isNull _display) exitWith {};
        if !(_display getVariable ["A3YT_uiAlive", false]) exitWith {};
        if ((_display getVariable ["A3YT_volumeDebounceToken", -1]) isNotEqualTo _token) exitWith {};

        [_display] call (uiNamespace getVariable ["A3YT_fnc_applyLiveVolumeUi", {false}]);
    };

    true
};

private _fnc_addUrl = {
    params [
        ["_display", displayNull, [displayNull]],
        ["_explicitUrl", "", [""]],
        ["_clearUrlCtrl", true, [true]]
    ];

    if (isNull _display) exitWith {false};
    if (_display getVariable ["A3YT_addBusy", false]) exitWith {false};

    private _urlCtrl = _display displayCtrl 2611901;
    private _addCtrl = _display displayCtrl 2611902;
    private _rawUrl = trim (if (_explicitUrl isEqualTo "") then {ctrlText _urlCtrl} else {_explicitUrl});
    [format ["addUrl clicked rawUrl=%1", _rawUrl]] call (uiNamespace getVariable ["A3YT_fnc_logDebugUi", {}]);
    if (_rawUrl isEqualTo "") exitWith {
        ["addUrl aborted empty url"] call (uiNamespace getVariable ["A3YT_fnc_logDebugUi", {}]);
        [localize "STR_A3YT_HINT_URL_REQUIRED", 3] call (uiNamespace getVariable ["A3YT_fnc_showTransientHintUi", {}]);
        false
    };

    _display setVariable ["A3YT_addBusy", true];
    if !(isNull _addCtrl) then {
        _addCtrl ctrlEnable false;
    };

    private _items = +(_display getVariable ["A3YT_queueItems", []]);
    private _added = false;
    [format ["addUrl initialQueueCount=%1", count _items]] call (uiNamespace getVariable ["A3YT_fnc_logDebugUi", {}]);

    if ([_rawUrl] call (uiNamespace getVariable ["A3YT_fnc_isPlaylistUrlUi", {false}])) then {
        private _playlistResponse = ["playlistload", [_rawUrl]] call A3YT_fnc_callExtension;
        private _playlistMessage = _playlistResponse param [0, "err|no_response"];
        private _playlistParts = _playlistMessage splitString "|";
        [format ["addUrl playlistload response=%1", _playlistMessage]] call (uiNamespace getVariable ["A3YT_fnc_logDebugUi", {}]);

        if ((_playlistParts param [0, "err"]) isNotEqualTo "ok" || {(_playlistParts param [1, ""]) isNotEqualTo "playlistload"}) exitWith {
            [format [localize "STR_A3YT_HINT_PLAYLIST_FAILED", _playlistParts param [2, _playlistMessage]], 5] call (uiNamespace getVariable ["A3YT_fnc_showTransientHintUi", {}]);
            _display setVariable ["A3YT_addBusy", false];
            if !(isNull _addCtrl) then {
                _addCtrl ctrlEnable true;
            };
            false
        };

        private _token = parseNumber (_playlistParts param [2, "0"]);
        private _count = parseNumber (_playlistParts param [3, "0"]);
        private _addedCount = 0;

        for "_index" from 0 to (_count - 1) do {
            private _itemResponse = ["playlistitem", [str _token, str _index]] call A3YT_fnc_callExtension;
            private _itemMessage = _itemResponse param [0, "err|no_response"];
            private _itemParts = _itemMessage splitString "|";
            if ((_itemParts param [0, "err"]) isEqualTo "ok" && {(_itemParts param [1, ""]) isEqualTo "playlistitem"}) then {
                private _url = trim (_itemParts param [2, ""]);
                if !(_url isEqualTo "") then {
                    private _title = trim (_itemParts param [3, _url]);
                    if (_title isEqualTo "") then {
                        _title = _url;
                    };

                    _items pushBack [_url, _title];
                    _addedCount = _addedCount + 1;
                };
            };
        };

        if (_addedCount > 0) then {
            _added = true;
            [format ["addUrl playlist addedCount=%1", _addedCount]] call (uiNamespace getVariable ["A3YT_fnc_logDebugUi", {}]);
            [format [localize "STR_A3YT_HINT_PLAYLIST_ADDED", _addedCount], 4] call (uiNamespace getVariable ["A3YT_fnc_showTransientHintUi", {}]);
        } else {
            ["addUrl playlist no items returned"] call (uiNamespace getVariable ["A3YT_fnc_logDebugUi", {}]);
            [format [localize "STR_A3YT_HINT_PLAYLIST_FAILED", "empty playlist response"], 5] call (uiNamespace getVariable ["A3YT_fnc_showTransientHintUi", {}]);
        };
    } else {
        private _title = _rawUrl;
        private _titleResponse = ["title", [_rawUrl]] call A3YT_fnc_callExtension;
        private _titleMessage = _titleResponse param [0, "err|no_response"];
        private _titleParts = _titleMessage splitString "|";
        [format ["addUrl title response=%1", _titleMessage]] call (uiNamespace getVariable ["A3YT_fnc_logDebugUi", {}]);
        if ((_titleParts param [0, "err"]) isEqualTo "ok" && {(_titleParts param [1, ""]) isEqualTo "title"}) then {
            _title = _titleParts param [2, _rawUrl];
        };

        _items pushBack [_rawUrl, _title];
        _added = true;
        [format ["addUrl single pushed title=%1 newCount=%2", _title, count _items]] call (uiNamespace getVariable ["A3YT_fnc_logDebugUi", {}]);
    };

    if (_added) then {
        _display setVariable ["A3YT_queueItems", _items];
        [_display] call (uiNamespace getVariable ["A3YT_fnc_refreshQueueRowsUi", {}]);
        if (_clearUrlCtrl) then {
            _urlCtrl ctrlSetText "";
        };
        diag_log format ["[A3YT] ui_add_success queueCount=%1 url=%2", count _items, _rawUrl];
        [_display] call (uiNamespace getVariable ["A3YT_fnc_publishDraftUi", {false}]);
    } else {
        diag_log format ["[A3YT] ui_add_noop url=%1", _rawUrl];
    };

    _display setVariable ["A3YT_addBusy", false];
    if !(isNull _addCtrl) then {
        _addCtrl ctrlEnable true;
    };

    _added
};

private _fnc_startQueue = {
    params ["_display"];

    if (isNull _display) exitWith {false};

    private _pendingUrl = trim ctrlText (_display displayCtrl 2611901);
    if !(_pendingUrl isEqualTo "") then {
        private _added = [_display, _pendingUrl, true] call (uiNamespace getVariable ["A3YT_fnc_addQueueItemUi", {false}]);
        if (!_added) exitWith {false};
    };

    private _queue = +(_display getVariable ["A3YT_queueItems", []]);
    if ((count _queue) isEqualTo 0) exitWith {
        hint localize "STR_A3YT_HINT_QUEUE_EMPTY";
        false
    };

    diag_log format ["[A3YT] ui_start queueCount=%1 volumeText=%2 notify=%3", count _queue, ctrlText (_display displayCtrl 2611903), cbChecked (_display displayCtrl 2611904)];
    [_display, "apply", []] call (uiNamespace getVariable ["A3YT_fnc_dispatchQueueActionUi", {false}]);
};

private _fnc_syncTimeline = {
    params ["_display"];

    if (isNull _display) exitWith {};

    private _timelineSlider = _display displayCtrl 2611912;
    if (isNull _timelineSlider) exitWith {};

    private _timelineResponse = ["timeline", []] call A3YT_fnc_callExtension;
    private _timelineMessage = _timelineResponse param [0, "err|no_response"];
    private _timelineParts = _timelineMessage splitString "|";
    if ((_timelineParts param [0, "err"]) isNotEqualTo "ok" || {(_timelineParts param [1, ""]) isNotEqualTo "timeline"}) exitWith {};

    private _state = _timelineParts param [2, "idle"];
    private _positionMs = round (parseNumber (_timelineParts param [3, "0"]));
    private _durationMs = round (parseNumber (_timelineParts param [4, "0"]));
    _positionMs = _positionMs max 0;
    _durationMs = _durationMs max 0;

    _display setVariable ["A3YT_lastTimelineState", _state];
    _display setVariable ["A3YT_lastTimelineDuration", _durationMs];

    _timelineSlider ctrlEnable (_durationMs > 0);
    _timelineSlider sliderSetRange [0, (_durationMs max 1)];

    if !(_display getVariable ["A3YT_sliderDragging", false]) then {
        _timelineSlider sliderSetPosition (_positionMs min (_durationMs max 1));
    };

    private _shownPosition = if (_display getVariable ["A3YT_sliderDragging", false]) then {
        round sliderPosition _timelineSlider
    } else {
        _positionMs
    };

    [_display, _shownPosition, _durationMs] call (uiNamespace getVariable ["A3YT_fnc_updateTimelineTextUi", {}]);
    [_display] call (uiNamespace getVariable ["A3YT_fnc_refreshActionButtonsUi", {}]);
};

private _fnc_onUnload = {
    params ["_displayOrControl"];

    private _display = _displayOrControl;
    if (_displayOrControl isEqualType controlNull) then {
        _display = ctrlParent _displayOrControl;
    };

    if (!isNull _display) then {
        _display setVariable ["A3YT_uiAlive", false];
        [_display] call (uiNamespace getVariable ["A3YT_fnc_unregisterSharedStateHandlersUi", {}]);
        if ((uiNamespace getVariable ["A3YT_activeYoutubeDisplay", displayNull]) isEqualTo _display) then {
            uiNamespace setVariable ["A3YT_activeYoutubeDisplay", displayNull];
        };
    };

    private _logic = missionNamespace getVariable ["BIS_fnc_initCuratorAttributes_target", objNull];
    if (!isNull _logic) then {
        deleteVehicle _logic;
    };

    missionNamespace setVariable ["BIS_fnc_initCuratorAttributes_target", objNull];
};

uiNamespace setVariable ["A3YT_fnc_normalizeQueueItemUi", _fnc_normalizeQueueItem];
uiNamespace setVariable ["A3YT_fnc_normalizeQueueDataUi", _fnc_normalizeQueue];
uiNamespace setVariable ["A3YT_fnc_formatTimeUi", _fnc_formatTime];
uiNamespace setVariable ["A3YT_fnc_isPlaylistUrlUi", _fnc_isPlaylistUrl];
uiNamespace setVariable ["A3YT_fnc_cleanupQueueRowsUi", _fnc_cleanupRowControls];
uiNamespace setVariable ["A3YT_fnc_refreshActionButtonsUi", _fnc_refreshActionButtons];
uiNamespace setVariable ["A3YT_fnc_getSharedStateUi", _fnc_getSharedState];
uiNamespace setVariable ["A3YT_fnc_publishDraftUi", _fnc_publishDraft];
uiNamespace setVariable ["A3YT_fnc_syncSharedStateUi", _fnc_syncSharedState];
uiNamespace setVariable ["A3YT_fnc_unregisterSharedStateHandlersUi", _fnc_unregisterSharedStateHandlers];
uiNamespace setVariable ["A3YT_fnc_registerSharedStateHandlersUi", _fnc_registerSharedStateHandlers];
uiNamespace setVariable ["A3YT_fnc_updateTimelineTextUi", _fnc_updateTimelineText];
uiNamespace setVariable ["A3YT_fnc_refreshQueueRowsUi", _fnc_refreshQueueRows];
uiNamespace setVariable ["A3YT_fnc_deleteQueueItemUi", _fnc_deleteQueueItem];
uiNamespace setVariable ["A3YT_fnc_moveQueueItemUi", _fnc_moveQueueItem];
uiNamespace setVariable ["A3YT_fnc_dispatchQueueActionUi", _fnc_dispatchAction];
uiNamespace setVariable ["A3YT_fnc_applyLiveVolumeUi", _fnc_applyLiveVolume];
uiNamespace setVariable ["A3YT_fnc_scheduleLiveVolumeUi", _fnc_scheduleLiveVolume];
uiNamespace setVariable ["A3YT_fnc_addQueueItemUi", _fnc_addUrl];
uiNamespace setVariable ["A3YT_fnc_startQueueUi", _fnc_startQueue];
uiNamespace setVariable ["A3YT_fnc_syncTimelineUi", _fnc_syncTimeline];

private _sharedState = call _fnc_getSharedState;
private _currentQueue = [+(_sharedState param [0, []])] call _fnc_normalizeQueue;
[format [
    "init sharedQueueCount=%1 volume=%2 notify=%3 consume=%4 loop=%5",
    count _currentQueue,
    _sharedState param [1, 70],
    _sharedState param [2, false],
    _sharedState param [3, false],
    _sharedState param [4, false]
]] call (uiNamespace getVariable ["A3YT_fnc_logDebugUi", {}]);
_display setVariable ["A3YT_gridW", _gridW];
_display setVariable ["A3YT_gridH", _gridH];
_display setVariable ["A3YT_queueItems", _currentQueue];
_display setVariable ["A3YT_queueRowControls", []];
_display setVariable ["A3YT_sliderDragging", false];
_display setVariable ["A3YT_lastTimelineDuration", 0];
_display setVariable ["A3YT_uiAlive", true];
_display setVariable ["A3YT_addBusy", false];
_display setVariable ["A3YT_sharedStateHandlerIds", []];
_display setVariable ["A3YT_volumeHasFocus", false];
_display setVariable ["A3YT_volumeDebounceToken", 0];

uiNamespace setVariable ["A3YT_activeYoutubeDisplay", _display];

_urlCtrl ctrlSetText "";
_volumeCtrl ctrlSetText str (_sharedState param [1, 70]);
_notifyCtrl cbSetChecked (_sharedState param [2, false]);
_consumePlayedCtrl cbSetChecked (_sharedState param [3, false]);
_loopQueueCtrl cbSetChecked (_sharedState param [4, false]);

_timelineSlider sliderSetRange [0, 1];
_timelineSlider sliderSetPosition 0;
_timelineSlider ctrlEnable false;
[_display, 0, 0] call _fnc_updateTimelineText;

_display displayAddEventHandler ["Unload", _fnc_onUnload];

_addCtrl ctrlAddEventHandler ["ButtonClick", {
    private _button = _this param [0, controlNull];
    private _display = ctrlParent _button;
    if (isNull _display) exitWith {};
    [_display, "", true] call (uiNamespace getVariable ["A3YT_fnc_addQueueItemUi", {false}]);
}];

_startCtrl ctrlAddEventHandler ["ButtonClick", {
    private _button = _this param [0, controlNull];
    private _display = ctrlParent _button;
    if (isNull _display) exitWith {};
    [_display] call (uiNamespace getVariable ["A3YT_fnc_startQueueUi", {false}]);
}];

_pauseCtrl ctrlAddEventHandler ["ButtonClick", {
    private _button = _this param [0, controlNull];
    private _display = ctrlParent _button;
    if (isNull _display) exitWith {};
    private _action = if (missionNamespace getVariable ["A3YT_queuePaused", false]) then {"resume"} else {"pause"};
    [_display, _action, []] call (uiNamespace getVariable ["A3YT_fnc_dispatchQueueActionUi", {false}]);
}];

_stopCtrl ctrlAddEventHandler ["ButtonClick", {
    private _button = _this param [0, controlNull];
    private _display = ctrlParent _button;
    if (isNull _display) exitWith {};
    [_display, "stop", []] call (uiNamespace getVariable ["A3YT_fnc_dispatchQueueActionUi", {false}]);
}];

_timelineSlider ctrlAddEventHandler ["MouseButtonDown", {
    private _slider = _this param [0, controlNull];
    private _display = ctrlParent _slider;
    if (isNull _display) exitWith {};
    _display setVariable ["A3YT_sliderDragging", true];
}];

_timelineSlider ctrlAddEventHandler ["MouseButtonUp", {
    private _slider = _this param [0, controlNull];
    private _display = ctrlParent _slider;
    if (isNull _display) exitWith {};

    _display setVariable ["A3YT_sliderDragging", false];
    private _durationMs = _display getVariable ["A3YT_lastTimelineDuration", 0];
    if (_durationMs <= 0) exitWith {};

    private _seekMs = round sliderPosition _slider;
    [_display, "seek", _seekMs] call (uiNamespace getVariable ["A3YT_fnc_dispatchQueueActionUi", {false}]);
    [_display] call (uiNamespace getVariable ["A3YT_fnc_syncTimelineUi", {}]);
}];

_timelineSlider ctrlAddEventHandler ["SliderPosChanged", {
    params ["_slider", "_position"];
    private _display = ctrlParent _slider;
    if (isNull _display || {!(_display getVariable ["A3YT_sliderDragging", false])}) exitWith {};
    private _durationMs = _display getVariable ["A3YT_lastTimelineDuration", 0];
    [_display, round _position, _durationMs] call (uiNamespace getVariable ["A3YT_fnc_updateTimelineTextUi", {}]);
}];

_volumeCtrl ctrlAddEventHandler ["SetFocus", {
    private _ctrl = _this param [0, controlNull];
    private _display = ctrlParent _ctrl;
    if (isNull _display) exitWith {};
    _display setVariable ["A3YT_volumeHasFocus", true];
}];

_volumeCtrl ctrlAddEventHandler ["KillFocus", {
    private _ctrl = _this param [0, controlNull];
    private _display = ctrlParent _ctrl;
    if (isNull _display) exitWith {};
    _display setVariable ["A3YT_volumeHasFocus", false];
    _display setVariable ["A3YT_volumeDebounceToken", (_display getVariable ["A3YT_volumeDebounceToken", 0]) + 1];
    [_display] call (uiNamespace getVariable ["A3YT_fnc_publishDraftUi", {false}]);
    [_display] call (uiNamespace getVariable ["A3YT_fnc_applyLiveVolumeUi", {false}]);
    [_display] call (uiNamespace getVariable ["A3YT_fnc_syncSharedStateUi", {}]);
}];

_volumeCtrl ctrlAddEventHandler ["KeyUp", {
    private _ctrl = _this param [0, controlNull];
    private _display = ctrlParent _ctrl;
    if (isNull _display) exitWith {};
    [_display] call (uiNamespace getVariable ["A3YT_fnc_publishDraftUi", {false}]);
    [_display, 0.35] call (uiNamespace getVariable ["A3YT_fnc_scheduleLiveVolumeUi", {false}]);
}];

_notifyCtrl ctrlAddEventHandler ["CheckedChanged", {
    private _ctrl = _this param [0, controlNull];
    private _display = ctrlParent _ctrl;
    if (isNull _display) exitWith {};
    [_display] call (uiNamespace getVariable ["A3YT_fnc_publishDraftUi", {false}]);
}];

_consumePlayedCtrl ctrlAddEventHandler ["CheckedChanged", {
    private _ctrl = _this param [0, controlNull];
    private _display = ctrlParent _ctrl;
    if (isNull _display) exitWith {};
    private _loopCtrl = _display displayCtrl 2611916;
    if ((_this param [1, 0]) > 0 && {!isNull _loopCtrl} && {cbChecked _loopCtrl}) then {
        _loopCtrl cbSetChecked false;
    };
    [_display] call (uiNamespace getVariable ["A3YT_fnc_publishDraftUi", {false}]);
}];

_loopQueueCtrl ctrlAddEventHandler ["CheckedChanged", {
    private _ctrl = _this param [0, controlNull];
    private _display = ctrlParent _ctrl;
    if (isNull _display) exitWith {};
    private _consumeCtrl = _display displayCtrl 2611915;
    if ((_this param [1, 0]) > 0 && {!isNull _consumeCtrl} && {cbChecked _consumeCtrl}) then {
        _consumeCtrl cbSetChecked false;
    };
    [_display] call (uiNamespace getVariable ["A3YT_fnc_publishDraftUi", {false}]);
}];

_urlCtrl ctrlAddEventHandler ["KeyUp", {
    private _ctrl = _this param [0, controlNull];
    private _display = ctrlParent _ctrl;
    if (isNull _display) exitWith {};
    [_display] call (uiNamespace getVariable ["A3YT_fnc_refreshActionButtonsUi", {}]);
}];

[_display] call _fnc_refreshQueueRows;
[_display] call _fnc_refreshActionButtons;
[_display] call _fnc_syncSharedState;
[_display] call _fnc_registerSharedStateHandlers;
[_display] call _fnc_syncTimeline;

[_display] spawn {
    params ["_display"];

    while {!isNull _display && {_display getVariable ["A3YT_uiAlive", false]}} do {
        [_display] call (uiNamespace getVariable ["A3YT_fnc_syncTimelineUi", {}]);
        sleep 0.15;
    };
};
