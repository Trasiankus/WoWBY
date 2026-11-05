-- WoWBY/core/spells.lua — spell / item / aura tooltips.
-- Split from core.lua (tools/split_core.py); shared state lives in the addon namespace W.
local _, W = ...
-- ---------- spell + item tooltips (data/spells_items.lua; IDs verified against Forever EN at build) ----------
-- Descriptions: the tooltip shows RENDERED text ("deals 150% damage"), so each EN template was turned
-- into an anchored Lua pattern at build time; its captures (the numbers) are poured into the BE template.
-- No match -> the line stays English (never wrong numbers).
W.SN = WoWBY_SpellNames or {}
local SD = WoWBY_SpellDesc or {}
local SK = WoWBY_SpellDescKey or {}
W.IT = WoWBY_Items or {}
-- rendered numbers carry English units ("18 sec", "2 min") -> Belarusian abbreviations like EN "sec" / RU "сек."
-- (user 2026-09-25: "Дзейнічае 10 сек."); a doubled dot before the template's own "." is collapsed below
local UNITS = { sec = "сек.", secs = "сек.", min = "хв.", mins = "хв.", hr = "гадз.", hrs = "гадз.", hour = "гадз.",
                hours = "гадз.", day = "д", days = "д", yd = "м", yds = "м", yards = "м" }
-- ruRU client (R665): the Russian units in rendered numbers ("10 сек.", "2 мин.", "1 ч.", "30 м")
local UNITS_RU = { ["сек"] = "сек.", ["с"] = "сек.", ["мин"] = "хв.", ["ч"] = "гадз.", ["час"] = "гадз.",
                   ["часа"] = "гадз.", ["часов"] = "гадз.", ["д"] = "д", ["дн"] = "д", ["день"] = "д", ["дня"] = "д",
                   ["дней"] = "д", ["м"] = "м", ["ярд"] = "м", ["ярда"] = "м", ["ярдов"] = "м" }
local function units_be(v)
    v = v:gsub("\194\160", " ")          -- the client can put a no-break space in "1 hour" (stayed English in game)
    v = v:gsub("\226\128[\128-\138\175]", " ")   -- and the other Unicode spaces (U+2000–200A, narrow U+202F): R98
    v = v:gsub("\226\129\159", " ")               -- U+205F medium math space
    local a, b = v:match("^([%d%.,]+) to ([%d%.,]+)$")               -- damage ranges: "14 to 17"
    if a then return "ад " .. a .. " да " .. b end
    if W.RU then
        local ra, rb = v:match("^([%d%.,]+)[%-–—]+([%d%.,]+)$")      -- "14–17"
        if not ra then ra, rb = v:match("^от ([%d%.,]+) до ([%d%.,]+)$") end
        if ra then return "ад " .. ra .. " да " .. rb end
        v = v:gsub("([%d%.,]+)[%s\194\160]*([\208\209][\128-\191\208\209]*)%.?", function(n, u)
            local b2 = UNITS_RU[cyr_lower(u)]
            return b2 and (n .. " " .. b2) or nil
        end)
    end
    -- any odd separator bytes between the number and an English unit (R98: "1 hour" stayed English in game)
    return (v:gsub("([%d%.]+)[%s\128-\191\194\226]*(%a+)", function(n, u)
        local b2 = UNITS[u:lower()]
        if not b2 then return nil end
        return n .. " " .. b2
    end))
