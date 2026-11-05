-- WoWBY/core/nameplates.lua — name-only nameplate labels.
-- Split from core.lua (tools/split_core.py); shared state lives in the addon namespace W.
local _, W = ...
-- ---------- name-only nameplates (Turtle experiment) ----------
-- Engine overhead names can't be translated; nameplates can. With this option NPC nameplates show only the
-- (Belarusian) name and the engine NPC names are turned off -> looks like "nameplates off", translated.
-- TAINT RULE (learned 2026-09-21): Forever's nameplates are RESTRICTED regions. Never write fields or call
-- methods on Blizzard's nameplate frames (setting uf.showOnlyName made Blizzard's UpdateAnchors fail with
-- "Can't measure restricted regions", tainted by WoWBY). Only SetAlpha on sub-frames: a pure display
-- property Blizzard never reads back. Re-applied by a light ticker because Blizzard may reset alphas.
-- (nameplateShowAll — "always show nameplates" — is the owner's own choice, R27 2026-09-29: with it off the labels
-- appear only in combat)
local NAMEONLY_CVARS = { nameplateShowEnemies = "1", nameplateShowFriends = "1",
                         nameplateShowFriendlyNPCs = "1", UnitNameNPC = "0",
                         UnitNameFriendlySpecialNPCName = "0", UnitNameHostleNPC = "0", UnitNameInteractiveNPC = "0",
                         -- players / pets / minions / critters (UnitNameFriendly*, UnitNameNonCombatCreatureName) are NOT
                         -- forced any more (owner 2026-10-08, R253): Blizzard's own checkboxes decide, our labels follow them
                         -- distance scaling (engine CVars, all present in WowB.exe): full size up to 10 yd, shrinking
                         -- to 0.6 at 40 yd. The defaults (min = max distance) gave a constant 0.90 near and far;
                         -- 0.4 from 5 yd (first try) made player names a few steps away too small (owner 2026-09-28).
                         -- The TARGET's plate never scales by distance (engine: selected scale) — nothing to set for it.
                         nameplateMinScale = "0.6", nameplateMaxScale = "1",
                         nameplateMaxScaleDistance = "10", nameplateMinScaleDistance = "40" }
-- forced to 0 before R253: the owner's own values come back once from WoWBY_DB.cvar_backup
local FREED_CVARS = { "UnitNameNonCombatCreatureName", "UnitNameFriendlyPlayerName", "UnitNameFriendlyPetName",
                      "UnitNameFriendlyGuardianName", "UnitNameFriendlyMinionName", "UnitNameFriendlyTotemName" }
local function cvar_on(cv) return C_CVar and C_CVar.GetCVar(cv) == "1" end
local NP_PARTS = { "HealthBarsContainer", "CastBarsContainer", "AurasFrame", "ClassificationFrame",
                   "LevelFrame", "PlayerLevelDiffFrame" }
-- Our own label instead of Blizzard's name (owner 2026-09-26): name + <title> like the engine's overhead names, set
-- LOWER (where the hidden health bar was). It is OUR frame, parented to UIParent and only anchored to the plate —
-- nothing is written to or measured on the restricted nameplate; Blizzard's name is just faded (SetAlpha).
W.np_label = setmetatable({}, { __mode = "k" })     -- plate -> our label frame
local np_title = {}                                       -- GUID -> EN title or false (tooltip data read once)
local TITLES_NP = WoWBY_Titles or {}
local NP_OFFSET_Y = 0
local NP_FONT_MULT = 1.8                 -- lift above the plate bottom; label size vs the nameplate font
local QUEST_NPC, QUEST_REQ = WoWBY_QuestNPC or {}, WoWBY_QuestReq or {}
-- R69: does this NPC have something for THIS player right now? It ends a quest in the log, or starts one that is not
-- done / not in the log and whose race, class, level, prerequisites (all / any) and exclusive quests allow it.
-- Cached per NPC until the quest log / level changes.
local qcache = {}
local function in_log(q) return C_QuestLog.GetLogIndexForQuestID(q) ~= nil end
local function done(q) return C_QuestLog.IsQuestFlaggedCompleted(q) end
local function can_take(q)
    local r = QUEST_REQ[q]
    if not r or done(q) or in_log(q) then return false end
    if r[1] > 0 and UnitLevel("player") < r[1] then return false end
    local race, class = select(3, UnitRace("player")), select(3, UnitClass("player"))
    if r[2] > 0 and race and bit.band(r[2], bit.lshift(1, race - 1)) == 0 then return false end
    if r[3] > 0 and class and bit.band(r[3], bit.lshift(1, class - 1)) == 0 then return false end
    for _, p in ipairs(r[4]) do if not done(p) then return false end end
    if #r[5] > 0 then
        local any = false
        for _, p in ipairs(r[5]) do if done(p) then any = true break end end
        if not any then return false end
    end
    for _, x in ipairs(r[6]) do if done(x) or in_log(x) then return false end end
    return true
