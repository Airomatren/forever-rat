-- Forever Rat: auto-accept res / summons / friend and guild invites, keyword auto-invite, auto role,
-- auto combat log and an early pull log. WoW: Forever build of Lazy Rat.
local ADDON = ...

-- Swap Media\icon.tga (64x64, 32-bit TGA) to change the minimap/addon-list icon.
local ICON = "Interface\\AddOns\\ForeverRat\\Media\\icon"

local DEFAULTS = {
    res = true, bres = true, summon = true,
    notifyChat = true, notifyWarning = true, earlyPull = true, autoLog = true,
    autoInvite = false, inviteKeyword = "inv", inviteFriendsOnly = true, acceptInvite = true,
    autoRole = false,
    minimapShow = true, minimapAngle = 225,
}
local CHAR_DEFAULTS = { groupRole = "DAMAGER" }
local db, charDb

local function Notify(msg)
    if db.notifyChat then print("|cffc8a165Forever Rat:|r " .. msg) end
    if db.notifyWarning then RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo.RAID_WARNING) end
end

---------------------------------------------------------------------------
-- Resurrection / summons
---------------------------------------------------------------------------
local function OnResurrect(caster)
    local battle = IsEncounterInProgress() or (caster and UnitAffectingCombat(caster))
    if not db[battle and "bres" or "res"] then return end
    AcceptResurrect()
    StaticPopup_Hide("RESURRECT")
    StaticPopup_Hide("RESURRECT_NO_SICKNESS")
    StaticPopup_Hide("RESURRECT_NO_TIMER")
    Notify((battle and "Battle res" or "Res") .. " accepted from " .. (caster or "?"))
end

local events = CreateFrame("Frame")

local function OnSummon()
    if not db.summon then return end
    -- Summons can't be taken in combat; try again once combat drops.
    if UnitAffectingCombat("player") then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    C_Timer.After(0.5, function()
        if (C_SummonInfo.GetSummonConfirmTimeLeft() or 0) <= 0 then return end
        local who = C_SummonInfo.GetSummonConfirmSummoner() or "?"
        C_SummonInfo.ConfirmSummon()
        StaticPopup_Hide("CONFIRM_SUMMON")
        Notify("Summon accepted from " .. who)
    end)
end

---------------------------------------------------------------------------
-- Group invites: keyword auto-invite, auto-accept from friends and guild
---------------------------------------------------------------------------
-- Scans Battle.net friends' WoW characters by GUID or name; GetAccountInfoByGUID alone missed them in Forever.
local function IsBNetFriend(guid, name)
    local char, realm = strsplit("-", name or "", 2)
    char, realm = char:lower(), realm and realm:lower()
    for i = 1, BNGetNumFriends() do
        for j = 1, C_BattleNet.GetFriendNumGameAccounts(i) do
            local g = C_BattleNet.GetFriendGameAccountInfo(i, j)
            if g and g.clientProgram == BNET_CLIENT_WOW then
                if guid and g.playerGuid == guid then return true end
                -- "Name-Realm" drops spaces and dashes from the realm.
                if g.characterName and g.characterName:lower() == char
                    and (not realm or not g.realmName or g.realmName:gsub("[%s%-]", ""):lower() == realm) then
                    return true
                end
            end
        end
    end
    return false
end

-- Character friend, Battle.net friend or guild member.
local function IsFriendOrGuild(guid, name)
    if issecretvalue then
        if guid and issecretvalue(guid) then guid = nil end
        if name and issecretvalue(name) then name = nil end
    end
    if not (guid or name) then return false end
    if guid and (C_FriendList.IsFriend(guid) or IsGuildMember(guid) or C_BattleNet.GetAccountInfoByGUID(guid)) then return true end
    if name and (C_FriendList.GetFriendInfo(name) or IsGuildMember(name)) then return true end
    return IsBNetFriend(guid, name)
end

-- Whisper text can be a secret value in instance combat; those whispers are skipped.
-- isKnown is only called once everything else passes, since it scans the friends list; nil means always known.
local function OnWhisper(msg, sender, invite, isKnown)
    if not db.autoInvite or (issecretvalue and (issecretvalue(msg) or issecretvalue(sender))) then return end
    local keyword = strtrim(db.inviteKeyword or ""):lower()
    -- Whole-message match, so "don't inv me" doesn't trigger an invite.
    if keyword == "" or strtrim(msg):lower() ~= keyword then return end
    if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then return end
    if db.inviteFriendsOnly and isKnown and not isKnown() then return end
    invite()
    Notify("Invited " .. sender .. ".")
