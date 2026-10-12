"""Execute the production SQF clock/advance functions in the SQF interpreter.

Install sqflint into build/test-deps if it is not already available.
Only missing/incorrect primitive commands in that older interpreter are adapted.
"""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / "build" / "test-deps"))
from sqf.interpreter import interpret, EXPRESSIONS, Interpreter
from sqf.expressions import BinaryExpression, UnaryExpression
from sqf.types import Array, Number, Type, Boolean, Keyword, Nothing
from sqf.exceptions import SQFWarning

class StateInterpreter(Interpreter):
    def exception(self, error):
        if not isinstance(error, SQFWarning):
            raise error

EXPRESSIONS.insert(0, BinaryExpression(Type, Keyword("params"), Array, Nothing,
    lambda lhs, rhs, interpreter: interpreter.add_params(rhs, lhs)))
EXPRESSIONS.insert(0, UnaryExpression(Keyword("!"), Boolean, Boolean,
    lambda rhs, _: not rhs.value))

EXPRESSIONS.insert(0, BinaryExpression(Array, Keyword("param"), Array, None,
    lambda lhs, rhs, _: lhs.value[int(rhs.value[0].value)]
    if 0 <= int(rhs.value[0].value) < len(lhs.value) else rhs.value[1]))
EXPRESSIONS.insert(0, BinaryExpression(Type, Keyword("isequalto"), Type, Boolean,
    lambda lhs, rhs, _: lhs == rhs))
EXPRESSIONS.insert(0, BinaryExpression(Number, Keyword(">"), Number, Boolean,
    lambda lhs, rhs, _: lhs.value > rhs.value))

# Arithmetic primitives absent from the older interpreter used by seek.
for name, operation in (("min", min), ("max", max)):
    EXPRESSIONS.insert(0, BinaryExpression(Number, Keyword(name), Number, Number,
        lambda lhs, rhs, _, operation=operation: operation(lhs.value,rhs.value)))
EXPRESSIONS.insert(0, UnaryExpression(Keyword("round"), Number, Number,
    lambda rhs, _: round(rhs.value)))

functions = root / "src" / "addon" / "a3yt_radio" / "functions"
source = "\n".join(f"A3YTR_fnc_{name} = {{{(functions / ('fn_' + name + '.sqf')).read_text(encoding='utf-8')}}};"
    for name in ("advance", "tick", "seek"))

def plain(value):
    return [plain(item) for item in value.value] if isinstance(value, Array) else value.value

def run(expression):
    _, result = interpret(source + "\n" + expression, StateInterpreter())
    return plain(result)

queue = '["track A", "track B"]'
state = f'[{queue}, 0, 70, 100, 2, 60000, -1]'
paused = run(f'[{state}, true, false, false, 110] call A3YTR_fnc_tick')
assert paused == [["track A", "track B"], 0, 70, 100, 3, 60000, 110], paused
assert run(f'[[{queue},0,70,100,3,60000,110],true,false,false,1000] call A3YTR_fnc_tick') == paused
resumed = run(f'[[{queue},0,70,100,3,60000,110],true,true,false,200] call A3YTR_fnc_tick')
assert resumed == [["track A", "track B"], 0, 70, 190, 4, 60000, -1], resumed
running = run(f'[{state},false,false,false,110] call A3YTR_fnc_tick')
assert running == [["track A", "track B"], 0, 70, 100, 2, 60000, -1], running
for loop, expected_index in (("true", 0), ("false", -1)):
    last = f'[{queue},1,70,100,2,60000,-1]'
    ended = run(f'[{last},{loop},162] call A3YTR_fnc_advance')
    assert ended[0] == ["track A", "track B"] and ended[1] == expected_index and ended[4:] == [3,0,-1], ended
    timed = run(f'[{last},true,true,{loop},162] call A3YTR_fnc_tick')
    assert timed == ended, timed
idle = run(f'[[{queue},-1,70,0,3,0,-1],true,true,true,1000] call A3YTR_fnc_tick')
assert idle[1] == -1 and idle[4] == 3, idle
print("PASS: actual SQF pause/resume, engine bypass, queue retention, loop, duration advance and idle state")

manual = run(f'[{state},true,true,false,110,true] call A3YTR_fnc_tick')
assert manual == [["track A", "track B"],0,70,100,3,60000,110], manual
assert run(f'[{state},false,true,false,110,true] call A3YTR_fnc_tick') == manual
held = run(f'[[{queue},0,70,100,3,60000,110],true,true,false,200,true] call A3YTR_fnc_tick')
assert held == manual, held
resumedManual = run(f'[[{queue},0,70,100,3,60000,110],true,true,false,200,false] call A3YTR_fnc_tick')
assert resumedManual == [["track A","track B"],0,70,190,4,60000,-1], resumedManual
assert run(f'[[{queue},0,70,100,3,60000,110],true,false,false,200,false] call A3YTR_fnc_tick') == manual
print("PASS: manual PAUSE retains clock, PLAY resumes offset, engine-off guard remains effective")

sought = run(f'[{state},30000,110] call A3YTR_fnc_seek')
assert sought == [["track A","track B"],0,70,80,3,60000,-1], sought
pausedSeek = run(f'[[{queue},0,70,100,3,60000,110],45000,200] call A3YTR_fnc_seek')
assert pausedSeek == [["track A","track B"],0,70,65,4,60000,110], pausedSeek
assert run(f'[{state},-100,110] call A3YTR_fnc_seek')[3] == 110
assert abs(run(f'[{state},999999,110] call A3YTR_fnc_seek')[3] - 50.001) < 0.001
unknown=f'[{queue},0,70,100,2,0,-1]'
unknownResult=run(f'[{unknown},30000,110] call A3YTR_fnc_seek')
assert unknownResult == [["track A","track B"],0,70,100,2,0,-1], unknownResult
print("PASS: running/paused seek, bounds, generation and unknown-duration guard")
