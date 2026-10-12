// Pure synchronized seek. Paused tracks keep their paused clock anchor.
params ["_state", "_requestedMs", "_now"];
_state params ["_queue", "_index", "_volume", "_started", "_generation"];
private _duration = _state param [5,0];
private _pausedAt = _state param [6,-1];
private _updated = _state;
if (_index >= 0 && {_index < count _queue} && {_duration > 0}) then {
    private _target = round ((_requestedMs max 0) min ((_duration - 1) max 0));
    private _anchor = if (_pausedAt >= 0) then {_pausedAt} else {_now};
    _updated = [_queue, _index, _volume, _anchor - _target / 1000, _generation + 1, _duration, _pausedAt];
};
_updated
