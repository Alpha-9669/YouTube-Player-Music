private _legacyAction = "";
private _queue = [];
private _volume = 70;
private _notify = true;
private _generation = -1;
private _controlAction = "";
private _seekMs = -1;
private _prefetchUrl = "";
private _consumePlayed = missionNamespace getVariable ["A3YT_localQueueConsumePlayed", false];
private _loopQueue = missionNamespace getVariable ["A3YT_localQueueLoop", false];
private _baseIndex = missionNamespace getVariable ["A3YT_localQueueBaseIndex", 0];

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
    {
        private _entry = [_x] call _fnc_normalizeQueueItem;
        if ((count _entry) > 0) then {
            _normalized pushBack _entry;
        };
    } forEach _items;

    _normalized
};

if ((_this isEqualType []) && {(count _this) > 0} && {(_this param [0, []]) isEqualType ""}) then {
    _legacyAction = toLower (_this param [0, "play", [""]]);
    switch (_legacyAction) do {
        case "pause": {
            _controlAction = _legacyAction;
            _notify = _this param [1, missionNamespace getVariable ["A3YT_localQueueNotify", true], [true]];
            _generation = _this param [2, missionNamespace getVariable ["A3YT_localQueueGeneration", 0], [0]];
            _queue = +(missionNamespace getVariable ["A3YT_localQueue", []]);
            _volume = missionNamespace getVariable ["A3YT_localQueueVolume", 70];
            _consumePlayed = missionNamespace getVariable ["A3YT_localQueueConsumePlayed", false];
            _loopQueue = missionNamespace getVariable ["A3YT_localQueueLoop", false];
            _baseIndex = missionNamespace getVariable ["A3YT_localQueueBaseIndex", 0];
        };

        case "resume": {
            _controlAction = _legacyAction;
            _notify = _this param [1, missionNamespace getVariable ["A3YT_localQueueNotify", true], [true]];
            _generation = _this param [2, missionNamespace getVariable ["A3YT_localQueueGeneration", 0], [0]];
            _queue = +(missionNamespace getVariable ["A3YT_localQueue", []]);
            _volume = missionNamespace getVariable ["A3YT_localQueueVolume", 70];
            _consumePlayed = missionNamespace getVariable ["A3YT_localQueueConsumePlayed", false];
            _loopQueue = missionNamespace getVariable ["A3YT_localQueueLoop", false];
            _baseIndex = missionNamespace getVariable ["A3YT_localQueueBaseIndex", 0];
        };

        case "volume": {
            _controlAction = _legacyAction;
            _volume = _this param [1, missionNamespace getVariable ["A3YT_localQueueVolume", 70], [0]];
            _generation = _this param [2, missionNamespace getVariable ["A3YT_localQueueGeneration", 0], [0]];
            _queue = +(missionNamespace getVariable ["A3YT_localQueue", []]);
            _notify = missionNamespace getVariable ["A3YT_localQueueNotify", true];
            _consumePlayed = missionNamespace getVariable ["A3YT_localQueueConsumePlayed", false];
            _loopQueue = missionNamespace getVariable ["A3YT_localQueueLoop", false];
            _baseIndex = missionNamespace getVariable ["A3YT_localQueueBaseIndex", 0];
        };

        case "stop": {
            _controlAction = _legacyAction;
            _notify = _this param [1, missionNamespace getVariable ["A3YT_localQueueNotify", true], [true]];
            _generation = _this param [2, missionNamespace getVariable ["A3YT_localQueueGeneration", 0], [0]];
            _queue = +(missionNamespace getVariable ["A3YT_localQueue", []]);
            _volume = missionNamespace getVariable ["A3YT_localQueueVolume", 70];
            _consumePlayed = missionNamespace getVariable ["A3YT_localQueueConsumePlayed", false];
            _loopQueue = missionNamespace getVariable ["A3YT_localQueueLoop", false];
            _baseIndex = missionNamespace getVariable ["A3YT_localQueueBaseIndex", 0];
        };

        case "seek": {
            _controlAction = _legacyAction;
            _seekMs = _this param [1, 0, [0]];
            _generation = _this param [2, missionNamespace getVariable ["A3YT_localQueueGeneration", 0], [0]];
            _queue = +(missionNamespace getVariable ["A3YT_localQueue", []]);
            _volume = missionNamespace getVariable ["A3YT_localQueueVolume", 70];
            _notify = missionNamespace getVariable ["A3YT_localQueueNotify", true];
            _consumePlayed = missionNamespace getVariable ["A3YT_localQueueConsumePlayed", false];
            _loopQueue = missionNamespace getVariable ["A3YT_localQueueLoop", false];
            _baseIndex = missionNamespace getVariable ["A3YT_localQueueBaseIndex", 0];
        };

        case "prefetch": {
            _controlAction = _legacyAction;
            _prefetchUrl = trim (_this param [1, "", [""]]);
            _generation = missionNamespace getVariable ["A3YT_localQueueGeneration", 0];
            _queue = +(missionNamespace getVariable ["A3YT_localQueue", []]);
            _volume = missionNamespace getVariable ["A3YT_localQueueVolume", 70];
            _notify = missionNamespace getVariable ["A3YT_localQueueNotify", true];
            _consumePlayed = missionNamespace getVariable ["A3YT_localQueueConsumePlayed", false];
            _loopQueue = missionNamespace getVariable ["A3YT_localQueueLoop", false];
            _baseIndex = missionNamespace getVariable ["A3YT_localQueueBaseIndex", 0];
        };

        case "update": {
            _controlAction = "update";
            _queue = _this param [1, [], [[]]];
            _volume = _this param [2, missionNamespace getVariable ["A3YT_localQueueVolume", 70], [0]];
            _notify = _this param [3, missionNamespace getVariable ["A3YT_localQueueNotify", true], [true]];
            _generation = _this param [4, missionNamespace getVariable ["A3YT_localQueueGeneration", 0], [0]];
            _baseIndex = _this param [5, missionNamespace getVariable ["A3YT_localQueueBaseIndex", 0], [0]];
            _consumePlayed = _this param [6, missionNamespace getVariable ["A3YT_localQueueConsumePlayed", false], [true]];
            _loopQueue = _this param [7, missionNamespace getVariable ["A3YT_localQueueLoop", false], [true]];
        };

        default {
            private _legacyUrl = _this param [1, "", [""]];
            _volume = _this param [2, 70, [0]];
            _notify = _this param [3, true, [true]];

            _queue = if (_legacyAction isEqualTo "stop") then {[]} else {[_legacyUrl]};
            _generation = (missionNamespace getVariable ["A3YT_localQueueGeneration", 0]) + 1;
        };
    };
} else {
    _queue = _this param [0, [], [[]]];
    _volume = _this param [1, 70, [0]];
    _notify = _this param [2, true, [true]];
    _generation = _this param [3, (missionNamespace getVariable ["A3YT_localQueueGeneration", 0]) + 1, [0]];
    _baseIndex = _this param [4, 0, [0]];
    _consumePlayed = _this param [5, missionNamespace getVariable ["A3YT_localQueueConsumePlayed", false], [true]];
    _loopQueue = _this param [6, missionNamespace getVariable ["A3YT_localQueueLoop", false], [true]];
};