end

-- Battle.net whispers name the account, so invite the WoW: Forever character it's on (if any).
local function OnBNWhisper(msg, sender, bnSenderID)
    if not bnSenderID or (issecretvalue and issecretvalue(bnSenderID)) then return end
    local account = C_BattleNet.GetAccountInfoByID(bnSenderID)
    local game = account and account.gameAccountInfo
    if not (game and game.isOnline and game.clientProgram == BNET_CLIENT_WOW
        and game.wowProjectID == WOW_PROJECT_ID and game.gameAccountID) then return end
    -- Battle.net whispers only ever come from Battle.net friends, so no friend check.
    OnWhisper(msg, sender, function() BNInviteFriend(game.gameAccountID) end)
end

local function OnPartyInvite(inviter, guid)
    if not db.acceptInvite or not IsFriendOrGuild(guid, inviter) then return end
    AcceptGroup()
    StaticPopup_Hide("PARTY_INVITE")
    Notify("Accepted group invite from " .. (inviter or "?") .. ".")
end

-- GROUP_JOINED fires once per group, so later role changes are left alone.
local ROLE_NAMES = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
local function OnGroupJoined()
    if not db.autoRole then return end
    -- The role isn't settable the instant you join; give the group a moment to form.
    C_Timer.After(1, function()
        local role = charDb.groupRole
        -- shortcut: a join during combat is skipped, not retried; add a PLAYER_REGEN_ENABLED retry if that bites.
        if not IsInGroup() or InCombatLockdown() or UnitGroupRolesAssigned("player") == role then return end
        local canTank, canHeal, canDps = UnitGetAvailableRoles("player")
        if not ({ TANK = canTank, HEALER = canHeal, DAMAGER = canDps })[role] then return end
        UnitSetRole("player", role)
        Notify("Role set to " .. ROLE_NAMES[role] .. ".")
    end)
end

---------------------------------------------------------------------------
-- Auto combat log: on in dungeons and raids, off when you leave
---------------------------------------------------------------------------
-- db.loggingByUs survives /reload, so only a log this addon started is ever stopped; a manual /combatlog is left alone.
local function UpdateCombatLog()
    local inInstance, kind = IsInInstance()
    local want = db.autoLog and inInstance and (kind == "party" or kind == "raid")
    if want and not LoggingCombat() then
        C_CVar.SetCVar("advancedCombatLogging", "1") -- Warcraft Logs needs advanced logging
        LoggingCombat(true)
        db.loggingByUs = true
        Notify("Combat logging started.")
    elseif not want and db.loggingByUs then
        LoggingCombat(false)
        db.loggingByUs = nil
        Notify("Combat logging stopped.")
    end
end

---------------------------------------------------------------------------
-- Early pull log: combat starting before a pull countdown reaches zero
---------------------------------------------------------------------------
-- The modern client can hand addons secret values that can't be stored or shown; treat them as unknown.
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local countdownEnd, countdownBy, cancelledAt, lastPull, lastPullAt
local earlyList -- the Early Pull page's list box, once the menu is built

-- Newest first. Unix time and encounter ID are kept on each line so the log can be matched to Warcraft Logs.
local function EarlyPullText()
    local lines = {}
    for i = #db.earlyPulls, 1, -1 do
        local e = db.earlyPulls[i]
        lines[#lines + 1] = string.format("%s | %.2fs early | %s | countdown by %s | %d | %s",
            date("%Y-%m-%d %H:%M:%S", e.time), e.early, e.where or "?", e.by or "?", e.time, e.encounterID or "")
    end
    return #lines > 0 and table.concat(lines, "\n") or "No early pulls logged yet."
end

local function RefreshEarlyList()
    if earlyList then earlyList:SetText(EarlyPullText()) end
end

local function OnCountdownStart(timeRemaining, initiatedByName)
    timeRemaining = Plain(timeRemaining)
    if not timeRemaining then return end
    countdownEnd, countdownBy, cancelledAt = GetTime() + timeRemaining, Plain(initiatedByName), nil
end

