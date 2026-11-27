local ADDON = "HealerStats"
local CHAT_COOLDOWN = 10

local db, pending
local ui = {}
local wipeActive = false
local lastReply = 0

local function Print(msg)
    print("|cff33ff99HealerStats|r: " .. msg)
end

local function InitDB()
    HealerStatsDB = HealerStatsDB or {}
    db = HealerStatsDB
    db.runs = db.runs or {}
    db.extraDungeons = db.extraDungeons or {}
    db.pending = db.pending or { dungeon = nil, completed = false, wipes = 0, deaths = 0 }
    pending = db.pending
end

local function DungeonList()
    local list, seen = {}, {}
    for _, n in ipairs(HealerStatsDungeons) do list[#list + 1] = n; seen[n] = true end
    for _, n in ipairs(db.extraDungeons) do
        if not seen[n] then list[#list + 1] = n; seen[n] = true end
    end
    table.sort(list)
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
    local total, completed, noWipe, noDeath = #db.runs, 0, 0, 0
    for _, r in ipairs(db.runs) do
        if r.completed or r.success then completed = completed + 1 end
        if (r.wipes or 0) == 0 then noWipe = noWipe + 1 end
        if (r.deaths or 0) == 0 then noDeath = noDeath + 1 end
    end
    return {
        string.format("Healer stats: Out of %d dungeons run", total),
        string.format("%d%% were completed", Pct(completed, total)),
        string.format("%d%% were without wipes", Pct(noWipe, total)),
        string.format("%d%% were without any deaths", Pct(noDeath, total)),
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
    if IsInGuild() then return "GUILD" end
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local function RefreshUI()
    if not ui.frame then return end
    ui.dropdown:SetText(pending.dungeon or "Select dungeon")
    ui.completed:SetChecked(pending.completed)
    ui.wipes:SetText(tostring(pending.wipes))
    ui.deaths:SetText(tostring(pending.deaths))
    ui.stats:SetText(table.concat(SummaryLines(), "\n"))
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
        local f = CreateFrame("Frame", "HealerStatsCopyFrame", UIParent, "BasicFrameTemplateWithInset")
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

local function BuildUI_()
    local f = HealerStatsFrame or CreateFrame("Frame", "HealerStatsFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(300, 275)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.TitleText:SetText("Healer Stats")
    tinsert(UISpecialFrames, "HealerStatsFrame")

    local rec = CreateFrame("Frame", nil, f)
    rec:SetPoint("TOPLEFT", 0, -52)
    rec:SetPoint("BOTTOMRIGHT")
    local statsPane = CreateFrame("Frame", nil, f)
    statsPane:SetPoint("TOPLEFT", 0, -52)
    statsPane:SetPoint("BOTTOMRIGHT")
    statsPane:Hide()

    local tabs = {}
    local function SelectTab(i)
        rec:SetShown(i == 1)
        statsPane:SetShown(i == 2)
        for n, t in ipairs(tabs) do t:SetEnabled(n ~= i) end
        if i == 2 then RefreshUI() end
    end
    for i, name in ipairs({ "Record", "Stats" }) do
        local t = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        t:SetSize(80, 22)
        t:SetPoint("TOPLEFT", 14 + (i - 1) * 84, -28)
        t:SetText(name)
        t:SetScript("OnClick", function() SelectTab(i) end)
        tabs[i] = t
    end
    SelectTab(1)

    local label = rec:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 20, -38)
    label:SetText("Dungeon")
    -- Custom dropdown: UIDropDownMenuTemplate taints Blizzard's shared menu code.
    local dd = CreateFrame("Button", nil, rec, "UIPanelButtonTemplate")
    dd:SetSize(200, 24)
    dd:SetPoint("TOPLEFT", 86, -34)
    local list = CreateFrame("Frame", nil, rec, "BackdropTemplate")
    list:SetSize(200, 150)
    list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, 0)
    list:SetFrameStrata("DIALOG")
    list:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    list:SetBackdropColor(0, 0, 0, 0.95)
    list:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    list:Hide()
    local sf = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", -26, 4)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(170, 1)
    sf:SetScrollChild(content)
    local rows = {}
    local function Populate()
        local names = DungeonList()
        for i, name in ipairs(names) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Button", nil, content)
                row:SetSize(170, 20)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * 20)
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", 4, 0)
                row:SetScript("OnClick", function(self)
                    pending.dungeon = self.name
                    list:Hide()
                    RefreshUI()
                end)
                rows[i] = row
            end
            row.name = name
            row.text:SetText(name)
            row:Show()
        end
        for i = #names + 1, #rows do rows[i]:Hide() end
        content:SetHeight(#names * 20)
    end
    dd:SetScript("OnClick", function()
        if list:IsShown() then list:Hide() else Populate(); list:Show() end
    end)
    f:HookScript("OnHide", function() list:Hide() end)
    ui.dropdown = dd

    local cb = CreateFrame("CheckButton", "HealerStatsCompletedCheck", rec, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, -90)
    local cbText = cb.Text or cb.text or _G[cb:GetName() .. "Text"]
    if cbText then cbText:SetText("Completed") end
    cb:SetScript("OnClick", function(self) pending.completed = self:GetChecked() and true or false end)
    ui.completed = cb

    ui.wipes = NumberBox(rec, "Wipes", -128, "wipes")
    ui.deaths = NumberBox(rec, "Deaths", -156, "deaths")

    Button(rec, "Save", 120, "BOTTOMLEFT", 16, 14, function()
        ui.wipes:ClearFocus(); ui.deaths:ClearFocus()
        SaveRun()
    end)
    Button(rec, "Reset", 120, "BOTTOMRIGHT", -16, 14, ResetPending)

    ui.stats = statsPane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.stats:SetPoint("TOPLEFT", 20, -10)
    ui.stats:SetWidth(260)
    ui.stats:SetJustifyH("LEFT")
    ui.stats:SetJustifyV("TOP")
    Button(statsPane, "Copy stats", 120, "BOTTOMLEFT", 16, 14, ShowCopyBox)
    Button(statsPane, "Post to chat", 120, "BOTTOMRIGHT", -16, 14, function()
        local ch = GroupChannel()
        if ch then SendSummary(ch) else PrintSummary() end
    end)
    ui.frame = f
    RefreshUI()
end

local function BuildUI()
    local ok, err = pcall(BuildUI_)
    if not ok then Print("UI error: " .. tostring(err)) end
end

local function ToggleUI()
    if not ui.frame then BuildUI() end
    if not ui.frame then return end
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

-- COMBAT_LOG_EVENT_UNFILTERED is forbidden to addons on modern clients, so poll group state.
local deadState = {}

local function DoPoll()
    if not InDungeon() then
        if next(deadState) then wipe(deadState) end
        return
    end
    for _, u in ipairs(GroupUnits()) do
        if UnitExists(u) then
            -- Key by unit token: GUIDs can be unusable "secret" values in combat.
            local dead = UnitIsDeadOrGhost(u) and not UnitIsFeignDeath(u) and true or false
            if dead and not deadState[u] then
                pending.deaths = pending.deaths + 1
                RefreshUI()
            end
            deadState[u] = dead
        else
            deadState[u] = nil
        end
    end
    CheckWipe()
end

local pollFailures = 0
local function PollDeaths()
    if pollFailures >= 3 then return end
    local ok, err = pcall(DoPoll)
    if ok then
        pollFailures = 0
    else
        pollFailures = pollFailures + 1
        if pollFailures >= 3 then
            Print("Automatic tracking disabled after errors: " .. tostring(err))
        end
    end
end

---------------------------------------------------------------------------
-- Chat trigger: someone typing just "healerstats"
---------------------------------------------------------------------------
local chatChannels = {
    CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID", CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_GUILD = "GUILD"
}

local function OnChat(event, msg)
    -- Chat text is a "secret" value in instances/combat; addons cannot read it.
    if not msg or (issecretvalue and issecretvalue(msg)) then return end
    if msg:lower():match("^%s*(.-)%s*$") ~= "healerstats" then return end
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
    local arg = (input or ""):lower():match("^%s*(%S*)")
    if arg == "stats" then
        PrintSummary()
    elseif arg == "post" then
        local ch = GroupChannel()
        if ch then SendSummary(ch) else PrintSummary() end
    else
        ToggleUI()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if not arg1 or arg1:lower() ~= ADDON:lower() then return end
        InitDB()
        for e in pairs(chatChannels) do frame:RegisterEvent(e) end
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        C_Timer.NewTicker(1, PollDeaths)
        frame:RegisterEvent("PLAYER_ALIVE")
        frame:RegisterEvent("PLAYER_UNGHOST")
        frame:RegisterEvent("PLAYER_DEAD")
        frame:RegisterEvent("ADDON_ACTION_BLOCKED")
        frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if arg1 and arg1:lower() == ADDON:lower() then Print("Blocked action: " .. tostring(arg2)) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnEnterWorld()
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" or event == "PLAYER_DEAD" then
        C_Timer.After(0.5, CheckWipe)
    elseif chatChannels[event] then
        OnChat(event, arg1)
    end
end)
