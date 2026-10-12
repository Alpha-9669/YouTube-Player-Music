// Pure state transition shared by Next, completion reports and the server clock.
params ["_state", "_loop", "_now"];
_state params ["_queue", "_index", "_volume", "_started", "_generation"];
private _nextState = _state;
if (count _queue > 0) then {
    _index = _index + 1;
    if (_index >= count _queue) then {_index = if (_loop) then {0} else {-1}};
    _nextState = [_queue, _index, _volume, if (_index < 0) then {0} else {_now}, _generation + 1, 0, -1];
};
_nextState
