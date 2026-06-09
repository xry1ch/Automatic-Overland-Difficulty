AODifficulty = AODifficulty or {}

local Addon = AODifficulty
local ADDON_NAME = "AOD"
local ADDON_DISPLAY_NAME = "AOD"
local ADDON_AUTHOR = "|cFFFF00Wrynch|r"
local ADDON_VERSION = "1.0.0"
local EVENT_NAMESPACE = ADDON_DISPLAY_NAME
local SAVED_VARS_NAME = "AODifficulty_SavedVariables"
local SAVED_VARS_VERSION = 1

local NO_CHANGE = -1

local SITUATION_DELVES = "delves"
local SITUATION_PUBLIC_DUNGEONS = "publicDungeons"
local SITUATION_OLD_GROUP_DUNGEONS = "groupDungeons"
local SITUATION_OPEN_WORLD = "openWorld"

local SETTINGS_DEFAULTS =
{
    enabled = true,
    situations =
    {
        [SITUATION_DELVES] = NO_CHANGE,
        [SITUATION_PUBLIC_DUNGEONS] = NO_CHANGE,
        [SITUATION_OPEN_WORLD] = NO_CHANGE,
    },
    regions =
    {
        ["*"] = NO_CHANGE,
    },
    migrations =
    {
        publicDungeonsFromGroupDungeons = false,
    },
}

local SCOPE_DEFAULTS =
{
    accountBoundSettings = true,
}

local SITUATION_BY_ZONE_DISPLAY_TYPE =
{
    [ZONE_DISPLAY_TYPE_DELVE] = SITUATION_DELVES,
    [ZONE_DISPLAY_TYPE_GROUP_DELVE] = SITUATION_DELVES,
    [ZONE_DISPLAY_TYPE_PUBLIC_DUNGEON] = SITUATION_PUBLIC_DUNGEONS,
    [ZONE_DISPLAY_TYPE_NONE] = SITUATION_OPEN_WORLD,
}

local VALID_DIFFICULTIES =
{
    [OVERLAND_DIFFICULTY_TYPE_BASEGAME] = true,
    [OVERLAND_DIFFICULTY_TYPE_JOURNEYMAN] = true,
    [OVERLAND_DIFFICULTY_TYPE_ADVENTURER] = true,
    [OVERLAND_DIFFICULTY_TYPE_VETERAN] = true,
}

local function IsValidDifficulty(value)
    return value == NO_CHANGE or VALID_DIFFICULTIES[value] == true
end

local function NormalizeDifficulty(value)
    if IsValidDifficulty(value) then
        return value
    end
    return NO_CHANGE
end

local function BuildDifficultyChoices()
    local choices =
    {
        "Do not change",
        GetString("SI_OVERLANDDIFFICULTYTYPE", OVERLAND_DIFFICULTY_TYPE_BASEGAME),
        GetString("SI_OVERLANDDIFFICULTYTYPE", OVERLAND_DIFFICULTY_TYPE_JOURNEYMAN),
        GetString("SI_OVERLANDDIFFICULTYTYPE", OVERLAND_DIFFICULTY_TYPE_ADVENTURER),
        GetString("SI_OVERLANDDIFFICULTYTYPE", OVERLAND_DIFFICULTY_TYPE_VETERAN),
    }

    local values =
    {
        NO_CHANGE,
        OVERLAND_DIFFICULTY_TYPE_BASEGAME,
        OVERLAND_DIFFICULTY_TYPE_JOURNEYMAN,
        OVERLAND_DIFFICULTY_TYPE_ADVENTURER,
        OVERLAND_DIFFICULTY_TYPE_VETERAN,
    }

    return choices, values
end

local function GetProfileName()
    return GetWorldName()
end

function Addon:GetSituationSettings(situation)
    local savedVars = self.savedVars
    if not savedVars or not savedVars.situations then
        return NO_CHANGE
    end
    return NormalizeDifficulty(savedVars.situations[situation])
