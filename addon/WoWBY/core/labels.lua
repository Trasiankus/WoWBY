-- WoWBY/core/labels.lua — quest labels, reputation, refresh.
-- Split from core.lua (tools/split_core.py); shared state lives in the addon namespace W.
local _, W = ...
-- ---------- quest-content GlobalStrings (quest strings ONLY — see Anniversary core for why) ----------
local LABELS = {
    OBJECTIVES_LABEL = "Мэты задання", QUEST_OBJECTIVES = "Мэты задання", DESCRIPTION_LABEL = "Апісанне",
    REWARD_TEXT = "Узнагароды", REWARD_ITEMS_ONLY = "Вы атрымаеце:", REWARD_ITEMS = "Вы атрымаеце таксама:",
    REWARD_CHOICES = "Вы зможаце выбраць адну з гэтых узнагарод:", REWARD_CHOOSE = "Выберыце ўзнагароду:",
    QUEST_PROGRESS = "Прагрэс задання",
    AVAILABLE_QUESTS = "Даступныя заданні", CURRENT_QUESTS = "Цяперашнія заданні",
    TURN_IN_ITEMS = "Патрэбныя рэчы:",
}
local label_orig = {}
function W.apply_labels()
    for k, be in pairs(LABELS) do
        if label_orig[k] == nil then label_orig[k] = _G[k] or false end
        _G[k] = W.on("quests") and be or (label_orig[k] or nil)
    end
end

