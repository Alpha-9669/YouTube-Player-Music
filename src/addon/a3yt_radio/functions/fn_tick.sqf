// State: queue, index (-1 when completed), volume, start, generation, duration,
// pausedAt (-1 when running). Power loss pauses the clock without deleting music.
params ["_state", "_requireEngine", "_engineOn", "_loop", "_now", ["_manualPause", false, [false]]];
_state params ["_queue", "_index", "_volume", "_started", "_generation"];
private _duration = _state param [5, 0];
private _pausedAt = _state param [6, -1];
private _updated = [_queue, _index, _volume, _started, _generation, _duration, -1];
if (count _queue > 0 && {_index >= 0}) then {
    if (_manualPause || {_requireEngine && {!_engineOn}}) then {
        if (_pausedAt < 0) then {_pausedAt = _now; _generation = _generation + 1};
        _updated = [_queue, _index, _volume, _started, _generation, _duration, _pausedAt];
    } else {
        if (_pausedAt >= 0) then {
            _started = _started + (_now - _pausedAt);
            _generation = _generation + 1;
        };
        _updated = [_queue, _index, _volume, _started, _generation, _duration, -1];
        if (_duration > 0 && {_now - _started > _duration / 1000 + 1}) then {
            _updated = [_updated, _loop, _now] call A3YTR_fnc_advance;
        };
    };
};
_updated