end

function Addon:SetSituationSettings(situation, difficulty)
    difficulty = NormalizeDifficulty(difficulty)
    if self.savedVars.situations[situation] ~= difficulty then
        self.savedVars.situations[situation] = difficulty
    end
    self:ApplyCurrentSituation()
end

function Addon:GetRegionSettings(regionId)
    local savedVars = self.savedVars
    if not savedVars or regionId == nil or type(savedVars.regions) ~= "table" then
        return NO_CHANGE
    end
    return NormalizeDifficulty(savedVars.regions[regionId])
end

function Addon:SetRegionSettings(regionId, difficulty)
    if regionId == nil then
        return
    end

    difficulty = NormalizeDifficulty(difficulty)
    if type(self.savedVars.regions) ~= "table" then
        self.savedVars.regions = {}
    end

    if difficulty == NO_CHANGE then
        if rawget(self.savedVars.regions, regionId) ~= nil then
            self.savedVars.regions[regionId] = nil
        end
    elseif self.savedVars.regions[regionId] ~= difficulty then
        self.savedVars.regions[regionId] = difficulty
    end

    self:ApplyCurrentSituation()
end

function Addon:ResetRegionSettings()
    if type(self.savedVars.regions) ~= "table" then
        self.savedVars.regions = {}
    else
        for regionId in pairs(self.savedVars.regions) do
            self.savedVars.regions[regionId] = nil
        end
    end

    self:ApplyCurrentSituation()
end

function Addon:GetPlayerRegionId()
    local zoneIndex = GetUnitZoneIndex("player")
    if not zoneIndex then
        return nil
    end

    local zoneId = GetZoneId(zoneIndex)
    local regionId = GetZoneStoryZoneIdForZoneId(zoneId)
    if regionId == 0 then
        return nil
    end

    return regionId
end

function Addon:MigrateSavedVars()
    local savedVars = self.savedVars
    savedVars.situations = savedVars.situations or {}
    if type(savedVars.regions) ~= "table" then
        savedVars.regions = {}
    end
    savedVars.migrations = savedVars.migrations or {}

    for regionId, difficulty in pairs(savedVars.regions) do
        if NormalizeDifficulty(difficulty) == NO_CHANGE then
            savedVars.regions[regionId] = nil
        end
    end

    if savedVars.migrations.publicDungeonsFromGroupDungeons then
        return
    end

    local oldDifficulty = NormalizeDifficulty(savedVars.situations[SITUATION_OLD_GROUP_DUNGEONS])
    if oldDifficulty ~= NO_CHANGE and self:GetSituationSettings(SITUATION_PUBLIC_DUNGEONS) == NO_CHANGE then
        savedVars.situations[SITUATION_PUBLIC_DUNGEONS] = oldDifficulty
    end

    savedVars.migrations.publicDungeonsFromGroupDungeons = true
end

function Addon:GetCurrentSituation()
    return SITUATION_BY_ZONE_DISPLAY_TYPE[self.currentZoneDisplayType]
end

function Addon:SetPendingZoneDisplayType(zoneDisplayType)
    self.pendingZoneDisplayType = zoneDisplayType
    self.hasPendingZoneDisplayType = true
end

function Addon:ApplyCurrentSituation()
    if not self.savedVars or not self.savedVars.enabled then
        return
    end

    local desiredDifficulty = self:GetRegionSettings(self:GetPlayerRegionId())
    if desiredDifficulty == NO_CHANGE then
        local situation = self:GetCurrentSituation()
        if not situation then
            return
        end

        desiredDifficulty = self:GetSituationSettings(situation)
        if desiredDifficulty == NO_CHANGE then
            return
        end
    end

    if GetOverlandDifficultyDisabledReason() ~= OVERLAND_DIFFICULTY_DISABLED_REASON_NONE then
        return
    end

    if GetOverlandDifficulty() ~= desiredDifficulty then
        RequestChangePlayerOverlandDifficulty(desiredDifficulty)
    end
