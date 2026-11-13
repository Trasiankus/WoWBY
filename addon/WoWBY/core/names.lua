-- WoWBY/core/names.lua — NPC names (nameplates, unit/object tooltips, target frames).
-- Split from core.lua (tools/split_core.py); shared state lives in the addon namespace W.
local _, W = ...
-- ---------- NPC names: nameplates, unit tooltips, target frame ----------
-- nohv: don't harvest a miss (players, their pets/minions: only NPC / enemy / object names are worth translating)
-- id: the NPC id when known (ruRU client, R665: the harvest keeps it, so the Russian miss maps back to the EN name)
function W.name_be(en, nohv, id)
    en = plain(en)
    -- already Belarusian (a label we set ourselves: Cyrillic lead bytes 208/209) -> not a miss
    if not nohv and en and en ~= "" and not W.N[en] and not W.ours(en) then W.harvest("names", en, id) end
    return (en and W.on("names")) and W.N[en] or nil
end
-- female unit -> feminine name where the build made one (WoWBY_NamesF: «Вартавая Месяцовай паляны»)
-- pets / minions (R214, owner 2026-10-07): the name is the owner's choice (or the family by default) → never translated;
-- the title "Grob Vuujin's Pet" → «Гадаванец Grob Vuujin» (tooltip line 2 and the overhead label)
local PET_WORD = { Pet = "Гадаванец", Minion = "Прыслужнік", Guardian = "Ахоўнік", Companion = "Спадарожнік" }
function W.pet_title_be(t)
    t = plain(t)
    if not t then return nil end
    -- the line can come in one colour ("|cffffffffElassarana Swiftwind's Pet|r", R315): kept around the BE text
    local col, inner, r = t:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
    local core = inner or t
    if W.RU then core = W.en_line(core) end              -- «Питомец X» → "X's Pet" (R665)
    local owner, kind = core:match("^(.+)'s (%a+)$")
    -- R824: an NPC owner ("Razormane Hunter's Pet", a server-only title) → its BE name after a colon (no genitive form
    -- known: «Гадаванец: Паляўнічы Вастрагрывых»); a player owner keeps the name as is
    local npc = owner and W.on("names") and W.N[owner]
    local be = owner and PET_WORD[kind] and (npc and (PET_WORD[kind] .. ": " .. npc) or (PET_WORD[kind] .. " " .. owner))
    return be and ((col or "") .. be .. (r or "")) or nil
end
function W.name_be_unit(en, unit)
    local u = type(unit) == "string" and unit or nil
    if u and UnitIsPlayer(u) then return nil end              -- players keep their own names, never harvested
    if u and UnitPlayerControlled(u) then return nil end      -- pets keep their names (R214)
    local id
    if W.RU and u then
        local g = W.sid_ok(UnitGUID(u))
        id = type(g) == "string" and tonumber(g:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")) or nil
    end
    -- hunter pets, companions, minions: not harvested; R968: battle pets / other players' companions carry names their
    -- owners typed ("Sausage") — translated if known, never collected
    local named = u and ((UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(u))
        or (UnitIsBattlePetCompanion and UnitIsBattlePetCompanion(u)) or (UnitIsBattlePet and UnitIsBattlePet(u)))
    local be = W.name_be(en, (u and UnitPlayerControlled(u)) or named, id)
    if be and u and UnitSex(u) == 3 then
        be = (WoWBY_NamesF or {})[plain(en)] or be
    end
    return be
end
function W.set_be(fs, be) if fs then W.set_font(fs); W.swap(fs, be) end end
if _G.CompactUnitFrame_UpdateName then
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
        local u = frame and frame.displayedUnit or (frame and frame.unit)
        if type(u) ~= "string" or not u:find("^nameplate") then return end   -- party/raid frames: never touched
        if UnitIsPlayer(u) then return end                   -- players keep their own names
        if frame and frame.name and not (frame.IsForbidden and frame:IsForbidden()) then
            local be = W.name_be_unit(plain(frame.name:GetText()), u)
            if be then W.set_be(frame.name, be) end
            if WoWBY_DB and WoWBY_DB.nameonly and frame.unit and not UnitIsPlayer(frame.unit) then
                local r, g, bb = UnitSelectionColor(frame.unit, true)      -- keep reaction colour (bar hidden)
                if r then pcall(frame.name.SetTextColor, frame.name, r, g, bb) end
            end
        end
    end)
