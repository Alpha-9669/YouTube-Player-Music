class CfgPatches
{
    class A3YT_player
    {
        name = "$STR_A3YT_PATCH_NAME";
        author = "Alpha";
        requiredVersion = 2.14;
        requiredAddons[] = {"A3_Modules_F", "cba_ui"};
        units[] = {"A3YT_ModuleYoutubeAudio"};
        weapons[] = {};
    };
};

class RscText;
class RscEdit;
class RscButton;
class RscCheckBox;
class RscListBox;
class RscControlsGroup;
class RscControlsGroupNoScrollbars;
class RscXSliderH;
class RscDisplayAttributes
{
    class Controls
    {
        class Background;
        class Title;
        class Content;
        class ButtonOK;
        class ButtonCancel;
    };
};

class A3YT_RscAttributeYoutube: RscControlsGroupNoScrollbars
{
    idc = 2611900;
    x = 0 * (((safeZoneW / safeZoneH) min 1.2) / 40);
    y = 0 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
    w = 34 * (((safeZoneW / safeZoneH) min 1.2) / 40);
    h = 14.4 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);

    class controls
    {
        class UrlLabel: RscText
        {
            idc = -1;
            text = "$STR_A3YT_UI_NEW_URL";
            x = 0;
            y = 0;
            w = 14 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            colorBackground[] = {0,0,0,0};
        };

        class UrlValue: RscEdit
        {
            idc = 2611901;
            x = 0;
            y = 1.1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 27.2 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            colorBackground[] = {0,0,0,0.2};
        };

        class AddButton: RscButton
        {
            idc = 2611902;
            text = "$STR_A3YT_UI_ADD";
            x = 28.0 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            y = 1.1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 6.0 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
        };

        class VolumeLabel: RscText
        {
            idc = -1;
            text = "$STR_A3YT_UI_VOLUME";
            x = 0;
            y = 2.35 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 6.4 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            colorBackground[] = {0,0,0,0};
        };

        class VolumeValue: RscEdit
        {
            idc = 2611903;
            x = 6.8 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            y = 2.35 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 4.4 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            colorBackground[] = {0,0,0,0.2};
        };

        class NotifyLabel: RscText
        {
            idc = -1;
            text = "$STR_A3YT_UI_NOTIFY";
            x = 12.4 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            y = 2.35 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 8.6 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            colorBackground[] = {0,0,0,0};
        };

        class NotifyValue: RscCheckBox
        {
            idc = 2611904;
            x = 21.4 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            y = 2.35 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 1 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
        };

        class ConsumePlayedLabel: RscText
        {
            idc = -1;
            text = "$STR_A3YT_UI_CONSUME_PLAYED";
            x = 12.4 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            y = 3.35 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 8.6 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            colorBackground[] = {0,0,0,0};
        };

        class ConsumePlayedValue: RscCheckBox
        {
            idc = 2611915;
            x = 21.4 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            y = 3.35 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 1 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
        };

        class LoopQueueLabel: RscText
        {
            idc = -1;
            text = "$STR_A3YT_UI_LOOP_QUEUE";
            x = 0;
            y = 3.35 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 6.4 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            colorBackground[] = {0,0,0,0};
        };

        class LoopQueueValue: RscCheckBox
        {
            idc = 2611916;
            x = 6.8 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            y = 3.35 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 1 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
        };

        class LoopQueueSpacer: RscText
        {
            idc = -1;
            x = 8.2 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            y = 3.35 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 3.4 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 0.9 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            colorBackground[] = {0,0,0,0};
        };

        class TimelineLabel: RscText
        {
            idc = -1;
            text = "$STR_A3YT_UI_TIMELINE";
            x = 0;
            y = 4.45 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 18 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 0.8 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            colorBackground[] = {0,0,0,0};
        };

        class TimelineValue: RscText
        {
            idc = 2611913;
            text = "00:00 / 00:00";
            x = 24.5 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            y = 4.45 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 9.5 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 0.8 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            style = 1;
            colorBackground[] = {0,0,0,0};
        };

        class TimelineSlider: RscXSliderH
        {
            idc = 2611912;
            x = 0;
            y = 5.35 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 34 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 0.9 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
        };

        class QueueLabel: RscText
        {
            idc = -1;
            text = "$STR_A3YT_UI_QUEUE";
            x = 0;
            y = 6.55 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 10 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            colorBackground[] = {0,0,0,0};
        };

        class QueueGroup: RscControlsGroup
        {
            idc = 2611914;
            x = 0;
            y = 7.55 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 34 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 5.7 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            colorBackground[] = {0,0,0,0.2};
        };

        class StartButton: RscButton
        {
            idc = 2611911;
            text = "$STR_A3YT_UI_START";
            x = 0;
            y = 13.55 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 10.7 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
        };

        class PauseResumeButton: RscButton
        {
            idc = 2611909;
            text = "$STR_A3YT_UI_PAUSE_PLAYLIST";
            x = 11.65 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            y = 13.55 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 10.7 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
        };

        class StopPlaylistButton: RscButton
        {
            idc = 2611910;
            text = "$STR_A3YT_UI_STOP_PLAYLIST";
            x = 23.3 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            y = 13.55 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            w = 10.7 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
        };
    };
};