-- ---------- reputation: standing labels (GlobalStrings) ----------
-- R607 (2026-10-16, taintLog 11): NO C_Reputation wraps any more. The XP / reputation bar calls
-- C_Reputation.GetWatchedFactionData at login; our wrapper tainted the bar's state (shownBarIndex), Edit Mode read it
-- ("WoWBY blocked" popup, TargetUnit / FocusUnit blocked, party frames "compare a secret") and in combat the action
-- bars could not be re-anchored and vanished. Faction names / descriptions are swapped where SHOWN (ui_be knows
-- WoWBY_Factions; reputation rows are panel FontStrings; the detail pane has its own hooks).
-- standing labels are plain GlobalStrings read by the reputation UI (not protected, not menu) -> set at
-- the source, so rows never flash English
-- R620: the watched-faction bar text ("Darnassus 500 / 3000") — DISPLAY ONLY: our own frame checks the bar texts EVERY
-- frame (Blizzard re-sets them on hover / show, not only on events: a 1 s re-check showed English for a second) and
-- swaps a changed one before it is drawn; unchanged text = one string compare. No hooks / fields on the status bars
-- (an Edit Mode system: touching their state is what broke Edit Mode and the combat action bars in R607)
local bar_done = setmetatable({}, { __mode = "k" })
local function tr_status_bars()
    if not (W.is_be() and W.on("ui")) then return end
    local FA = WoWBY_Factions or {}
    local mgr = _G.StatusTrackingBarManager
    for _, c in ipairs(mgr and mgr.barContainers or {}) do
        for _, bar in pairs(type(c.bars) == "table" and c.bars or {}) do
            local fs = type(bar) == "table" and bar.OverlayFrame and bar.OverlayFrame.Text
            local t = fs and plain(fs:GetText())
            if t and t ~= "" and t ~= bar_done[fs] then
                local nm, rest = t:match("^(.-)( %-?[%d,]+ / [%d,]+)$")
                nm = nm or t
                local acc = nm:match("^(.-) %(.+%)$")                 -- "Name (Account Wide)"
                local be = FA[nm] or (acc and FA[acc] and (FA[acc] .. nm:sub(#acc + 1)))
                if be then W.swap(fs, be .. (rest or "")) end
                bar_done[fs] = plain(fs:GetText())        -- unchanged text next frame → nothing to do
            end
        end
    end
end
do
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function() pcall(tr_status_bars) end)
end
local STANDING_KEYS = {}
for i = 1, 8 do STANDING_KEYS[#STANDING_KEYS + 1] = "FACTION_STANDING_LABEL" .. i
                STANDING_KEYS[#STANDING_KEYS + 1] = "FACTION_STANDING_LABEL" .. i .. "_FEMALE" end
local standing_orig = {}
function W.apply_standings()
    for _, k in ipairs(STANDING_KEYS) do
        if standing_orig[k] == nil then standing_orig[k] = _G[k] or false end
        local en = standing_orig[k]
        if en then _G[k] = (W.on("ui") and W.UI[en]) or en end
    end
end

-- ---------- search boxes (R241): SearchBoxTemplate sets its grey "Search" hint ONCE at OnLoad from the template's
-- instructionText; bag / bank boxes exist before we load -> swapped here, later boxes via the OnLoad post-hook.
-- Display only (the hint FontString); protected boxes (LFG list) are left alone.
local search_boxes, search_hooked = {}, false
local function search_hint(box)
    if not (box and box.Instructions and box.instructionText) then return end
    if (box.IsForbidden and box:IsForbidden()) or (box.IsProtected and box:IsProtected()) then return end
    search_boxes[box] = true
    local en = plain(box.instructionText)
    local be = en and W.on("ui") and W.ui_be(en)
    pcall(box.Instructions.SetText, box.Instructions, (be and be ~= en) and be or en)
end
function W.apply_search_boxes()
    if not search_hooked and _G.SearchBoxTemplate_OnLoad then
        search_hooked = true
        hooksecurefunc("SearchBoxTemplate_OnLoad", function(box) pcall(search_hint, box) end)
    end
    for _, n in ipairs(_G.ITEM_SEARCHBAR_LIST or {}) do pcall(search_hint, _G[n]) end
    for box in pairs(search_boxes) do pcall(search_hint, box) end
end

-- ---------- refresh (after any settings change) ----------
function W.refresh()
    W.apply_labels(); W.apply_standings(); W.apply_search_boxes(); W.apply_chat_tabs(); if W.apply_chat_words then W.apply_chat_words() end; W.apply_buttons(); W.tr_zone_text(); W.target_name()
    for _, p in ipairs({ "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel", "QuestFrameGreetingPanel" }) do
        local fr = _G[p]
        if fr and fr:IsShown() then fr:Hide(); fr:Show() end
    end
    -- R696 (owner): an open NPC dialogue kept the old language — its greeting / options come from the C_GossipInfo wraps
    -- when it is built, so rebuild it (GossipFrame:Update only re-reads the gossip and refills its list; next frame, out
    -- of combat, never through the UI panel manager — R406)
    local gf = _G.GossipFrame
    if gf and gf:IsShown() and gf.Update and not InCombatLockdown() then
        C_Timer.After(0, function() if gf:IsShown() then pcall(gf.Update, gf) end end)
    end
    if QuestMapFrame and QuestMapFrame:IsShown() and QuestLogQuests_Update then QuestLogQuests_Update() end
    -- R384/R406: the open quest details are filled by Blizzard through our getter wraps → after a language switch their
    -- texts are written back with plain SetText from the getters (now answering in the new language). NOT by calling
    -- QuestMapFrame_ShowQuestDetails / NavBar:Refresh from here: that ran Blizzard's panel code from addon code, the
    -- UI panel manager kept tainted state, and entering Edit Mode from the Esc menu then failed in the party frames
    -- ("compare secret oldR … tainted by WoWBY", 2026-10-11). The map path updates on the next map change.
    local df = QuestMapFrame and QuestMapFrame.DetailsFrame
    local qid = df and df:IsShown() and QuestMapFrame_GetDetailQuestID and QuestMapFrame_GetDetailQuestID()
    if qid and qid ~= 0 then
        local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qid)
        if W.is_be() and W.on("quests") then title = W.be_title(qid) or title end
        local desc, obj = GetQuestLogQuestText()
        if _G.QuestInfoTitleHeader and title then QuestInfoTitleHeader:SetText(title) end
        if _G.QuestInfoDescriptionText and desc then QuestInfoDescriptionText:SetText(desc) end
        if _G.QuestInfoObjectivesText and obj then QuestInfoObjectivesText:SetText(obj) end
    end
    W.details_post()
    if ObjectiveTrackerManager and ObjectiveTrackerManager.UpdateAll then pcall(ObjectiveTrackerManager.UpdateAll, ObjectiveTrackerManager) end
    for path in pairs(W.hooked) do W.run_panel(W.resolve(path)) end
    if W.spellbook_update then W.spellbook_update() end      -- R389: names back to BE (Blizzard does not re-set them)
end
-- R160 (owner again 2026-11-05): a newly accepted quest stays out of the objective tracker until the language toggle, whose
-- UpdateAll shows it. Cause still unknown (no error logged, no taint log). Workaround: the same call after QUEST_ACCEPTED,
-- never in combat. If taint errors appear on accepting a quest, this is the first suspect.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("QUEST_ACCEPTED")
    f:SetScript("OnEvent", function()
        C_Timer.After(0.3, function()
            if InCombatLockdown() or not (ObjectiveTrackerManager and ObjectiveTrackerManager.UpdateAll) then return end
            pcall(ObjectiveTrackerManager.UpdateAll, ObjectiveTrackerManager)
        end)
    end)
end
-- calendar holiday view (R197): Blizzard joins the description and "Begins / Ends" (CALENDAR_HOLIDAYFRAME_BEGINSENDS)
-- into one ScrollingFont text, so the whole string never matched; re-built here from the holiday info
local cal_hooked = false
function W.hook_calendar()
    if cal_hooked or not _G.CalendarViewHolidayFrame_Update then return end
    cal_hooked = true
    local function post()
        if not (W.is_be() and W.on("ui")) then return end
        local f = _G.CalendarViewHolidayFrame
        local idx = C_Calendar and C_Calendar.GetEventIndex and C_Calendar.GetEventIndex()
        local info = idx and C_Calendar.GetHolidayInfo(idx.offsetMonths, idx.monthDay, idx.eventIndex)
        -- R602: the title (Header:Setup(name)) too — only the 1 s panel ticker caught it, so it changed late or not at all
        local name = info and plain(info.name)
        local hdr = f and f.Header
        local bn = name and name ~= "" and W.ui_be(name)
        if bn and hdr and hdr.Text then
            W.swap(hdr.Text, bn)
            if hdr.UpdateWidth then hdr:UpdateWidth() end
        end
        local desc = info and plain(info.description)
        local be = desc and desc ~= "" and W.ui_be(desc)
        if not (be and f and f.ScrollingFont) then return end
        if info.startTime and info.endTime then
            local s, e = info.startTime, info.endTime
            -- day.month (R242; FormatShortDate gave the US 6/21)
            be = be .. "|n|nПачатак: " .. ("%02d.%02d"):format(s.monthDay, s.month) .. " "
                 .. GameTime_GetFormattedTime(s.hour, s.minute, true) .. "|nКанец: "
                 .. ("%02d.%02d"):format(e.monthDay, e.month) .. " " .. GameTime_GetFormattedTime(e.hour, e.minute, true)
        end
        W.swap(f.ScrollingFont, be)
    end
    -- R226: Blizzard keeps the ORIGINAL function as CalendarViewHolidayFrame.update (OnLoad) and calls that copy on
    -- refresh → hook the global (OnShow path) AND the frame's copy (hooksecurefunc on a table key: no taint)
    hooksecurefunc("CalendarViewHolidayFrame_Update", function() pcall(post) end)
    local hf = _G.CalendarViewHolidayFrame
    if hf and type(hf.update) == "function" then hooksecurefunc(hf, "update", function() pcall(post) end) end
end