end
local function npc_has_quest(id)
    local e = id and QUEST_NPC[id]
    if not e then return false end
    local c = qcache[id]
    if c ~= nil then return c end
    local has = false
    for _, q in ipairs(e[2]) do if in_log(q) then has = true break end end
    -- R83 (owner): only CURRENT quests by default — givers of quests you could take show only with WoWBY_DB.np_offers
    if not has and WoWBY_DB.np_offers then for _, q in ipairs(e[1]) do if can_take(q) then has = true break end end end
    qcache[id] = has
    return has
end
-- mobs you still have to kill / loot (R532, owner: "NPC для заданняў" showed no quest mobs — UnitIsRelatedToActiveQuest
-- does not flag them on this client): the unit's tooltip lists its quest objectives (line type QuestObjective = 8,
-- "0/8 Plainstrider Meat"); an unfinished count, or a line without one, = a quest mob. Cached per GUID until the
-- quest log changes.
local qmob = {}
local function quest_mob(unit)
    local guid = W.sid_ok(UnitGUID(unit))
    if not guid then return false end
    local c = qmob[guid]
    if c ~= nil then return c end
    local has = false
    local ok, data = pcall(C_TooltipInfo and C_TooltipInfo.GetUnit or function() end, unit)
    for _, l in ipairs(ok and type(data) == "table" and data.lines or {}) do
        if l.type == 8 then
            local t = plain(l.leftText)
            local a, b = (t or ""):match("(%d+)%s*/%s*(%d+)")
            if t and (not a or tonumber(a) < tonumber(b)) then has = true; break end
        end
    end
    qmob[guid] = has
    return has
end
do
    local f = CreateFrame("Frame")
    for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "PLAYER_LEVEL_UP" }) do f:RegisterEvent(ev) end
    f:SetScript("OnEvent", function() wipe(qcache); wipe(qmob) end)
end
local TITLE_EN                                           -- BE title -> EN key (built on first need)
local function unit_title(unit)
    -- sid_ok (R747): unit GUIDs are SECRET in Forever instances — indexing np_title with one errors
    local guid = W.sid_ok(UnitGUID(unit))
    if not guid then return nil end
    if np_title[guid] == nil then
        np_title[guid] = false
        local ok, data = pcall(C_TooltipInfo and C_TooltipInfo.GetUnit or function() end, unit)
        local l2 = ok and type(data) == "table" and data.lines and data.lines[2]
        local t = l2 and plain(l2.leftText)
        -- line 2 is the title only when it is not the "Level 12 Humanoid" line
        if type(t) == "string" and t ~= "" and not t:find("%d") and not t:find("^Level") then np_title[guid] = t end
    end
    local t = np_title[guid] or nil
    -- the tooltip data can come back already translated by our tooltip pre-call (masculine) -> back to the EN key,
    -- so the label picks the right gender itself
    if t and t:find("[\208\209]") then
        if not TITLE_EN then
            TITLE_EN = {}
            for en, be in pairs(TITLES_NP) do TITLE_EN[be] = TITLE_EN[be] or en end
        end
        t = TITLE_EN[t] or t
    end
    return t
