-- Luacheck settings for the addon's Lua (run as "luacheck src").
std = "lua51"
max_line_length = false
-- AGENTS.md asks for every local to start with an explicit value, so a
-- first assignment that is later replaced is expected.
ignore = { "311" }

-- Globals the addon defines for the client to find.
globals = {
    "CVarBrowserDB",
    "CVarBrowser_OnAddonCompartmentClick",
    "CVarBrowser_OnAddonCompartmentEnter",
    "CVarBrowser_OnAddonCompartmentLeave",
    "SLASH_CVARBROWSER1",
    "SLASH_CVARBROWSER2",
    "SLASH_CVARBROWSER3",
}

-- Client APIs. Each file localizes the ones it uses at its top.
read_globals = {
    "C_AddOns",
    "C_CVar",
    "C_Console",
    "C_Timer",
    "ConsoleGetAllCommands",
    "CreateFont",
    "CreateFrame",
    "DEFAULT_CHAT_FRAME",
    "Enum",
    "GameTooltip",
    "GetAddOnMetadata",
    "GetCVar",
    "GetCVarDefault",
    "GetCVarInfo",
    "GetCursorPosition",
    "GetPhysicalScreenSize",
    "InCombatLockdown",
    "IsAltKeyDown",
    "IsControlKeyDown",
    "IsMouseButtonDown",
    "IsShiftKeyDown",
    "Minimap",
    "STANDARD_TEXT_FONT",
    "SetCVar",
    SlashCmdList = { fields = { CVARBROWSER = { read_only = false } } },
    "UIParent",
    "UISpecialFrames",
    "date",
    "time",
}
