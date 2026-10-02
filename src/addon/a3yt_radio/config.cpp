class CfgPatches
{
    class A3YT_radio
    {
        name = "YouTube Player Music Vehicle Radio";
        requiredVersion = 2.14;
        requiredAddons[] = {"A3YT_player", "cba_keybinding"};
        units[] = {};
        weapons[] = {};
    };
};

class RscText;
class RscEdit;
class RscButton;
class RscListBox;

class A3YTR_RscRadio
{
    idd = 2611940;
    movingEnable = 0;
    enableSimulation = 1;
    onLoad = "['load', _this select 0] call A3YTR_fnc_ui";
    class ControlsBackground
    {
        class Background: RscText
        {
            idc = -1;
            x = safeZoneX + safeZoneW * 0.5 - 0.25;
            y = safeZoneY + safeZoneH * 0.5 - 0.22;
            w = 0.5;
            h = 0.44;
            colorBackground[] = {0,0,0,0.88};
        };
        class Title: RscText
        {
            idc = -1;
            text = "$STR_A3YTR_TITLE";
            x = safeZoneX + safeZoneW * 0.5 - 0.25;
            y = safeZoneY + safeZoneH * 0.5 - 0.22;
            w = 0.5;
            h = 0.04;
            colorBackground[] = {0.55,0.36,0.05,0.95};
        };
    };
    class Controls
    {
        class Url: RscEdit
        {
            idc = 2611941;
            text = "";
            x = safeZoneX + safeZoneW * 0.5 - 0.23;
            y = safeZoneY + safeZoneH * 0.5 - 0.16;
            w = 0.35;
            h = 0.04;
        };
        class Add: RscButton
        {
            idc = -1;
            text = "$STR_A3YTR_ADD";
            x = safeZoneX + safeZoneW * 0.5 + 0.13;
            y = safeZoneY + safeZoneH * 0.5 - 0.16;
            w = 0.1;
            h = 0.04;
            onButtonClick = "['add', ctrlParent (_this select 0)] spawn A3YTR_fnc_ui";
        };
        class Queue: RscListBox
        {
            idc = 2611942;
            x = safeZoneX + safeZoneW * 0.5 - 0.23;
            y = safeZoneY + safeZoneH * 0.5 - 0.10;
            w = 0.46;
            h = 0.18;
        };
        class VolumeLabel: RscText
        {
            idc = -1;
            text = "$STR_A3YTR_VOLUME";
            x = safeZoneX + safeZoneW * 0.5 - 0.23;
            y = safeZoneY + safeZoneH * 0.5 + 0.09;
            w = 0.29;
            h = 0.04;
        };
        class Volume: RscEdit
        {
            idc = 2611943;
            text = "70";
            x = safeZoneX + safeZoneW * 0.5 + 0.12;
            y = safeZoneY + safeZoneH * 0.5 + 0.09;
            w = 0.11;
            h = 0.04;
        };
        class Apply: RscButton
        {
            idc = -1;
            text = "$STR_A3YTR_APPLY";
            x = safeZoneX + safeZoneW * 0.5 - 0.23;
            y = safeZoneY + safeZoneH * 0.5 + 0.15;
            w = 0.1;
            h = 0.04;
            onButtonClick = "['volume', ctrlParent (_this select 0)] call A3YTR_fnc_ui";
        };
        class Next: RscButton
        {
            idc = -1;
            text = "$STR_A3YTR_NEXT";
            x = safeZoneX + safeZoneW * 0.5 - 0.12;
            y = safeZoneY + safeZoneH * 0.5 + 0.15;
            w = 0.1;
            h = 0.04;
            onButtonClick = "['next', ctrlParent (_this select 0)] call A3YTR_fnc_ui";
        };
        class Stop: RscButton
        {
            idc = -1;
            text = "$STR_A3YTR_STOP";
            x = safeZoneX + safeZoneW * 0.5 - 0.01;
            y = safeZoneY + safeZoneH * 0.5 + 0.15;
            w = 0.1;
            h = 0.04;
            onButtonClick = "['stop', ctrlParent (_this select 0)] call A3YTR_fnc_ui";
        };
        class Close: RscButton
        {
            idc = -1;
            text = "$STR_A3YT_UI_CLOSE";
            x = safeZoneX + safeZoneW * 0.5 + 0.10;
            y = safeZoneY + safeZoneH * 0.5 + 0.15;
            w = 0.13;
            h = 0.04;
            onButtonClick = "closeDialog 0";
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
            class command {};
            class listener {};
            class ui {};
        };
    };
};