local function OnCombatStart(encounterID, encounterName)
    local now = GetTime()
    -- ENCOUNTER_START can trail PLAYER_REGEN_DISABLED; give the entry just logged its boss.
    if encounterID and lastPull and now - lastPullAt < 3 and not lastPull.encounterID then
        lastPull.encounterID = Plain(encounterID)
        lastPull.where = Plain(encounterName) or lastPull.where
        RefreshEarlyList()
        return
    end
    if not (db.earlyPull and countdownEnd and now < countdownEnd) then return end
    -- A cancel well before combat was someone stopping the countdown, not the pull itself.
    if cancelledAt and now - cancelledAt > 0.5 then
        countdownEnd = nil
        return
    end
    lastPull = {
        time = time(), early = countdownEnd - now, by = countdownBy,
        encounterID = Plain(encounterID), where = Plain(encounterName) or GetRealZoneText(),
    }
    lastPullAt, countdownEnd = now, nil
    tinsert(db.earlyPulls, lastPull)
    RefreshEarlyList()
end

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------
local menu, minimapBtn

-- Flat dark palette, same look as MythicPlusCount's options panel.
local FONT = "Fonts\\FRIZQT__.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local C = {
    bg        = { 0.08, 0.08, 0.10, 0.95 },
    border    = { 0.25, 0.25, 0.30, 1 },
    accent    = { 0.30, 0.70, 1.00, 1 },
    text      = { 0.85, 0.85, 0.85, 1 },
    dim       = { 0.55, 0.55, 0.60, 1 },
    tabBg     = { 0.10, 0.10, 0.12, 1 },
    tabActive = { 0.18, 0.18, 0.22, 1 },
    tabHover  = { 0.14, 0.14, 0.18, 1 },
    box       = { 0.15, 0.15, 0.18, 1 },
}

local function Text(parent, size, color, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, flags or "")
    fs:SetTextColor(unpack(color))
    return fs
end

local function Backdrop(f, bg, border)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(unpack(bg))
    f:SetBackdropBorderColor(unpack(border))
end

-- Builds one settings page; y walks down the page as rows are added.
local function NewPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", 150, -46)
    page:SetPoint("BOTTOMRIGHT", -16, 16)
    page:Hide()
    local y = 0

    function page:Header(text)
        if y ~= 0 then y = y - 10 end
        local fs = Text(self, 13, C.accent, "OUTLINE")
        fs:SetPoint("TOPLEFT", 0, y)
        fs:SetText(text)
        local line = self:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
        line:SetPoint("RIGHT")
        line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
        y = y - 28
    end

    function page:Check(key, label, onChange, store)
        store = store or db
        local cb = CreateFrame("CheckButton", nil, self, "BackdropTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", 6, y)
        Backdrop(cb, C.box, C.border)
        cb:SetHighlightTexture(WHITE)
        cb:GetHighlightTexture():SetVertexColor(0.3, 0.6, 1, 0.2)
        local fill = cb:CreateTexture(nil, "OVERLAY")
        fill:SetSize(12, 12)
        fill:SetPoint("CENTER")
        fill:SetColorTexture(unpack(C.accent))
        local label_ = Text(cb, 12, C.text, "OUTLINE")
        label_:SetPoint("LEFT", cb, "RIGHT", 8, 0)
        label_:SetText(label)

        local function Refresh()
            local on = cb:GetChecked()
            fill:SetShown(on)
            cb:SetBackdropBorderColor(unpack(on and C.accent or C.border))
        end
        cb:SetChecked(store[key])
        Refresh()
        cb:SetScript("OnClick", function()
            store[key] = cb:GetChecked()
            Refresh()
            if onChange then onChange() end
        end)
        y = y - 32
    end

    function page:Note(text)
        local fs = Text(self, 10, C.dim)
        fs:SetPoint("TOPLEFT", 34, y + 8)
        fs:SetWidth(410) -- fixed width so GetStringHeight is right before the page is laid out
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        y = y - fs:GetStringHeight() - 6
    end

    -- Row of buttons where exactly one is picked; choices = { { value, label }, ... }.
    function page:Choice(key, choices, store)
        store = store or db
        local buttons = {}
        local function Refresh()
            for _, b in ipairs(buttons) do
                local on = store[key] == b.value
                b:SetBackdropBorderColor(unpack(on and C.accent or C.border))
                b.label:SetTextColor(unpack(on and { 1, 1, 1, 1 } or C.dim))
            end
        end
        for i, c in ipairs(choices) do
            local b = CreateFrame("Button", nil, self, "BackdropTemplate")
            b:SetSize(90, 22)
            b:SetPoint("TOPLEFT", 34 + (i - 1) * 96, y)
            Backdrop(b, C.box, C.border)
            b.value = c[1]
            b.label = Text(b, 11, C.dim, "OUTLINE")
            b.label:SetPoint("CENTER")
            b.label:SetText(c[2])
            b:SetScript("OnClick", function()
                store[key] = b.value
                Refresh()
            end)
            buttons[i] = b
        end
        Refresh()
        y = y - 30
    end

    -- Labelled text box, indented under the checkbox above it.
    function page:Input(key, label)
        local fs = Text(self, 12, C.text, "OUTLINE")
        fs:SetPoint("TOPLEFT", 34, y - 3)
        fs:SetText(label)
        local eb = CreateFrame("EditBox", nil, self, "BackdropTemplate")
        eb:SetSize(140, 20)
        eb:SetPoint("LEFT", fs, "RIGHT", 8, 0)
        Backdrop(eb, C.box, C.border)
        eb:SetFont(FONT, 11, "")
        eb:SetTextColor(unpack(C.text))
        eb:SetTextInsets(6, 6, 0, 0)
        eb:SetAutoFocus(false)
        eb:SetText(db[key] or "")
        eb:SetScript("OnTextChanged", function(self) db[key] = self:GetText() end)
        eb:SetScript("OnEnterPressed", eb.ClearFocus)
        eb:SetScript("OnEscapePressed", eb.ClearFocus)
        y = y - 30
    end

    -- Stretches a frame over the rest of the page.
    function page:Fill(frame)
        frame:SetPoint("TOPLEFT", 6, y)
        frame:SetPoint("BOTTOMRIGHT")
    end

    return page
