local addonName = ...

local BUTTON_NAME = "GSCTwitchEmotes"
local LDB_BUTTON_NAME = "LibDBIcon10_" .. BUTTON_NAME
local ICON_PATH = "Interface\\AddOns\\GSCTwitchEmotes\\emotes\\Guild.tga"

local VALID_MODES = {
    always = true,
    hover = true,
    never = true,
}

local NEXT_MODE = {
    always = "hover",
    hover = "never",
    never = "always",
}

local MODE_LABEL = {
    always = "Always",
    hover = "On Hover",
    never = "Never",
}

local DEFAULT_SETTINGS = {
    enabled = true,
    minimapMode = "hover",
    minimap = {
        hide = false,
    },
}

local registeredEmotes = {}
local animatorWrapped = false
local autocompleteWrapped = false
local autocompleteRebuilt = false
local minimapMenu = nil

local LDB = nil
local LDBIcon = nil

local minimapHover = false
local buttonHover = false
local hoverHooksInstalled = false

local BROWSER_COLUMNS = 4
local BROWSER_ROWS = 8
local BROWSER_PER_PAGE = BROWSER_COLUMNS * BROWSER_ROWS
local BROWSER_CELL_WIDTH = 132
local BROWSER_CELL_HEIGHT = 66
local BROWSER_ICON_SIZE = 32
local currentEmotePage = 1
local emoteBrowser = nil
local emoteCells = {}
local browserPageText = nil
local browserPrevButton = nil
local browserNextButton = nil

local OWN_TAG_PATTERN = "(|TInterface\\AddOns\\GSCTwitchEmotes\\.-|t)"

local SetMinimapMode -- forward declaration
local ToggleEmoteBrowser -- forward declaration
local RefreshSettingsPanel -- forward declaration

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c
end

local legacyIsAddOnLoaded = IsAddOnLoaded

local function IsAddOnLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name) == true
    end

    if type(legacyIsAddOnLoaded) == "function" then
        return legacyIsAddOnLoaded(name) == true
    end

    return false
end

local function EnsureSettings()
    if type(GSCTwitchEmotes_Settings) ~= "table" then
        GSCTwitchEmotes_Settings = {}
    end

    for key, value in pairs(DEFAULT_SETTINGS) do
        if GSCTwitchEmotes_Settings[key] == nil then
            GSCTwitchEmotes_Settings[key] = value
        end
    end

    if type(GSCTwitchEmotes_Settings.minimap) ~= "table" then
        GSCTwitchEmotes_Settings.minimap = {}
    end

    if not VALID_MODES[GSCTwitchEmotes_Settings.minimapMode] then
        GSCTwitchEmotes_Settings.minimapMode = "hover"
    end

    GSCTwitchEmotes_Settings.minimap.hide = (GSCTwitchEmotes_Settings.minimapMode == "never")
end

local function CopyAnimationMetadata()
    if type(TwitchEmotes_animation_metadata) ~= "table" then
        TwitchEmotes_animation_metadata = {}
    end

    if type(GSCTwitchEmotes_animation_metadata) ~= "table" then return end

    for path, meta in pairs(GSCTwitchEmotes_animation_metadata) do
        if type(meta) ~= "table" or not meta.grid then
            TwitchEmotes_animation_metadata[path] = meta
        end
    end
end