end
local function label_for(plate)
    local f = W.np_label[plate]
    if not f then
        -- a CHILD of the plate: inherits its distance scaling (and hides with it). Nothing is written to or measured
        -- on the plate itself; if the client ever refuses the parent, fall back to UIParent (fixed size).
        -- try the plate's UnitFrame (holds Blizzard's name, which visibly scales), then the plate; the engine applies
        -- the distance scale to one of them. Both refused -> f.fixed: style_plate falls back to Blizzard's own name.
        for _, parent in ipairs({ plate.UnitFrame, plate }) do
            local ok, fr = pcall(CreateFrame, "Frame", nil, parent)
            if ok and fr then f = fr; f.kind = parent == plate and "plate" or "unitframe"; break end
        end
        if not f then f = CreateFrame("Frame", nil, UIParent); f.kind = "fixed"; f.fixed = true end
        f:SetSize(1, 1)
        -- exactly Blizzard's nameplate-name font (SystemFont_NamePlate, repointed to the BY face by patch_fonts): as a
        -- child of the plate it then sizes and scales like the original nameplate names (fixed pt sizes were too big)
        local fo = _G.SystemFont_NamePlate and "SystemFont_NamePlate" or "GameFontNormalSmall"
        local file, size, flags = _G[fo]:GetFont()
        for _, k in ipairs({ "name", "title" }) do
            f[k] = f:CreateFontString(nil, "OVERLAY", fo)
            pcall(f[k].SetFont, f[k], W.by_font(file) or W.FONT, (size or 9) * NP_FONT_MULT, flags or "")
            -- no shadow, like Blizzard's nameplate names (the shadow option was removed, R224)
            f[k]:SetShadowOffset(0, 0); f[k]:SetShadowColor(0, 0, 0, 0)
        end
        -- the block sits on the plate's BOTTOM edge (nearest the head): title at the bottom, name above it
        f.title:SetPoint("BOTTOM", f, "CENTER", 0, 0)
        W.np_label[plate] = f
    end
    return f
end
-- the engine never distance-scales the TARGET's plate (selected scale): our label shrinks itself in coarse steps
-- from CheckInteractDistance (3 ≈ 10 yd, 4 ≈ 28 yd), matching the CVars above (1 → 0.6 between 10 and 40 yd)
local function target_scale(unit)
    if not UnitIsUnit(unit, "target") then return 1 end
    local ok10, near10 = pcall(CheckInteractDistance, unit, 3)
    local ok28, near28 = pcall(CheckInteractDistance, unit, 4)
    if ok10 and near10 then return 1 elseif ok28 and near28 then return 0.8 elseif ok28 and near28 == false then return 0.6 end
    return 1
end
-- R164: the steps come from only two range checks, so the label GLIDES to the new scale (~0.3 s) instead of
-- jumping. OnUpdate on OUR label frame only while it is moving.
local function glide(f, elapsed)
    local cur, want = f:GetScale(), f.want_scale or 1
    local d = want - cur
    if math.abs(d) < 0.005 then f:SetScale(want); f:SetScript("OnUpdate", nil); return end
    f:SetScale(cur + d * math.min(1, elapsed * 8))
end
local function set_label_scale(f, s)
    f.want_scale = s
    if math.abs(f:GetScale() - s) >= 0.005 then f:SetScript("OnUpdate", glide) end
