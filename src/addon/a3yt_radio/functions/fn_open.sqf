if (!hasInterface || {dialog}) exitWith {false};
private _vehicle = objectParent player;
if (isNull _vehicle || {!alive _vehicle} || {!(_vehicle isKindOf "LandVehicle" || {_vehicle isKindOf "Air"} || {_vehicle isKindOf "Ship"})}) exitWith {false};
createDialog "A3YTR_RscRadio";
true
