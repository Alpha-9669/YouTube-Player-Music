if (!isServer) exitWith {};

while {true} do {
    {
        if (!(_x getVariable ["A3YT_addonUnlocked", false])) then {
            _x addCuratorAddons ["A3YT_player"];
            _x setVariable ["A3YT_addonUnlocked", true, true];
        };
    } forEach allCurators;

    sleep 5;
}
