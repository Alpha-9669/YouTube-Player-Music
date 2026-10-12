import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import test_radio_state as t
from sqf.expressions import BinaryExpression,UnaryExpression
from sqf.types import Array,Keyword,Nothing,Number
from sqf.interpreter import EXPRESSIONS,interpret

from sqf.keywords import KEYWORDS,BINARY_OPERATORS
KEYWORDS.add('insert');BINARY_OPERATORS.add('insert')

def insert(lhs,rhs,_):
 index=int(rhs.value[0].value);lhs.value[index:index]=rhs.value[1].value
 return Nothing()
EXPRESSIONS.insert(0,BinaryExpression(Array,Keyword('deleteat'),Number,None,lambda lhs,rhs,_:lhs.value.pop(int(rhs.value))))
EXPRESSIONS.insert(0,BinaryExpression(Array,Keyword('insert'),Array,Nothing,insert))
EXPRESSIONS.insert(0,UnaryExpression(Keyword('abs'),Number,Number,lambda rhs,_:abs(rhs.value)))
s=(t.root/'src/addon/a3yt_radio/functions/fn_command.sqf').read_text();a=s.index('case "move": {')+len('case "move": {');b=s.index('    case "remove":',a);body=s[a:b].rsplit('};',1)[0]
for start in range(4):
 for target in range(4):
  for playing in range(4):
   code=f'_queue=["A","B","C","D"];_index={playing};_payload=[{start},{target-start}];'+body+'[_queue,_index]'
   _,result=interpret(code,t.StateInterpreter());actual=t.plain(result)
   expected=list('ABCD');item=expected.pop(start);expected.insert(target,item)
   assert actual==[expected,expected.index('ABCD'[playing])],(start,target,playing,actual)
print('PASS: production SQF reorder preserves playing track for all 64 combinations')