end
-- R303 (owner 2026-10-09): Blizzard's soft-target icon (the moon / gossip cursor over the NPC, SoftTargetFrame 24×24 on
-- the plate) shrinks with our distance scaling and looks tiny next to the 1.8× label → faded (alpha only: the plate is
-- restricted) and drawn again in OUR label, sized to the name font. Same rules as Blizzard's UpdateSoftTargetIcon.
local NPC_ = _G.NamePlateConstants or {}
local function soft_cvar(k, d) return C_CVar and C_CVar.GetCVar(NPC_[k] or d) end
local function soft_icon(f, uf, unit)
    local bl = uf and uf.SoftTargetFrame
    local want = false
    if f and unit and (tonumber(soft_cvar("SOFT_TARGET_NAMEPLATE_SIZE_CVAR", "SoftTargetNameplateSize")) or 0) > 0 then
        want = (soft_cvar("SOFT_TARGET_ICON_ENEMY_CVAR", "SoftTargetIconEnemy") == "1" and UnitIsUnit(unit, "softenemy"))
            or (soft_cvar("SOFT_TARGET_ICON_FRIEND_CVAR", "SoftTargetIconFriend") == "1" and UnitIsUnit(unit, "softfriend"))
            or (soft_cvar("SOFT_TARGET_ICON_INTERACT_CVAR", "SoftTargetIconInteract") == "1" and UnitIsUnit(unit, "softinteract"))
    end
    local has = false
    if want then
        -- like Blizzard: a fixed-size holder, the texture fills it (SetUnitCursorTexture gives the texture its own
        -- cursor size — sized directly, the moon came out several times too big, R307)
        if not f.iconf then
            f.iconf = CreateFrame("Frame", nil, f)
            f.icon = f.iconf:CreateTexture(nil, "OVERLAY")
            f.icon:SetAllPoints(f.iconf)
        end
        local ok, r = pcall(SetUnitCursorTexture, f.icon, unit, nil, nil, true)
        has = ok and r
    end
    if has then
        -- about the height of the name line and a half (Blizzard: 24 px over a ~12 px name)
        local h = f.name:GetStringHeight()
        local sz = math.max(12, math.min(40, math.floor((h > 0 and h or 16) * 1.5 + 0.5)))
        f.icon:SetAllPoints(f.iconf)
        f.iconf:SetSize(sz, sz)
        f.iconf:ClearAllPoints()
        f.iconf:SetPoint("BOTTOM", f.name, "TOP", 0, 1)
        f.iconf:Show()
    elseif f and f.iconf then
        f.iconf:Hide()
    end
    if bl and bl.SetAlpha then pcall(bl.SetAlpha, bl, has and 0 or 1) end
end
-- R743 (owner 2026-10-23): a second mode WITH health bars (WoWBY_DB.np_bars): Blizzard's bars / cast bars / auras stay,
-- only its English name is faded; our label sits right above the health bar at about Blizzard's name size (the 1.8×
-- font × 0.6); the «Імёны NPC» choice decides which NPC plates show at all (bar + name), as in the no-bars mode
local BARS_SCALE = 0.6
local function bars_on() return WoWBY_DB and WoWBY_DB.nameonly and WoWBY_DB.np_bars end
local function place(f, plate, uf, s)
    f:ClearAllPoints()
    local hb = bars_on() and uf.HealthBarsContainer
    if hb then f:SetPoint("CENTER", hb, "TOP", 0, 2)        -- anchored only; nothing on the plate is written / measured
    else f:SetPoint("CENTER", plate, "BOTTOM", 0, NP_OFFSET_Y) end   -- plate bottom = right above the head
    set_label_scale(f, s * (hb and BARS_SCALE or 1))
    -- with bars the names get Blizzard's nameplate shadow (owner 2026-10-23: like the plates' own names); without
    -- bars none (owner R224)
    for _, k in ipairs({ "name", "title" }) do
        -- 1.7 at the 0.6 label scale ≈ Blizzard's 1 px (1 was ~0.6 px: hardly visible, owner)
        f[k]:SetShadowOffset(hb and 1.7 or 0, hb and -1.7 or 0); f[k]:SetShadowColor(0, 0, 0, hb and 1 or 0)
    end
