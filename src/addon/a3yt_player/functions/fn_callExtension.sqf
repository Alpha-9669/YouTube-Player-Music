params [
    ["_command", "", [""]],
    ["_args", [], [[]]]
];

if (_command isEqualTo "") exitWith {
    ["err|missing_argument|command", 1, 0]
};

private _debugEnabled = missionNamespace getVariable ["A3YT_debugPlayback", false];
private _debugApplied = missionNamespace getVariable ["A3YT_debugPlaybackApplied", -1];
private _debugTarget = if (_debugEnabled) then {1} else {0};

if (_debugApplied != _debugTarget) then {
    private _debugResult = "youtube_player_music" callExtension format ["debug|%1", _debugTarget];
    missionNamespace setVariable ["A3YT_debugPlaybackApplied", _debugTarget];
    diag_log format ["[A3YT][EXTDBG] debug=%1 result=%2", _debugTarget, _debugResult];
};

private _payload = [_command];

{
    _payload pushBack (if (_x isEqualType "") then {_x} else {str _x});
} forEach _args;

private _startedAt = diag_tickTime;
private _result = ["youtube_player_music" callExtension (_payload joinString "|"), 0, 0];
private _elapsedMs = round ((diag_tickTime - _startedAt) * 1000);
private _commandLower = toLower _command;

if (_debugEnabled) then {
    if !(_commandLower in ["status", "timeline"]) then {
        diag_log format [
            "[A3YT][EXTCALL] command=%1 args=%2 elapsedMs=%3 result=%4",
            _command,
            _args,
            _elapsedMs,
            _result
        ];
    } else {
        if (_elapsedMs >= 250) then {
            diag_log format [
                "[A3YT][EXTCALL] slow command=%1 elapsedMs=%2 result=%3",
                _command,
                _elapsedMs,
                _result
            ];
        };
    };
};

_result
