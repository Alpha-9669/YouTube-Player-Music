private _logic = objNull;
private _units = [];
private _activated = true;
private _hasDirectDispatch = false;
private _directAction = "apply";
private _directQueue = [];
private _directVolume = 70;
private _directNotify = true;
private _directExtra = [];
private _directConsumePlayed = false;
private _directLoopQueue = false;

if ((_this isEqualType []) && {(count _this) > 0}) then {
    private _first = _this param [0, objNull];

    if (_first isEqualType "") then {
        private _mode = toLower _first;
        private _input = _this param [1, []];

        switch (_mode) do {
            case "dispatch": {
                _hasDirectDispatch = true;
                _directAction = toLower (_input param [0, "apply"]);
                _directQueue = _input param [1, [], [[]]];
                _directVolume = _input param [2, 70, [0]];
                _directNotify = _input param [3, true, [true]];
                _directExtra = _input param [4, []];
                _directConsumePlayed = _input param [5, missionNamespace getVariable ["A3YT_queueConsumePlayed", false], [true]];
                _directLoopQueue = _input param [6, missionNamespace getVariable ["A3YT_queueLoop", false], [true]];
            };

            case "init": {
                if (_input isEqualType [] && {(count _input) > 0}) then {
                    _logic = _input param [0, objNull];
                    _activated = _input param [1, true];
                };
            };

            default {
                _logic = _input param [0, objNull];
            };
        };
    } else {
        _logic = _this param [0, objNull];
        _units = _this param [1, []];
        _activated = _this param [2, true];
    };
};

if (!_hasDirectDispatch && {isNull _logic}) exitWith {
    diag_log format ["[A3YT] Module called without logic. _this=%1", _this];
};

if (!_activated) exitWith {};

// Direct queue controls are authoritative on the server.  Reject remote
// control commands from clients that do not currently own a curator logic.
// Progress reports remain accepted from playback clients and are guarded by
// the queue generation/monotonic consumed counter below.
private _authorizedDispatch = true;
private _dispatchOwner = if (!isNil "remoteExecutedOwner" && {remoteExecutedOwner > 0}) then {remoteExecutedOwner} else {clientOwner};
if (_hasDirectDispatch && {isServer} && {_directAction isNotEqualTo "progress"} && {!isNil "remoteExecutedOwner"} && {remoteExecutedOwner > 2}) then {
    private _requestOwner = remoteExecutedOwner;
    private _requestPlayer = objNull;
    {
        if ((owner _x) isEqualTo _requestOwner) exitWith {
            _requestPlayer = _x;
        };
    } forEach allPlayers;

    _authorizedDispatch = !isNull _requestPlayer && {!isNull (getAssignedCuratorLogic _requestPlayer)};
};

if (_hasDirectDispatch && {isServer} && {_directAction isEqualTo "progress"}) then {
    private _controllerOwner = missionNamespace getVariable ["A3YT_queueControllerOwner", -1];
    if (_controllerOwner >= 0 && {_dispatchOwner isNotEqualTo _controllerOwner}) then {
        _authorizedDispatch = false;
    };
};

if (!_authorizedDispatch) exitWith {
    diag_log format ["[A3YT] rejected unauthorized dispatch owner=%1 action=%2", _dispatchOwner, _directAction];
};

if (_hasDirectDispatch && {isServer} && {_directAction in ["draft", "apply"]}) then {
    missionNamespace setVariable ["A3YT_queueControllerOwner", _dispatchOwner];
};

private _fnc_normalizeQueueItem = {
    params [["_item", [], ["", []]]];

    if (_item isEqualType "") exitWith {
        private _url = trim _item;
        if (_url isEqualTo "") exitWith {[]};
        [_url, _url]
    };

    if !(_item isEqualType []) exitWith {[]};

    private _url = trim (_item param [0, "", [""]]);
    if (_url isEqualTo "") exitWith {[]};

    private _title = trim (_item param [1, _url, [""]]);
    if (_title isEqualTo "") then {
        _title = _url;
    };

    [_url, _title]
};

private _fnc_normalizeQueue = {
    params [["_items", [], [[]]]];

    private _normalized = [];
    {
        private _entry = [_x] call _fnc_normalizeQueueItem;
        if ((count _entry) > 0) then {
            _normalized pushBack _entry;
        };
    } forEach _items;

    _normalized
};

private _currentQueue = +(missionNamespace getVariable ["A3YT_queue", []]);
_currentQueue = [_currentQueue] call _fnc_normalizeQueue;

private _queue = if (_hasDirectDispatch) then {
    [_directQueue] call _fnc_normalizeQueue
} else {
    [(_logic getVariable ["Queue", missionNamespace getVariable ["A3YT_queue", []]])] call _fnc_normalizeQueue
};

private _volume = if (_hasDirectDispatch) then {
    round _directVolume
} else {
    round (_logic getVariable ["Volume", 70])
};

private _notify = if (_hasDirectDispatch) then {
    _directNotify
} else {
    _logic getVariable ["Notify", true]
};

