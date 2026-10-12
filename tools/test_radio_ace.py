"""Execute the real ACE condition with vehicle primitives supplied by the test."""
from pathlib import Path
import re
import test_radio_state as t
from sqf.expressions import UnaryExpression,BinaryExpression
from sqf.types import Number,String,Boolean,Keyword
from sqf.interpreter import EXPRESSIONS,interpret
EXPRESSIONS.insert(0,UnaryExpression(Keyword("isnull"),Number,Boolean,lambda rhs,_:rhs.value==0))
EXPRESSIONS.insert(0,UnaryExpression(Keyword("alive"),Number,Boolean,lambda rhs,_:rhs.value not in (0,5)))
EXPRESSIONS.insert(0,BinaryExpression(Number,Keyword("iskindof"),String,Boolean,
    lambda lhs,rhs,_:{1:"LandVehicle",2:"Air",3:"Ship",4:"CAManBase",5:"LandVehicle"}.get(lhs.value)==rhs.value))
s=(t.root/"src/addon/a3yt_radio/functions/fn_postInit.sqf").read_text(encoding="utf-8")
condition=re.search(r"\},\s*\{\s*(private _vehicle = objectParent player;.*?)\},\s*\{\},\s*\[\]",s,re.S).group(1)
for vehicle,expected in ((0,False),(1,True),(2,True),(3,True),(4,False),(5,False)):
    code=condition.replace("objectParent player",str(vehicle))
    _,result=interpret(code,t.StateInterpreter())
    assert isinstance(result,Boolean) and result.value==expected,(vehicle,result)
assert "A3YTR_aceInteraction" not in s
print("PASS: actual ACE condition returns Bool for null, land, air, ship, infantry and destroyed vehicle")
