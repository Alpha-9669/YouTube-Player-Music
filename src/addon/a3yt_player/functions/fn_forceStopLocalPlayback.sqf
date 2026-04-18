params [
    ["_reason", "manual", [""]],
    ["_logResult", true, [true]]
];

if (!hasInterface) exitWith {"ok|no_interface"};

private _generation = (missionNamespace getVariable ["A3YT_localQueueGeneration", 0]) + 1;
missionNamespace setVariable ["A3YT_localQueueGeneration", _generation];
missionNamespace setVariable ["A3YT_localQueue", []];
missionNamespace setVariable ["A3YT_localQueuePaused", false];
missionNamespace setVariable ["A3YT_localQueueCurrentIndex", 0];
missionNamespace setVariable ["A3YT_localQueueBaseIndex", 0];
missionNamespace setVariable ["A3YT_localQueueReportedConsumed", -1];
missionNamespace setVariable ["A3YT_localQueueConsumePlayed", false];
missionNamespace setVariable ["A3YT_localQueueLoop", false];
missionNamespace setVariable ["A3YT_localQueueWorkerRunning", false];
missionNamespace setVariable ["A3YT_localQueueWorkerGeneration", -1];
missionNamespace setVariable ["A3YT_localQueuePendingSeekMs", -1];
missionNamespace setVariable ["A3YT_localQueuePendingSeekIssuedAt", -1];
missionNamespace setVariable ["A3YT_localQueueLastSeekAt", -1];
missionNamespace setVariable ["A3YT_localQueueLastSeekMs", -1];

private _stopResult = ["stop", []] call A3YT_fnc_callExtension;

if (_logResult) then {
    diag_log format ["[A3YT] force_stop reason=%1 result=%2", _reason, _stopResult];
};

_stopResult