private _action = if (_hasDirectDispatch) then {
    _directAction
} else {
    toLower (_logic getVariable ["Action", "apply"])
};

private _consumePlayed = if (_hasDirectDispatch) then {
    _directConsumePlayed
} else {
    missionNamespace getVariable ["A3YT_queueConsumePlayed", false]
};

private _loopQueue = if (_hasDirectDispatch) then {
    _directLoopQueue
} else {
    missionNamespace getVariable ["A3YT_queueLoop", false]
};

if (_loopQueue) then {
    _consumePlayed = false;
};

private _clampedVolume = (_volume max 0) min 100;
private _currentGeneration = missionNamespace getVariable ["A3YT_queueGeneration", 0];
private _currentPaused = missionNamespace getVariable ["A3YT_queuePaused", false];
private _currentConsumedCount = missionNamespace getVariable ["A3YT_queueConsumedCount", 0];

private _fnc_storeDraft = {
    params ["_queueDraft", "_volumeDraft", "_notifyDraft", "_consumeDraft", "_loopDraft"];

    missionNamespace setVariable ["A3YT_queueDraft", _queueDraft, true];
    missionNamespace setVariable ["A3YT_queueDraftVolume", _volumeDraft, true];
    missionNamespace setVariable ["A3YT_queueDraftNotify", _notifyDraft, true];
    missionNamespace setVariable ["A3YT_queueDraftConsumePlayed", _consumeDraft, true];
    missionNamespace setVariable ["A3YT_queueDraftLoop", _loopDraft, true];

    if (missionNamespace getVariable ["A3YT_debugUi", false]) then {
        diag_log format [
            "[A3YT][SERVER] storeDraft queueCount=%1 volume=%2 notify=%3 consume=%4 loop=%5",
            count _queueDraft,
            _volumeDraft,
            _notifyDraft,
            _consumeDraft,
            _loopDraft
        ];
    };
};

private _fnc_getQueueHeadUrl = {
    params [["_items", [], [[]]]];

    if ((count _items) isEqualTo 0) exitWith {""};

    private _entry = [_items param [0, []]] call _fnc_normalizeQueueItem;
    trim (_entry param [0, ""])
};

private _fnc_prefetchHead = {
    params [["_items", [], [[]]], ["_force", false, [true]]];

    private _headUrl = [_items] call _fnc_getQueueHeadUrl;
    private _lastHeadUrl = missionNamespace getVariable ["A3YT_queuePrefetchHead", ""];
    if (!_force && {_headUrl isEqualTo _lastHeadUrl}) exitWith {};

    missionNamespace setVariable ["A3YT_queuePrefetchHead", _headUrl];
    if (_headUrl isEqualTo "") exitWith {};

    ["prefetch", _headUrl] remoteExec ["A3YT_fnc_handleLocalPlayback", 0, false];
};

diag_log format [
    "[A3YT] module_dispatch direct=%1 action=%2 queueCount=%3 volume=%4 notify=%5 consumePlayed=%6 loop=%7 currentQueueCount=%8 consumed=%9",
    _hasDirectDispatch,
    _action,
    count _queue,
    _clampedVolume,
    _notify,
    _consumePlayed,
    _loopQueue,
    count _currentQueue,
    _currentConsumedCount
];

private _canHotUpdate = false;
if (_action isEqualTo "apply" && {(count _currentQueue) > 0} && {(count _queue) >= (count _currentQueue)}) then {
    _canHotUpdate = true;
    for "_index" from 0 to ((count _currentQueue) - 1) do {
        private _existing = _currentQueue param [_index, []];
        private _incoming = _queue param [_index, []];
        if ((_existing param [0, ""]) isNotEqualTo (_incoming param [0, ""])) exitWith {
            _canHotUpdate = false;
        };
    };
};

