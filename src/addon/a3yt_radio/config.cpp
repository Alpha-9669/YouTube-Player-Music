class CfgPatches
{
    class A3YT_radio
    {
        name = "YouTube Player Music Vehicle Radio";
        requiredVersion = 2.20;
        requiredAddons[] = {"A3YT_player", "cba_keybinding", "cba_settings"};
        units[] = {};
        weapons[] = {};
    };
};

class RscText;
class RscTextMulti;
class RscEdit;
class RscButton;
class RscListBox;

class A3YTR_RscRadio
{
    idd = 2611940;
    movingEnable = 0;
    enableSimulation = 1;
    onLoad = "['load', _this select 0] call A3YTR_fnc_html";
    class Controls
    {
        class Browser
        {
            type = 106;
            idc = 2611990;
            style = 0;
            deletable = 0;
            colorBackground[] = {0,0,0,0};
            x = safeZoneX + safeZoneW * 0.19;
            y = safeZoneY + safeZoneH * 0.18;
            w = safeZoneW * 0.62;
            h = safeZoneH * 0.78;
            allowExternalURL = 0;
            url = "";
        };
        // Existing asynchronous metadata loader uses these invisible controls.
        class URL: RscEdit
        {
            idc = 2611941;
            x = -10; y = -10; w = 0; h = 0;
            colorBackground[] = {0.082,0.082,0.082,1};
            colorText[] = {0.86,0.86,0.86,1};
            colorSelection[] = {0.35,0.35,0.35,1};
            font = "RobotoCondensed";
            shadow = 0;
            canModify = 1;
            autocomplete = "";
            onKillFocus = "['draft',ctrlParent (_this select 0)] call A3YTR_fnc_html";
            onKeyDown = "if ((_this select 1) in [28,156]) then {['add',ctrlParent (_this select 0)] spawn A3YTR_fnc_ui;true} else {false}";
        };
        class Add: RscButton
        {
            idc = 2611958;
            x = -10; y = -10; w = 0; h = 0;
            text = "Add";
            colorBackground[] = {0.22,0.22,0.21,1};
            colorBackgroundActive[] = {0.26,0.26,0.25,1};
            colorBackgroundDisabled[] = {0.16,0.16,0.16,1};
            colorText[] = {0.82,0.82,0.80,1};
            font = "RobotoCondensed";
            shadow = 0;
            onButtonClick = "['add',ctrlParent (_this select 0)] spawn A3YTR_fnc_ui";
        };
    };
};

class CfgFunctions
{
    class A3YTR
    {
        tag = "A3YTR";
        class Core
        {
            file = "\a3yt_radio\functions";
            class postInit {postInit = 1;};
            class preInit {preInit = 1;};
            class open {};
            class advance {};
            class tick {};
            class seek {};
            class command {};
            class listener {};
            class ui {};
            class html {};
        };
    };
};
