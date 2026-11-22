local ADDON = "HealerRuns"
local CHAT_COOLDOWN = 10

local db, pending
local ui = {}
local wipeActive = false
local lastReply = 0

local function Print(msg)
    print("|cff33ff99HealerRuns|r: " .. msg)
end

local function InitDB()
    HealerRunsDB = HealerRunsDB or {}
    db = HealerRunsDB
    db.runs = db.runs or {}
    db.extraDungeons = db.extraDungeons or {}
    db.pending = db.pending or { dungeon = nil, completed = false, wipes = 0, deaths = 0 }
    pending = db.pending
end

local function DungeonList()
    local list, seen = {}, {}
    for _, n in ipairs(HealerRunsDungeons) do list[#list + 1] = n; seen[n] = true end
    for _, n in ipairs(db.extraDungeons) do
        if not seen[n] then list[#list + 1] = n; seen[n] = true end
    end
    return list
end

---------------------------------------------------------------------------
-- Statistics
---------------------------------------------------------------------------
local function Pct(n, d)
    if d == 0 then return 0 end
    return math.floor(n / d * 100 + 0.5)
end

local function SummaryLines()
    local total, completed, perfect, noWipe, deaths = #db.runs, 0, 0, 0, 0
    for _, r in ipairs(db.runs) do
        local d, w = r.deaths or 0, r.wipes or 0
        deaths = deaths + d
        if r.completed or r.success then
            completed = completed + 1
            if d == 0 and w == 0 then perfect = perfect + 1 end
        end
        if w == 0 then noWipe = noWipe + 1 end
    end
    return {
        string.format("%d dungeons completed out of %d runs (%d%%)", completed, total, Pct(completed, total)),
        string.format("%d%% perfect runs without deaths", Pct(perfect, total)),
        string.format("%d%% runs without wipes", Pct(noWipe, total)),
        string.format("%d deaths on my watch (sorry!)", deaths),
    }
end

local function PrintSummary()
    for _, l in ipairs(SummaryLines()) do Print(l) end
end

local function SendSummary(channel)
    for _, l in ipairs(SummaryLines()) do SendChatMessage(l, channel) end
end

local function GroupChannel()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local function RefreshUI()
    if not ui.frame then return end
    UIDropDownMenu_SetText(ui.dropdown, pending.dungeon or "Select dungeon")
    ui.completed:SetChecked(pending.completed)
    ui.wipes:SetText(tostring(pending.wipes))
    ui.deaths:SetText(tostring(pending.deaths))
end

local function ResetPending()
    pending.dungeon, pending.completed, pending.wipes, pending.deaths = nil, false, 0, 0
    wipeActive = false
    RefreshUI()
end

local function SaveRun()
    if not pending.dungeon then
        Print("Select a dungeon first.")
        return
    end
    table.insert(db.runs, {
        dungeon = pending.dungeon,
        completed = pending.completed,
        wipes = pending.wipes,
        deaths = pending.deaths,
        time = time(),
    })
    Print(string.format("Saved %s: %s, %d wipe(s), %d death(s).", pending.dungeon,
        pending.completed and "completed" or "not completed", pending.wipes, pending.deaths))
    ResetPending()
end

local function ShowCopyBox()
    if not ui.copy then
        local f = CreateFrame("Frame", "HealerRunsCopyFrame", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(360, 120)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f.TitleText:SetText("Press Ctrl+C to copy")
        local eb = CreateFrame("EditBox", nil, f)
        eb:SetMultiLine(true)
        eb:SetFontObject(ChatFontNormal)
        eb:SetPoint("TOPLEFT", 14, -30)
        eb:SetPoint("BOTTOMRIGHT", -14, 12)
        eb:SetAutoFocus(true)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        eb:SetScript("OnKeyUp", function(_, key)
            if IsControlKeyDown() and key == "C" then f:Hide() end
        end)
        f.edit = eb
        ui.copy = f
    end
    ui.copy.edit:SetText(table.concat(SummaryLines(), "\n"))
    ui.copy:Show()
    ui.copy.edit:HighlightText()
    ui.copy.edit:SetFocus()
end

local function NumberBox(parent, label, y, key)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 20, y)
    fs:SetText(label)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(40, 20)
    eb:SetPoint("TOPLEFT", 120, y + 4)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(3)
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    eb:SetScript("OnEditFocusLost", function(self)
        pending[key] = tonumber(self:GetText()) or 0
        self:SetText(tostring(pending[key]))
    end)
    return eb
end

local function Button(parent, text, w, point, x, y, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetPoint(point, x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function BuildUI()
    local f = CreateFrame("Frame", "HealerRunsFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(300, 250)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.TitleText:SetText("Healer Stats")
    tinsert(UISpecialFrames, "HealerRunsFrame")
    ui.frame = f

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 20, -38)
    label:SetText("Dungeon")
    local dd = CreateFrame("Frame", "HealerRunsDropdown", f, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", 60, -52)
    UIDropDownMenu_SetWidth(dd, 190)
    UIDropDownMenu_Initialize(dd, function()
        for _, name in ipairs(DungeonList()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.checked = pending.dungeon == name
            info.func = function()
                pending.dungeon = name
                RefreshUI()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    ui.dropdown = dd

    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, -90)
    cb.text:SetText("Completed")
    cb:SetScript("OnClick", function(self) pending.completed = self:GetChecked() and true or false end)
    ui.completed = cb

    ui.wipes = NumberBox(f, "Wipes", -128, "wipes")
    ui.deaths = NumberBox(f, "Deaths", -156, "deaths")

    Button(f, "Save", 80, "BOTTOMLEFT", 16, 44, function()
        ui.wipes:ClearFocus(); ui.deaths:ClearFocus()
        SaveRun()
    end)
    Button(f, "Reset", 80, "BOTTOM", 0, 44, ResetPending)
    Button(f, "Copy stats", 80, "BOTTOMRIGHT", -16, 44, ShowCopyBox)
    Button(f, "Post to group chat", 268, "BOTTOM", 0, 14, function()
        local ch = GroupChannel()
        if ch then SendSummary(ch) else PrintSummary() end
    end)
    RefreshUI()
end

local function ToggleUI()
    if not ui.frame then BuildUI() end
    if ui.frame:IsShown() then ui.frame:Hide() else RefreshUI(); ui.frame:Show() end
end

---------------------------------------------------------------------------
-- Automatic tracking (only updates the pending run, never saves)
---------------------------------------------------------------------------
local function InDungeon()
    local inInstance, kind = IsInInstance()
    return inInstance and kind == "party"
end

local function OnEnterWorld()
    if not InDungeon() then return end
    local name = GetInstanceInfo()
    if pending.dungeon ~= name then
        ResetPending()
        pending.dungeon = name
    end
    local known = false
    for _, n in ipairs(DungeonList()) do if n == name then known = true break end end
    if not known then table.insert(db.extraDungeons, name) end
    RefreshUI()
end

local function GroupUnits()
    local units = { "player" }
    if IsInRaid() then
        units = {}
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    return units
end

local function GroupUnitForGUID(guid)
    for _, u in ipairs(GroupUnits()) do
        if UnitExists(u) and UnitGUID(u) == guid then return u end
    end
end

local function CheckWipe()
    if not InDungeon() then return end
    local anyAlive = false
    for _, u in ipairs(GroupUnits()) do
        if UnitExists(u) and UnitIsConnected(u) and not UnitIsDeadOrGhost(u) then
            anyAlive = true
            break
        end
    end
    if anyAlive then
        wipeActive = false
    elseif not wipeActive then
        wipeActive = true
        pending.wipes = pending.wipes + 1
        RefreshUI()
    end
end

local function OnCombatLog()
    local _, sub, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
    if sub ~= "UNIT_DIED" or not InDungeon() or not destGUID:find("^Player") then return end
    local unit = GroupUnitForGUID(destGUID)
    if unit and not UnitIsFeignDeath(unit) then
        pending.deaths = pending.deaths + 1
        RefreshUI()
        C_Timer.After(0.5, CheckWipe)
    end
end

---------------------------------------------------------------------------
-- Chat trigger: someone typing just "healerstats"
---------------------------------------------------------------------------
local chatChannels = {
    CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID", CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_GUILD = "GUILD", CHAT_MSG_SAY = "SAY",
}

local function OnChat(event, msg)
    if not msg or msg:lower():match("^%s*(.-)%s*$") ~= "healerstats" then return end
    local now = GetTime()
    if now - lastReply < CHAT_COOLDOWN then return end
    lastReply = now
    SendSummary(chatChannels[event])
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
SLASH_HEALERSTATS1 = "/healerstats"
SlashCmdList["HEALERSTATS"] = function(input)
    if (input or ""):lower():match("^%s*stats") then PrintSummary() else ToggleUI() end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        InitDB()
        for e in pairs(chatChannels) do frame:RegisterEvent(e) end
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        frame:RegisterEvent("PLAYER_ALIVE")
        frame:RegisterEvent("PLAYER_UNGHOST")
        frame:RegisterEvent("PLAYER_DEAD")
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnEnterWorld()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" or event == "PLAYER_DEAD" then
        C_Timer.After(0.5, CheckWipe)
    elseif chatChannels[event] then
        OnChat(event, arg1)
    end
end)
