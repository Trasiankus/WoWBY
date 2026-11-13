-- WoWBY/core/zones.lua — zone names, map pins, quest-log harvest scan.
-- Split from core.lua (tools/split_core.py); shared state lives in the addon namespace W.
local _, W = ...
-- ---------- zones (getter overrides, ClassicUA approach) ----------
local function ztr(s)
    -- (R625: never harvest our own Belarusian — the display hooks see already-swapped names: «Тэндальскі гай» was queued)
    if type(s) == "string" and s ~= "" and not W.ours(s) and not (W.Z[s] or W.Z[W.strtrim(s)]) then
        W.harvest("zones", s)
    end
    if W.on("zones") and type(s) == "string" then return W.Z[s] or W.Z[W.strtrim(s)] or s end
    return s
end
do
    -- R156 (2026-10-01): NO overrides of GetZoneText / GetRealZoneText / GetSubZoneText / GetMinimapZoneText any more.
    -- The objective tracker calls GetRealZoneText on ZONE_CHANGED_NEW_AREA; our wrapper tainted it, the tainted
    -- MarkDirty ran the next tracker update tainted, and ShouldShowMawBuffs → GetAuraDataByIndex failed ("Auras cannot
    -- be accessed when secret while tainted by WoWBY"). Zone names are now swapped where they are SHOWN
    -- (W.tr_zone_text: minimap, zone fade text; minimap zone tooltip; tracker headers).
    -- R607 (2026-10-16, taintLog 11): the C_Map.GetMapInfo / GetMapInfoAtPosition / GetAreaInfo and
    -- C_AreaPoiInfo.GetAreaPOIInfo wraps are gone too — every Blizzard caller (map canvas, Who list filters, PTR
    -- reporter…) ran tainted after calling them ("reading field GetMapInfo … tainted by WoWBY"). Map titles / nav bar,
    -- city-pin hover labels and tooltips are translated where shown (map_retext, tooltip line pass: Z / POI / N).
end
-- R607: world-map hover area label (AreaLabelFrame: Name + Description) — its names came from the C_Map / AreaPOI
-- wraps; now swapped after Blizzard's EvaluateLabels (hook on our map's label INSTANCE: the map canvas is not secure)
local area_hooked = setmetatable({}, { __mode = "k" })
local function area_post(lab)
    if not (W.is_be() and lab) then return end
    local nm = lab.Name and plain(lab.Name:GetText())
    local be = nm and nm ~= "" and W.on("zones") and (W.Z[nm] or W.Z[W.strtrim(nm)] or (WoWBY_POI or {})[nm] or W.N[nm])
    if be then W.swap(lab.Name, be) elseif nm and nm ~= "" then ztr(nm) end
    local ds = lab.Description and plain(lab.Description:GetText())
    local dbe = ds and ds ~= "" and W.ui_be(ds)
    if dbe and dbe ~= ds then W.swap(lab.Description, dbe) end
end
function W.hook_area_label()
    local wm = _G.WorldMapFrame
    for dp in pairs(wm and wm.dataProviders or {}) do
        local lab = type(dp) == "table" and dp.Label
        if lab and not area_hooked[lab] and lab.EvaluateLabels then
            area_hooked[lab] = true
            hooksecurefunc(lab, "EvaluateLabels", area_post)
        end
    end
end
local function tr_zone_fs(fs)
    local cur = fs and fs.GetText and plain(fs:GetText())
    if not cur or cur == "" then return end
    local be = W.Z[cur] or W.Z[W.strtrim(cur)]
    if be then W.set_be(fs, be) else ztr(cur) end        -- ztr only records the miss (harvest)
end
W.zone_be = function(t)                                  -- exact zone name → BE (tracker headers, minimap tooltip)
    t = plain(t)
    return t and t ~= "" and W.on("zones") and (W.Z[t] or W.Z[W.strtrim(t)]) or nil
end
-- display hooks on Blizzard's GLOBAL functions (the hook key is written into _G, not into a frame): same frame,
-- no English flash. SetZoneText runs right after the zone / subzone fade strings are set.
local zhooked = false
function W.hook_zones()
    if zhooked then return end
    zhooked = true
    if _G.SetZoneText then hooksecurefunc("SetZoneText", function() pcall(W.tr_zone_text) end) end
    if _G.Minimap_Update then hooksecurefunc("Minimap_Update", function() pcall(W.tr_zone_text) end) end
    if _G.Minimap_SetTooltip then
        hooksecurefunc("Minimap_SetTooltip", function()
            if not (W.is_be() and GameTooltip:IsShown()) then return end
            local changed = false
            for i = 1, GameTooltip:NumLines() do
                local fs = _G["GameTooltipTextLeft" .. i]
                local be = fs and W.zone_be(fs:GetText())
                if be then W.set_font(fs); W.swap(fs, be); changed = true end
            end
            if changed then GameTooltip:Show() end
        end)
    end
end
function W.tr_zone_text()
    if not W.on("zones") then return end
    tr_zone_fs(_G.MinimapZoneText)
    tr_zone_fs(_G.ZoneTextString)
    tr_zone_fs(_G.SubZoneTextString)
    -- the smaller line under the zone name: "(Alliance Territory)", "Sanctuary"… (UI words, not zone names)
    for _, n in ipairs({ "PVPInfoTextString", "PVPArenaTextString" }) do
        local fs = _G[n]
        local t = fs and plain(fs:GetText())
        local be = t and t ~= "" and W.ui_be(t)
        if be and be ~= t then W.set_be(fs, be) end
    end
end

-- ---------- harvest: quest log scan (titles, description, objective lines), throttled ----------
local last_scan = 0
function W.scan_quest_log()
    if not W.hv_on() or not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
    local now = GetTime()
    if now - last_scan < 3 then return end
    last_scan = now
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local qid = info.questID
            if W.needs_harvest(qid, "t") then W.harvest_quest(qid, "t", info.title) end
            if W.needs_harvest(qid, "d") or W.needs_harvest(qid, "o") then GetQuestLogQuestText(i) end  -- wrap records
            for _, ob in ipairs(C_QuestLog.GetQuestObjectives(qid) or {}) do
                -- R958 (owner 2026-11-13: counter never back to 0): only lines WoWBY cannot show in Belarusian; every
                -- objective of the log had been collected and re-counted each session until the next login prune
                if ob.text and ob.text ~= "" and not W.obj_line_be(ob.text, qid) then
                    W.harvest("objectives", ob.text, qid)
                end
            end
        elseif info and info.isHeader then
            ztr(info.title)                                  -- zone headers: records misses
        end
    end
end

W.hook_zones()