end
local function style_plate(plate)
    local uf = plate and plate.UnitFrame
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return end
    local unit = uf.unit
    local hide = WoWBY_DB and WoWBY_DB.nameonly and unit and UnitExists(unit) and not UnitIsPlayer(unit)
    local fade = hide and not bars_on()
    for _, k in ipairs(NP_PARTS) do
        local fr = uf[k]
        if fr and fr.SetAlpha then pcall(fr.SetAlpha, fr, fade and 0 or 1) end
    end
    -- friendly PLAYERS (owner 2026-09-28): Blizzard cuts their names to the plate width ("Therwindris Sabrem…") and
    -- draws a shadow; our label shows the full name instead (never translated, Blizzard's colour kept). Enemy players
    -- keep Blizzard's plate: it still has a health bar our label would cover.
    local friend_pc = WoWBY_DB and WoWBY_DB.nameonly and unit and UnitExists(unit) and UnitIsPlayer(unit)
        and UnitIsFriend and UnitIsFriend("player", unit) and WoWBY_DB.np_mode ~= "blizz"
    if friend_pc and not cvar_on("UnitNameFriendlyPlayerName") then   -- Blizzard "Players" unticked: no name at all
        pcall(uf.name.SetAlpha, uf.name, 0)
        local f = W.np_label[plate]
        if f then f:Hide() end
        soft_icon(nil, uf, unit)
        return
    end
    if friend_pc then
        local ok, r, g, b = pcall(uf.name.GetTextColor, uf.name)
        pcall(uf.name.SetAlpha, uf.name, 0)
        local en = plain(UnitName(unit))
        local f = en and label_for(plate)
        if not f or f.fixed then pcall(uf.name.SetAlpha, uf.name, 1); if f then f:Hide() end; return end
        -- same layout as an NPC label (R25, owner 2026-09-29): name + «<guild>» like an NPC title, never translated
        local guild = plain((GetGuildInfo(unit)))
        f.name:SetText(en); f.title:SetText(guild and guild ~= "" and ("<" .. guild .. ">") or "")
        f.name:ClearAllPoints()
        if guild and guild ~= "" then f.name:SetPoint("BOTTOM", f.title, "TOP", 0, 1)
        else f.name:SetPoint("BOTTOM", f, "CENTER", 0, 0) end
        if ok and r then f.name:SetTextColor(r, g, b); f.title:SetTextColor(r, g, b) end
        place(f, plate, uf, target_scale(unit))
        f:Show()
        soft_icon(f, uf, unit)
        return
    end
    if uf.name and uf.name.SetAlpha then pcall(uf.name.SetAlpha, uf.name, hide and 0 or 1) end
    local f = W.np_label[plate]
    -- owner 2026-09-26: label only for the target, quest NPCs (givers + active-quest mobs) and enemies in combat with you;
    -- everyone else shows nothing, like "nameplates off"
    -- enemies only while fighting you (on your threat list), not every attackable mob around
    local mode = (WoWBY_DB and WoWBY_DB.npc_mode) or 1       -- the owner's "NPC names" choice (see NPC_NAME_CVARS)
    local attackable = UnitCanAttack("player", unit)
    local guid = W.sid_ok(UnitGUID(unit))                    -- R747: secret in instances → no NPC id, no quest marker
    local quest = (C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest and C_QuestLog.UnitIsRelatedToActiveQuest(unit))
        or (guid and npc_has_quest(tonumber((select(6, strsplit("-", guid))) or "")))
        or (attackable and quest_mob(unit))
    local fighting = attackable and UnitThreatSituation and UnitThreatSituation("player", unit) ~= nil
    -- players' pets / guardians / minions and critters / companions follow Blizzard's own "Minions" / "Critters"
    -- checkboxes (R253, owner 2026-10-08; were WoWBY copies np_minions / np_critters)
    local owned = UnitPlayerControlled(unit)
    local critter = not owned and UnitCreatureType and UnitCreatureType(unit) == "Critter"
    local show
    if owned or critter then
        show = hide and (UnitIsUnit(unit, "target")
            or (owned and (cvar_on("UnitNameFriendlyMinionName") or cvar_on("UnitNameFriendlyPetName")
                           or cvar_on("UnitNameFriendlyGuardianName")))
            or (critter and cvar_on("UnitNameNonCombatCreatureName")))
    else
        show = hide and (UnitIsUnit(unit, "target")
            or (mode ~= 5 and (quest or fighting))                -- 1 tracked: quest NPCs + enemies fighting you
            or (mode == 2 and attackable)                         -- 2 hostile
            or mode == 3 or mode == 4)                            -- 3 hostile + interactive, 4 all
    end
    -- R743: with bars the «Імёны NPC» choice picks whole plates (owner: the dropdown "didn't do a thing"): an NPC
    -- outside it loses bar + name, like Blizzard hiding its plate; one inside keeps both
    if bars_on() and hide then
        for _, k in ipairs(NP_PARTS) do
            local fr = uf[k]
            if fr and fr.SetAlpha then pcall(fr.SetAlpha, fr, show and 1 or 0) end
        end
    end
    if not show then
        if f then f:Hide() end
        soft_icon(nil, uf, unit)                          -- Blizzard's own icon back
        return
    end
    f = label_for(plate)
    if f.fixed or WoWBY_DB.np_mode == "blizz" then       -- could not follow the plate's scale / chosen: first state
        f:Hide()                                          -- (Blizzard's own translated name, scales, no title)
        soft_icon(nil, uf, unit)
        pcall(uf.name.SetAlpha, uf.name, 1)
        local r, g, b = UnitSelectionColor(unit, true)
        if r then pcall(uf.name.SetTextColor, uf.name, r, g, b) end
        return
    end
    local en = plain(UnitName(unit))
    if not en then if f then f:Hide() end; pcall(uf.name.SetAlpha, uf.name, 1); soft_icon(nil, uf, unit); return end
    -- players' pets / minions: the name is the owner's choice, or the creature family by default ("Cat" → «Кот»)
    local pc = UnitPlayerControlled(unit)
    f.name:SetText(W.name_be_unit(en, unit) or en)          -- pets keep their own name (R214)
    local t = unit_title(unit)
    -- English mode (or names off): the title stays English too, like the name above it
    local tbe = t and W.on("names") and (UnitSex(unit) == 3 and (WoWBY_TitlesF or {})[t] or TITLES_NP[t]
                                         or (pc and W.pet_title_be(t)))
    if t and not tbe and pc and W.on("names") then
        W.any_name = true                                 -- "%s's Pet" → «Гадаванец: Stariela Solitas» (name kept)
        local ok, be = pcall(W.ui_be, t)
        W.any_name = false
        if ok and be ~= t then tbe = be end
    end
    f.title:SetText(t and ("<" .. (tbe or t) .. ">") or "")
    f.name:ClearAllPoints()
    if t then f.name:SetPoint("BOTTOM", f.title, "TOP", 0, 1) else f.name:SetPoint("BOTTOM", f, "CENTER", 0, 0) end
    -- the hidden bar carried the hostile/neutral/friendly colour -> the label takes it
    local r, g, b = UnitSelectionColor(unit, true)
    if r then f.name:SetTextColor(r, g, b); f.title:SetTextColor(r, g, b) end
    place(f, plate, uf, target_scale(unit))
    f:Show()
    soft_icon(f, uf, unit)
end
function W.set_np_bars(v)                                    -- R743: the with-bars mode switch (options window)
    WoWBY_DB.np_bars = v or nil
    W.style_all_plates()
end
function W.plate_removed(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    local f = plate and W.np_label[plate]
    if f then f:Hide() end
end
local np_ticker
function W.style_all_plates()
    for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates() or {}) do style_plate(plate) end
end
function W.plate_added(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if plate and WoWBY_DB and WoWBY_DB.nameonly then style_plate(plate) end
end
-- Blizzard's Settings > Nameplates > "NPC names" dropdown (blizzard_settingsdefinitions_frame/nameplates.lua) writes
-- these four CVars; its GetValue: 4 = all, 3 = hostile+interactive, 2 = hostile (+quest), 1 = tracked/quest, 5 = none.
-- With our option on the engine names stay OFF (they are English), and our labels follow the choice instead
-- (owner 2026-09-28). A dropdown change while the option is on is noticed by the ticker: new choice stored, engine
-- names silenced again. The backup keeps the owner's latest choice, so turning the option off restores it.
local NPC_NAME_CVARS = { "UnitNameNPC", "UnitNameFriendlySpecialNPCName", "UnitNameHostleNPC", "UnitNameInteractiveNPC" }
local function npc_mode_from_cvars()
    if cvar_on("UnitNameNPC") then return 4 end
    local special, hostile = cvar_on("UnitNameFriendlySpecialNPCName"), cvar_on("UnitNameHostleNPC")
    if special and hostile and cvar_on("UnitNameInteractiveNPC") then return 3 end
    if special and hostile then return 2 end
    if special then return 1 end
    return 5
end
local function any_npc_name_on()
    for _, cv in ipairs(NPC_NAME_CVARS) do if cvar_on(cv) then return true end end
    return false
end
W.npc_mode_from_cvars = npc_mode_from_cvars
-- R253: the player / pet / critter name CVars WoWBY used to hold at 0 get the owner's saved values back (once)
function W.restore_freed_cvars()
    local bk = WoWBY_DB and WoWBY_DB.cvar_backup
    if not bk or InCombatLockdown() or not C_CVar then return end
    for _, cv in ipairs(FREED_CVARS) do
        if bk[cv] ~= nil then pcall(C_CVar.SetCVar, cv, bk[cv]); bk[cv] = nil end
    end
end
-- keep the option's CVars in force (a "reset to defaults" or a dropdown change undoes them); out of combat only
local function enforce_cvars()
    if not (WoWBY_DB and WoWBY_DB.nameonly) or InCombatLockdown() or not C_CVar then return end
    if any_npc_name_on() then                                        -- the owner picked something in the dropdown
        WoWBY_DB.npc_mode = npc_mode_from_cvars()
        WoWBY_DB.cvar_backup = WoWBY_DB.cvar_backup or {}
        for _, cv in ipairs(NPC_NAME_CVARS) do WoWBY_DB.cvar_backup[cv] = C_CVar.GetCVar(cv) end
    end
    W.restore_freed_cvars()
    for cv, val in pairs(NAMEONLY_CVARS) do
        local cur = C_CVar.GetCVar(cv)
        if cur ~= nil and cur ~= val then pcall(C_CVar.SetCVar, cv, val) end
    end
end
local enforce_t = 0
function W.start_np_ticker()
    if np_ticker then np_ticker:Cancel(); np_ticker = nil end
    if WoWBY_DB and WoWBY_DB.nameonly then
        np_ticker = C_Timer.NewTicker(0.25, function()
            W.style_all_plates()
            enforce_t = enforce_t + 1
            if enforce_t >= 8 then enforce_t = 0; enforce_cvars() end     -- every 2 s
        end)
    end
end
function W.set_nameonly(v)
    if InCombatLockdown() then
        DEFAULT_CHAT_FRAME:AddMessage("|cff8080ffWoWBY:|r нельга змяніць у баі — паспрабуйце пасля бою.")
        return false
    end
    if v and not WoWBY_DB.nameonly and any_npc_name_on() then
        WoWBY_DB.npc_mode = npc_mode_from_cvars()                  -- the dropdown choice our labels will follow
    end
    W.restore_freed_cvars()
    WoWBY_DB.nameonly = v or nil
    WoWBY_DB.cvar_backup = WoWBY_DB.cvar_backup or {}
    for cv, val in pairs(NAMEONLY_CVARS) do
        if C_CVar and C_CVar.GetCVar(cv) ~= nil then
            if v then
                if WoWBY_DB.cvar_backup[cv] == nil then WoWBY_DB.cvar_backup[cv] = C_CVar.GetCVar(cv) end
                pcall(C_CVar.SetCVar, cv, val)
            elseif WoWBY_DB.cvar_backup[cv] ~= nil then
                pcall(C_CVar.SetCVar, cv, WoWBY_DB.cvar_backup[cv])
            end
        end
    end
    if not v then WoWBY_DB.cvar_backup = nil end
    W.style_all_plates()                                   -- off: alphas back to 1
    W.start_np_ticker()
    return true
end