class A3YT_RscDisplayAttributesModuleYoutube: RscDisplayAttributes
{
    onLoad = "['onLoad', _this, 'A3YT_RscDisplayAttributesModuleYoutube'] call A3YT_fnc_zeusAttributes";
    onUnload = "['onUnload', _this, 'A3YT_RscDisplayAttributesModuleYoutube'] call A3YT_fnc_zeusAttributes";

    class Controls: Controls
    {
        class Background: Background
        {
            x = safeZoneX + (safeZoneW - (34 * (((safeZoneW / safeZoneH) min 1.2) / 40))) * 0.5;
            y = safeZoneY + (safeZoneH - (16.5 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25))) * 0.5;
            w = 34 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 16.5 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
        };
        class Title: Title
        {
            x = safeZoneX + (safeZoneW - (34 * (((safeZoneW / safeZoneH) min 1.2) / 40))) * 0.5;
            y = safeZoneY + (safeZoneH - (16.5 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25))) * 0.5 - (1 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25));
            w = 34 * (((safeZoneW / safeZoneH) min 1.2) / 40);
        };
        class Content: Content
        {
            x = safeZoneX + (safeZoneW - (34 * (((safeZoneW / safeZoneH) min 1.2) / 40))) * 0.5;
            y = safeZoneY + (safeZoneH - (16.5 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25))) * 0.5;
            w = 34 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            h = 14.6 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25);
            class Controls
            {
                class A3YTSettings: A3YT_RscAttributeYoutube {};
            };
        };
        class ButtonOK: ButtonOK
        {
            x = safeZoneX + (safeZoneW - (34 * (((safeZoneW / safeZoneH) min 1.2) / 40))) * 0.5 + (21 * (((safeZoneW / safeZoneH) min 1.2) / 40));
            y = safeZoneY + (safeZoneH - (16.5 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25))) * 0.5 + (15.75 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25));
            w = 13 * (((safeZoneW / safeZoneH) min 1.2) / 40);
            onLoad = "_this call A3YT_fnc_uiModuleYoutube";
        };
        class ButtonCancel: ButtonCancel
        {
            x = safeZoneX + (safeZoneW - (34 * (((safeZoneW / safeZoneH) min 1.2) / 40))) * 0.5;
            y = safeZoneY + (safeZoneH - (16.5 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25))) * 0.5 + (15.75 * ((((safeZoneW / safeZoneH) min 1.2) / 1.2) / 25));
            w = 13 * (((safeZoneW / safeZoneH) min 1.2) / 40);
        };
    };
};

class A3YT_RscDisplayLocalVolumeSettings
{
    idd = 2611930;
    movingEnable = 0;
    enableSimulation = 1;
    onLoad = "_this call A3YT_fnc_uiLocalVolumeSettings";

    class ControlsBackground
    {
        class Background: RscText
        {
            idc = -1;
            x = safeZoneX + (safeZoneW * 0.5) - 0.21;
            y = safeZoneY + (safeZoneH * 0.5) - 0.16;
            w = 0.42;
            h = 0.32;
            colorBackground[] = {0,0,0,0.82};
        };

        class Title: RscText
        {
            idc = -1;
            text = "$STR_A3YT_PAUSE_LOCAL_VOLUME_TITLE";
            x = safeZoneX + (safeZoneW * 0.5) - 0.21;
            y = safeZoneY + (safeZoneH * 0.5) - 0.16;
            w = 0.42;
            h = 0.04;
            colorBackground[] = {0.55,0.36,0.05,0.95};
        };
    };

    class Controls
    {
        class VolumeLabel: RscText
        {
            idc = -1;
            text = "$STR_A3YT_SETTING_LOCAL_VOLUME_NAME";
            x = safeZoneX + (safeZoneW * 0.5) - 0.18;
            y = safeZoneY + (safeZoneH * 0.5) - 0.095;
            w = 0.24;
            h = 0.035;
            colorBackground[] = {0,0,0,0};
        };

        class VolumeValue: RscEdit
        {
            idc = 2611931;
            x = safeZoneX + (safeZoneW * 0.5) + 0.08;
            y = safeZoneY + (safeZoneH * 0.5) - 0.095;
            w = 0.10;
            h = 0.035;
            colorBackground[] = {0,0,0,0.35};
        };

        class OverrideLabel: RscText
        {
            idc = -1;
            text = "$STR_A3YT_SETTING_LOCAL_VOLUME_OVERRIDE_NAME";
            x = safeZoneX + (safeZoneW * 0.5) - 0.18;
            y = safeZoneY + (safeZoneH * 0.5) - 0.04;
            w = 0.24;
            h = 0.035;
            colorBackground[] = {0,0,0,0};
        };