end
local function render_desc(key, text)
    local d = key and SD[key]
    -- ruRU client (R665): the RU templates' patterns into the same BE template first (data/ru.lua WoWBY_SpellDescRU)
    local dr = key and W.SD_RU and W.SD_RU[key]
    if not ((d or dr) and text) then return nil end
    -- SD[key] = { pattern, parts [, pattern2, parts2 …] }: one pair per branch of the EN `$?s123[A][B]` conditionals
    -- (build_addon desc_variants, R562: Entangling Roots "You may only have 1 target Rooted…" never matched)
    local t0, caps, parts = text:gsub("\r", ""), nil, nil
    for _, dd in ipairs({ dr or false, d or false }) do
        for i = 1, dd and #dd or 0, 2 do
            local c = { t0:match(dd[i]) }
            if #c > 0 then caps, parts = c, dd[i + 1]; break end
        end
        if caps then break end
    end
    if not caps then return nil end
    local out, female = {}, UnitSex("player") == 3
    for _, p in ipairs(parts) do
        local tp = type(p)
        if tp == "string" then out[#out + 1] = p
        elseif tp == "number" then
            local c = caps[p] or ""
            local z = W.on("zones") and W.Z[c]          -- "$z" (Hearthstone: "Returns you to Razor Hill")
            -- R217: a capture holding English PROSE is either a $@spelldesc reference (another spell's text — translate it
            -- as a description of its own) or a sentence Forever added that the lazy capture swallowed → then the whole
            -- line stays English (no half-English lines like "Restores 58 health over 18 сек. Must remain seated…")
            local prose = c:find("%a+ %a+ %a+ %a+")
                or (W.RU and c:find("[%a\208\209][%a\128-\191\208\209]* [%a\208\209][%a\128-\191\208\209]* [%a\208\209][%a\128-\191\208\209]* [%a\208\209]"))
            if not z and prose then
                local sub
                for _, k2 in ipairs(W.desc_keys_by_start(c)) do
                    if k2 ~= key then sub = render_desc(k2, c); if sub then break end end
                end
                if not sub then return nil end
                z = sub
            elseif z and (out[#out] or ""):find("[уў] $") then  -- after «у»: accusative of feminine words (у Жалезнакузню)
                z = z:gsub("(%S+)", function(w)
                    if w:find("ая$") then return (w:gsub("ая$", "ую")) end
                    if w:find("яя$") then return (w:gsub("яя$", "юю")) end
                    if w:find("а$") then return (w:gsub("а$", "у")) end
                    if w:find("я$") then return (w:gsub("я$", "ю")) end
                    return w
                end)
            end
            out[#out + 1] = z or units_be(c)
        else out[#out + 1] = female and p[2] or p[1] end
    end
    -- (EN "sec.  Must" double spaces and an empty last embedded block leave "  " / a trailing space: tidied, R279)
    local s = table.concat(out)
    if s:find("|4", 1, true) then s = W.plural_forms(s) end      -- BE $l plural word by the number before it (R553)
    return (s:gsub("(сек)%.%.", "%1."):gsub("(хв)%.%.", "%1."):gsub("(гадз)%.%.", "%1.")
            :gsub("([^\n ]) +", "%1 "):gsub(" +$", ""))
end
W.render_desc = render_desc
-- descriptions indexed by their first literal WORD, built once on first use (R216: "Restores (.-) health…" has only
-- 9 literal bytes before the first capture, so the old 12-byte index never held the food descriptions)
local START_IDX
-- patterns that OPEN with an embedded description ("^(.-) If you spend at least 10 sec eating…": Forever food =
-- $@spelldesc433 + its own sentence, R279) have no first word: kept with the literal text after the capture
local LEAD = {}
-- first words: English, or (ruRU client, R665) Russian — letters of either script
local WORD = "[%a\208\209][%a'\128-\191\208\209]+"
function W.desc_keys_by_start(text)
    if not START_IDX then
        START_IDX = {}
        local function index(k, d)
            local seen = {}
            for i = 1, type(d) == "table" and #d or 0, 2 do
                local p = type(d[i]) == "string" and d[i]
                local w = p and p:match("^%^(" .. WORD .. ") ")
                if w then
                    if not seen[w] then
                        seen[w] = true
                        START_IDX[w] = START_IDX[w] or {}
                        table.insert(START_IDX[w], k)
                    end
                elseif p then
                    local lit = p:match("^%^%(%.%-%)([^%%%(]+)")      -- literal run right after the leading capture
                    if lit and #lit >= 12 then LEAD[#LEAD + 1] = { lit, k } end
                end
            end
        end
        for k, d in pairs(SD) do index(k, d) end
        for k, d in pairs(W.SD_RU or {}) do index(k, d) end
    end
    local w = type(text) == "string" and text:match("^(" .. WORD .. ") ")
    local keys = w and START_IDX[w] or {}
    if type(text) ~= "string" then return keys end
    local out
    for _, e in ipairs(LEAD) do
        if text:find(e[1], 1, true) then
            out = out or { unpack(keys) }
            out[#out + 1] = e[2]
        end
    end
    return out or keys
end
-- item "Use:" lines end with the item cooldown ("… (1 Hr Cooldown)", ITEM_COOLDOWN_TOTAL_*): cut it off before the
-- description match, put it back in Belarusian (2026-10-07: Hearthstone / food "Use:" lines stayed English)
local CD_UNIT = { Sec = "сек.", Min = "хв.", Hr = "гадз.", Hour = "гадз.", Hours = "гадз.", Day = "дзён", Days = "дзён" }
local function cooldown_be(n, unit)
    local u = CD_UNIT[unit]
    if not u then return nil end
    if u == "дзён" then
        local k = tonumber(n); local m10, m100 = k % 10, k % 100
        u = (m10 == 1 and m100 ~= 11) and "дзень" or (m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14)) and "дні" or "дзён"
    end
    return "(Аднаўленне: " .. n .. " " .. u .. ")"
end
-- Forever appends its own well-fed XP sentence to food lines (spell 142418): cut it off, put it back in Belarusian (R217)
local function xp_tail(body, tail)
    local core, n = (body or ""):match("^(.-)%s*Additionally, experience gained from kills is increased by (%d+)%%%.$")
    if not core then return body, tail end
    return core, " Акрамя таго, вопыт, які атрымліваецца за забойствы, павялічваецца на " .. n .. "%." .. (tail or "")
end
-- a whole drawn "Use: … (N Hr Cooldown)" line → BE, trying every description with the same literal start (R203)
-- item spell lines by their rendered text: "Use:" and (R321) "Equip:" / "Chance on hit:" — an item whose spell id is not
-- mapped (quiver "Equip: Increases ranged attack speed by 10%.") is matched by the description patterns
local TRIGGERS = { { "^Use: (.+)$", "Ужыць: " }, { "^Equip: (.+)$", "Калі на персанажы: " },
                   { "^Chance on hit: (.+)$", "Магчымы эфект пры трапленні: " } }
-- ruRU client (R665): the client's own trigger words («Использование:», «Если на персонаже:», …) from its GlobalStrings
local function esc(s) return (s:gsub("%p", "%%%0")) end
if W.RU then
    for g, be in pairs({ ITEM_SPELL_TRIGGER_ONUSE = "Ужыць: ", ITEM_SPELL_TRIGGER_ONEQUIP = "Калі на персанажы: ",
                         ITEM_SPELL_TRIGGER_ONPROC = "Магчымы эфект пры трапленні: " }) do
        local s = type(_G[g]) == "string" and _G[g]
        if s then TRIGGERS[#TRIGGERS + 1] = { "^" .. esc(s) .. " (.+)$", be } end
    end
end
-- the item's "Use:" word on this client
local function use_prefix()
    return (W.RU and type(ITEM_SPELL_TRIGGER_ONUSE) == "string" and ITEM_SPELL_TRIGGER_ONUSE or "Use:") .. " "
end
-- "… (1 Hr Cooldown)" / ruRU «… (Восстановление: 1 ч.)» cut off the description → (body, Belarusian tail)
local CD_RU = { ["сек"] = "Sec", ["с"] = "Sec", ["мин"] = "Min", ["ч"] = "Hr", ["час"] = "Hour", ["часа"] = "Hours",
                ["часов"] = "Hours", ["д"] = "Days", ["дн"] = "Days", ["день"] = "Day", ["дня"] = "Days", ["дней"] = "Days" }
local function cut_cooldown(body)
    local core, n, unit = (body or ""):match("^(.-)%s*%((%d+)[%s\194\160]+(%a+)[%s\194\160]+Cooldown%)%s*$")
    if not core and W.RU then
        local u
        core, n, u = (body or ""):match("^(.-)%s*%(Восстановление: (%d+)[%s\194\160]+([^%s%.%)]+)%.?%)%s*$")
        unit = u and CD_RU[cyr_lower(u)]
    end
    if core and cooldown_be(n, unit) then return core, " " .. cooldown_be(n, unit) end
    return body, ""
end
function W.use_line_be(t)
    if not (W.on("spells") and type(t) == "string") then return nil end
    -- tooltip DATA keeps the plural escape unresolved: "(1 |4Sec:Sec; Cooldown)" (R383, the drawn text has "1 Sec")
    if t:find("|4", 1, true) then t = W.plural_forms(t) end
    local body, head
    for _, tr in ipairs(TRIGGERS) do
        body = t:match(tr[1])
        if body then head = tr[2]; break end
    end
    if not body then                       -- set bonuses: "(3) Set: …" (ITEM_SET_BONUS_GRAY), "Set: …" (R733)
        local n, b = t:match("^%((%d+)%) Set: (.+)$")
        if n then
            local k = tonumber(n) % 100
            local w = (k % 10 == 1 and k ~= 11) and "прадмет"
                or (k % 10 >= 2 and k % 10 <= 4 and (k < 12 or k > 14)) and "прадметы" or "прадметаў"
            body, head = b, "Камплект (" .. n .. " " .. w .. "): "
        else
            body = t:match("^Set: (.+)$")
            if body then head = "Камплект: " end
        end
    end
    if not body then return nil end
    local tail
    body, tail = cut_cooldown(body)
    body, tail = xp_tail(body, tail)
    for _, k in ipairs(W.desc_keys_by_start(body)) do
        local be = render_desc(k, body)
        if be then return head .. be .. tail end
    end
end
local function tr_desc_lines(lines, key, prefix_en, prefix_be)
    if not key then return end
    for i = 2, #lines do
        local t = plain(lines[i].leftText)
        if type(t) == "string" and t:find("|4", 1, true) then t = W.plural_forms(t) end   -- "(1 |4Sec:Sec; Cooldown)", R383
        if type(t) == "string" then
            local body = t
            if prefix_en then body = t:match("^" .. esc(prefix_en) .. "(.*)$") end
            local tail
            body, tail = cut_cooldown(body)
            body, tail = xp_tail(body, tail)
            local be = body and render_desc(key, body)
            if be then lines[i].leftText = (prefix_be or "") .. be .. tail; return true end
        end
    end
end
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    W.TIP.pre(Enum.TooltipDataType.Spell, function(tt, data)
        local id = data and W.sid_ok(data.id)
        if not (W.on("spells") and id and data.lines) then return end
        local l1 = data.lines[1]
        local en1 = l1 and plain(l1.leftText) or ""
        local nm = W.SN[id] or (WoWBY_SpellNamesEN or {})[en1]                          -- by id, else by EN name
        -- camping recipes show "First Aid: First Aid Kit" (profession: spell, R563) → «Першая дапамога: Аптэчка» (owner)
        local pre, rest = en1:match("^([^:]+): (.+)$")
        if pre and not (WoWBY_SpellNamesEN or {})[en1] then
            local pb, rb = W.ui_be(pre), W.spell_name_be(rest) or W.IE[rest]
            if pb and pb ~= pre and rb and (not W.SN[id] or W.SN[id] == rb) then nm = pb .. ": " .. rb end
        end
        if nm and l1 then l1.leftText = nm end
        tr_desc_lines(data.lines, SK[id])
    end)
    if Enum.TooltipDataType.UnitAura then
        W.TIP.pre(Enum.TooltipDataType.UnitAura, function(tt, data)
            if not (W.on("spells") and data and data.lines) then return end
            local id = W.sid_ok(data.id)
            if id then
                -- by id, else by the EN name (R195: "Rapid Regeneration" had no id entry, only SE)
                local l1n = data.lines[1] and plain(data.lines[1].leftText)
                local nm = W.SN[id] or (l1n and W.spell_name_be(l1n))
                if nm and data.lines[1] then data.lines[1].leftText = nm end
                tr_desc_lines(data.lines, (WoWBY_AuraDescKey or {})[id] or SK[id])
                return
            end
            -- id is SECRET (buff frame, often in combat): go by the English name on line 1
            local l1 = data.lines[1]
            local en = l1 and plain(l1.leftText)
            local e = en and (WoWBY_AuraByName or {})[en]
            local nm = en and W.spell_name_be(en)
            if nm then l1.leftText = nm end
            if not e then return end
            for _, k in ipairs(e[2] or {}) do
                if tr_desc_lines(data.lines, k) then break end
            end
        end)
    end
    W.TIP.pre(Enum.TooltipDataType.Item, function(tt, data)
        local id = data and W.sid_ok(data.id)
        if not (W.on("spells") and id and data.lines) then return end
        local l1 = data.lines[1]
        local en1 = l1 and plain(l1.leftText) or ""
        local nm = W.IE[en1] or W.IT[id]                                     -- by EN name, else by id
        -- random suffix (R335): "Charger's Armor of Frost Protection" = base + «of …» → BE base + BE suffix
        -- (the id alone gives the BASE name, which dropped the suffix)
        local base, suf = en1:match("^(.-) (of .+)$")
        local sbe = suf and WoWBY_Suffix and WoWBY_Suffix[suf]
        if sbe and not W.IE[en1] then
            local bbe = W.IE[base] or W.IT[id]
            -- ў / у at the suffix start by the base's last letter (R351: «Боты ўхілення», «Шчыт ухілення»)
            if bbe and (sbe:sub(1, 2) == "ў" or sbe:sub(1, 2) == "у") then
                local last = bbe:match("([%z\1-\127\194-\244][\128-\191]*)$")
                local vowel = last and ("аеёіоуыэюяАЕЁІОУЫЭЮЯ"):find(last, 1, true)
                sbe = (vowel and "ў" or "у") .. sbe:sub(3)
            end
            nm = bbe and (bbe .. " " .. sbe) or nil
        end
        if nm and l1 then l1.leftText = nm end
        local sid = C_Item and C_Item.GetItemSpell and select(2, C_Item.GetItemSpell(id))
        if sid and tr_desc_lines(data.lines, SK[sid], use_prefix(), "Ужыць: ") then return end
        -- R203: the item spell id can be unknown when the tooltip is built (Hearthstone / food stayed English):
        -- try every description whose literal start matches the "Use:" line
        for i = 2, #data.lines do
            local t = plain(data.lines[i].leftText)
            local body = type(t) == "string" and t:match("^" .. esc(use_prefix()) .. "(.+)$")
            if body then
                for _, k in ipairs(W.desc_keys_by_start(body)) do
                    if tr_desc_lines(data.lines, k, use_prefix(), "Ужыць: ") then return end
                end
            end
        end
    end)
    -- R734: items the client keeps encrypted (new Forever items: "Elixir of Endless Experience") are in no file we can
    -- read → harvest the name and the Use / Equip / flavour lines that stayed English (registered after the translator)
    W.TIP.pre(Enum.TooltipDataType.Item, function(tt, data)
        local id = data and W.sid_ok(data.id)
        if not (W.hv_on() and id and data.lines and data.lines[1]) then return end
        local en1 = plain(data.lines[1].leftText)
        if type(en1) ~= "string" or en1 == "" or W.ours(en1) or W.IE[en1] or W.IT[id] then return end
        local d = {}
        for i = 2, #data.lines do
            local t = plain(data.lines[i].leftText)
            if type(t) == "string" and not W.ours(t) and (t:find("^Use: ") or t:find("^Equip: ")
                    or t:find("^Chance on hit: ") or t:find('^"')) then
                d[#d + 1] = t
            end
        end
        W.harvest("items", tostring(id), { n = en1, d = d })
    end)
end

-- spell book (Blizzard_PlayerSpells, load-on-demand): names under the icons ("Mark of the Wild" -> «Знак прыроды»).
-- WowUkrainizer's way: after each page update (the paged frame's own OnUpdate callback + OnShow) the visible items'
-- Name FontStrings get SetText — by spell id, else by the EN name. Nothing is hooked on the item buttons themselves.
local spellbook_hooked = false
function W.hook_spellbook()
    local sb = _G.PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
    local paged = sb and sb.PagedSpellsFrame
    if spellbook_hooked or not (paged and paged.EnumerateFrames) then return end
    spellbook_hooked = true
    -- R388: a long BE name («Тэлепартацыя: Месяцовая паляна») wrapped and lost its second line → the font shrinks
    -- step by step (down to 9) until the name is no longer truncated; English gets its own size back
    local base_size = setmetatable({}, { __mode = "k" })
    local base_wrap = setmetatable({}, { __mode = "k" })
    local function fit(fs, be_mode)
        local file, size, flags = fs:GetFont()
        if not (file and size) then return end
        base_size[fs] = base_size[fs] or size
        if base_wrap[fs] == nil and fs.GetWordWrap then base_wrap[fs] = fs:GetWordWrap() and true or false end
        local want = base_size[fs]
        if size ~= want then pcall(fs.SetFont, fs, file, want, flags or "") end
        -- the name wrapped onto a 2nd line the button hides — not "truncated" for the game (R388 still cut): one line
        -- in BE mode, so IsTruncated sees it; English gets Blizzard's wrapping back
        if fs.SetWordWrap and base_wrap[fs] ~= nil then pcall(fs.SetWordWrap, fs, (not be_mode) and base_wrap[fs]) end
        if not be_mode then return end
        local s = want
        local function too_wide()
            if fs.IsTruncated and fs:IsTruncated() then return true end
            local w = fs:GetWidth()
            return w and w > 0 and fs:GetStringWidth() > w + 1
        end
        while too_wide() and s > 9 do
            s = s - 1
            pcall(fs.SetFont, fs, file, s, flags or "")
        end
    end
    local function update()
        local be_mode = W.is_be() and W.on("spells")
        for _, fr in paged:EnumerateFrames() do
            local info = fr.spellBookItemInfo
            if info and fr.Name then
                if be_mode then
                    local en = plain(fr.Name:GetText())
                    local id = W.sid_ok(info.spellID)
                    local be = (id and W.SN[id]) or (en and ((WoWBY_AuraByName or {})[en] or {})[1])
                        or (en and (WoWBY_SpellNamesEN or {})[en])
                    if be and en and be ~= en then W.swap(fr.Name, be) end
                end
                pcall(fit, fr.Name, be_mode)
            end
        end
    end
    W.spellbook_update = function() if sb:IsShown() then pcall(update) end end   -- language switch (R389)
    sb:HookScript("OnShow", function() C_Timer.After(0, update) end)   -- not mid secure path (R29)
    if paged.RegisterCallback and PagedContentFrameBaseMixin and PagedContentFrameBaseMixin.Event then
        paged:RegisterCallback(PagedContentFrameBaseMixin.Event.OnUpdate, update, "WoWBY")
    end
end

-- a spell's Belarusian name by its EN name (lists that carry no spell id: trainer rows, talent tooltips)
function W.spell_name_be(en)
    en = plain(en)
    if not (en and W.on("spells")) then return nil end
    return ((WoWBY_AuraByName or {})[en] or {})[1] or (WoWBY_SpellNamesEN or {})[en]
end

-- trainer window rows (Blizzard_TrainerUI, load-on-demand): spell name, "(Rank 2)", and the requirements line
-- "Requires: Level 8, Healing Touch (Rank 1)" rebuilt piece by piece — all pieces known or the line stays English.
-- Post-hook on the global row initializer (the scroll box calls it by name every time a row is filled).
local function req_part_be(p)
    local be = W.ui_be(p)                                 -- "Level |cffffffff8|r"
    if be then return be end
    local c, inner, r = p:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
    local core = inner or p
    local nm, sub = core:match("^(.-) %((.-)%)$")         -- "Healing Touch (Rank 1)", "Bear Form (Shapeshift)"
    local out = W.spell_name_be(nm or core)
    if not out then return nil end
    if sub then
        local sb = W.ui_be(sub)
        if not sb then return nil end
        out = out .. " (" .. sb .. ")"
    end
    return c and (c .. out .. r) or out
end
local function requirements_be(t)
    if W.RU then t = W.en_line(t) end                     -- «Требуется: …» → "Requires …" (R665)
    local head, rest = t:match("^(Requires:) (.+)$")
    if not head and W.RU then                             -- ITEM_REQ_SKILL's English has no colon
        rest = t:match("^Requires (.+)$")
        head = rest and "Requires:"
    end
    if not head then return W.ui_be(t) end                -- "Already Known" …
    local parts = {}
    for p in (rest .. ", "):gmatch("(.-), ") do
        local b = req_part_be(p)
        if not b then return nil end
        parts[#parts + 1] = b
    end
    return (W.ui_be(head) or head) .. " " .. table.concat(parts, ", ")
end
W.trainer_requirements_be = requirements_be       -- (exposed for tools/addon_probe.py)
local trainer_hooked = false
function W.hook_trainer()
    if trainer_hooked or type(_G.ClassTrainerFrame_InitServiceButton) ~= "function" then return end
    trainer_hooked = true
    -- window title = the trainer's name: ClassTrainerFrame_Update re-sets it (SetTitle(UnitName("npc"))) on every
    -- update, after the OnShow pass of R502 had run (R528) → post-hook the update itself
    if type(_G.ClassTrainerFrame_Update) == "function" then
        hooksecurefunc("ClassTrainerFrame_Update", function()
            local tf = _G.ClassTrainerFrame
            local fs = tf and tf.GetTitleText and tf:GetTitleText()
            local t = fs and plain(fs:GetText())
            local be = t and W.is_be() and W.on("names") and W.name_be_unit(t, "npc")
            if be then W.set_font(fs); W.swap(fs, be) end
        end)
    end
    -- R785 (owner: «Месяц…» cut though the row has room): the name's width was measured for the English. Name and «(Ранг 1)»
    -- are re-fitted to the real text, in the row's space left of the price; a too long name still ends in "…"
    local function text_w(fs)
        return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
    end
    local function fit_trainer_row(btn)
        if not (btn.name and btn.nameSubText and btn.GetWidth) then return end
        local sub = btn.nameSubText:GetText() ~= "" and text_w(btn.nameSubText) + 2 or 0
        local price = 0
        if btn.money and btn.money:IsShown() then price = btn.money:GetWidth() end
        if btn.alternateCost and btn.alternateCost:IsShown() then price = text_w(btn.alternateCost) + 15 end
        local room = btn:GetWidth() - 48 - price - 10 - sub                  -- 48 = icon + its gaps
        btn.name:SetWidth(math.max(40, math.min(text_w(btn.name) + 2, room)))
        btn.nameSubText:SetWidth(sub)
    end
    hooksecurefunc("ClassTrainerFrame_InitServiceButton", function(btn)
        if not btn then return end
        if not (W.is_be() and W.on("spells")) then pcall(fit_trainer_row, btn); return end
        local t = btn.name and plain(btn.name:GetText())
        if t then
            local c, inner, r = t:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
            local be = W.spell_name_be(inner or t)
            if be then W.swap(btn.name, c and (c .. be .. r) or be) end
        end
        local s = btn.nameSubText and plain(btn.nameSubText:GetText())
        local sub = s and s:match("^%((.+)%)$")
        local sb = sub and W.ui_be(sub)
        if sb then W.swap(btn.nameSubText, "(" .. sb .. ")") end
        local q = btn.subText and plain(btn.subText:GetText())
        local qb = q and q ~= "" and requirements_be(q)
        if qb and qb ~= q then W.swap(btn.subText, qb) end
        pcall(fit_trainer_row, btn)
    end)
end