if (!hasInterface) exitWith {
    ""
};

if (_controlAction isEqualTo "prefetch") exitWith {
    if (_prefetchUrl isEqualTo "") exitWith {"err|missing_argument|url"};

    private _prefetchResult = ["prefetch", [_prefetchUrl]] call A3YT_fnc_callExtension;
    diag_log format ["[A3YT] queue_prefetch result=%1 url=%2", _prefetchResult, _prefetchUrl];
    "ok|queue_prefetch"
};

private _previousGeneration = missionNamespace getVariable ["A3YT_localQueueGeneration", -1];
private _wasWorkerRunning = missionNamespace getVariable ["A3YT_localQueueWorkerRunning", false];
private _previousBaseIndex = missionNamespace getVariable ["A3YT_localQueueBaseIndex", 0];

_queue = [_queue] call _fnc_normalizeQueue;
private _clampedVolume = (_volume max 0) min 100;
private _effectiveVolume = [_clampedVolume] call A3YT_fnc_getEffectiveVolume;
if (_loopQueue) then {
    _consumePlayed = false;
};

diag_log format [
    "[A3YT] handleLocalPlayback action=%1 controlAction=%2 queueCount=%3 generation=%4 volume=%5 effectiveVolume=%6 notify=%7 loop=%8",
    _legacyAction,
    _controlAction,
    count _queue,
    _generation,
    _clampedVolume,
    _effectiveVolume,
    _notify,
    _loopQueue
];

