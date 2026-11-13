-- WoWBY/core/tooltips.lua — tooltip line translation + tooltip hooks.
-- Split from core.lua (tools/split_core.py); shared state lives in the addon namespace W.
local _, W = ...
-- engine-generated spell tooltip lines (not GlobalStrings): cost, range, cast time, rank, cooldown, …
local SPELL_LINES = {
    { "^(%d+) Mana$", "%1 маны" }, { "^(%d+) Rage$", "%1 лютасці" }, { "^(%d+) Energy$", "%1 энергіі" },
    { "^(%d+) Focus$", "%1 засяроджанасці" }, { "^([%d%.]+) yd range$", "Далёкасць %1 м" },
    { "^Melee Range$", "Блізкі бой" }, { "^Unlimited range$", "Неабмежаваная далёкасць" },
    { "^([%d%.]+) sec cast$", "Чытанне %1 сек." }, { "^([%d%.]+) min cast$", "Чытанне %1 хв." },
    -- neuter (дзеянне), owner 2026-10-01 R182
    { "^Instant$", "Імгненнае" }, { "^Instant cast$", "Імгненнае" }, { "^Channeled$", "Паточнае" },
    { "^Passive$", "Пасіўнае" },
    { "^Next melee$", "Наступны ўдар" }, { "^Rank (%d+)$", "Ранг %1" },
    { "^([%d%.]+) sec cooldown$", "Аднаўленне %1 сек." }, { "^([%d%.]+) min cooldown$", "Аднаўленне %1 хв." },
    { "^Sell Price:", "Кошт:" },                  -- "Requires / Reagents / Tools: …": req_list_be (every piece known)
    { "^(%d+) seconds? remaining$", "Засталося %1 сек." }, { "^(%d+) minutes? remaining$", "Засталося %1 хв." },
    { "^(%d+) hours? remaining$", "Засталося %1 гадз." }, { "^(%d+) days? remaining$", "Засталося %1 д" },
    -- short forms (PET_TIME_LEFT_*: the ruRU client's buff timer «Осталось 52 сек.», R667)
    { "^(%d+) sec left$", "Засталося %1 сек." }, { "^(%d+) min left$", "Засталося %1 хв." },
    { "^Magic$", "Магія" }, { "^Curse$", "Праклён" }, { "^Poison$", "Яд" }, { "^Disease$", "Хвароба" },
}
-- The beta's "Press F6 to submit an issue for this …" hint stays ENGLISH (R293, 2026-10-09): Blizzard_PTRFeedback looks
-- for "to submit an issue for this" in the tooltip before adding it (talent tooltips are filled twice: talent + spell);
-- a translated line hid it from that check and the hint showed twice. Beta-only, gone at release.
local function detect_tooltip_female(tt)
    local unit = tt and tt.GetUnit and select(2, tt:GetUnit())
    return (unit and UnitExists(unit) and UnitSex(unit) == 3) or false
end
-- "Requires Bear Form, Dire Bear Form" / "Requires Blacksmithing (75)": every comma piece must be known (spell /
-- form name, UI word, item) — else nil; SPELL_LINES used to pass English pieces through (R18, 2026-09-29)
-- Same for recipe lines "Reagents: Stringy Wolf Meat, |cffff2020Mild Spices|r" and "Tools: …" (R23): pieces may carry
-- their own colour (red = missing) and a count "(2)".
-- The separator after the label is kept: SPELL_REAGENTS is "Reagents: |n" (the list on the next line, R656).
local LIST_HEADS = { { "^Requires:", "Патрабуецца:" },       -- recipe tool / spell focus (R317, red when missing)
                     { "^Requires", "Патрабуецца:" }, { "^Reagents:", "Рэагенты:" },
                     { "^Tools:", "Інструменты:" },
                     -- R628: a line whose label another pass already swapped («Патрабуецца: Cooking Fire», the red
                     -- spell focus on recipe tooltips) — the pieces still get translated
                     { "^Патрабуецца:", "Патрабуецца:" }, { "^Рэагенты:", "Рэагенты:" },
                     { "^Інструменты:", "Інструменты:" } }
local function req_list_be(t)
    -- R923: the label in its own colour — profession window "Requires: Forge" arrives as "|cffffd100Requires:|r Forge"
    -- (PROFESSIONS_REQUIRED_TOOLS' |cnNORMAL_FONT_COLOR: resolved) or already half-swapped «|cff…Патрабуецца:|r Forge»
    local cc, lab, tail = t:match("^(|c%x%x%x%x%x%x%x%x)([^|]-:)|r(.+)$")
    if not cc then cc, lab, tail = t:match("^(|cn[%w_]+:)([^|]-:)|r(.+)$") end
    if cc then
        local be = req_list_be(lab .. tail)
        if not be then return nil end
        local bl, brest = be:match("^([^:]-:)(.*)$")
        return bl and (cc .. bl .. "|r" .. brest) or nil
    end
    local rest, head
    for _, h in ipairs(LIST_HEADS) do
        local s, e = t:find(h[1])
        if s then
            local sep, r = t:sub(e + 1):match("^(%s*|n%s*)(.+)$")
            if not sep then sep, r = t:sub(e + 1):match("^(%s+)(.+)$") end
            if r then
                rest, head = r, h[2] .. (h[1] == "^Requires" and " " or sep)
                break
            end
        end
    end
    if not rest or W.ours(rest) then return nil end
    local out = {}
    for piece in (rest .. ", "):gmatch("(.-), ") do
        local c, inner, r = piece:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
        local nm, num = (inner or piece):match("^(.-) (%(%d+%))$")
        local core = nm or inner or piece
        local be = W.spell_name_be(core) or W.ui_be(core) or W.IE[core]
        if not be then return nil end
        be = be .. (num and (" " .. num) or "")
        out[#out + 1] = c and (c .. be .. r) or be
    end
    -- R661 (owner): "Requires" lists of several pieces one per line («Патрабуецца: Аблічча мядзведзя,» / «Аблічча
    -- лютага мядзведзя») — the Belarusian names made those tooltips very wide
    local sep = (#out > 1 and head:find("^Патрабуецца")) and ",\n" or ", "
    return head .. table.concat(out, sep)
end
W.req_list_be = req_list_be                      -- (exposed for tools/addon_probe.py)
-- recipe tooltips list the reagents with NO heading (R921, QA 2026-11-11): "Thin Kodo Leather (3), Light Leather (4),
-- Coarse Thread" — every piece must be a known ITEM name (+ optional "(N)"), and a single piece needs the count
function W.reagent_line_be(t)
    if not W.on("spells") or t:find("|", 1, true) or W.ours(t) then return nil end
    local out, counted = {}, false
    for piece in (t .. ", "):gmatch("(.-), ") do
        local nm, num = piece:match("^(.-) (%(%d+%))$")
        local be = W.IE[nm or piece]
        if not be then return nil end
        counted = counted or num ~= nil
        out[#out + 1] = be .. (num and (" " .. num) or "")
    end
    if #out < 2 and not counted then return nil end
    return table.concat(out, ", ")
end
-- FULLDATE "Sunday, October 11 2026" (calendar day tooltips, R314) → «Нядзеля, 11 кастрычніка 2026» (month genitive)
local WEEKDAY_BE = { Monday = "Панядзелак", Tuesday = "Аўторак", Wednesday = "Серада", Thursday = "Чацвер",
                     Friday = "Пятніца", Saturday = "Субота", Sunday = "Нядзеля" }
local MONTH_GEN_BE = { January = "студзеня", February = "лютага", March = "сакавіка", April = "красавіка", May = "мая",
                       June = "чэрвеня", July = "ліпеня", August = "жніўня", September = "верасня",
                       October = "кастрычніка", November = "лістапада", December = "снежня" }
-- ruRU client (R665): FULLDATE «11 октября 2026 г., воскресенье» (declined month, lowercase weekday)
local WEEKDAY_RU = { ["понедельник"] = "Monday", ["вторник"] = "Tuesday", ["среда"] = "Wednesday", ["четверг"] = "Thursday",
                     ["пятница"] = "Friday", ["суббота"] = "Saturday", ["воскресенье"] = "Sunday" }
local MONTH_RU = { ["января"] = "January", ["февраля"] = "February", ["марта"] = "March", ["апреля"] = "April",
                   ["мая"] = "May", ["июня"] = "June", ["июля"] = "July", ["августа"] = "August",
                   ["сентября"] = "September", ["октября"] = "October", ["ноября"] = "November", ["декабря"] = "December" }
function W.date_be(t)
    if W.RU then
        local d, mo, y, wd = t:match("^(%d+) (%S+) (%d+) г%.?, (%S+)$")
        if not d then d, mo, y = t:match("^(%d+) (%S+) (%d+) г%.?$") end
        local m = mo and MONTH_RU[cyr_lower(mo)]
        local w = wd and WEEKDAY_RU[cyr_lower(wd)]
        if m and (w or not wd) then
            return (w and (WEEKDAY_BE[w] .. ", ") or "") .. d .. " " .. MONTH_GEN_BE[m] .. " " .. y
        end
    end
    local wd, mo, d, y = t:match("^(%a+), (%a+) (%d+) (%d+)$")
    if wd and WEEKDAY_BE[wd] and MONTH_GEN_BE[mo] then return WEEKDAY_BE[wd] .. ", " .. d .. " " .. MONTH_GEN_BE[mo] .. " " .. y end
    mo, d, y = t:match("^(%a+) (%d+),? (%d+)$")                    -- "October 11 2026" without the weekday
    if mo and MONTH_GEN_BE[mo] then return d .. " " .. MONTH_GEN_BE[mo] .. " " .. y end
end
-- texts of several lines with no whole-text match (R387: engine-built proficiency / language spells
-- "You are fluent in the following languages:\nCommon\nDarnassian"): translated line by line — list headers here,
-- list items by the header's kind (armour words, languages), other lines like a tooltip line; all lines or nothing
local LIST_HEAD = {
    ["You are proficient in the use of the following armor types:"] = { "Вы ўмееце насіць наступныя тыпы даспехаў:", "armor" },
    ["You are proficient in the use of the following weapon types:"] = { "Вы ўмееце карыстацца наступнымі тыпамі зброі:", "ui" },
    ["You are fluent in the following languages:"] = { "Вы свабодна валодаеце наступнымі мовамі:", "lang" },
}
local ARMOR_WORDS = { Cloth = "Тканіна", Leather = "Скура", Mail = "Кальчуга", Plate = "Латы", Shields = "Шчыты",
                      Shield = "Шчыт" }
if W.ru_alias then W.ru_alias(LIST_HEAD, "ui"); W.ru_alias(ARMOR_WORDS, "ui") end      -- ruRU client (R665)
local tooltip_line_be, tooltip_line_core
local function multiline_be(t)
    local out, kind = {}, nil
    for line in (t .. "\n"):gmatch("(.-)\n") do
        local s = W.strtrim(line)
        -- R660: lines come coloured in game (yellow header "|cffffd200You are fluent…|r", white list) → colour codes
        -- peeled off and put back around the translation
        local pre, post = "", ""
        local c, rest = s:match("^(|c%x%x%x%x%x%x%x%x)(.*)$")
        if c then pre, s = c, rest end
        if s:sub(1, 2) == "|r" then pre, s = pre .. "|r", s:sub(3) end
        c, rest = s:match("^(.-)(|c%x%x%x%x%x%x%x%x)$")       -- a colour opened at the line end for the next line
        if c then s, post = c, rest end
        if s:sub(-2) == "|r" then post, s = "|r" .. post, s:sub(1, -3) end
        s = W.strtrim(s)
        local b
        if s == "" then b = line; pre, post = "", ""
        elseif LIST_HEAD[s] then b, kind = LIST_HEAD[s][1], LIST_HEAD[s][2]
        elseif kind == "armor" then b = ARMOR_WORDS[s] or W.UI[s]
        elseif kind == "lang" then b = W.LANG and W.LANG[s]
        else b = W.UI[s] or tooltip_line_be(s) end
        if not b then return nil end
        out[#out + 1] = pre .. b .. post
    end
    return table.concat(out, "\n")
end
function tooltip_line_be(t)
    t = plain(t)
    if not t then return nil end
    -- named colours "|cnRED_FONT_COLOR:Cooking Fire|r" (a missing recipe tool, R662): every rule below knows only the
    -- hex form → each named colour becomes a placeholder hex for the lookup and is put back in the result
    if t:find("|cn", 1, true) then
        local map, k = {}, 0
        local conv = t:gsub("|cn[%w_]+:", function(c)
            k = k + 1
            local f = ("|c0fcafe%02x"):format(k)
            map[f] = c
            return f
        end)
        if conv == t then return nil end
        local be = tooltip_line_be(conv)
        return be and (be:gsub("|c0fcafe%x%x", map)) or nil
    end
    -- ruRU client (R665): each English reading of the Russian line through the English rules below, then the line
    -- itself (names / zones / items / descriptions are found through the RU aliases)
    if W.RU then
        for _, e in ipairs(W.ru_lines_en(t) or {}) do
            local b = tooltip_line_core(e)
            if b then return b end
        end
    end
    return tooltip_line_core(t)
end
function tooltip_line_core(t)
    local dt = W.date_be(t)
    if dt then return dt end
    local pt = W.on("names") and W.pet_title_be(t)                   -- "X's Pet" → «Гадаванец X» (R315)
    if pt then return pt end
    local rq = req_list_be(t) or W.reagent_line_be(t)
    if rq then return rq end
    if t == "Back" then return "Спіна" end
    -- a whole line that is a quest title wins over the UI formats (R567: "Camping 101: First Aid" was built piece by piece
    -- as «Адпачынак у лагеры 101: …» in a minimap tooltip while the log said «Лагераванне 101: …»)
    local qt = W.on("quests") and #t > 3 and t:find(W.LET) and W.qtitle_be and W.qtitle_be(t)
    if qt then return qt end
    -- crafted items "<Made by Arvel>" (ITEM_CREATED_BY, R657): the crafter is always a player — name kept, like "Loot:"
    local mc, crafter, mr = t:match("^(|c%x%x%x%x%x%x%x%x)<Made by ([^<>|]+)>(|r)$")
    if not crafter then crafter = t:match("^<Made by ([^<>|]+)>$"); mc, mr = "", "" end
    if crafter then return mc .. "<Вытворца: " .. crafter .. ">" .. mr end
    -- unit tooltip "Loot: <player>" (who may loot this corpse): the name is a player's, unknown by design (owner R554)
    local looter = t:match("^Loot: (.+)$")
    if looter and not looter:find(":") then
        local known = W.ui_be(t)                                      -- "Loot: Group Loot" & co. are UI strings
        if known and known ~= t then return known end
        return "Здабыча: " .. (W.name_be(looter, true) or looter)    -- R958: a player's name, never harvested
    end
    -- game-menu performance tooltip (R123): per-addon memory "(48.20 MB) WoWBY" and the protocol block ("TCP" and
    -- addon names are not "known" captures, so the generic formats reject them)
    local mem, unit, addon = t:match("^%(([%d%.,]+) ([MK]B)%) (.+)$")
    if mem then return "(" .. mem .. " " .. (unit == "MB" and "МБ" or "КБ") .. ") " .. addon end
    local ph, pw = t:match("^Communication Protocol:\nHome: (%S+)\nWorld: (%S+)$")
    if ph then return "Пратакол сувязі:\nЛакальны: " .. ph .. "\nГлабальны: " .. pw end
    ph, pw = t:match("^Internet Protocols:\nHome: (%S+)\nWorld: (%S+)$")
    if ph then return "Інтэрнэт-пратаколы:\nЛакальны: " .. ph .. "\nГлабальны: " .. pw end
    -- comparison deltas: the number in its own colour, then the stat ("|cff00ff00+4|r Agility", R114)
    local num, stat = t:match("^(|c%x%x%x%x%x%x%x%x[%+%-]?[%d%.,]+|r%s+)(.+)$")
    if num then
        local b = W.ui_be(stat)
        if b and b ~= stat then return num .. b end
    end               -- item slot (cloak), not the «Назад» button
    -- armour types on the item tooltip's right side (R37): "Mail" is «Пошта» everywhere else (mailbox)
    -- weapon types too (R105: "Axe" stayed English)
    local armor = ({ Mail = "Кальчуга", Cloth = "Тканіна", Leather = "Скура", Plate = "Латы",
                     Axe = "Сякера", Sword = "Меч", Mace = "Булава", Dagger = "Кінжал", Staff = "Посах",
                     Polearm = "Дрэўкавая зброя", Bow = "Лук", Gun = "Агнястрэльная зброя", Crossbow = "Арбалет",
                     Wand = "Жазло", ["Fist Weapon"] = "Кісцевая зброя", ["Fishing Pole"] = "Вуда",
                     Idol = "Ідал", Totem = "Татэм", Libram = "Лібрам", Arrow = "Страла", Bullet = "Куля",
                     Thrown = "Кідальная зброя", Shield = "Шчыт" })[t]
    if armor then return armor end
    local use = W.use_line_be and W.use_line_be(t)                 -- item "Use: …" line (R203)
    if use then return use end
    -- choice talents (Feral Charge: bear / cat) are built with plain AddLine, no spell data (R288): a line that is a
    -- spell description, or a spell name with a "(Cat)" suffix, is matched like the spell tooltip would be
    if W.on("spells") and #t > 15 and t:find(W.RU and "^[%u\208\209]" or "^%u") and W.desc_keys_by_start then
        for _, k in ipairs(W.desc_keys_by_start(t)) do
            local d = W.render_desc(k, t)
            if d then return d end
        end
    end
    if W.on("spells") and t:find(" %(%a[%a ]*%)$") then
        local nm = W.spell_name_be(t)
        if nm then return nm end
    end
    if W.current_tooltip_female then                       -- "Warrior" line of a female unit -> «Ваярка»
        local g = W.ui_val(t)
        if g ~= t then return g end
    end
    local be = W.ui_be(t)
    if not be and W.on("zones") then                        -- a whole line that is a faction or place ("Darnassus")
        be = (WoWBY_Factions or {})[t] or W.Z[t] or (WoWBY_POI or {})[t]   -- R607: POI (city pin labels) here now
    end
    if not be then
        local head, tail = t:match("^(.-)(%s*|c%x%x%x%x%x%x%x%x%s*%(.-%)|r)$")   -- "Name |cff..(C)|r", "Backpack|cff.. (F12)|r"
        -- bag slot buttons: "Soft Saber Sack |cff..(F11)|r" = the bag's item name + keybind
        local hb = head and (W.ui_be(head) or (W.on("spells") and W.IE and W.IE[head]))
        if hb then be = hb .. tail end
    end
    if not be and W.on("spells") and W.IE and W.IE[t] then
        be = W.IE[t]                         -- a bag slot without a keybind: the bare item name (R237)
    end
    if not be and W.on("spells") and W.IE then
        local sp, nm = t:match("^(%s+)(.+)$")  -- item set pieces under the set name: "  Arcanist Crown" (R733)
        if nm and W.IE[nm] then be = sp .. W.IE[nm] end
    end
    if not be then
        -- engine lines, also inside one colour ("|cff…Press F6 to submit an issue for this Spell|r" is blue)
        -- (the PTR feedback line opens a colour and never closes it: "|c0042b1fePress F6 …" — |r optional, R37)
        local c0, inner0, r0 = t:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
        if not c0 then c0, inner0 = t:match("^(|c%x%x%x%x%x%x%x%x)(.+)$"); r0 = "" end
        local core = inner0 or t
        for _, r in ipairs(SPELL_LINES) do
            if core:find(r[1]) then
                local out = core:gsub(r[1], r[2])
                be = inner0 and (c0 .. out .. r0) or out
                break
            end
        end
        -- talents: "Spend 25 more points in Balance Talents" (the tree name through the UI dictionary)
        local pts, tree = core:match("^Spend (%d+) more points? in (.+) Talents$")
        local tree_be = tree and (W.ui_be(tree) or tree)
        if pts and tree_be ~= tree then
            local out = W.plural_forms(("Выдаткуйце яшчэ %s |4ачко:ачкі:ачкоў; на таленты «%s»"):format(pts, tree_be))
            be = inner0 and (c0 .. out .. r0) or out
        end
    end
    -- composite lines built from several strings, e.g. the settings option list
    -- "|cffffffffNone|r: |cffffd100Disable self casting.|r": translate each coloured piece
    -- all pieces or nothing (owner 2026-09-25: no half-translated lines)
    if not be and t:find("|c%x%x%x%x%x%x%x%x") then
        local ok_all = true
        local out = t:gsub("(|c%x%x%x%x%x%x%x%x)(.-)(|r)", function(c, inner, r)
            if not inner:find(W.LET) then return nil end
            -- a red tool / reagent name after «Патрабуецца:» (R375) is an item or spell focus, not a UI word
            local b = W.ui_be(inner) or (W.on("spells") and (W.IE[inner] or W.spell_name_be(inner))) or W.Z[inner]
            if b then return c .. b .. r end
            ok_all = false
        end)
        local rest = out:gsub("|c%x%x%x%x%x%x%x%x.-|r", "")      -- text outside the colours must be punctuation
        if ok_all and not rest:find(W.LET) and out ~= t then be = out end
    end
    if not be then
        local a, b = t:match("^([^:|]+): (.+)$")                 -- plain "Label: description"
        if a and W.ui_be(a) and W.ui_be(b) then be = W.ui_be(a) .. ": " .. W.ui_be(b) end
    end
    if not be and t:find("\n", 1, true) then be = multiline_be(t) end
    return be
end
W.tooltip_line_be = tooltip_line_be
-- unit tooltips: the class line ("Warrior" → «Ваяр») in its class colour (owner 2026-10-07; WoW fonts have no bold)
local function class_coloured(en, be)
    if W.RU then en = W.en_line(en) end                  -- «Друид» → "Druid" (R665)
    if not rawget(W.CLASSES, en) then return be end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[(en:gsub(" ", "")):upper()]
    return c and c.colorStr and ("|c" .. c.colorStr .. be .. "|r") or be
end
-- two-word Forever race names make the unit level line very wide («Узровень 3 Небароджаны Вышэйшага ордэна (Гулец)"):
-- the line breaks after the first word of the race (owner 2026-10-12, R432)
local LONG_RACES = {}
for en, pair in pairs(W.RACES) do
    if en:find(" ") then
        for _, be in ipairs(pair) do
            local a, b = be:match("^(%S+) (.+)$")
            if a then LONG_RACES[#LONG_RACES + 1] = { be, a .. "\n" .. b } end
        end
    end
end
local function split_long_race(be)
    if not be:find("^Узровень") then return be end
    for _, r in ipairs(LONG_RACES) do
        local s, e = be:find(r[1], 1, true)
        if s then return be:sub(1, s - 1) .. r[2] .. be:sub(e + 1) end
    end
    return be
end
if TooltipDataProcessor and TooltipDataProcessor.AllTypes then
    W.TIP.line(TooltipDataProcessor.AllTypes, function(tt, ld)
        if not (W.on("ui") and ld) then return end
        local keep = tt and W.TIP.keep[tt]                  -- a player's guild name (names.lua unit pre-call, R106)
        if keep and keep.at == GetTime() and plain(ld.leftText) == keep.text then return end
        W.current_tooltip_female = detect_tooltip_female(tt)
        local data = tt and tt.GetPrimaryTooltipData and tt:GetPrimaryTooltipData()
        local unit_tip = data and W.sid_ok(data.type) == 2
        -- a pet's name (line 1) is its owner's choice: "Bear" must not become «Мядзведзь» via the UI words (R214)
        local g = unit_tip and W.sid_ok(data.guid)
        -- R920: a PLAYER's name too (a player "Heal Undead" had become «Лечым: Наўе» via the UI format "Heal %s")
        if type(g) == "string" and (g:find("^Pet") or g:find("^Player")) and data.lines and data.lines[1] == ld then
            W.current_tooltip_female = false; return
        end
        for _, k in ipairs({ "leftText", "rightText" }) do
            local t = plain(ld[k])
            if t and t ~= "" then
                local be = tooltip_line_be(t)
                if be and be ~= t and unit_tip then be = split_long_race(be) end
                if be and be ~= t then ld[k] = unit_tip and class_coloured(t, be) or be end
            end
        end
        W.current_tooltip_female = false
    end)
end

-- tooltip lines: exact UI strings ("Soulbound", "Two-Hand"), micro-menu names with their keybind suffix,
-- and the "Sell Price:" prefix
local function tr_tooltip(tt)
    if not W.on("ui") or not tt or (tt.IsForbidden and tt:IsForbidden()) or W.dual_active(tt) then return end
    -- bilingual mode (R400): an action-bar tooltip stays SHOWN while you move between buttons (no OnShow) and is
    -- re-filled from the button's UpdateTooltip → this pass builds the card too, and never translates in place
    if W.dual_on() and (tt == GameTooltip or tt == _G.ItemRefTooltip) and W.dual_plain_build then
        if W.dual_plain_build(tt) then return true end
        if W.TIP.plain[tt] or W.TIP.dual[tt] then return end
    end
    local n = tt.GetName and tt:GetName()
    if not n then return end
    W.current_tooltip_female = detect_tooltip_female(tt)
    local changed = false
    -- talent (and other spell) tooltips built line by line, not from spell tooltip data: line 1 is the spell's EN
    -- name ("Moonfury") -> its BE name, and the description is tried against every rank's pattern of that name
    local data = tt.GetPrimaryTooltipData and tt:GetPrimaryTooltipData()
    local dtype = data and W.sid_ok(data.type)
    local dguid = data and W.sid_ok(data.guid)
    local guild2 = dtype == 2 and type(dguid) == "string" and dguid:find("^Player") ~= nil   -- line 2 = guild (R106)
    local l1 = _G[n .. "TextLeft1"]
    local t1 = l1 and plain(l1:GetText())
    local sp = t1 and (dtype == nil or dtype == 1) and W.on("spells") and (WoWBY_AuraByName or {})[t1]
    -- world objects hovered in the game world ("Strange Fruited Plant", R328): the tooltip comes as plain text or Object
    -- data the pre-call missed → line 1 swapped when it is a whole known name (never on unit tooltips: players)
    local unit = tt.GetUnit and select(2, tt:GetUnit())
    -- R968: a lootable object named like an item ("Small Black Pouch") takes the item's Belarusian name
    local objb = t1 and not sp and not unit and (dtype == nil or dtype == 4) and W.on("names")
        and (W.N[t1] or (W.on("spells") and W.IE[t1]))
    if objb then
        W.set_font(l1); l1:SetText(objb); changed = true
    elseif t1 and dtype == 4 and not unit and not W.N[t1] and not W.IE[t1] and not W.ours(t1) then
        W.harvest("objects", t1)                       -- R600: untranslated world object ("Leyline")
    end
    if sp then
        if sp[1] then l1:SetText(sp[1]); changed = true end
        for i = 2, tt:NumLines() do
            local fs = _G[n .. "TextLeft" .. i]
            local t = fs and plain(fs:GetText())
            for _, k in ipairs(t and sp[2] or {}) do
                local be = W.render_desc(k, t)
                if be then fs:SetText(be); changed = true; break end
            end
        end
    end
    for i = 1, tt:NumLines() do
        for _, side in ipairs({ "TextLeft", "TextRight" }) do
            local fs = _G[n .. side .. i]
            local t = fs and plain(fs:GetText())
            if t and t ~= "" and not (i == 2 and guild2 and not t:find("^" .. (LEVEL or "Level") .. " "))
                and not (i == 1 and guild2) then                -- R920: line 1 = the player's name, kept
                local be = tooltip_line_be(t)
                if be and be ~= t then fs:SetText(be); changed = true end
            end
        end
    end
    W.current_tooltip_female = false
    return changed
end
-- quest hover tooltips: quest log / tracker, world-map quest + quest-offer pins, minimap quest pins (R72/R73). Line 1 = the
-- title, often coloured by difficulty (SetQuestTitleLevelAndDifficultyColor) and/or with an icon or "[12] " level in
-- front; "- objective" lines after it. The title is swapped when it is exactly this quest's EN title (owner.questID) or
-- any known quest title; objectives via obj_line_be with that quest id.
local function title_parts(t)
    local pre, core = t:match("^(.*|[tTaA]%s*)(.-)$")
    if not core then pre, core = "", t end
    local col, inner, r = core:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
    if not inner then col, inner, r = core:match("^(|cn[^:]*:)(.-)(|r)$") end
    local key = inner or core
    local lv = key:match("^%[%d+[^%]]*%]%s*")
    if lv then key = key:sub(#lv + 1) end
    return pre, col, lv or "", key, r
end
-- an objective's own colour after the dash ("|cffffffff0/3 Small Egg", the closing |r optional — R531: without |r the
-- R524 match failed and the line turned yellow) → code, bare text, closing ("" when absent)
local function obj_colour(rest)
    local oc, inner = rest:match("^(|c%x%x%x%x%x%x%x%x)(.*)$")
    if not oc then oc, inner = rest:match("^(|cn[^:|]*:)(.*)$") end
    if not oc then return nil, rest, "" end
    local orr = inner:match("|r$") and "|r" or ""
    if orr ~= "" then inner = inner:sub(1, -3) end
    return oc, inner, orr
end
local function tr_quest_tooltip(tt, qid_hint)
    local owner = tt.GetOwner and tt:GetOwner()
    local n = tt.GetName and tt:GetName()
    if not (n and W.is_be() and W.on("quests")) then return false end
    local l1 = _G[n .. "TextLeft1"]
    local t = l1 and plain(l1:GetText())
    if not t or t == "" then return false end
    local qid = (owner and W.sid_ok(owner.questID)) or W.sid_ok(qid_hint)
    local pre, col, lv, key, r = title_parts(t)
    local be
    -- the owner's questID only counts when its title is this tooltip's: the world-map quest AREA blob (R146) keeps
    -- 0 or the quest it draws, not the one under the cursor → then the id from the quest log by the exact EN title.
    -- R612: the title may already be OURS — Blizzard's SetText(title) shows the tooltip (our OnShow pass swaps the
    -- title) before the objective lines are added, so the later pass saw a Belarusian title, dropped the id and left
    -- "- 7/10 Stolen Shen'dar Supplies" English
    if qid then
        local en = type(qid) == "number" and qid > 0 and (plain(C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qid)) or W.QT[tostring(qid)])
        if en ~= key and not (type(qid) == "number" and qid > 0 and W.be_title(qid) == key) then qid = nil end
    end
    if not qid and #key > 3 and not key:find("\n") and C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID and plain(info.title) == key then qid = info.questID break end
        end
    end
    if qid then
        local en = plain(C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qid)) or W.QT[tostring(qid)]
        if en == key then be = W.be_title(qid) end
    end
    if not be and #key > 3 and not key:find("\n") then
        be = W.qtitle_be and W.qtitle_be(key)
    end
    local changed = false
    if be and be ~= key then
        W.set_font(l1); l1:SetText(pre .. (col and (col .. lv .. be .. (r or "")) or (lv .. be))); changed = true
        if not qid then                                          -- objectives need the id: from the log by title
            for i = 1, C_QuestLog.GetNumQuestLogEntries() do
                local info = C_QuestLog.GetInfo(i)
                if info and not info.isHeader and plain(info.title) == key then qid = info.questID break end
            end
        end
    end
    if not (be or qid) then return false end
    for i = 2, tt:NumLines() do
        local fs = _G[n .. "TextLeft" .. i]
        local lt = fs and plain(fs:GetText())
        local rest = lt and lt:match("^%- (.+)$")
        local oc, oinner, orr
        if rest then oc, oinner, orr = obj_colour(rest) end
        local b = rest and qid and W.obj_line_be(oinner or rest, qid)
        if b then fs:SetText("- " .. (oc and (oc .. b .. orr) or b)); changed = true end     -- colour kept (R524)
        -- R942 (owner screenshot): a quest with no objective rows shows its objectives SENTENCE without the dash
        -- ("Speak with Cairne Bloodhoof in Thunder Bluff.") → the quest's BE "o"
        if not rest and lt and lt ~= "" and qid and not W.ours(lt) and not lt:find("^<") then
            local b2 = W.obj_line_be(lt, qid)
            if b2 then W.set_font(fs); fs:SetText(b2); changed = true end
        end
    end
    return changed
end
local tt_busy = false
-- minimap blips (hover): the engine writes NPC names / quest titles into GameTooltip, several blips as
-- "Name\nName2", sometimes after a |T..|t icon. Each line is a whole name or title -> N / quest log EN title.
local function log_titles()
    local m, ids = {}, {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return m, ids end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        local en = info and not info.isHeader and info.questID and plain(info.title)
        if en then m[en] = W.be_title(info.questID); ids[en] = info.questID end
    end
    return m, ids
end
-- quest lines in unit / object tooltips: "The Enchanted Glade" (line type QuestTitle = 17) and its objectives
-- ("0/6 Bloodfeather Belt", QuestObjective = 8) — edited in the tooltip DATA before drawing, like the other lines
if TooltipDataProcessor and TooltipDataProcessor.AllTypes then
    W.TIP.pre(TooltipDataProcessor.AllTypes, function(tt, data)
        if not (W.is_be() and W.on("quests") and data and data.lines) then return end
        local titles, ids, qid
        for _, l in ipairs(data.lines) do
            if l.type == 17 or l.type == 8 then
                local t = plain(l.leftText)
                if t then
                    if l.type == 17 then
                        if not titles then titles, ids = log_titles() end
                        qid = ids[t]
                        if titles[t] then l.leftText = titles[t] end
                    else
                        local pre, core = t:match("^(%s*%-?%s*)(.+)$")
                        local be = core and W.obj_line_be(core, qid)
                        if be then l.leftText = pre .. be end
                    end
                end
            end
        end
    end)
end
-- quest LINKS clicked in chat (R313: ItemRefTooltip, tooltip data type Quest = 23, data.id = quest id): title, the
-- objective sentence (first long line that is not a "- …" row or a "Label:") = the quest's BE "o", then the
-- "- 1 x Ursal the Mauler" rows
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    W.TIP.pre(Enum.TooltipDataType.Quest or 23, function(tt, data)
        if not (W.is_be() and W.on("quests") and data and data.lines) then return end
        local qid = W.sid_ok(data.id)
        local e = type(qid) == "number" and W.entry_for(qid)
        if not e then return end
        local o_done = false
        for i, l in ipairs(data.lines) do
            local t = plain(l.leftText)
            if t and t ~= "" then
                local ui = i > 1 and not o_done and W.ui_be(t)
                if i == 1 then
                    if e.t then l.leftText = W.substitute(e.t, qid) end
                elseif ui then
                    -- status line "You are on this quest" (R370: 21 chars — it was taken for the objective sentence)
                    l.leftText = ui
                elseif not o_done and e.o and #t > 20 and not t:find(":%s*$") and not t:find("^%s*%-") then
                    local be = W.substitute(e.o, qid)
                    if be and be ~= "" then l.leftText = be end
                    o_done = true
                else
                    local pre, rest = t:match("^(%s*%-%s*)(.+)$")
                    local b = rest and W.obj_line_be(rest, qid)
                    if b then l.leftText = pre .. b end
                end
            end
        end
    end)
end
local qt_rev
W.qtitle_be = function(en)         -- quest log first (live EN titles), then the WoWBY guard titles
    local m = log_titles()
    if m[en] then return m[en] end
    local cur = W.orig_title_text and GetQuestID and plain(W.orig_title_text())     -- the quest window just accepted
    if cur and cur == en then return W.be_title(GetQuestID()) end
    local fv = WoWBY_QTitleFV and WoWBY_QTitleFV[en]             -- Forever-new quests (not in the log)
    if fv then return W.be_title(fv) end
    if not qt_rev then                                           -- WoWBY guard titles, reverse index built once (R567:
        qt_rev = {}                                              -- now asked for every tooltip line)
        for id, t in pairs(W.QT) do
            if type(t) == "string" and not qt_rev[t] then qt_rev[t] = tonumber(id) end
        end
    end
    local id = qt_rev[en]
    if id then return W.be_title(id) end
    -- ruRU client (R665): a Russian title not in the log → its EN title(s) (WoWBY_RU.quests) → the same lookups
    local ens = W.RU and WoWBY_RU and WoWBY_RU.quests and WoWBY_RU.quests[en]
    for _, e in ipairs(type(ens) == "table" and ens or { ens }) do
        local q = (WoWBY_QTitleFV and rawget(WoWBY_QTitleFV, e)) or qt_rev[e]
        if q then return W.be_title(q) end
    end
end
local function tr_minimap_tooltip(tt)
    local owner = tt.GetOwner and tt:GetOwner()
    local on_mm = false                                   -- the minimap or anything inside it (pins, the cluster)
    local o, depth = owner, 0
    while o and depth < 6 and not on_mm do
        local nm = o.GetName and o:GetName() or ""
        on_mm = o == _G.Minimap or o == _G.MinimapCluster or nm:find("^Minimap") ~= nil
        o = o.GetParent and o:GetParent(); depth = depth + 1
    end
    -- R148: pins whose owner addons cannot see (GetOwner() = nil: Questie / HereBeDragons minimap pins, map blobs) get
    -- the same whole-line swap — only exact NPC names and quest titles change, so it is safe for any tooltip
    if owner == nil then on_mm = true end
    -- minimap blips on this client: tooltip data type MinimapMouseover (21), owner = UIParent, the names / titles as
    -- ONE line separated by \n (/wowby tt, 2026-09-30)
    if not on_mm then
        local d = tt.GetPrimaryTooltipData and tt:GetPrimaryTooltipData()
        local mmt = Enum and Enum.TooltipDataType and Enum.TooltipDataType.MinimapMouseover or 21
        if d and d.type == mmt then on_mm = true end
    end
    if not on_mm or not W.is_be() then return false end
    local n, titles, changed = tt.GetName and tt:GetName(), nil, false
    local tids, cur_qid
    if not n then return false end
    for i = 1, tt:NumLines() do
        local fs = _G[n .. "TextLeft" .. i]
        local t = fs and plain(fs:GetText())
        if t and t ~= "" then
            local out = t:gsub("[^\n]+", function(seg)
                -- icons in front: |T…|t textures or |A…|a atlases (the quest arrow "▲ Heeding the Call")
                local pre, core = seg:match("^(.*|[tTaA]%s*)(.-)$")
                if not core then pre, core = "", seg end
                -- one colour can wrap SEVERAL lines ("|cff…Crown of the Earth\nEyes of the Sentinels|r", R89):
                -- the opening code and the closing |r are stripped separately
                -- R534: the minimap opens the objectives' white at the END of the title line ("Title|cffffffff\n- 0/3
                -- Small Egg\n- 2/8 Strider Meat|r") → a trailing code is cut off and put back after the translation
                local tailc = core:match("|c%x%x%x%x%x%x%x%x$") or core:match("|cn[^:|]*:$")
                if tailc then core = core:sub(1, -#tailc - 1) end
                local col = core:match("^|c%x%x%x%x%x%x%x%x") or core:match("^|cn[^:]*:")
                local inner = col and core:sub(#col + 1) or core
                local r = inner:match("|r$")
                if r then inner = inner:sub(1, -3) end
                if not (col or r) then inner = nil end
                local key = inner or core
                -- R297: objective lines under a quest title ("- 0/1 Raven Claw Talisman"), id from the title above
                local rest = key:match("^%-%s*(.+)$")
                if rest then
                    -- the objective may carry its own colour after the dash ("- |cffffffff0/3 Small Egg|r", white
                    -- under a yellow title): kept around the translation (R524: BE lines turned all yellow)
                    local oc, oinner, orr = obj_colour(rest)
                    local b = W.on("quests") and W.obj_line_be(oinner, cur_qid)
                    if b and oc then b = oc .. b .. orr end
                    return b and (pre .. (col or "") .. "- " .. b .. (r or "") .. (tailc or "")) or nil
                end
                local be = W.on("names") and W.N[key]
                if not be and W.on("quests") then
                    if not titles then titles, tids = log_titles() end
                    -- R299: objective-marker titles kept English ("The Relics of Wakening" over a swapped objective) →
                    -- also try the bare text: every colour code / |r and outer spaces removed
                    local bare = key:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
                    be = titles[key] or titles[bare] or (W.qtitle_be and (W.qtitle_be(key) or W.qtitle_be(bare)))
                    if be then cur_qid = tids[key] or tids[bare] end
                end
                -- R625: town-tracking blips name the SERVICE ("Skinning Trainer", "Innkeeper", "Flight Master") = NPC
                -- titles → the title table, then whole UI labels ("Mailbox")
                if not be and W.on("names") then be = (WoWBY_Titles or {})[key] end
                if not be and W.on("ui") then be = W.ui_be(key) end
                -- R646: unknown minimap places ("Valanaar Inn") were never collected → harvested as objects; only
                -- several-word plain text (player names have no spaces; colour codes / links are skipped)
                if not be and key:find(" ") and not key:find("|", 1, true) and not W.ours(key) and #key < 60 then
                    W.harvest("objects", key)
                end
                if not be then return nil end
                return pre .. (col or "") .. be .. (r or "") .. (tailc or "")
            end)
            if out ~= t then
                W.set_font(fs); fs:SetText(out); changed = true
            end
        end
    end
    return changed
end
W.tr_minimap_tooltip = tr_minimap_tooltip        -- for tools/addon_probe.py tests (R970)
-- aura tooltips whose data is SECRET (target / party buff buttons, R47): the data is never touched (writing into it
-- tainted Blizzard, 2026-09-28). Out of combat, one frame after it is shown, only the drawn FontStrings are swapped
-- — name by EN (WoWBY_AuraByName), description by the name's desc keys, "Magic" / "22 minutes remaining" as usual.
-- Secret texts stay (plain() gives nil).
local function tr_secret_aura(tt)
    if InCombatLockdown() or not (tt and tt.GetName and tt:GetName()) or not (W.is_be() and W.on("spells")) then return end
    local n, changed = tt:GetName(), false
    local l1 = _G[n .. "TextLeft1"]
    local en = l1 and plain(l1:GetText())
    local e = en and (WoWBY_AuraByName or {})[en]
    -- R954 (owner: target buffs / debuffs stay English): the target frame's aura buttons may hide their owner from
    -- addons → a secret tooltip whose line 1 is a known aura name counts as an aura card too
    local owner = tt.GetOwner and tt:GetOwner()
    if not (e or (owner and (owner.auraInstanceID or owner.buttonInfo or (owner.GetName and (owner:GetName() or ""):find("Aura"))))) then
        return
    end
    -- and the name: many auras have no BE name in the aura table, only in the by-EN spell names («Бонусы лагера»)
    local nm = e and (e[1] or (W.spell_name_be and W.spell_name_be(en)))
    if nm and nm ~= en then W.set_font(l1); l1:SetText(nm); changed = true end
    for i = 2, tt:NumLines() do
        for _, side in ipairs({ "Left", "Right" }) do
            local fs = _G[n .. "Text" .. side .. i]
            local t = fs and fs:IsShown() and plain(fs:GetText())
            if t and t ~= "" then
                local be
                for _, k in ipairs(e and e[2] or {}) do
                    be = W.render_desc(k, t)
                    if be then break end
                end
                be = be or tooltip_line_be(t)
                if be and be ~= t then W.set_font(fs); fs:SetText(be); changed = true end
            end
        end
    end
    if changed and tt.Show then tt:Show() end
end
-- player corpse (R153): "Corpse of Basili" — the capture is a player's name, unknown by design → accepted as a
-- name for this one line (W.any_name, like "%s's Pet")
local function tr_corpse(tt)
    local fs = tt == GameTooltip and _G.GameTooltipTextLeft1
    local t = fs and W.is_be() and W.on("ui") and plain(fs:GetText())
    if t and W.RU then t = W.en_line(t) end              -- «Труп X» → "Corpse of X" (R665)
    if not (t and t:find("^Corpse of ")) then return false end
    W.any_name = true
    local ok, be = pcall(W.ui_be, t)
    W.any_name = false
    if ok and be and be ~= t then fs:SetText(be); return true end
    return false
end
-- bilingual card for tooltips built line by line, with no tooltip data (R385: talents, Legacy talents): the drawn
-- English lines are read, each translated like the normal pass would, and the changed ones appended under the separator
local function dual_plain(tt)
    if not (W.dual_on() and (tt == GameTooltip or tt == _G.ItemRefTooltip)) or W.TIP.secret[tt] then return false end
    if W.TIP.dual[tt] then return false end                                -- a card is already there
    -- only tooltips with game data of their own (spells, talents, auras: R393 "plain" mode); plain UI tooltips (game
    -- menu performance, buttons) are not bilingual (owner R416) — they are translated in place as usual
    if not W.TIP.plain[tt] then return false end
    local name = tt:GetName()
    local out, any = {}, false
    -- a buff / debuff (R415): its description by the aura's own desc keys (WoWBY_AuraByName), like tr_secret_aura
    local l1 = _G[name .. "TextLeft1"]
    local aura = (WoWBY_AuraByName or {})[plain(l1 and l1:GetText()) or ""]
    for i = 1, tt:NumLines() do
        local l, r = _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i]
        local lt = l and plain(l:GetText())
        local rt = r and r:IsShown() and plain(r:GetText()) or nil
        -- a line another hook already turned Belarusian (tab tooltip «Заблакавана») is not repeated (R393)
        if lt and lt ~= "" and lt ~= " " and not W.ours(lt) then
            local lb
            if i == 1 then lb = (W.on("spells") and W.spell_name_be(lt)) or W.ui_be(lt)
            else
                for _, k in ipairs(aura and aura[2] or {}) do
                    lb = W.render_desc(k, lt)
                    if lb then break end
                end
                lb = lb or tooltip_line_be(lt)
            end
            local rb = rt and rt ~= "" and tooltip_line_be(rt) or nil
            if (lb and lb ~= lt) or (rb and rb ~= rt) then
                any = true
                local lr, lg, lb2 = l:GetTextColor()
                local rr, rg, rb2 = 1, 1, 1
                if r then rr, rg, rb2 = r:GetTextColor() end
                out[#out + 1] = { lb or lt, rt and (rb or rt) or nil, lr, lg, lb2, rr, rg, rb2 }
            end
        end
    end
    if not any then return false end
    W.TIP.dual[tt] = { lines = {} }
    W.dual_divider(tt)
    for _, o in ipairs(out) do
        if o[2] then tt:AddDoubleLine(o[1], o[2], o[3], o[4], o[5], o[6], o[7], o[8])
        else tt:AddLine(o[1], o[3], o[4], o[5], true) end
    end
    tt:Show()
    return true
end
W.dual_plain_build = dual_plain                    -- also from tr_tooltip (R400: no OnShow between action buttons)
-- R608: the "secret data" mark is cleared only on OnHide; a tooltip re-filled while shown with plain SetText (map quest
-- pins: no tooltip data at all) kept a stale mark from the previous unit / aura tooltip → skipped until a later refresh
-- (~1 s English). No data now → no secret.
local function clear_stale_secret(tt)
    if tt and W.TIP.secret[tt] and tt.GetPrimaryTooltipData then
        local ok, d = pcall(tt.GetPrimaryTooltipData, tt)
        if ok and d == nil then W.TIP.secret[tt] = nil end
    end
end
local function tt_post(tt)
    clear_stale_secret(tt)
    if dual_plain(tt) then return end
    if tt and W.dual_active(tt) then return end               -- bilingual card (R381): the English half stays English
    if tt and W.TIP.secret[tt] and not tt_busy then
        -- bilingual (R415): the English stays; the aura hint box under it shows the Belarusian (W.aura_hint ticker)
        if W.dual_on() then return end
        C_Timer.After(0, function() if tt:IsShown() then pcall(tr_secret_aura, tt) end end)
        return
    end
    if tt_busy or (tt and W.TIP.secret[tt]) then return end
    tt_busy = true
    -- R970 (owner 2026-11-13: minimap quest blips English again): one failing step left tt_busy = true for good and
    -- every later tooltip was skipped → each step runs protected, its error is logged once (WoWBY_DB.errors)
    local function step(fn, name)
        local ok, r = pcall(fn, tt)
        if not ok then
            W.tt_err = W.tt_err or {}
            if not W.tt_err[name] and W.log_error then W.log_error("tooltip " .. name .. ": " .. tostring(r)) end
            W.tt_err[name] = true
            return false
        end
        return r
    end
    local q = step(tr_quest_tooltip, "quest")
    local mm = step(tr_minimap_tooltip, "minimap")
    local cp = step(tr_corpse, "corpse")
    local tr = step(tr_tooltip, "main")
    tt_busy = false
    if (tr or q or mm or cp) and tt.Show then tt:Show() end
end
if GameTooltip then
    if TooltipDataProcessor and TooltipDataProcessor.AllTypes then
        W.TIP.post(TooltipDataProcessor.AllTypes, tt_post)
    end
end
-- plain-text tooltips (no tooltip data): GameTooltip + separate tooltip frames, e.g. SettingsTooltip (options
-- panel, built with AddLine) — hooked as they appear (some come with load-on-demand addons)
local TOOLTIPS = { "GameTooltip", "SettingsTooltip", "ItemRefTooltip", "EmbeddedItemTooltip",
                   "ShoppingTooltip1", "ShoppingTooltip2",        -- + item comparison (R114)
                   -- R988: barbershop / customization buttons ("Reset Camera", "Body 1", "Tauren Form"; load-on-demand)
                   "CustomizationNoHeaderTooltip" }
local tt_hooked = {}
-- item comparison (R117): the delta block ("If you replace this item…", "+4 Agility") is re-added on every comparison
-- refresh; translating on show left it English for a frame each time → blink. Swap right after SetItemTooltip.
local cmp_hooked = false
local function hook_comparison()
    if cmp_hooked or not (TooltipComparisonManager and TooltipComparisonManager.SetItemTooltip) then return end
    cmp_hooked = true
    -- the delta block ("If you replace this item…", "+2.8 damage per second") is AddLine'd after the item data and the
    -- compare tooltips are rebuilt while you hover: BE showed for a moment, then English (2026-10-07). Pass now AND next
    -- frame (the rebuild can run before the tooltip is shown); errors kept in WoWBY_DB.errors instead of vanishing.
    -- R657: an equipped CRAFTED item's data holds a secret value (the crafter's name) → the whole comparison tooltip was
    -- marked secret and the delta block stayed English. Its drawn lines are still swapped out of combat (texts that are
    -- themselves secret stay English via plain) — the R47 way for secret aura tooltips; never the data.
    local function hands_off(tt) return W.TIP.secret[tt] and InCombatLockdown() end
    local function pass()
        if not W.is_be() then return end
        for _, n in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2" }) do
            local tt = _G[n]
            if tt and tt:IsShown() and not hands_off(tt) then
                local ok, err = pcall(tr_tooltip, tt)
                if not ok and WoWBY_DB then
                    WoWBY_DB.errors = WoWBY_DB.errors or {}
                    WoWBY_DB.errors["compare"] = tostring(err)
                end
            end
        end
    end
    hooksecurefunc(TooltipComparisonManager, "SetItemTooltip", function()
        pass()
        C_Timer.After(0, pass)
    end)
    -- R207: still blinked and ran out of the box — swap each comparison line the moment Blizzard adds it (global helper
    -- functions, post-hook = no taint), so every later measure and Show() sees the Belarusian text
    local SHOP = {}
    for _, n in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2" }) do if _G[n] then SHOP[_G[n]] = n end end
    local function last_line(tt)
        local n = SHOP[tt]
        if not (n and W.is_be() and W.on("ui")) or hands_off(tt) then return end
        local fs = _G[n .. "TextLeft" .. tt:NumLines()]
        local t = fs and plain(fs:GetText())
        local be = t and t ~= "" and tooltip_line_be(t)
        -- R347: no Show() here any more — re-measuring after EVERY delta line resized the box mid-build, and Blizzard
        -- re-anchors both comparison tooltips against those sizes → the comparison jumped on each 0.2 s rebuild. One
        -- re-measure after the whole build (GameTooltip_ShowCompareItem post-hook below, as WowUkrainizer does).
        if be and be ~= t then fs:SetText(be) end
    end
    -- errors of the comparison passes are kept in WoWBY_DB.errors (R657: they used to vanish in pcall)
    local function cmp_err(key, ok, err)
        if ok or not WoWBY_DB then return end
        WoWBY_DB.errors = WoWBY_DB.errors or {}
        WoWBY_DB.errors[key] = tostring(err)
    end
    for _, fn in ipairs({ "GameTooltip_AddNormalLine", "GameTooltip_AddHighlightLine", "GameTooltip_AddDisabledLine" }) do
        if _G[fn] then hooksecurefunc(fn, function(tt) cmp_err("cmp_line", pcall(last_line, tt)) end) end
    end
    -- per-frame safety net (owner idea, R347): a comparison tooltip's own OnUpdate runs before the frame is drawn → any
    -- line still English there (added by a path we do not hook) is swapped before it is ever seen; width only re-measured
    -- when a BE line is WIDER than the box (never shrink → no jumping). Cheap: a signature of the line texts.
    local sig_seen = {}
    local function frame_check(tt)
        if not (W.is_be() and W.on("ui")) or hands_off(tt) then return end
        local n, k = SHOP[tt], tt:NumLines()
        local last = _G[n .. "TextLeft" .. k]
        local sig = k .. "|" .. tostring(last and plain(last:GetText()))
        if sig == sig_seen[tt] then return end
        local grew = false
        for i = 2, k do
            local fs = _G[n .. "TextLeft" .. i]
            local t = fs and fs:IsShown() and plain(fs:GetText())
            local be = t and t ~= "" and t:find(W.LET) and tooltip_line_be(t)
            if be and be ~= t then
                fs:SetText(be)
                if fs:GetStringWidth() + 20 > tt:GetWidth() then grew = true end
            end
        end
        last = _G[n .. "TextLeft" .. tt:NumLines()]
        sig_seen[tt] = tt:NumLines() .. "|" .. tostring(last and plain(last:GetText()))
        -- R657: no Show() here — Show() re-draws the tooltip's stored ENGLISH lines (diagnosed in game: the swapped
        -- text read back English right after Show), so a Show after our swap undid it every frame. Width: remeasure.
        if W.cmp_debug and WoWBY_DB then                  -- /wowby cmpdebug: what changes between frames
            WoWBY_DB.cmp_log = WoWBY_DB.cmp_log or {}
            local log = WoWBY_DB.cmp_log
            if #log < 300 then
                local p1, rel, p2, x, y = tt:GetPoint(1)
                log[#log + 1] = string.format("%.2f %s lines=%d w=%d grew=%s pt=%s/%s %d,%d", GetTime(), n, k,
                    tt:GetWidth(), tostring(grew), tostring(p1), tostring(p2), x or 0, y or 0)
            end
        end
    end
    for tt in pairs(SHOP) do tt:HookScript("OnUpdate", function(self) cmp_err("cmp_frame", pcall(frame_check, self)) end) end
    -- R657: Show() re-draws the stored English lines → order: swap, measure the Belarusian widths, give the box that
    -- minimum width, Show() (sizes it; may put English back), swap again WITHOUT a Show. Wrapped lines (the long
    -- "If you replace this item…" header) do not count for the width. The minimum is cleared on hide.
    local function swap_list(tt)
        local n, out = SHOP[tt], {}
        for i = 2, tt:NumLines() do
            local fs = _G[n .. "TextLeft" .. i]
            local t = fs and fs:IsShown() and plain(fs:GetText())
            local be = t and t ~= "" and t:find(W.LET) and tooltip_line_be(t)
            if be and be ~= t then out[#out + 1] = { fs, be, fs:GetNumLines() > 1 } end
        end
        return out
    end
    local function remeasure()
        if not (W.is_be() and W.on("ui")) then return end
        for tt in pairs(SHOP) do
            if tt:IsShown() and not hands_off(tt) then
                local list = swap_list(tt)
                local need = 0
                for _, x in ipairs(list) do
                    x[1]:SetText(x[2])
                    if not x[3] then need = math.max(need, x[1]:GetStringWidth()) end
                end
                if need > 0 and tt.SetMinimumWidth then tt:SetMinimumWidth(math.ceil(need) + 20) end
                tt:Show()
                for _, x in ipairs(list) do
                    if plain(x[1]:GetText()) ~= x[2] then x[1]:SetText(x[2]) end
                end
            end
        end
    end
    for tt in pairs(SHOP) do
        tt:HookScript("OnHide", function(self) if self.SetMinimumWidth then self:SetMinimumWidth(0) end end)
    end
    if _G.GameTooltip_ShowCompareItem then
        hooksecurefunc("GameTooltip_ShowCompareItem", remeasure)
    elseif TooltipComparisonManager.RefreshItems then
        hooksecurefunc(TooltipComparisonManager, "RefreshItems", remeasure)
    end
end
-- talent / Legacy-tree tooltips (R273): the title is set by GameTooltip_SetTitle(tooltip, name) from the talent
-- button, not from spell tooltip data → a known spell name is swapped the moment it is set (global helper, post-hook)
local title_hooked = false
local function hook_titles()
    if title_hooked or not _G.GameTooltip_SetTitle then return end
    title_hooked = true
    hooksecurefunc("GameTooltip_SetTitle", function(tt, text)
        if not (W.is_be() and W.on("spells") and tt and tt.GetName) or W.TIP.secret[tt] then return end
        if W.dual_on() and tt == GameTooltip then return end      -- bilingual: the English card stays (R385)
        local name = tt:GetName()
        local fs = name and _G[name .. "TextLeft1"]
        local t = fs and plain(fs:GetText())
        local be = t and t ~= "" and (W.spell_name_be(t) or W.ui_be(t))
        if be and be ~= t then fs:SetText(be); if tt:IsShown() then tt:Show() end end
    end)
end
-- world-map quest AREA (blue blob, R146): its tooltip is rebuilt on every mouse move and GetOwner() is nil for
-- addons, so neither OnShow nor the owner-based OnUpdate pass sees it → post-hook the filler itself (same frame).
-- The pins get the mixin's functions when created (first map open, after this hook at login).
-- The blob pin is created when Blizzard_WorldMap loads (before WoWBY), so it already holds the mixin's original
-- UpdateTooltip (called from its OnUpdate EVERY frame) → hook the pin instances too, tracked in our own table.
local blob_hooked, blob_pins = false, {}
local function blob_post()
    local tt = GameTooltip
    if not (W.is_be() and tt:IsShown()) or W.TIP.secret[tt] then return end
    local ok, changed = pcall(tr_quest_tooltip, tt)
    if ok and changed then tt:Show() end                  -- re-measure: the box kept the English width
end
local function hook_blob_pins()
    local wm = _G.WorldMapFrame
    if not (wm and wm.EnumeratePinsByTemplate) then return end
    local guard = 0
    for pin in wm:EnumeratePinsByTemplate("QuestBlobPinTemplate") do
        guard = guard + 1
        if guard > 20 or type(pin) ~= "table" then break end         -- one blob pin in practice
        if not blob_pins[pin] and pin.UpdateTooltip then
            blob_pins[pin] = true
            hooksecurefunc(pin, "UpdateTooltip", blob_post)
        end
    end
end
-- map quest pins + quest-log rows (R566, owner: "every time I click a quest on the map its text blinks"): Blizzard
-- refills the tooltip on click while it stays shown (no OnShow), and our OnUpdate pass swapped it a frame later →
-- English flash. Both fillers fire an EventRegistry event right after their GameTooltip:Show → swap there (same frame).
local function pin_post(_, _, questID)                   -- both events pass (owner frame, questID)
    local tt = GameTooltip
    clear_stale_secret(tt)
    if not (W.is_be() and tt:IsShown()) or W.TIP.secret[tt] or W.dual_active(tt) then return end
    local ok1, q = pcall(tr_quest_tooltip, tt, questID)
    local ok2, o = pcall(tr_tooltip, tt)
    if (ok1 and q) or (ok2 and o) then tt:Show() end
end
if EventRegistry and EventRegistry.RegisterCallback then
    local owner = {}
    EventRegistry:RegisterCallback("MapCanvas.QuestPin.OnEnter", pin_post, owner)
    EventRegistry:RegisterCallback("QuestMapLogTitleButton.OnEnter", pin_post, owner)
end
local function hook_blob()
    if not blob_hooked and QuestBlobPinMixin and QuestBlobPinMixin.UpdateTooltip then
        blob_hooked = true
        hooksecurefunc(QuestBlobPinMixin, "UpdateTooltip", blob_post)
        local wm = _G.WorldMapFrame
        if wm and wm.HookScript then
            wm:HookScript("OnShow", function() C_Timer.After(0, hook_blob_pins) end)
        end
    end
    hook_blob_pins()
end
function W.hook_tooltips()
    if WoWBY_DB then WoWBY_DB.cmp_probe, WoWBY_DB.cmp_hooked = nil, nil end         -- R657 diagnosis leftovers
    hook_comparison()
    hook_titles()
    hook_blob()
    for _, n in ipairs(TOOLTIPS) do
        local tt = not tt_hooked[n] and _G[n]
        if tt and tt.HookScript then
            tt_hooked[n] = true
            -- lines added right after the first Show ("World Map (Tab)" under the zone name) are caught by a second
            -- pass next frame. No hook on GameTooltip:Show itself: a hooked method key on GameTooltip would taint
            -- every secure caller (unit frames in combat, secret values).
            -- the "secret data" mark belongs to ONE tooltip showing: plain SetText tooltips (bag slots "Assigned to:",
            -- R49) never pass the data pre-call, so a stale mark from the previous aura/cooldown tooltip skipped them
            tt:HookScript("OnHide", function(self)
                W.TIP.secret[self] = nil; W.TIP.dual[self] = nil; W.TIP.plain[self] = nil; W.dual_hide(self)
            end)
            -- comparison tab "Equipped" (R114): swapped right after SetText, so Blizzard's following
            -- SetWidth(Label:GetWidth()) already measures the Belarusian word
            local lab = tt.CompareHeader and tt.CompareHeader.Label
            if lab then
                hooksecurefunc(lab, "SetText", function(fs)
                    local t = W.is_be() and W.on("ui") and plain(fs:GetText())
                    local be = t and W.ui_be(t)
                    if be and be ~= t then fs:SetText(be) end
                end)
            end
            tt:HookScript("OnShow", function(self)
                tt_post(self)
                C_Timer.After(0, function() if self:IsShown() then tt_post(self) end end)
            end)
            -- minimap blips: the ENGINE rewrites the tooltip text while it stays shown (moving between dots), so no
            -- OnShow fires -> while the minimap owns it, re-translate whenever the first line changed (cheap check)
            if n == "GameTooltip" then
                local last
                local sig_done
                local aura_sig                               -- R621: drawn text after our last secret-aura swap
                tt:HookScript("OnUpdate", function(self)
                    -- owners with UpdateTooltip (bag slots "Assigned to: …", R54) rebuild the tooltip in English a few
                    -- times a second from GameTooltip's own OnUpdate, which runs just before this hook: re-translate
                    -- when the text changed since our last pass (same frame → no English flash)
                    local o = self:GetOwner()
                    if W.dual_active(self) then return end
                    clear_stale_secret(self)                 -- R608 (only does work while the mark is set)
                    -- R621: a buff whose tooltip data stayed SECRET after combat is re-filled in English every second
                    -- ("10 minutes remaining") — tr_secret_aura ran only once at OnShow → re-run it (drawn text only,
                    -- out of combat, same rules) whenever the drawn text changed since our last swap
                    -- R954: target-frame buff buttons hide that they are auras → also when line 1 is a known aura name
                    local a1 = W.TIP.secret[self] and plain(_G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText())
                    if W.TIP.secret[self] and not InCombatLockdown() and (a1 and (WoWBY_AuraByName or {})[a1]
                       or o and (o.auraInstanceID or o.buttonInfo or (o.GetName and (o:GetName() or ""):find("Aura")))) then
                        local l1, ln = _G.GameTooltipTextLeft1, _G["GameTooltipTextLeft" .. self:NumLines()]
                        local s = tostring(l1 and plain(l1:GetText())) .. "|" .. tostring(ln and plain(ln:GetText()))
                        if s ~= aura_sig then
                            pcall(tr_secret_aura, self)
                            l1, ln = _G.GameTooltipTextLeft1, _G["GameTooltipTextLeft" .. self:NumLines()]
                            aura_sig = tostring(l1 and plain(l1:GetText())) .. "|" .. tostring(ln and plain(ln:GetText()))
                        end
                        return
                    end
                    -- R580: default-anchored tooltips (owner = UIParent: the XP bar "Normal / 100% of normal experience",
                    -- filled from the bar's OnEnter while the tooltip may already be shown) — the bar is an Edit Mode
                    -- system frame, so it gets no hook of ours; the text signature check catches the refill instead
                    if o and o ~= _G.Minimap and (o.UpdateTooltip or W.sid_ok(o.questID) or o == UIParent) and W.is_be() and not W.TIP.secret[self] then
                        local n = self:NumLines()
                        local fl = _G.GameTooltipTextLeft1
                        local fs = n > 1 and _G["GameTooltipTextLeft" .. n]
                        local sig = n .. "|" .. tostring(fl and plain(fl:GetText())) .. "|" .. tostring(fs and plain(fs:GetText()))
                        if sig ~= sig_done then
                            local q = tr_quest_tooltip(self)                -- map quest pins re-fill too (R75)
                            -- R329: no re-measure while the item comparison is open: the item tooltip rebuilds every
                            -- few frames, and each Show() here resized it → Blizzard re-anchored both comparison
                            -- tooltips against it → the whole comparison blinked
                            local cmp = _G.ShoppingTooltip1 and ShoppingTooltip1:IsShown()
                            if (tr_tooltip(self) or q) and not cmp then self:Show() end
                            fs = n > 1 and _G["GameTooltipTextLeft" .. self:NumLines()]
                            sig_done = self:NumLines() .. "|" .. tostring(fl and plain(fl:GetText())) .. "|" .. tostring(fs and plain(fs:GetText()))
                        end
                    elseif W.is_be() and not W.TIP.secret[self] and self:NumLines() > 1 then
                        -- R297: quest objective markers (minimap / map split-objective pins: "The Relics of Wakening" +
                        -- "- 0/1 Raven Claw Talisman") are rewritten while the tooltip stays shown, by owners we cannot
                        -- see → whenever line 2 is a "- objective" line and the text changed, the quest pass runs
                        local l2 = plain(_G.GameTooltipTextLeft2 and _G.GameTooltipTextLeft2:GetText())
                        if l2 and l2:find("^%- ") then
                            local fl = _G.GameTooltipTextLeft1
                            local sig = self:NumLines() .. "|" .. tostring(fl and plain(fl:GetText())) .. "|" .. l2
                            if sig ~= sig_done then
                                if tr_quest_tooltip(self) then self:Show() end
                                sig_done = self:NumLines() .. "|" .. tostring(fl and plain(fl:GetText())) .. "|"
                                    .. tostring(plain(_G.GameTooltipTextLeft2:GetText()))
                            end
                        end
                    end
                    local d = self.GetPrimaryTooltipData and self:GetPrimaryTooltipData()
                    local mm = self:GetOwner() == _G.Minimap or (d and d.type == ((Enum and Enum.TooltipDataType
                        and Enum.TooltipDataType.MinimapMouseover) or 21))
                    if not mm or not W.is_be() then last = nil; return end
                    local fs = _G.GameTooltipTextLeft1
                    local t = fs and plain(fs:GetText())
                    if t and t ~= last then
                        tr_minimap_tooltip(self)
                        last = plain(fs:GetText())
                    end
                end)
            end
        end
    end
    -- tooltips Blizzard REBUILDS every second while hovered (clock: ClearLines + AddLine each tick) -> swap after
    -- each rebuild, not only on show (it reverted to English after a second)
    -- character-sheet stats: the stat frame's UpdateTooltip IS one of these functions (re-run ~every 0.2 s while hovered);
    -- swapping right after it, in the same frame, means no English flash (an OnUpdate re-check blinked, 2026-09-28)
    -- calendar button (R52): GameTimeFrame rebuilds its tooltip in its own OnUpdate (XML-bound, so hooking the global
    -- GameTimeFrame_OnUpdate does nothing) → our OnUpdate after it, only while it owns GameTooltip
    if _G.GameTimeFrame and not tt_hooked.GameTimeFrame then
        tt_hooked.GameTimeFrame = true
        GameTimeFrame:HookScript("OnUpdate", function(self)
            if GameTooltip:IsOwned(self) and tr_tooltip(GameTooltip) then GameTooltip:Show() end
        end)
    end
    for _, fn in ipairs({ "MainMenuBarPerformanceBarFrame_OnEnter", "TimeManagerClockButton_UpdateTooltip", "GameTime_UpdateTooltip", "MovementSpeed_OnEnter",
                          "PaperDollStatTooltip", "CharacterDamageFrame_OnEnter", "CharacterSpellBonusDamage_OnEnter",
                          "Mastery_OnEnter", "CharacterAttackPowerFrame_OnEnter", "CharacterRangedDamageFrame_OnEnter" }) do
        if not tt_hooked[fn] and type(_G[fn]) == "function" then
            tt_hooked[fn] = true
            hooksecurefunc(fn, function() if tr_tooltip(GameTooltip) then GameTooltip:Show() end end)
        end
    end
end
W.hook_tooltips()

-- dropdown lists (Blizzard_Menu: settings options, filters, …) are separate frames built on open: swap their
-- FontStrings after Blizzard fills them (display only, like the panels). Labels are measured before the swap, so
-- a longer Belarusian label that got cut with "…" is widened instead.
local function retext_menu_fs(r)
    pcall(function()                                     -- compositor regions forbid some methods: stay safe
        local et = W.EMOTE_LABEL and plain(r:GetText())
        if et and W.EMOTE_LABEL[et] and W.is_be() and W.on("ui") then W.swap(r, W.EMOTE_LABEL[et]); return end
        W.retext_fs(r, true)
        -- the quest's right-click menu (tracker / log, R408) is titled with the quest name
        local t = W.is_be() and W.on("quests") and plain(r:GetText())
        local qb = t and #t > 3 and not W.ours(t) and W.qtitle_be and W.qtitle_be(t)
        if qb and qb ~= t then W.swap(r, qb) end
        -- R720: item names as menu rows (transmog "Transmogrify as:" sources, in their quality colour)
        t = W.is_be() and W.on("spells") and plain(r:GetText())
        if t and not W.ours(t) then
            local c, name = t:match("^(|c%x%x%x%x%x%x%x%x)(.-)|r$")
            -- R822: spell names too (minimap tracking menu "Find Herbs", "Track Beasts")
            local be = W.IE[name or t] or W.spell_name_be(name or t)
            if be then W.swap(r, c and (c .. be .. "|r") or be) end
        end
    end)
end
local function retext_menu(menu) W.each_fs(menu, 8, retext_menu_fs) end
-- R611 (owner 2026-10-16: quest-map filter labels ran past the box): the menu box is sized from each row's measured
-- regions right after the row's initializers run, so swapping on show left it at the English width. Through Blizzard's
-- own extension point (Menu.ModifyMenu, every tag in WoWBY_MenuTags, unit popups excluded) each row gets one more
-- initializer that puts the Belarusian in and re-fits the FontString BEFORE the measure. No SetWidth on menu frames.
local function menu_fit_fs(r)
    local t = plain(r:GetText())
    retext_menu_fs(r)
    local n = plain(r:GetText())
    if n and n ~= t and r.SetTextToFit then pcall(r.SetTextToFit, r, n) end
end
local function menu_init(frame)
    if W.is_be() and W.on("ui") then pcall(W.each_fs, frame, 3, menu_fit_fs) end
end
local function menu_add_init(desc, depth)
    if depth > 6 then return end
    for _, d in desc:EnumerateElementDescriptions() do
        d:AddInitializer(menu_init)
        menu_add_init(d, depth + 1)
    end
end
if _G.Menu and Menu.ModifyMenu and type(WoWBY_MenuTags) == "table" then
    local function on_menu(_, root)
        if W.is_be() and W.on("ui") then pcall(menu_add_init, root, 0) end
    end
    for _, tag in ipairs(WoWBY_MenuTags) do pcall(Menu.ModifyMenu, tag, on_menu) end
end
if EventRegistry and EventRegistry.RegisterCallback then
    local menu_tickers = {}                               -- one per open menu (submenus are menus too)
    -- R914 (QA screenshot 2026-11-11: setting a raid target from the target's right-click menu → "WoWBY has been blocked
    -- from an action only available to the Blizzard UI"): unit popups (tags MENU_UNIT_*) run protected actions
    -- (SetRaidTargetIcon, focus, invite…) from their rows; our row re-texting tainted them. Leave unit menus English —
    -- the same rule as Menu.ModifyMenu above (unit popups excluded), now also for this show-time pass.
    local function unit_menu_open()
        local mgr = _G.Menu and Menu.GetManager and Menu.GetManager()
        local ok, tags = pcall(function() return mgr and mgr:GetOpenMenuTags() end)
        if ok and type(tags) == "table" then
            for _, t in pairs(tags) do
                if type(t) == "string" and t:find("^MENU_UNIT_") then return true end
            end
        end
        local ok2, root = pcall(function() return mgr and mgr:GetOpenMenu() end)
        local ok3, tag = pcall(function() return root and root:ToDebugString() end)
        return ok2 and ok3 and type(tag) == "string" and tag:find("^MENU_UNIT_") ~= nil
    end
    EventRegistry:RegisterCallback("MenuProxy.OnShow", function(_, menu)
        if not (W.on("ui") and menu) or unit_menu_open() then return end
        C_Timer.After(0, function() if menu:IsShown() then retext_menu(menu, 0) end end)
        if menu_tickers[menu] then menu_tickers[menu]:Cancel() end
        menu_tickers[menu] = C_Timer.NewTicker(0.3, function()   -- scrolling lists re-use their rows
            if menu:IsShown() then retext_menu(menu, 0)
            elseif menu_tickers[menu] then menu_tickers[menu]:Cancel(); menu_tickers[menu] = nil end
        end)
    end, "WoWBY")
end
if _G.SetTooltipMoney then   -- item "Sell Price:" is a money-frame prefix, not a tooltip line
    hooksecurefunc("SetTooltipMoney", function(frame)
        if not W.on("ui") or not (frame and frame.GetName and frame.shownMoneyFrames) then return end
        local mf = _G[(frame:GetName() or "") .. "MoneyFrame" .. frame.shownMoneyFrames]
        local fs = mf and (mf.PrefixText or _G[mf:GetName() .. "PrefixText"])
        local t = fs and plain(fs:GetText())
        -- (the client's own word: «Цена продажи» on ruRU, R665)
        local sp = (SELL_PRICE or "Sell Price"):gsub("%p", "%%%0")
        if t and t:find("^" .. sp) then fs:SetText((t:gsub("^" .. sp .. ":?", "Кошт:"))) end
    end)
end

-- ---------- aura hint (R59): target / player buff buttons use AuraButtonTooltip (Blizzard_AuraContainer), a tooltip
-- with FORBIDDEN aspects that its owner re-fills several times a second — swapping its lines would blink and risks taint.
-- Instead OUR own box sits under it: BE name (+ "Magic" etc.) and the BE description rendered from the drawn EN text.
-- The tooltip is only read (pcall; secret texts give nil → no box). Nothing is written into Blizzard's frames.
do
    -- the tooltip frames: Blizzard's own accessor first (the global may be hidden from addons), then the globals
    function W.aura_tips()
        local t = {}
        local ok, d = pcall(function() return AuraContainerUtil and AuraContainerUtil.GetDefaultTooltip() end)
        if ok and d then t.AuraButtonTooltip = d end
        t.AuraButtonTooltip = t.AuraButtonTooltip or _G.AuraButtonTooltip
        t.PrivateAurasTooltip = _G.PrivateAurasTooltip
        return t
    end
    local box, last, acc
    -- its lines have NO global names (/wowby tt: TextLeft1 = nil, 2026-09-29) → read, in this order: the tooltip data
    -- (GameTooltipDataMixin), named lines, or the drawn FontStrings sorted top→bottom (first in a row = left).
    local cache, cache_t = nil, nil
    local function lines_of(tt)
        local now = GetTime()
        if cache and cache_t == now and cache.tt == tt then return cache end
        local L = { tt = tt, Left = {}, Right = {} }
        local ok, d = pcall(function() return tt.GetPrimaryTooltipData and tt:GetPrimaryTooltipData() end)
        if ok and type(d) == "table" and not (issecretvalue and issecretvalue(d.lines)) and type(d.lines) == "table" then
            for i, l in ipairs(d.lines) do
                if not (issecretvalue and issecretvalue(l)) then
                    L.Left[i] = plain(l.leftText); L.Right[i] = plain(l.rightText)
                end
            end
            if L.Left[1] then L.via = "data" end
        end
        if not L.Left[1] then
            local n = tt:GetName() or ""
            for i = 1, 8 do
                local fl, fr = _G[n .. "TextLeft" .. i], _G[n .. "TextRight" .. i]
                local okl, tl = pcall(function() return fl and fl:IsShown() and plain(fl:GetText()) or nil end)
                local okr, tr = pcall(function() return fr and fr:IsShown() and plain(fr:GetText()) or nil end)
                L.Left[i], L.Right[i] = okl and tl or nil, okr and tr or nil
            end
            if L.Left[1] then L.via = "names" end
        end
        if not L.Left[1] then
            local fss = {}
            pcall(function()
                for _, r in ipairs({ tt:GetRegions() }) do
                    if r.GetObjectType and r:GetObjectType() == "FontString" and r:IsShown() then
                        local t, top, left = plain(r:GetText()), r:GetTop(), r:GetLeft()
                        if t and t ~= "" and top and left and not (issecretvalue and (issecretvalue(top) or issecretvalue(left))) then
                            fss[#fss + 1] = { t = t, top = top, left = left }
                        end
                    end
                end
            end)
            table.sort(fss, function(a, b) if math.abs(a.top - b.top) > 3 then return a.top > b.top end return a.left < b.left end)
            local row, prev = 0, nil
            for _, f in ipairs(fss) do
                if not prev or math.abs(prev - f.top) > 3 then row = row + 1; L.Left[row] = f.t
                else L.Right[row] = f.t end
                prev = f.top
            end
        end
        if L.Left[1] and not L.via then L.via = "regions" end
        L.via = L.via or "nothing readable"
        cache, cache_t = L, now
        return L
    end
    local function read(tt, side, i) return lines_of(tt)[side][i] end
    W.aura_lines = lines_of                   -- /wowby tt
    local function make()
        box = CreateFrame("Frame", "WoWBYAuraHint", UIParent, "BackdropTemplate")
        box:SetFrameStrata("TOOLTIP"); box:SetClampedToScreen(true); box:Hide()
        box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                          edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14,
                          insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        box:SetBackdropColor(0.05, 0.05, 0.08, 0.92); box:SetBackdropBorderColor(0.5, 0.5, 1)
        local function fs(size, r, g, b)
            local f = box:CreateFontString(nil, "ARTWORK")
            f:SetFont(W.FONT, size, ""); f:SetTextColor(r, g, b); f:SetJustifyH("LEFT"); f:SetWordWrap(true)
            return f
        end
        box.name = fs(13, 1, 0.82, 0); box.name:SetPoint("TOPLEFT", 9, -8)
        box.kind = fs(12, 1, 0.82, 0); box.kind:SetPoint("TOPRIGHT", -9, -8); box.kind:SetJustifyH("RIGHT")
        box.desc = fs(12, 1, 1, 1); box.desc:SetPoint("TOPLEFT", box.name, "BOTTOMLEFT", 0, -3)
    end
    local function place(tt)
        box:ClearAllPoints()
        if pcall(box.SetPoint, box, "TOPLEFT", tt, "BOTTOMLEFT", 0, -2) then return true end
        local ok, l, b = pcall(function() return tt:GetLeft(), tt:GetBottom() end)
        if not (ok and l and b) or (issecretvalue and (issecretvalue(l) or issecretvalue(b))) then return false end
        local s = tt:GetEffectiveScale() / UIParent:GetEffectiveScale()
        box:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * s, b * s - 2)
        return true
    end
    local function fill(tt)
        local en = read(tt, "Left", 1)
        local e = en and (WoWBY_AuraByName or {})[en]
        if not e then return false end
        local desc
        for i = 2, 6 do
            local t = read(tt, "Left", i)
            if t and t ~= "" then
                for _, k in ipairs(e[2] or {}) do
                    desc = W.render_desc(k, t)
                    if desc then break end
                end
                if desc then break end
            end
        end
        -- R953: the aura table has no name for spells named only through the by-EN name tables («Бонусы лагера»)
        local nm = e[1] or (W.spell_name_be and W.spell_name_be(en))
        if not (nm or desc) then return false end
        local kind = read(tt, "Right", 1)
        box.name:SetText(nm or en)
        box.kind:SetText(kind and (W.ui_be(kind) or kind) or "")
        box.desc:SetText(desc or "")
        local w = math.max(220, math.min(320, (box.name:GetStringWidth() or 0) + (box.kind:GetStringWidth() or 0) + 40))
        box:SetWidth(w)
        box.desc:SetWidth(w - 18)
        box:SetHeight(18 + (box.name:GetStringHeight() or 13) + (desc and ((box.desc:GetStringHeight() or 13) + 4) or 0))
        return true
    end
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, el)
        acc = (acc or 0) + el
        if acc < 0.1 then return end
        acc = 0
        if not (W.is_be() and W.on("spells")) then if box then box:Hide() end return end
        local tt
        for _, f in pairs(W.aura_tips()) do
            local ok, shown = pcall(function() return f and f:IsShown() end)
            if ok and shown then tt = f break end
        end
        -- bilingual mode (R415): a buff tooltip on GameTooltip whose data is SECRET (target / party buffs) keeps its
        -- English; the same box shows the Belarusian under it (nothing written into the tooltip)
        -- R434: also any buff tooltip that got no card (own buffs: the owner can be hidden from addons, the data
        -- secret or re-filled every second) — recognised by its data type (UnitAura) or line 1 being a known aura name
        -- R953 (owner screenshots: "Camp Benefits" / "Boosted Rest" buff tooltips stayed English): not only in bilingual
        -- mode — any GameTooltip buff card still English (secret data, so nothing could be swapped) gets the box too
        if not tt and GameTooltip:IsShown() and not W.dual_active(GameTooltip) then
            local ok, aura = pcall(function()
                local o = GameTooltip:GetOwner()
                if o and (o.auraInstanceID or o.buttonInfo or (o.GetName and (o:GetName() or ""):find("Aura"))) then return true end
                local d = GameTooltip:GetPrimaryTooltipData()
                local ty = d and W.sid_ok(d.type)
                if ty and ty ~= 7 then return false end                 -- spells / items / units: their own card
                local l1 = plain(_G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText())
                return (ty == 7 or W.TIP.secret[GameTooltip]) and l1 and (WoWBY_AuraByName or {})[l1] ~= nil
            end)
            if ok and aura then tt = GameTooltip end
        end
        if not tt then if box and box:IsShown() then box:Hide() end last = nil return end
        local key = (read(tt, "Left", 1) or "") .. "\1" .. (read(tt, "Left", 2) or "")
        if key == last and box and box:IsShown() then return end
        last = key
        if not box then make() end
        if fill(tt) and place(tt) then box:Show() else box:Hide() end
    end)
end