end

function Addon:OnPlayerActivated()
    if self.hasPendingZoneDisplayType then
        self.currentZoneDisplayType = self.pendingZoneDisplayType
        self.pendingZoneDisplayType = nil
        self.hasPendingZoneDisplayType = false
    end

    self:ApplyCurrentSituation()
end

function Addon:OnPrepareForJump(_, _, _, _, zoneDisplayType)
    self:SetPendingZoneDisplayType(zoneDisplayType)
end

function Addon:OnAreaLoadStarted(_, _, _, _, _, _, zoneDisplayType)
    self:SetPendingZoneDisplayType(zoneDisplayType)
end

function Addon:CreateSituationDropdown(situation, name, tooltip, choices, values)
    return
    {
        type = "dropdown",
        name = name,
        tooltip = tooltip,
        choices = choices,
        choicesValues = values,
        sort = "numericvalue-up",
        getFunc = function()
            return self:GetSituationSettings(situation)
        end,
        setFunc = function(value)
            self:SetSituationSettings(situation, value)
        end,
        default = SETTINGS_DEFAULTS.situations[situation],
        width = "full",
    }
end

function Addon:CreateResetRegionsButton()
    return
    {
        type = "button",
        name = "Reset Zones",
        tooltip = "Set every zone override back to Do not change.",
        func = function()
            self:ResetRegionSettings()
        end,
        isDangerous = true,
        warning = "Reset all zone difficulty settings to Do not change?",
        width = "full",
    }
end

function Addon:CreateRegionDropdown(regionId, regionName, choices, values)
    return
    {
        type = "dropdown",
        name = regionName,
        tooltip = "When set to a difficulty, this zone overrides the matching situation setting.",
        choices = choices,
        choicesValues = values,
        sort = "numericvalue-up",
        getFunc = function()
            return self:GetRegionSettings(regionId)
        end,
        setFunc = function(value)
            self:SetRegionSettings(regionId, value)
        end,
        default = NO_CHANGE,
        width = "full",
    }
end