end

local function BuildMenu()
    menu = CreateFrame("Frame", "ForeverRatMenu", UIParent, "BackdropTemplate")
    menu:SetSize(620, 470)
    menu:SetPoint("CENTER")
    menu:SetFrameStrata("DIALOG")
    menu:SetMovable(true)
    menu:EnableMouse(true)
    menu:SetClampedToScreen(true)
    menu:RegisterForDrag("LeftButton")
    menu:SetScript("OnDragStart", menu.StartMoving)
    menu:SetScript("OnDragStop", menu.StopMovingOrSizing)
    Backdrop(menu, C.bg, C.border)
    menu:Hide()
    tinsert(UISpecialFrames, "ForeverRatMenu") -- Escape closes it

    local logo = menu:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(ICON)
    logo:SetSize(24, 24)
    logo:SetPoint("TOPLEFT", 12, -8)

    local title = Text(menu, 16, { 1, 1, 1, 1 }, "OUTLINE")
    title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    title:SetText("|cff8c8c99·|r  Forever Rat")

    local close = CreateFrame("Button", nil, menu)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -8, -8)
    local x = Text(close, 16, C.text, "OUTLINE")
    x:SetPoint("CENTER")
    x:SetText("X")
    close:SetScript("OnClick", function() menu:Hide() end)
    close:SetScript("OnEnter", function() x:SetTextColor(1, 1, 1) end)
    close:SetScript("OnLeave", function() x:SetTextColor(unpack(C.text)) end)

    local divider = menu:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 1, -40)
    divider:SetPoint("TOPRIGHT", -1, -40)
    divider:SetColorTexture(unpack(C.border))

    local sidebar = menu:CreateTexture(nil, "BACKGROUND", nil, 1)
    sidebar:SetPoint("TOPLEFT", 1, -41)
    sidebar:SetPoint("BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(132)
    sidebar:SetColorTexture(unpack(C.tabBg))

    -- Pages
    local general = NewPage(menu)
    general:Header("Resurrection")
    general:Check("res", "Auto-accept resurrections")
    general:Check("bres", "Auto-accept battle resurrections")
    general:Note("A res counts as a battle res during a boss encounter or while the caster is in combat.")
    general:Header("Summons")
    general:Check("summon", "Auto-accept summons")
    general:Note("If you're in combat, the summon is accepted once combat ends.")
    general:Header("Combat Log")
    general:Check("autoLog", "Auto combat log in dungeons and raids", UpdateCombatLog)
    general:Note("Starts the combat log when you enter a dungeon or raid and stops it when you leave. Turns on advanced combat logging for Warcraft Logs.")
    general:Header("Minimap")
    general:Check("minimapShow", "Show minimap button", function() minimapBtn:SetShown(db.minimapShow) end)

    local group = NewPage(menu)
    group:Header("Auto Invite")
    group:Check("autoInvite", "Invite players who whisper the keyword")
    group:Input("inviteKeyword", "Keyword:")
    group:Check("inviteFriendsOnly", "Only friends and guild members")
    group:Note("Works for normal and Battle.net whispers. The whole whisper must be the keyword (any capitalisation). Only invites while you're solo, the leader or an assistant.")
    group:Header("Auto Accept")
    group:Check("acceptInvite", "Accept group invites from friends and guild members")
    group:Note("Covers character friends, Battle.net friends and your guild. Invites from anyone else still ask as normal.")
    group:Header("Auto Role")
    group:Check("autoRole", "Set my role when I join a group")
    group:Choice("groupRole", { { "TANK", "Tank" }, { "HEALER", "Healer" }, { "DAMAGER", "Damage" } }, charDb)
    group:Note("Set once when you join, so you can still change it after. The role is saved per character; skipped if your class can't fill it.")

    local notifications = NewPage(menu)
    notifications:Header("Notifications")
    notifications:Check("notifyChat", "Chat message")
    notifications:Check("notifyWarning", "Raid warning message")
    notifications:Note("Shown whenever Forever Rat auto-accepts a res, summon or group invite, invites someone, sets your role, or starts or stops the combat log.")

    local early = NewPage(menu)
    early:Header("Early Pull")
    early:Check("earlyPull", "Log pulls that start before the countdown ends")
    early:Note("Each line: time, how early combat started, boss or zone, who started the countdown, Unix time and encounter ID. Click the list to select it all, then press |cffffffffCtrl+C|r to copy.")

    local clear = CreateFrame("Button", nil, early, "BackdropTemplate")
    clear:SetSize(90, 20)
    clear:SetPoint("TOPRIGHT", 0, -28)
    Backdrop(clear, C.box, C.border)
    local clearText = Text(clear, 11, C.text, "OUTLINE")
    clearText:SetPoint("CENTER")
    clearText:SetText("Clear Data")
    clear:SetScript("OnClick", function()
        wipe(db.earlyPulls)
        lastPull = nil
        RefreshEarlyList()
    end)
    clear:SetScript("OnEnter", function() clear:SetBackdropBorderColor(unpack(C.accent)) end)
    clear:SetScript("OnLeave", function() clear:SetBackdropBorderColor(unpack(C.border)) end)

    local box = CreateFrame("Frame", nil, early, "BackdropTemplate")
    early:Fill(box)
    Backdrop(box, C.box, C.border)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    earlyList = CreateFrame("EditBox", nil, scroll)
    earlyList:SetMultiLine(true)
    earlyList:SetAutoFocus(false)
    earlyList:SetFont(FONT, 11, "")
    earlyList:SetTextColor(unpack(C.text))
    earlyList:SetWidth(410)
    scroll:SetScrollChild(earlyList)
    -- Read-only: typing is undone, and focusing selects everything ready for Ctrl+C.
    earlyList:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(EarlyPullText())
            self:HighlightText()
        end
    end)
    earlyList:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    earlyList:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    RefreshEarlyList()

    -- Sidebar tabs
    local tabs = {}
    local function Select(sel)
        for _, t in ipairs(tabs) do
            local on = t == sel
            t.page:SetShown(on)
            t.bar:SetShown(on)
            t.bg:SetColorTexture(unpack(on and C.tabActive or C.tabBg))
            t.label:SetTextColor(unpack(on and { 1, 1, 1, 1 } or C.dim))
        end
    end
    -- A third field pins the tab to the bottom of the sidebar.
    local tabDefs = {
        { "General", general }, { "Group", group }, { "Notifications", notifications },
        { "Early Pull", early, true },
    }
    for i, def in ipairs(tabDefs) do
        local t = CreateFrame("Button", nil, menu)
        t:SetSize(132, 36)
        if def[3] then
            t:SetPoint("BOTTOMLEFT", 1, 1)
        else
            t:SetPoint("TOPLEFT", 1, -41 - (i - 1) * 36)
        end
        t.page = def[2]
        t.bg = t:CreateTexture(nil, "BACKGROUND", nil, 2)
        t.bg:SetAllPoints()
        t.bar = t:CreateTexture(nil, "ARTWORK")
        t.bar:SetPoint("TOPLEFT")
        t.bar:SetPoint("BOTTOMLEFT")
        t.bar:SetWidth(3)
        t.bar:SetColorTexture(unpack(C.accent))
        t.label = Text(t, 12, C.dim, "OUTLINE")
        t.label:SetPoint("LEFT", 14, 0)
        t.label:SetText(def[1])
        t:SetScript("OnClick", Select)
        t:SetScript("OnEnter", function() if not t.page:IsShown() then t.bg:SetColorTexture(unpack(C.tabHover)) end end)
        t:SetScript("OnLeave", function() if not t.page:IsShown() then t.bg:SetColorTexture(unpack(C.tabBg)) end end)
        tabs[i] = t
    end
    Select(tabs[1])