switch (_action) do {
    case "pause": {
        missionNamespace setVariable ["A3YT_queuePaused", true, true];
        ["pause", _notify, _currentGeneration] remoteExec ["A3YT_fnc_handleLocalPlayback", 0, false];
    };

    case "resume": {
        missionNamespace setVariable ["A3YT_queuePaused", false, true];
        ["resume", _notify, _currentGeneration] remoteExec ["A3YT_fnc_handleLocalPlayback", 0, false];
    };

    case "volume": {
        missionNamespace setVariable ["A3YT_queueVolume", _clampedVolume, true];
        missionNamespace setVariable ["A3YT_queueDraftVolume", _clampedVolume, true];
        ["volume", _clampedVolume, _currentGeneration] remoteExec ["A3YT_fnc_handleLocalPlayback", 0, false];
    };

    case "stop": {
        private _generation = _currentGeneration + 1;
        missionNamespace setVariable ["A3YT_queue", [], true];
        missionNamespace setVariable ["A3YT_queueVolume", _clampedVolume, true];
        missionNamespace setVariable ["A3YT_queueNotify", _notify, true];
        missionNamespace setVariable ["A3YT_queueConsumePlayed", _consumePlayed, true];
        missionNamespace setVariable ["A3YT_queueLoop", _loopQueue, true];
        missionNamespace setVariable ["A3YT_queueConsumedCount", 0, true];
        missionNamespace setVariable ["A3YT_queuePaused", false, true];
        missionNamespace setVariable ["A3YT_queueGeneration", _generation, true];
        missionNamespace setVariable ["A3YT_queuePrefetchHead", ""];
        [[], _clampedVolume, _notify, _consumePlayed, _loopQueue] call _fnc_storeDraft;
        ["stop", _notify, _generation] remoteExec ["A3YT_fnc_handleLocalPlayback", 0, false];
    };

    case "draft": {
        [_queue, _clampedVolume, _notify, _consumePlayed, _loopQueue] call _fnc_storeDraft;
        [_queue, false] call _fnc_prefetchHead;
    };

    case "progress": {
        if (_consumePlayed && {_directExtra isEqualType []} && {(count _directExtra) >= 2}) then {
            private _absoluteConsumed = round (_directExtra param [0, _currentConsumedCount, [0]]);
            private _progressGeneration = round (_directExtra param [1, _currentGeneration, [0]]);

            if (_progressGeneration isEqualTo _currentGeneration && {_absoluteConsumed > _currentConsumedCount}) then {
                private _delta = _absoluteConsumed - _currentConsumedCount;
                if (_delta > 0) then {
                    private _trimmedQueue = +_currentQueue;
                    _delta = _delta min (count _trimmedQueue);
                    _trimmedQueue = _trimmedQueue select [_delta];

                    missionNamespace setVariable ["A3YT_queue", _trimmedQueue, true];
                    missionNamespace setVariable ["A3YT_queueConsumedCount", _absoluteConsumed, true];
                    [
                        _trimmedQueue,
                        missionNamespace getVariable ["A3YT_queueVolume", _clampedVolume],
                        missionNamespace getVariable ["A3YT_queueNotify", _notify],
                        missionNamespace getVariable ["A3YT_queueConsumePlayed", _consumePlayed],
                        missionNamespace getVariable ["A3YT_queueLoop", _loopQueue]
                    ] call _fnc_storeDraft;

                    diag_log format ["[A3YT] queue_progress generation=%1 absoluteConsumed=%2 delta=%3 remaining=%4", _currentGeneration, _absoluteConsumed, _delta, count _trimmedQueue];
                };
            };
        };
    };

    case "seek": {
        private _seekMs = _directExtra;
        if !(_seekMs isEqualType 0) then {
            _seekMs = parseNumber str _seekMs;
        };

        _seekMs = round (_seekMs max 0);
        ["seek", _seekMs, _currentGeneration] remoteExec ["A3YT_fnc_handleLocalPlayback", 0, false];
    };

    default {
        if (_canHotUpdate) then {
            missionNamespace setVariable ["A3YT_queue", _queue, true];
            missionNamespace setVariable ["A3YT_queueVolume", _clampedVolume, true];
            missionNamespace setVariable ["A3YT_queueNotify", _notify, true];
            missionNamespace setVariable ["A3YT_queueConsumePlayed", _consumePlayed, true];
            missionNamespace setVariable ["A3YT_queueLoop", _loopQueue, true];
            missionNamespace setVariable ["A3YT_queuePaused", _currentPaused, true];
            [_queue, _clampedVolume, _notify, _consumePlayed, _loopQueue] call _fnc_storeDraft;
            [_queue, false] call _fnc_prefetchHead;
            ["update", _queue, _clampedVolume, _notify, _currentGeneration, _currentConsumedCount, _consumePlayed, _loopQueue] remoteExec ["A3YT_fnc_handleLocalPlayback", 0, false];
        } else {
            private _generation = _currentGeneration + 1;
            missionNamespace setVariable ["A3YT_queue", _queue, true];
            missionNamespace setVariable ["A3YT_queueVolume", _clampedVolume, true];
            missionNamespace setVariable ["A3YT_queueNotify", _notify, true];
            missionNamespace setVariable ["A3YT_queueConsumePlayed", _consumePlayed, true];
            missionNamespace setVariable ["A3YT_queueLoop", _loopQueue, true];
            missionNamespace setVariable ["A3YT_queueConsumedCount", 0, true];
            missionNamespace setVariable ["A3YT_queuePaused", false, true];
            missionNamespace setVariable ["A3YT_queueGeneration", _generation, true];
            [_queue, _clampedVolume, _notify, _consumePlayed, _loopQueue] call _fnc_storeDraft;
            [_queue, true] call _fnc_prefetchHead;

            [_queue, _clampedVolume, _notify, _generation, 0, _consumePlayed, _loopQueue] remoteExec ["A3YT_fnc_handleLocalPlayback", 0, false];
        };
    };
};

if (!_hasDirectDispatch && {!isNull _logic}) then {
    deleteVehicle _logic;
};