        class OverrideValue: RscCheckBox
        {
            idc = 2611932;
            x = safeZoneX + (safeZoneW * 0.5) + 0.08;
            y = safeZoneY + (safeZoneH * 0.5) - 0.04;
            w = 0.035;
            h = 0.035;
        };

        class EffectiveLabel: RscText
        {
            idc = -1;
            text = "$STR_A3YT_PAUSE_EFFECTIVE_VOLUME";
            x = safeZoneX + (safeZoneW * 0.5) - 0.18;
            y = safeZoneY + (safeZoneH * 0.5) + 0.02;
            w = 0.24;
            h = 0.035;
            colorBackground[] = {0,0,0,0};
        };

        class EffectiveValue: RscText
        {
            idc = 2611933;
            text = "";
            x = safeZoneX + (safeZoneW * 0.5) + 0.08;
            y = safeZoneY + (safeZoneH * 0.5) + 0.02;
            w = 0.10;
            h = 0.035;
            colorBackground[] = {0,0,0,0.2};
        };

        class ApplyButton: RscButton
        {
            idc = 2611934;
            text = "$STR_A3YT_UI_APPLY";
            x = safeZoneX + (safeZoneW * 0.5) - 0.18;
            y = safeZoneY + (safeZoneH * 0.5) + 0.09;
            w = 0.16;
            h = 0.04;
            onButtonClick = "['apply', ctrlParent (_this select 0)] call A3YT_fnc_uiLocalVolumeSettings";
        };

        class CloseButton: RscButton
        {
            idc = 2611935;
            text = "$STR_A3YT_UI_CLOSE";
            x = safeZoneX + (safeZoneW * 0.5) + 0.02;
            y = safeZoneY + (safeZoneH * 0.5) + 0.09;
            w = 0.16;
            h = 0.04;
            onButtonClick = "closeDialog 0";
        };
    };
};

class CfgFactionClasses
{
    class NO_CATEGORY;

    class A3YT_Category: NO_CATEGORY
    {
        displayName = "$STR_A3YT_CATEGORY";
    };
};

class CfgFunctions
{
    class A3YT
    {
        tag = "A3YT";

        class Core
        {
            file = "\a3yt_player\functions";
            class applyLocalVolumeSettings {};
            class callExtension {};
            class emptyFunction {};
            class forceStopLocalPlayback {};
            class getEffectiveVolume {};
            class handleLocalPlayback {};
            class moduleYoutube {};
            class monitorCurators {};
            class postInit
            {
                postInit = 1;
            };
            class registerSettings {};
            class uiLocalVolumeSettings {};
            class uiModuleYoutube {};
            class zeusAttributes {};
        };
    };
};

class CfgVehicles
{
    class Logic;
    class Module_F: Logic
    {
        class AttributesBase
        {
            class Default;
            class Edit;
            class Combo;
            class Checkbox;
        };

        class ModuleDescription
        {
            class AnyPlayer;
        };
    };

    class A3YT_ModuleYoutubeAudio: Module_F
    {
        scope = 2;
        scopeCurator = 2;
        displayName = "$STR_A3YT_MODULE_DISPLAY_NAME";
        category = "A3YT_Category";
        function = "A3YT_fnc_emptyFunction";
        functionPriority = 1;
        isGlobal = 0;
        isTriggerActivated = 0;
        isDisposable = 1;
        curatorCanAttach = 0;
        curatorInfoType = "A3YT_RscDisplayAttributesModuleYoutube";
        icon = "iconSound";

        class Attributes: AttributesBase
        {
            class Url: Edit
            {
                property = "A3YT_ModuleYoutubeAudio_Url";
                displayName = "$STR_A3YT_ATTR_URL_NAME";
                tooltip = "$STR_A3YT_ATTR_URL_TOOLTIP";
                typeName = "STRING";
                defaultValue = """""";
            };

            class Volume: Edit
            {
                property = "A3YT_ModuleYoutubeAudio_Volume";
                displayName = "$STR_A3YT_ATTR_VOLUME_NAME";
                tooltip = "$STR_A3YT_ATTR_VOLUME_TOOLTIP";
                typeName = "NUMBER";
                defaultValue = "70";
            };

            class Notify: Checkbox
            {
                property = "A3YT_ModuleYoutubeAudio_Notify";
                displayName = "$STR_A3YT_ATTR_NOTIFY_NAME";
                tooltip = "$STR_A3YT_ATTR_NOTIFY_TOOLTIP";
                typeName = "BOOL";
                defaultValue = "false";
            };
        };

        class ModuleDescription: ModuleDescription
        {
            description = "$STR_A3YT_MODULE_DESCRIPTION";
        };
    };
};