end
-- Tooltips are translated in the DATA before Blizzard draws them (TooltipDataProcessor pre-calls edit
-- tooltipData.lines[i].leftText) -> no English flash, no re-layout.
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    local TITLES = WoWBY_Titles or {}
    W.TIP.pre(Enum.TooltipDataType.Unit, function(tt, data)
        -- NPCs only: a PLAYER's name is never translated, even when it matches an NPC's ("Taerdas Swiftclaw", 2026-09-28)
        local guid = W.sid_ok(data and data.guid) or ""
        local npc = type(guid) == "string" and (guid:find("^Creature") or guid:find("^Vehicle")) ~= nil
        -- a PLAYER's line 2 is the guild name (when it is not the level line): typed by players → never translated (R106)
        W.TIP.keep[tt] = nil
        if type(guid) == "string" and guid:find("^Player") and data.lines and data.lines[2] then
            local g = plain(data.lines[2].leftText)
            if g and not g:find("^" .. (LEVEL or "Level") .. " ") then W.TIP.keep[tt] = { text = g, at = GetTime() } end
        end
        -- a PLAYER's name in their class colour (owner 2026-10-07), like the class line under it; NPCs keep Blizzard's
        -- reaction colours
        if type(guid) == "string" and guid:find("^Player") and W.is_be() and data.lines and data.lines[1] then
            local pn = plain(data.lines[1].leftText)
            local ok, _, cls = pcall(GetPlayerInfoByGUID, guid)
            local c = ok and type(cls) == "string" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
            if pn and pn ~= "" and c and c.colorStr and not pn:find("|c", 1, true) then
                data.lines[1].leftText = "|c" .. c.colorStr .. pn .. "|r"
            end
        end
        local l1 = npc and W.on("names") and data.lines and data.lines[1]
        -- pcall(tt.GetUnit) returns ok, name, UNIT -> the 3rd value (select 2 was the name: always masculine)
        local u = l1 and tt and tt.GetUnit and select(3, pcall(tt.GetUnit, tt))
        -- sid_ok (R747): a secret mouseover GUID (instances) must not be compared
        if l1 and type(u) ~= "string" and data.guid and W.sid_ok(UnitGUID("mouseover")) == data.guid then u = "mouseover" end
        local be = l1 and W.name_be_unit(plain(l1.leftText), u)
        if be then l1.leftText = be end
        -- NPC title under the name ("Bowyer" -> «Лукар»): NPCs only (a player's 2nd line is the guild), exact match
        local l2 = l1 and data.lines[2]
        local lt2 = l2 and plain(l2.leftText)
        if lt2 then
            local fem = type(u) == "string" and UnitSex(u) == 3
            local t = fem and (WoWBY_TitlesF or {})[lt2] or TITLES[lt2]
            if t then l2.leftText = t end
        end
        -- a player's pet: "Grob Vuujin's Pet". Hunter pets have no NPC guid (block above skipped); some pets DO have a
        -- Creature guid ("Tiparican Swiftmane's Pet" stayed English, R306) → tried for both
        local p2 = W.on("names") and data.lines and data.lines[2]
        local pt = p2 and W.pet_title_be(p2.leftText)
        if pt then p2.leftText = pt
        end
    end)
end
if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object then
    W.TIP.pre(Enum.TooltipDataType.Object, function(tt, data)
        local l1 = W.on("names") and data and data.lines and data.lines[1]
        local be = l1 and W.name_be(plain(l1.leftText))       -- misses are harvested like NPC names
        if be then l1.leftText = be end
    end)
end
-- R952 (owner screenshot: target-of-target NPC "Pyall Silentst…" stayed English): TargetOfTargetMixin runs Update from
-- OnUpdate, i.e. UnitFrame_Update re-sets the name EVERY frame, so our one-off SetText is gone next frame. No hooks on
-- unit frames (taint) → OUR label (a UIParent child) laid over the ToT name, Blizzard's name faded with SetAlpha (a
-- display call, as on the nameplates). Checked every 0.2 s; English mode / players / unknown names → Blizzard's own.
do
    local labels = {}
    -- R952e (owner test: Latin text in our UIParent label was dim too, with every value equal to Blizzard's) → the label
    -- is a text region of the name's own parent, same draw layer, right next to Blizzard's name: drawn the same way.
    -- Only a region is added (no hook, no field on the frame; our table keeps it); made out of combat.
    local function label_for(fr, name)
        local l = labels[fr]
        if not l then
            if InCombatLockdown() then return nil end
            local parent = name:GetParent() or fr
            local layer, sub = name:GetDrawLayer()
            local fs = parent:CreateFontString(nil, layer or "OVERLAY")
            if sub then pcall(fs.SetDrawLayer, fs, layer or "OVERLAY", math.min((sub or 0) + 1, 7)) end
            fs:SetWordWrap(false)
            l = { fs = fs, f = { Show = function() fs:Show() end, Hide = function() fs:Hide() end, IsShown = function() return fs:IsShown() end } }
            labels[fr] = l
            if fr == _G.TargetFrameToT then _G.WoWBYToTLabel = { fs = fs } end   -- /run diagnostics
        end
        return l
    end
    local function tot_tick()
        for _, fr in ipairs({ _G.TargetFrameToT, _G.FocusFrameToT }) do
            local name, u = fr and fr.name, fr and fr.unit
            if name then
                local be
                if W.on("names") and u and fr:IsVisible() and UnitExists(u) and not UnitIsPlayer(u) then
                    be = W.name_be_unit(plain(UnitName(u)), u)
                end
                local l = labels[fr]
                if be then l = label_for(fr, name) end
                if be and l then
                    l.fs:ClearAllPoints(); l.fs:SetAllPoints(name)
                    l.fs:SetFontObject(name:GetFontObject() or GameFontNormalSmall)
                    local ff, fsz, ffl = name:GetFont()
                    if ff and type(fsz) == "number" and fsz > 0 then pcall(l.fs.SetFont, l.fs, W.by_font(ff) or ff, fsz, ffl or "") end
                    l.fs:SetJustifyH(name:GetJustifyH() or "LEFT")
                    -- R952b (owner: "still dark"): the read-back colour came out dim → the game's normal name yellow
                    local c = _G.NORMAL_FONT_COLOR
                    if c and c.r then l.fs:SetTextColor(c.r, c.g, c.b) else l.fs:SetTextColor(1, 0.82, 0) end
                    local sr, sg, sb, sa = name:GetShadowColor()
                    local sx, sy = name:GetShadowOffset()
                    if type(sr) == "number" and not (issecretvalue and issecretvalue(sr)) then l.fs:SetShadowColor(sr, sg, sb, sa or 1) end
                    if type(sx) == "number" and not (issecretvalue and issecretvalue(sx)) then l.fs:SetShadowOffset(sx, sy) end
                    l.fs:SetText(be); l.f:Show()
                    name:SetAlpha(0)
                elseif l and l.f:IsShown() then
                    l.f:Hide(); name:SetAlpha(1)
                end
            end
        end
    end
    C_Timer.NewTicker(0.2, function() pcall(tot_tick) end)
end
function W.target_name()
    -- WowUkrainizer's way: plain SetText on the name FontString from OUR event handler, after Blizzard's own
    -- update. No hooks on the frame, no fields, no SetFont (GameFontNormalSmall is patched globally) -- the
    -- earlier per-object hooksecurefunc(fs, "SetText") wrote keys into the secure frame and tainted Edit Mode.
    if not W.on("names") then return end                   -- in combat too: you usually target what you fight
    for _, fr in ipairs({ _G.TargetFrame, _G.FocusFrame, _G.TargetFrameToT, _G.FocusFrameToT }) do
        local fs = fr and fr.name
        local u = fr and fr.unit
        if fs and u and UnitExists(u) and not UnitIsPlayer(u) then
            local be = W.name_be_unit(plain(fs:GetText()), u)
            if be then pcall(fs.SetText, fs, be) end
        end
    end
end