missionNamespace setVariable ["A3YT_localQueueGeneration", _generation];
missionNamespace setVariable ["A3YT_localQueue", _queue];
missionNamespace setVariable ["A3YT_localQueueVolume", _clampedVolume];
missionNamespace setVariable ["A3YT_localQueueEffectiveVolume", _effectiveVolume];
missionNamespace setVariable ["A3YT_localQueueNotify", _notify];
missionNamespace setVariable ["A3YT_localQueueBaseIndex", _baseIndex];
missionNamespace setVariable ["A3YT_localQueueConsumePlayed", _consumePlayed];
missionNamespace setVariable ["A3YT_localQueueLoop", _loopQueue];

if (_controlAction isEqualTo "pause") exitWith {
    missionNamespace setVariable ["A3YT_localQueuePaused", true];
    private _pauseResult = ["pause", []] call A3YT_fnc_callExtension;
    if (_notify) then {
        systemChat localize "STR_A3YT_CHAT_QUEUE_PAUSED";
    };

    diag_log format ["[A3YT] queue_paused result=%1", _pauseResult];
    "ok|queue_paused"
};

if (_controlAction isEqualTo "resume") exitWith {
    missionNamespace setVariable ["A3YT_localQueuePaused", false];
    private _resumeResult = ["resume", []] call A3YT_fnc_callExtension;
    if (_notify) then {
        systemChat localize "STR_A3YT_CHAT_QUEUE_RESUMED";
    };

    diag_log format ["[A3YT] queue_resumed result=%1", _resumeResult];
    "ok|queue_resumed"
};

if (_controlAction isEqualTo "volume") exitWith {
    missionNamespace setVariable ["A3YT_localQueueVolume", _clampedVolume];
    missionNamespace setVariable ["A3YT_localQueueEffectiveVolume", _effectiveVolume];
    private _volumeResult = ["volume", [str _effectiveVolume]] call A3YT_fnc_callExtension;
    diag_log format ["[A3YT] queue_volume result=%1 volume=%2 effectiveVolume=%3", _volumeResult, _clampedVolume, _effectiveVolume];
    "ok|queue_volume"
};

if (_controlAction isEqualTo "seek") exitWith {
    missionNamespace setVariable ["A3YT_localQueueLastSeekAt", diag_tickTime];
    missionNamespace setVariable ["A3YT_localQueueLastSeekMs", _seekMs max 0];
    missionNamespace setVariable ["A3YT_localQueuePendingSeekMs", _seekMs max 0];
    missionNamespace setVariable ["A3YT_localQueuePendingSeekIssuedAt", diag_tickTime];
    private _seekText = format ["%1", round (_seekMs max 0)];
    private _seekResult = ["seek", [_seekText]] call A3YT_fnc_callExtension;
    diag_log format ["[A3YT] queue_seek result=%1 positionMs=%2 seekText=%3", _seekResult, _seekMs, _seekText];
    "ok|queue_seek"
};

if (_controlAction isEqualTo "stop" || {_legacyAction isEqualTo "stop"} || {(count _queue) isEqualTo 0}) exitWith {
    missionNamespace setVariable ["A3YT_localQueuePaused", false];
    missionNamespace setVariable ["A3YT_localQueue", []];
    missionNamespace setVariable ["A3YT_localQueueCurrentIndex", 0];
    missionNamespace setVariable ["A3YT_localQueueBaseIndex", 0];
    missionNamespace setVariable ["A3YT_localQueueReportedConsumed", -1];
    missionNamespace setVariable ["A3YT_localQueueLoop", false];
    private _stopResult = ["stop", []] call A3YT_fnc_callExtension;
    if (_notify) then {
        systemChat localize "STR_A3YT_CHAT_QUEUE_CLEARED";
    };

    diag_log format ["[A3YT] queue_cleared result=%1", _stopResult];
    "ok|queue_cleared"
};