function Addon:BuildRegionDropdownControls(choices, values)
    local regions = {}
    local regionId = GetNextZoneStoryZoneId(nil)

    while regionId do
        local regionName = GetZoneNameById(regionId)
        if regionName ~= nil and regionName ~= "" then
            regions[#regions + 1] =
            {
                id = regionId,
                name = ZO_CachedStrFormat(SI_ZONE_NAME, regionName),
            }
        end

        regionId = GetNextZoneStoryZoneId(regionId)
    end

    table.sort(regions, function(left, right)
        if left.name == right.name then
            return left.id < right.id
        end
        return left.name < right.name
    end)

    local controls =
    {
        self:CreateResetRegionsButton(),
    }

    for index = 1, #regions do
        local region = regions[index]
        controls[#controls + 1] = self:CreateRegionDropdown(region.id, region.name, choices, values)
    end

    return controls
end

function Addon:LoadActiveSettings()
    local profileName = GetProfileName()
    if self.scopeVars.accountBoundSettings ~= false then
        self.savedVars = ZO_SavedVars:NewAccountWide(SAVED_VARS_NAME, SAVED_VARS_VERSION, "Settings", SETTINGS_DEFAULTS, profileName)
    else
        self.savedVars = ZO_SavedVars:NewCharacterIdSettings(SAVED_VARS_NAME, SAVED_VARS_VERSION, "Settings", SETTINGS_DEFAULTS, profileName)
    end

    self:MigrateSavedVars()
end

function Addon:RegisterSettings()
    local LAM = LibAddonMenu2
    if not LAM then
        return
    end

    local choices, values = BuildDifficultyChoices()

    local panelData =
    {
        type = "panel",
        name = ADDON_DISPLAY_NAME,
        displayName = ADDON_DISPLAY_NAME,
        author = ADDON_AUTHOR,
        version = ADDON_VERSION,
        slashCommand = "/aodifficulty",
        registerForRefresh = true,
        registerForDefaults = true,
    }

    local optionsTable =
    {
        {
            type = "checkbox",
            name = "Enabled",
            tooltip = "Request difficulty changes automatically.",
            getFunc = function()
                return self.savedVars.enabled
            end,
            setFunc = function(value)
                if self.savedVars.enabled ~= value then
                    self.savedVars.enabled = value
                end
                self:ApplyCurrentSituation()
            end,
            default = SETTINGS_DEFAULTS.enabled,
            width = "full",
        },
        {
            type = "checkbox",
            name = "Account Bound Settings",
            tooltip = "Share settings across characters.",
            getFunc = function()
                return self.scopeVars.accountBoundSettings ~= false
            end,
            setFunc = function(value)
                self.scopeVars.accountBoundSettings = value
                self:LoadActiveSettings()
                self:ApplyCurrentSituation()
            end,
            default = SCOPE_DEFAULTS.accountBoundSettings,
            width = "full",
        },
        {
            type = "header",
            name = "Situations",
            width = "full",
        },
        self:CreateSituationDropdown(
            SITUATION_DELVES,
            "Delves",
            "Delves and group delves.",
            choices,
            values
        ),
        self:CreateSituationDropdown(
            SITUATION_PUBLIC_DUNGEONS,
            "Public Dungeons",
            "Public dungeon zones.",
            choices,
            values
        ),
        self:CreateSituationDropdown(
            SITUATION_OPEN_WORLD,
            "Open World",
            "Standard overland zones.",
            choices,
            values
        ),
        {
            type = "submenu",
            name = "Zones",
            tooltip = "Set difficulty changes for large map zones.",
            controls = self:BuildRegionDropdownControls(choices, values),
        },
    }

    LAM:RegisterAddonPanel(ADDON_NAME, panelData)
    LAM:RegisterOptionControls(ADDON_NAME, optionsTable)
end

function Addon:RegisterEvents()
    local eventManager = EVENT_MANAGER

    eventManager:RegisterForEvent(EVENT_NAMESPACE, EVENT_PLAYER_ACTIVATED, function(...)
        self:OnPlayerActivated(...)
    end)

    eventManager:RegisterForEvent(EVENT_NAMESPACE, EVENT_PREPARE_FOR_JUMP, function(...)
        self:OnPrepareForJump(...)
    end)

    -- Verified in esoui/app/loadingscreen/sharedloadingscreen.lua. This event is not listed in ESOUIDocumentation.txt.
    if EVENT_AREA_LOAD_STARTED ~= nil then
        eventManager:RegisterForEvent(EVENT_NAMESPACE, EVENT_AREA_LOAD_STARTED, function(...)
            self:OnAreaLoadStarted(...)
        end)
    end

    eventManager:RegisterForEvent(EVENT_NAMESPACE, EVENT_OVERLAND_DIFFICULTY_CHANGED, function()
        self:ApplyCurrentSituation()
    end)

    eventManager:RegisterForEvent(EVENT_NAMESPACE, EVENT_OVERLAND_DIFFICULTY_DISABLED_BY_SERVER_CHANGED, function()
        self:ApplyCurrentSituation()
    end)
end

function Addon:Initialize()
    local profileName = GetProfileName()
    self.scopeVars = ZO_SavedVars:NewAccountWide(SAVED_VARS_NAME, SAVED_VARS_VERSION, "Scope", SCOPE_DEFAULTS, profileName)
    self:LoadActiveSettings()
    self:RegisterSettings()
    self:RegisterEvents()
end

local function OnAddOnLoaded(_, addonName)
    if addonName ~= ADDON_NAME then
        return
    end

    EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE, EVENT_ADD_ON_LOADED)
    Addon:Initialize()
end

EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