end

local function ToggleMenu()
    if not menu then BuildMenu() end
    menu:SetShown(not menu:IsShown())
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
local function PlaceMinimapButton()
    local a = math.rad(db.minimapAngle)
    local r = Minimap:GetWidth() / 2 + 10
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function BuildMinimapButton()
    local b = CreateFrame("Button", "ForeverRatMinimapButton", Minimap)
    minimapBtn = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", ToggleMenu)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            db.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            PlaceMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Forever Rat")
        GameTooltip:AddLine("Click to open settings. Drag to move.", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    PlaceMinimapButton()
    b:SetShown(db.minimapShow)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        ForeverRatDB = ForeverRatDB or {}
        db = ForeverRatDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        db.earlyPulls = db.earlyPulls or {}
        ForeverRatCharDB = ForeverRatCharDB or {}
        charDb = ForeverRatCharDB
        for k, v in pairs(CHAR_DEFAULTS) do
            if charDb[k] == nil then charDb[k] = v end
        end
        BuildMinimapButton()
        self:RegisterEvent("RESURRECT_REQUEST")
        self:RegisterEvent("CONFIRM_SUMMON")
        self:RegisterEvent("START_PLAYER_COUNTDOWN")
        self:RegisterEvent("CANCEL_PLAYER_COUNTDOWN")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("ENCOUNTER_START")
        -- Entering or leaving an instance always has a loading screen; zone changes inside one are ignored
        -- so a log stopped by hand mid-instance stays stopped.
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("CHAT_MSG_WHISPER")
        self:RegisterEvent("CHAT_MSG_BN_WHISPER")
        self:RegisterEvent("PARTY_INVITE_REQUEST")
        self:RegisterEvent("GROUP_JOINED")
    elseif event == "GROUP_JOINED" then
        OnGroupJoined()
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateCombatLog()
    elseif event == "CHAT_MSG_WHISPER" then
        local msg, sender = ...
        local guid = select(12, ...)
        OnWhisper(msg, sender, function() C_PartyInfo.InviteUnit(sender) end, function() return IsFriendOrGuild(guid, sender) end)
    elseif event == "CHAT_MSG_BN_WHISPER" then
        local msg, sender = ...
        OnBNWhisper(msg, sender, (select(13, ...)))
    elseif event == "PARTY_INVITE_REQUEST" then
        local inviter, _, _, _, _, _, guid = ...
        OnPartyInvite(inviter, guid)
    elseif event == "START_PLAYER_COUNTDOWN" then
        local _, timeRemaining, _, _, initiatedByName = ...
        OnCountdownStart(timeRemaining, initiatedByName)
    elseif event == "CANCEL_PLAYER_COUNTDOWN" then
        cancelledAt = GetTime()
    elseif event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()
    elseif event == "ENCOUNTER_START" then
        OnCombatStart(...)
    elseif event == "RESURRECT_REQUEST" then
        OnResurrect(...)
    elseif event == "CONFIRM_SUMMON" then
        OnSummon()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        OnSummon()
    end
end)

SLASH_FOREVERRAT1 = "/fr"
SlashCmdList.FOREVERRAT = ToggleMenu