if (_controlAction isEqualTo "update" && {_wasWorkerRunning} && {_generation isEqualTo _previousGeneration}) exitWith {
    private _currentIndex = missionNamespace getVariable ["A3YT_localQueueCurrentIndex", 0];
    private _baseDelta = _baseIndex - _previousBaseIndex;
    if (_baseDelta != 0) then {
        _currentIndex = (_currentIndex - _baseDelta) max 0;
        missionNamespace setVariable ["A3YT_localQueueCurrentIndex", _currentIndex];
    };

    diag_log format ["[A3YT] queue_updated_in_place generation=%1 items=%2", _generation, count _queue];
    "ok|queue_updated_in_place"
};

missionNamespace setVariable ["A3YT_localQueuePaused", false];
missionNamespace setVariable ["A3YT_localQueueCurrentIndex", 0];
missionNamespace setVariable ["A3YT_localQueueReportedConsumed", _baseIndex];

[_generation] spawn {
    params ["_generation"];

    missionNamespace setVariable ["A3YT_localQueueWorkerRunning", true];
    missionNamespace setVariable ["A3YT_localQueueWorkerGeneration", _generation];

    private _prefetchedIndex = -1;
    private _pollDelay = 0.15;
    private _abortQueue = false;
    private _currentIndex = missionNamespace getVariable ["A3YT_localQueueCurrentIndex", 0];

    private _fnc_reportProgress = {
        params ["_currentIndex"];

        if (
            (missionNamespace getVariable ["A3YT_localQueueLoop", false])
            || {!(missionNamespace getVariable ["A3YT_localQueueConsumePlayed", false])}
        ) exitWith {};

        private _absoluteConsumed = (missionNamespace getVariable ["A3YT_localQueueBaseIndex", 0]) + _currentIndex;
        private _reported = missionNamespace getVariable ["A3YT_localQueueReportedConsumed", -1];
        if (_absoluteConsumed <= _reported) exitWith {};

        missionNamespace setVariable ["A3YT_localQueueReportedConsumed", _absoluteConsumed];

        private _payload = [
            "progress",
            [],
            missionNamespace getVariable ["A3YT_localQueueVolume", 70],
            missionNamespace getVariable ["A3YT_localQueueNotify", true],
            [_absoluteConsumed, _generation],
            true
        ];

        if (isServer) then {
            ["dispatch", _payload] call A3YT_fnc_moduleYoutube;
        } else {
            ["dispatch", _payload] remoteExecCall ["A3YT_fnc_moduleYoutube", 2, false];
        };
    };

    private _fnc_normalizeQueueItemLocal = {
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

    private _fnc_getTimelineInfo = {
        private _response = ["timeline", []] call A3YT_fnc_callExtension;
        private _message = _response param [0, "err|no_response"];
        private _parts = _message splitString "|";

        if ((_parts param [0, ""]) isEqualTo "ok" && {(_parts param [1, ""]) isEqualTo "timeline"}) exitWith {
            [
                _parts param [2, "unknown"],
                round (parseNumber (_parts param [3, "0"])),
                round (parseNumber (_parts param [4, "0"])),
                _message
            ]
        };

        ["error", 0, 0, _message]
    };

    private _fnc_getQueueItemAt = {
        params ["_index"];
        private _queueNow = +(missionNamespace getVariable ["A3YT_localQueue", []]);
        if (_index < 0 || {_index >= count _queueNow}) exitWith {[]};
        [_queueNow param [_index, []]] call _fnc_normalizeQueueItemLocal
    };

    private _fnc_prefetchIndex = {
        params ["_index"];
        private _entry = [_index] call _fnc_getQueueItemAt;
        private _url = _entry param [0, ""];
        if !(_url isEqualTo "") then {
            ["prefetch", [_url]] call A3YT_fnc_callExtension;
            _prefetchedIndex = _index;
        };
    };

    if (_currentIndex < 0) then {
        _currentIndex = 0;
    };

    [_currentIndex] call _fnc_prefetchIndex;

    scopeName "A3YT_mainLoop";
    while {!_abortQueue} do {
        if (_generation isNotEqualTo (missionNamespace getVariable ["A3YT_localQueueGeneration", -1])) exitWith {
            _abortQueue = true;
        };

        private _queueNow = +(missionNamespace getVariable ["A3YT_localQueue", []]);
        if (_currentIndex >= count _queueNow) then {
            if ((count _queueNow) > 0 && {missionNamespace getVariable ["A3YT_localQueueLoop", false]}) then {
                _currentIndex = 0;
                missionNamespace setVariable ["A3YT_localQueueCurrentIndex", _currentIndex];
                _prefetchedIndex = -1;
                [_currentIndex] call _fnc_prefetchIndex;
            } else {
                breakOut "A3YT_mainLoop";
            };
        };

        private _entry = [_queueNow param [_currentIndex, []]] call _fnc_normalizeQueueItemLocal;
        private _url = _entry param [0, ""];
        private _title = _entry param [1, _url];
        if (_url isEqualTo "") then {
            _currentIndex = _currentIndex + 1;
            missionNamespace setVariable ["A3YT_localQueueCurrentIndex", _currentIndex];
            [_currentIndex] call _fnc_reportProgress;
        } else {
            missionNamespace setVariable ["A3YT_localQueueCurrentIndex", _currentIndex];

            private _notify = missionNamespace getVariable ["A3YT_localQueueNotify", true];
            private _sourceVolume = missionNamespace getVariable ["A3YT_localQueueVolume", 70];
            private _volume = [_sourceVolume] call A3YT_fnc_getEffectiveVolume;
            missionNamespace setVariable ["A3YT_localQueueEffectiveVolume", _volume];
            private _queueCount = count _queueNow;

            if (_notify) then {
                systemChat format [localize "STR_A3YT_CHAT_QUEUE_PROGRESS", _currentIndex + 1, _queueCount, _title];
            };

            private _debugPlayback = missionNamespace getVariable ["A3YT_debugPlayback", false];
            private _playStartedAt = diag_tickTime;
            private _playResult = ["play", [_url, str _volume]] call A3YT_fnc_callExtension;
            private _playMessage = _playResult param [0, "err|no_response"];
            private _playParts = _playMessage splitString "|";

            if (_debugPlayback) then {
                diag_log format [
                    "[A3YT][PLAY] play_request generation=%1 index=%2 url=%3 volume=%4 effectiveVolume=%5 result=%6",
                    _generation,
                    _currentIndex,
                    _url,
                    _sourceVolume,
                    _volume,
                    _playResult
                ];
            };

            if ((_playParts param [0, "err"]) isNotEqualTo "ok") then {
                if (_notify) then {
                    systemChat format [localize "STR_A3YT_CHAT_ERROR", _playParts param [2, _playMessage]];
                };

                diag_log format ["[A3YT] queue_item_failed url=%1 result=%2", _url, _playResult];
                _currentIndex = _currentIndex + 1;
                missionNamespace setVariable ["A3YT_localQueueCurrentIndex", _currentIndex];
            } else {
                private _sawPlaying = false;
                private _itemDone = false;
                private _itemCompleted = false;
                private _startupDeadline = diag_tickTime + 120;
                private _queuedNextPrefetch = false;
                private _lastLoggedState = "";
                private _lastPositionMs = -1;
                private _lastProgressAt = diag_tickTime;
                private _lastRecoveredSeekAt = -1;
                private _lastObservedSeekAt = -1;
                private _seekRecoveryAttempts = 0;

                while {!_itemDone && {!_abortQueue}} do {
                    if (_generation isNotEqualTo (missionNamespace getVariable ["A3YT_localQueueGeneration", -1])) then {
                        _abortQueue = true;
                    } else {
                        sleep _pollDelay;
                        private _timelineInfo = call _fnc_getTimelineInfo;
                        private _state = _timelineInfo param [0, "error"];
                        private _positionMs = _timelineInfo param [1, 0];
                        private _durationMs = _timelineInfo param [2, 0];
                        private _statusMessage = _timelineInfo param [3, "err|no_response"];
                        private _debugPlayback = missionNamespace getVariable ["A3YT_debugPlayback", false];

                        if (_debugPlayback && {_state isNotEqualTo _lastLoggedState}) then {
                            _lastLoggedState = _state;
                            diag_log format [
                                "[A3YT][PLAY] state generation=%1 index=%2 url=%3 state=%4 elapsedMs=%5 positionMs=%6 durationMs=%7 status=%8",
                                _generation,
                                _currentIndex,
                                _url,
                                _state,
                                round ((diag_tickTime - _playStartedAt) * 1000),
                                _positionMs,
                                _durationMs,
                                _statusMessage
                            ];
                        };

                        if (!_queuedNextPrefetch && {_state in ["resolving", "playing", "paused"]}) then {
                            private _nextIndex = _currentIndex + 1;
                            if (_nextIndex > _prefetchedIndex) then {
                                [_nextIndex] call _fnc_prefetchIndex;
                            };

                            _queuedNextPrefetch = true;
                        };

                        if (_state isEqualTo "playing") then {
                            _sawPlaying = true;
                            if (_positionMs > _lastPositionMs) then {
                                _lastPositionMs = _positionMs;
                                _lastProgressAt = diag_tickTime;
                            };
                        };

                        private _pendingSeekMs = missionNamespace getVariable ["A3YT_localQueuePendingSeekMs", -1];
                        private _pendingSeekIssuedAt = missionNamespace getVariable ["A3YT_localQueuePendingSeekIssuedAt", -1];
                        if (_pendingSeekMs >= 0 && {_state in ["playing", "paused"]}) then {
                            private _seekToleranceMs = (5000 max round (_pendingSeekMs / 20));
                            if (abs (_positionMs - _pendingSeekMs) <= _seekToleranceMs) then {
                                diag_log format [
                                    "[A3YT] queue_seek_ready url=%1 state=%2 requestedMs=%3 positionMs=%4 elapsedMs=%5",
                                    _url,
                                    _state,
                                    _pendingSeekMs,
                                    _positionMs,
                                    round ((diag_tickTime - _pendingSeekIssuedAt) * 1000)
                                ];
                                missionNamespace setVariable ["A3YT_localQueuePendingSeekMs", -1];
                                missionNamespace setVariable ["A3YT_localQueuePendingSeekIssuedAt", -1];
                                _lastProgressAt = diag_tickTime;
                            };
                        };

                        if (_state isEqualTo "paused") then {
                            _lastProgressAt = diag_tickTime;
                        };

                        if (_state isEqualTo "error") then {
                            private _notify = missionNamespace getVariable ["A3YT_localQueueNotify", true];
                            if (_notify) then {
                                systemChat format [localize "STR_A3YT_CHAT_ERROR", _statusMessage];
                            };
                            diag_log format ["[A3YT] queue_status_error url=%1 status=%2", _url, _statusMessage];
                            _itemDone = true;
                        };

                        if (!_itemDone && {_state isEqualTo "idle"} && {_sawPlaying}) then {
                            _itemCompleted = true;
                            _itemDone = true;
                        };

                        if (!_itemDone && {!_sawPlaying} && {diag_tickTime > _startupDeadline}) then {
                            private _notify = missionNamespace getVariable ["A3YT_localQueueNotify", true];
                            if (_notify) then {
                                systemChat format [localize "STR_A3YT_CHAT_TIMEOUT", _currentIndex + 1];
                            };
                            diag_log format ["[A3YT] queue_timeout url=%1 status=%2", _url, _statusMessage];
                            ["stop", []] call A3YT_fnc_callExtension;
                            _abortQueue = true;
                            _itemDone = true;
                        };

                        private _lastSeekAt = missionNamespace getVariable ["A3YT_localQueueLastSeekAt", -1];
                        private _lastSeekMs = missionNamespace getVariable ["A3YT_localQueueLastSeekMs", -1];
                        if (_lastSeekAt > 0 && {_lastSeekAt isNotEqualTo _lastObservedSeekAt}) then {
                            _lastObservedSeekAt = _lastSeekAt;
                            _lastProgressAt = diag_tickTime;
                            _seekRecoveryAttempts = 0;
                        };
                        private _recentSeek = _lastSeekAt > 0 && {(diag_tickTime - _lastSeekAt) < 45};
                        private _stallTimeout = if (_recentSeek) then {
                            90
                        } else {
                            if (_durationMs >= 21600000) then {
                                180
                            } else {
                                if (_durationMs >= 3600000) then {90} else {30}
                            }
                        };

                        if (!_itemDone && {_sawPlaying} && {!(_state isEqualTo "paused")} && {(diag_tickTime - _lastProgressAt) > _stallTimeout}) then {
                            private _longTrackRecovery = _durationMs >= 3600000 && {_positionMs >= 0};
                            if (((_recentSeek && {_lastSeekMs >= 0}) || {_longTrackRecovery}) && {_seekRecoveryAttempts < 2}) then {
                                _lastRecoveredSeekAt = _lastSeekAt;
                                _seekRecoveryAttempts = _seekRecoveryAttempts + 1;
                                _lastProgressAt = diag_tickTime;
                                private _recoverySeekMs = if (_recentSeek && {_lastSeekMs >= 0}) then {_lastSeekMs} else {_positionMs};
                                private _retrySeekText = format ["%1", round _recoverySeekMs];
                                private _retrySeekResult = ["seek", [_retrySeekText]] call A3YT_fnc_callExtension;
                                diag_log format [
                                    "[A3YT] queue_seek_recover url=%1 state=%2 positionMs=%3 durationMs=%4 seekMs=%5 attempt=%6 result=%7",
                                    _url,
                                    _state,
                                    _positionMs,
                                    _durationMs,
                                    _recoverySeekMs,
                                    _seekRecoveryAttempts,
                                    _retrySeekResult
                                ];
                            } else {
                                private _notify = missionNamespace getVariable ["A3YT_localQueueNotify", true];
                                if (_notify) then {
                                    systemChat format [localize "STR_A3YT_CHAT_TIMEOUT", _currentIndex + 1];
                                };
                                diag_log format [
                                    "[A3YT] queue_stalled url=%1 state=%2 positionMs=%3 durationMs=%4 status=%5",
                                    _url,
                                    _state,
                                    _positionMs,
                                    _durationMs,
                                    _statusMessage
                                ];
                                ["stop", []] call A3YT_fnc_callExtension;
                                _abortQueue = true;
                                _itemDone = true;
                            };
                        };
                    };
                };

                if (!_abortQueue) then {
                    _currentIndex = _currentIndex + 1;
                    missionNamespace setVariable ["A3YT_localQueueCurrentIndex", _currentIndex];
                    if (_itemCompleted) then {
                        [_currentIndex] call _fnc_reportProgress;
                    };
                };
            };
        };
    };

    if (_generation isEqualTo (missionNamespace getVariable ["A3YT_localQueueWorkerGeneration", -1])) then {
        missionNamespace setVariable ["A3YT_localQueueWorkerRunning", false];
    };

    if (
        !_abortQueue
        && {_generation isEqualTo (missionNamespace getVariable ["A3YT_localQueueGeneration", -1])}
        && {!(missionNamespace getVariable ["A3YT_localQueueLoop", false])}
    ) then {
        missionNamespace setVariable ["A3YT_localQueue", []];
        missionNamespace setVariable ["A3YT_localQueueCurrentIndex", 0];

        if (missionNamespace getVariable ["A3YT_localQueueNotify", true]) then {
            systemChat localize "STR_A3YT_CHAT_QUEUE_FINISHED";
        };
    };
};

"ok|queue_updated"