local function RebuildAutocomplete()
    local suggestions = {}

    for name in pairs(registeredEmotes) do
        suggestions[#suggestions + 1] = name
    end

    if type(AllTwitchEmoteNames) == "table" then
        for _, name in ipairs(AllTwitchEmoteNames) do
            suggestions[#suggestions + 1] = name
        end
    end

    table.sort(suggestions)

    if not (Emoticons_Settings and Emoticons_Settings["ENABLE_AUTOCOMPLETE"]) then return end
    if type(SetupAutoComplete) ~= "function" then return end
    if not Emoticons_RenderSuggestionFN then return end

    for i = 1, (NUM_CHAT_WINDOWS or 0) do
        local chat = _G["ChatFrame" .. i]
        if chat and chat.editBox then
            SafeCall(SetupAutoComplete, chat.editBox, suggestions, 20, {
                perWord = true,
                activationChar = ":",
                closingChar = ":",
                minChars = 2,
                fuzzyMatch = true,
                onSuggestionApplied = function(suggestion)
                    if type(UpdateEmoteStats) == "function" then
                        SafeCall(UpdateEmoteStats, suggestion, true, false, false)
                    end
                end,
                renderSuggestionFN = Emoticons_RenderSuggestionFN,
                suggestionBiasFN = function(suggestion)
                    local stats = TwitchEmoteStatistics and TwitchEmoteStatistics[suggestion]
                    if type(stats) == "table" and tonumber(stats[1]) then
                        return tonumber(stats[1]) * 5
                    end
                    return 0
                end,
                interceptOnEnterPressed = true,
                addSpace = true,
                useTabToConfirm = Emoticons_Settings["AUTOCOMPLETE_CONFIRM_WITH_TAB"],
                useArrowButtons = true,
            })
        end
    end

    autocompleteRebuilt = true
end

local function MergeIntoAllTwitchEmoteNames()
    if type(AllTwitchEmoteNames) ~= "table" then return end

    local seen = {}
    for _, name in ipairs(AllTwitchEmoteNames) do
        seen[name] = true
    end

    for name in pairs(registeredEmotes) do
        if not seen[name] then
            AllTwitchEmoteNames[#AllTwitchEmoteNames + 1] = name
            seen[name] = true
        end
    end

    table.sort(AllTwitchEmoteNames)
end

-- Merge our emotes into every SetupAutoComplete call. Giga and the base addon
-- both rebuild the dropdown on their own; wrapping the function means our
-- names survive whichever one runs last.
local function WrapSetupAutoComplete()
    if autocompleteWrapped then return end
    if type(SetupAutoComplete) ~= "function" then return end

    local original = SetupAutoComplete

    SetupAutoComplete = function(editbox, valueList, maxButtonCount, settings)
        if type(valueList) == "table" then
            local seen = {}
            for _, name in ipairs(valueList) do
                seen[name] = true
            end

            for name in pairs(GSCTwitchEmotes_emotes or {}) do
                if not seen[name] then
                    valueList[#valueList + 1] = name
                    seen[name] = true
                end
            end

            table.sort(valueList)
        end

        return original(editbox, valueList, maxButtonCount, settings)
    end

    autocompleteWrapped = true
end

local function RegisterEmotes()
    registeredEmotes = {}

    if type(GSCTwitchEmotes_emotes) ~= "table" then return end
    if type(TwitchEmotes) ~= "table" or type(TwitchEmotes.AddEmote) ~= "function" then return end

    for name, path in pairs(GSCTwitchEmotes_emotes) do
        if type(name) == "string" and type(path) == "string" then
            SafeCall(TwitchEmotes.AddEmote, TwitchEmotes, name, name, path)
            registeredEmotes[name] = true
        end
    end

    MergeIntoAllTwitchEmoteNames()
    RebuildAutocomplete()
end

-- SexyMap automatically positions LibDBIcon buttons around the active map
-- shape and handles always/never/hover visibility when its "Let SexyMap
-- control button visibility" option is enabled. Mirror our mode into its
-- profile so the settings panel and SexyMap's UI stay in sync.
local function GetSexyMapButtonsProfile()
    if type(SexyMap2DB) ~= "table" then return nil end
    if not IsAddOnLoaded("SexyMap") then return nil end

    local profileName
    if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
        local name, surname = UnitNameUnmodified("player")
        profileName = (name or "") .. " " .. (surname or "")
    else
        local name = UnitNameUnmodified and UnitNameUnmodified("player") or UnitName("player")
        profileName = (name or "") .. "-" .. (GetRealmName() or "")
    end

    local profile = SexyMap2DB[profileName]
    if type(profile) == "string" then
        profile = SexyMap2DB[profile]
    end

    if type(profile) ~= "table" then return nil end
    if type(profile.buttons) ~= "table" then return nil end

    return profile.buttons
end

local function SexyMapControlsVisibility()
    local profile = GetSexyMapButtonsProfile()
    return profile ~= nil and profile.controlVisibility ~= false
end

local function SetSexyMapMode(mode)
    local profile = GetSexyMapButtonsProfile()
    if not profile then return false end

    if type(profile.visibilitySettings) ~= "table" then
        profile.visibilitySettings = {}
    end

    profile.visibilitySettings[LDB_BUTTON_NAME] = mode

    -- Best effort immediate apply. Newer builds expose their addon table
    -- globally; older ones only have the saved variable above.
    local sm = _G.SexyMap
    local module = sm and sm.buttons
    local button = LDBIcon and type(LDBIcon.GetMinimapButton) == "function"
        and LDBIcon:GetMinimapButton(BUTTON_NAME) or nil

    local appliedImmediately = false
    if module and button and type(module.ChangeFrameVisibility) == "function" then
        SafeCall(module.ChangeFrameVisibility, module, button, mode)
        appliedImmediately = true
    end

    return true, appliedImmediately
end

local function GetMinimapLDBButton()
    if not LDBIcon or type(LDBIcon.GetMinimapButton) ~= "function" then return nil end
    return LDBIcon:GetMinimapButton(BUTTON_NAME)
end

-- LibDBIcon:Show() repositions from db.minimapPos. SexyMap owns the position,
-- so use the button directly to avoid snapping back on reload.
local function ShowMinimapButton()
    local button = GetMinimapLDBButton()
    if button then
        SafeCall(button.Show, button)
    elseif LDBIcon then
        SafeCall(LDBIcon.Show, LDBIcon, BUTTON_NAME)
    end
end

local function HideMinimapButton()
    local button = GetMinimapLDBButton()
    if button then
        SafeCall(button.Hide, button)
    elseif LDBIcon then
        SafeCall(LDBIcon.Hide, LDBIcon, BUTTON_NAME)
    end
end

local function UpdateFallbackHover()
    if not LDBIcon then return end
    if not GSCTwitchEmotes_Settings then return end
    if SexyMapControlsVisibility() then return end

    local mode = GSCTwitchEmotes_Settings.minimapMode
    local show = false

    if mode == "always" then
        show = true
    elseif mode == "hover" then
        show = (minimapHover == true or buttonHover == true)
    end

    if show then
        GSCTwitchEmotes_Settings.minimap.hide = false
        ShowMinimapButton()
    else
        HideMinimapButton()
    end
end

local function InstallHoverHooks()
    if hoverHooksInstalled then return end

    local button = LDBIcon and type(LDBIcon.GetMinimapButton) == "function"
        and LDBIcon:GetMinimapButton(BUTTON_NAME) or nil

    if button then
        button:HookScript("OnEnter", function()
            buttonHover = true
            UpdateFallbackHover()
        end)
        button:HookScript("OnLeave", function()
            buttonHover = false
            UpdateFallbackHover()
        end)
    end

    if Minimap and type(Minimap.HookScript) == "function" then
        Minimap:HookScript("OnEnter", function()
            minimapHover = true
            UpdateFallbackHover()
        end)
        Minimap:HookScript("OnLeave", function()
            minimapHover = false
            UpdateFallbackHover()
        end)
    end

    hoverHooksInstalled = true
end

SetMinimapMode = function(mode, silent)
    if not VALID_MODES[mode] then return false end

    GSCTwitchEmotes_Settings.minimapMode = mode
    GSCTwitchEmotes_Settings.minimap.hide = (mode == "never")

    local sexyMapUpdated, sexyMapApplied = SetSexyMapMode(mode)

    if LDBIcon then
        if mode == "never" then
            if not sexyMapApplied then
                HideMinimapButton()
            end
        else
            ShowMinimapButton()
        end
    end

    UpdateFallbackHover()
    RefreshSettingsPanel()

    if not silent then
        print("|cFF7CFC00[GSC Twitch Emotes]|r Minimap button: " .. MODE_LABEL[mode])

        if IsAddOnLoaded("SexyMap") and not sexyMapApplied then
            print("|cFF7CFC00[GSC Twitch Emotes]|r SexyMap setting saved; /reload if the button does not update immediately.")
        end
    end

    return true
end

local function UpdateEmoteBrowserPage()
    if not emoteBrowser then return end

    local names = {}
    for name in pairs(GSCTwitchEmotes_emotes or {}) do
        names[#names + 1] = name
    end

    table.sort(names)

    local totalPages = math.max(1, math.ceil(#names / BROWSER_PER_PAGE))
    if currentEmotePage < 1 then currentEmotePage = 1 end
    if currentEmotePage > totalPages then currentEmotePage = totalPages end

    local firstIndex = (currentEmotePage - 1) * BROWSER_PER_PAGE + 1

    for i = 1, BROWSER_PER_PAGE do
        local cell = emoteCells[i]
        local name = names[firstIndex + i - 1]

        if not name then
            cell.frame:Hide()
        else
            cell.frame:Show()

            local path = GSCTwitchEmotes_emotes[name]
            local texturePath = type(path) == "string" and path:match("^(.-%.tga)") or nil
            cell.icon:SetTexture(texturePath)

            -- Keep wide emotes at their real shape (tag is path:height:width).
            local tagH, tagW = nil, nil
            if type(path) == "string" then
                tagH, tagW = path:match(":(%d+):(%d+)$")
            end
            local iconAspect = 1
            if tagH and tagW and tonumber(tagH) > 0 then
                iconAspect = tonumber(tagW) / tonumber(tagH)
            end
            local iconWidth = math.min(math.floor(BROWSER_ICON_SIZE * iconAspect + 0.5), BROWSER_CELL_WIDTH - 12)
            cell.icon:SetSize(iconWidth, BROWSER_ICON_SIZE)

            local meta = texturePath
                and ((GSCTwitchEmotes_animation_metadata and GSCTwitchEmotes_animation_metadata[texturePath])
                    or (TwitchEmotes_animation_metadata and TwitchEmotes_animation_metadata[texturePath]))
                or nil

            if type(meta) == "table" and meta.grid and meta.imageWidth and meta.imageHeight then
                local frameWidth = tonumber(meta.frameWidth) or 32
                local frameHeight = tonumber(meta.frameHeight) or 32
                cell.icon:SetTexCoord(
                    0,
                    frameWidth / meta.imageWidth,
                    0,
                    frameHeight / meta.imageHeight
                )
            elseif type(meta) == "table" and meta.nFrames and meta.imageHeight and meta.imageHeight > 0 then
                local frameHeight = tonumber(meta.frameHeight) or 32
                local pf = tonumber(meta.previewFrame) or 0
                if pf < 0 or pf >= meta.nFrames then pf = 0 end
                cell.icon:SetTexCoord(
                    0, 1,
                    (pf * frameHeight) / meta.imageHeight,
                    ((pf + 1) * frameHeight) / meta.imageHeight
                )
            else
                cell.icon:SetTexCoord(0, 1, 0, 1)
            end

            cell.label:SetText(name)
        end
    end

    browserPageText:SetText(string.format("Page %d / %d  (%d emotes)", currentEmotePage, totalPages, #names))

    if currentEmotePage <= 1 then
        browserPrevButton:Disable()
    else
        browserPrevButton:Enable()
    end

    if currentEmotePage >= totalPages then
        browserNextButton:Disable()
    else
        browserNextButton:Enable()
    end
end

ToggleEmoteBrowser = function()
    if not emoteBrowser then
        emoteBrowser = CreateFrame("Frame", "GSCTwitchEmotesBrowser", UIParent, "BackdropTemplate")
        emoteBrowser:SetSize(580, 620)
        emoteBrowser:SetPoint("CENTER")
        emoteBrowser:SetFrameStrata("DIALOG")
        emoteBrowser:SetMovable(true)
        emoteBrowser:EnableMouse(true)
        if type(emoteBrowser.EnableMouseWheel) == "function" then
            emoteBrowser:EnableMouseWheel(true)
        end
        emoteBrowser:RegisterForDrag("LeftButton")
        emoteBrowser:SetScript("OnDragStart", emoteBrowser.StartMoving)
        emoteBrowser:SetScript("OnDragStop", emoteBrowser.StopMovingOrSizing)
        emoteBrowser:SetScript("OnMouseWheel", function(_, delta)
            if delta > 0 then
                if currentEmotePage > 1 then
                    currentEmotePage = currentEmotePage - 1
                    UpdateEmoteBrowserPage()
                end
            else
                currentEmotePage = currentEmotePage + 1
                UpdateEmoteBrowserPage()
            end
        end)

        emoteBrowser:SetBackdrop({
            bgFile = "Interface\\AddOns\\GSCTwitchEmotes\\emotes\\solid.tga",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        emoteBrowser:SetBackdropColor(0, 0, 0, 0.8)
        emoteBrowser:SetBackdropBorderColor(1, 1, 1, 1)

        if type(UISpecialFrames) == "table" then
            tinsert(UISpecialFrames, emoteBrowser:GetName())
        end

        local title = emoteBrowser:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -18)
        title:SetText("GSC Twitch Emotes")

        local content = CreateFrame("Frame", nil, emoteBrowser)
        content:SetSize(BROWSER_COLUMNS * BROWSER_CELL_WIDTH, BROWSER_ROWS * BROWSER_CELL_HEIGHT)
        content:SetPoint("TOPLEFT", emoteBrowser, "TOPLEFT", 26, -54)

        for i = 1, BROWSER_PER_PAGE do
            local col = (i - 1) % BROWSER_COLUMNS
            local row = math.floor((i - 1) / BROWSER_COLUMNS)

            local cell = CreateFrame("Frame", nil, content)
            cell:SetSize(BROWSER_CELL_WIDTH, BROWSER_CELL_HEIGHT)
            cell:SetPoint("TOPLEFT", content, "TOPLEFT", col * BROWSER_CELL_WIDTH, -row * BROWSER_CELL_HEIGHT)

            local icon = cell:CreateTexture(nil, "ARTWORK")
            icon:SetSize(BROWSER_ICON_SIZE, BROWSER_ICON_SIZE)
            icon:SetPoint("TOP", cell, "TOP", 0, -4)

            local label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetWidth(BROWSER_CELL_WIDTH - 8)
            label:SetPoint("TOP", cell, "TOP", 0, -42)
            label:SetJustifyH("CENTER")

            emoteCells[i] = { frame = cell, icon = icon, label = label }
        end

        browserPageText = emoteBrowser:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        browserPageText:SetPoint("BOTTOM", 0, 22)

        browserPrevButton = CreateFrame("Button", nil, emoteBrowser, "GameMenuButtonTemplate")
        browserPrevButton:SetSize(90, 26)
        browserPrevButton:SetPoint("BOTTOMLEFT", emoteBrowser, "BOTTOMLEFT", 24, 12)
        browserPrevButton:SetText("Previous")
        browserPrevButton:SetScript("OnClick", function()
            if currentEmotePage > 1 then
                currentEmotePage = currentEmotePage - 1
                UpdateEmoteBrowserPage()
            end
        end)

        local closeButton = CreateFrame("Button", nil, emoteBrowser, "GameMenuButtonTemplate")
        closeButton:SetSize(70, 24)
        closeButton:SetPoint("TOPRIGHT", emoteBrowser, "TOPRIGHT", -24, -14)
        closeButton:SetText("Close")
        closeButton:SetScript("OnClick", function()
            emoteBrowser:Hide()
        end)

        browserNextButton = CreateFrame("Button", nil, emoteBrowser, "GameMenuButtonTemplate")
        browserNextButton:SetSize(90, 26)
        browserNextButton:SetPoint("BOTTOMRIGHT", emoteBrowser, "BOTTOMRIGHT", -24, 12)
        browserNextButton:SetText("Next")
        browserNextButton:SetScript("OnClick", function()
            currentEmotePage = currentEmotePage + 1
            UpdateEmoteBrowserPage()
        end)
    end

    local wasShown = emoteBrowser:IsShown()

    if not wasShown then
        currentEmotePage = 1
    end

    UpdateEmoteBrowserPage()
    emoteBrowser:Show()
    emoteBrowser:Raise()
end

-- Native AddOns settings page.
local SETTINGS_TITLE = "GSC Twitch Emotes"
local settingsCategory = nil
local legacySettingsPanel = nil
local modeCheckButtons = {}

RefreshSettingsPanel = function()
    for mode, button in pairs(modeCheckButtons) do
        if button.SetChecked then
            button:SetChecked(GSCTwitchEmotes_Settings.minimapMode == mode)
        end
    end
end

local function BuildSettingsPanel()
    local panel = CreateFrame("Frame", "GSCTwitchEmotesSettingsPanel", UIParent)
    panel.name = SETTINGS_TITLE

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(SETTINGS_TITLE)

    local intro = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 16, -42)
    intro:SetText("Minimap button visibility. Shape and dragging are handled by SexyMap when installed.")

    local section = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    section:SetPoint("TOPLEFT", 16, -74)
    section:SetText("Minimap Button")

    local modes = {
        { key = "always", label = "Always show" },
        { key = "hover", label = "Show only on hover" },
        { key = "never", label = "Hide button" },
    }

    for i, def in ipairs(modes) do
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", 20, -100 - ((i - 1) * 30))
        check.tooltipText = def.label
        check:SetScript("OnClick", function(self)
            if self:GetChecked() then
                SetMinimapMode(def.key)
            else
                self:SetChecked(true)
            end
        end)

        local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", check, "RIGHT", 4, 0)
        text:SetText(def.label)

        modeCheckButtons[def.key] = check
    end

    local openBrowser = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    openBrowser:SetSize(180, 28)
    openBrowser:SetPoint("TOPLEFT", 20, -210)
    openBrowser:SetText("Open Emote Browser")
    openBrowser:SetScript("OnClick", function()
        ToggleEmoteBrowser()
    end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 16, -250)
    hint:SetText("Left-click minimap button: emote browser | Right-click: settings | Shift+Right-click: hide button")

    RefreshSettingsPanel()
    return panel
end

local function RegisterSettingsPage()
    local panel = BuildSettingsPanel()

    if Settings
        and type(Settings.RegisterCanvasLayoutCategory) == "function"
        and type(Settings.RegisterAddOnCategory) == "function"
    then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        settingsCategory = category
        return
    end

    if type(InterfaceOptions_AddCategory) == "function" then
        InterfaceOptions_AddCategory(panel)
        legacySettingsPanel = panel
    end
end

local function OpenSettingsPage()
    if InCombatLockdown and InCombatLockdown() then
        print("|cFF7CFC00[GSC Twitch Emotes]|r Settings cannot be opened in combat.")
        return
    end

    if settingsCategory and Settings and type(Settings.OpenToCategory) == "function" then
        Settings.OpenToCategory(settingsCategory:GetID())
    elseif legacySettingsPanel and type(InterfaceOptionsFrame_OpenToCategory) == "function" then
        InterfaceOptionsFrame_OpenToCategory(legacySettingsPanel)
        InterfaceOptionsFrame_OpenToCategory(legacySettingsPanel)
    else
        print("|cFF7CFC00[GSC Twitch Emotes]|r Use the GSC Twitch Emotes settings panel.")
    end
end

local function ToggleMinimapMenu()
    if not minimapMenu then
        minimapMenu = CreateFrame("Frame", "GSCTwitchEmotesMinimapMenu", UIParent, "BasicFrameTemplateWithInset")
        minimapMenu:SetSize(230, 170)
        minimapMenu:SetPoint("CENTER")
        minimapMenu:SetMovable(true)
        minimapMenu:EnableMouse(true)
        minimapMenu:RegisterForDrag("LeftButton")
        minimapMenu:SetScript("OnDragStart", minimapMenu.StartMoving)
        minimapMenu:SetScript("OnDragStop", minimapMenu.StopMovingOrSizing)
        minimapMenu.title = minimapMenu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        minimapMenu.title:SetPoint("CENTER", minimapMenu.TitleBg, "CENTER", 0, 0)
        minimapMenu.title:SetText("GSC Twitch Emotes - Minimap")
        minimapMenu:Hide()

        if type(UISpecialFrames) == "table" then
            tinsert(UISpecialFrames, minimapMenu:GetName())
        end

        local order = { "always", "hover", "never" }
        for i, mode in ipairs(order) do
            local button = CreateFrame("Button", nil, minimapMenu, "GameMenuButtonTemplate")
            button:SetSize(190, 28)
            button:SetPoint("TOP", minimapMenu, "TOP", 0, -40 - ((i - 1) * 34))
            button:SetText(MODE_LABEL[mode])
            button:SetScript("OnClick", function()
                SetMinimapMode(mode)
                minimapMenu:Hide()
            end)
        end
    end

    if minimapMenu:IsShown() then
        minimapMenu:Hide()
    else
        minimapMenu:Show()
    end
end

local function InstallMinimapButton()
    if LibStub then
        LDB = LibStub("LibDataBroker-1.1", true)
        LDBIcon = LibStub("LibDBIcon-1.0", true)
    end

    if not LDB or not LDBIcon then return end

    local dataObject = LDB:GetDataObjectByName(BUTTON_NAME)
        or LDB:NewDataObject(BUTTON_NAME, {
            type = "launcher",
            text = "GSC Twitch Emotes",
            icon = ICON_PATH,
            OnClick = function(_, clickButton)
                if clickButton == "RightButton" then
                    if IsShiftKeyDown and IsShiftKeyDown() then
                        SetMinimapMode("never")
                    else
                        OpenSettingsPage()
                    end
                else
                    ToggleEmoteBrowser()
                end
            end,
            OnTooltipShow = function(tooltip)
                if not tooltip or not tooltip.AddLine then return end
                tooltip:AddLine("GSC Twitch Emotes")
                tooltip:AddLine("Left-click: open emote browser", 1, 1, 1)
                tooltip:AddLine("Right-click: open settings", 1, 1, 1)
                tooltip:AddLine("Shift+Right-click: hide button", 1, 1, 1)
                tooltip:AddLine("Current: " .. (MODE_LABEL[GSCTwitchEmotes_Settings.minimapMode] or "?"))
            end,
        })

    if not dataObject then return end

    GSCTwitchEmotes_Settings.minimap.hide = (GSCTwitchEmotes_Settings.minimapMode == "never")

    if not LDBIcon:IsRegistered(BUTTON_NAME) then
        LDBIcon:Register(BUTTON_NAME, dataObject, GSCTwitchEmotes_Settings.minimap)
    end

    InstallHoverHooks()
end

local function BuildGridFrameString(path, meta, framenum, displayHeight, displayWidth)
    local cols = tonumber(meta.cols) or 1
    local rows = tonumber(meta.rows) or 1
    local frameWidth = tonumber(meta.frameWidth) or 32
    local frameHeight = tonumber(meta.frameHeight) or 32
    local imageWidth = tonumber(meta.imageWidth) or (cols * frameWidth)
    local imageHeight = tonumber(meta.imageHeight) or (rows * frameHeight)

    local col = framenum % cols
    local row = math.floor(framenum / cols) % rows
    local left = col * frameWidth
    local right = left + frameWidth
    local top = row * frameHeight
    local bottom = top + frameHeight

    return "|T" .. path .. ":" .. displayHeight .. ":" .. displayWidth
        .. ":0:0:" .. imageWidth .. ":" .. imageHeight
        .. ":" .. left .. ":" .. right .. ":" .. top .. ":" .. bottom .. "|t"
end

-- Animates only GSCTwitchEmotes textures. Giga and the base animator keep
-- handling their own paths; this wrapper is installed at PLAYER_LOGIN so it
-- works no matter which extension addon loaded last.
local function ProcessOwnFontString(fontstring, widthOverride, heightOverride)
    if not fontstring or type(fontstring.GetText) ~= "function" then return end
    if fontstring.IsForbidden and fontstring:IsForbidden() then return end

    local txt = SafeCall(fontstring.GetText, fontstring)
    if type(txt) ~= "string" then return end
    if canaccessvalue and not canaccessvalue(txt) then return end
    if issecretvalue and issecretvalue(txt) then return end

    local metadata = type(GSCTwitchEmotes_animation_metadata) == "table"
        and GSCTwitchEmotes_animation_metadata
        or TwitchEmotes_animation_metadata
    if type(metadata) ~= "table" then return end

    local changed = false

    local newTxt = txt:gsub(OWN_TAG_PATTERN, function(tag)
        local imagepath = tag:match("|T([^:]+%.tga)")
        local animdata = imagepath and metadata[imagepath]

        if type(animdata) ~= "table" or not animdata.nFrames then
            return tag
        end

        local framenum = 0
        if type(TwitchEmotes_GetCurrentFrameNum) == "function" then
            framenum = SafeCall(TwitchEmotes_GetCurrentFrameNum, animdata) or 0
        elseif type(GetTime) == "function" then
            framenum = math.floor((GetTime() * (animdata.framerate or 18)) % animdata.nFrames)
        end

        local frameWidth = tonumber(animdata.frameWidth) or 32
        local frameHeight = tonumber(animdata.frameHeight) or 32
        local frameString

        if animdata.grid then
            local h = tonumber(heightOverride)
            local displayHeight = (h and h > 0) and h or 28
            local displayWidth = widthOverride or math.floor(
                displayHeight * frameWidth / frameHeight + 0.5
            )
            frameString = BuildGridFrameString(
                imagepath, animdata, framenum, displayHeight, displayWidth
            )
        elseif math.abs((tonumber(animdata.aspect) or (frameWidth / frameHeight)) - 1) > 0.03
            and type(TwitchEmotes_BuildEmoteFrameStringWithDimensions) == "function" then
            local h = tonumber(heightOverride)
            local displayHeight = (h and h > 0) and h or 28
            local trueAspect = tonumber(animdata.aspect) or (frameWidth / frameHeight)
            local displayWidth = math.floor(displayHeight * trueAspect + 0.5)
            frameString = SafeCall(
                TwitchEmotes_BuildEmoteFrameStringWithDimensions,
                imagepath, animdata, framenum, displayHeight, displayWidth
            )
        elseif widthOverride and heightOverride and type(TwitchEmotes_BuildEmoteFrameStringWithDimensions) == "function" then
            frameString = SafeCall(
                TwitchEmotes_BuildEmoteFrameStringWithDimensions,
                imagepath, animdata, framenum, heightOverride, widthOverride
            )
        elseif type(TwitchEmotes_BuildEmoteFrameString) == "function" then
            frameString = SafeCall(TwitchEmotes_BuildEmoteFrameString, imagepath, animdata, framenum)
        end

        if type(frameString) ~= "string" then return tag end
        changed = true
        return frameString
    end)

    if not changed then return end

    if type(fontstring.messageInfo) == "table" then
        fontstring.messageInfo.message = newTxt
    end

    SafeCall(fontstring.SetText, fontstring, newTxt)
end

local function InstallAnimatorWrapper()
    if animatorWrapped then return end

    local original = _G.TwitchEmotesAnimator_UpdateEmoteInFontString
    if type(original) ~= "function" then return end

    _G.TwitchEmotesAnimator_UpdateEmoteInFontString = function(fontstring, widthOverride, heightOverride)
        SafeCall(original, fontstring, widthOverride, heightOverride)
        ProcessOwnFontString(fontstring, widthOverride, heightOverride)
    end

    animatorWrapped = true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        EnsureSettings()
        CopyAnimationMetadata()
        WrapSetupAutoComplete()
        RegisterEmotes()
        InstallMinimapButton()
        RegisterSettingsPage()
    elseif event == "PLAYER_LOGIN" then
        CopyAnimationMetadata()
        InstallAnimatorWrapper()
        WrapSetupAutoComplete()

        if not autocompleteRebuilt then
            RegisterEmotes()
        end

        SetMinimapMode(GSCTwitchEmotes_Settings.minimapMode, true)

        -- Reapply after other PLAYER_LOGIN handlers (SexyMap included).
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function()
                SetMinimapMode(GSCTwitchEmotes_Settings.minimapMode, true)
                UpdateFallbackHover()
            end)
        end
    end
end)

SLASH_GSCTWITCHEMOTES1 = "/gsc"

SlashCmdList["GSCTWITCHEMOTES"] = function()
    ToggleEmoteBrowser()
end