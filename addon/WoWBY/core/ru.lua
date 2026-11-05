-- WoWBY/core/ru.lua — Russian client support (R665, owner 2026-10-18: "make the addon work on top of RU").
-- On a ruRU client the game hands WoWBY RUSSIAN text where every lookup is keyed by ENGLISH text. data/ru.lua (loaded
-- only on ruRU, tools/build_ru.py) holds RU → EN keys per domain, RU GlobalStrings formats that rebuild the ENGLISH line,
-- and RU spell-description patterns. Here:
--   * the shipped lookup tables fall back RU → EN through a metatable (W.N["Плотояд"] finds W.N["Flesh Eater"]); on enUS
--     nothing is installed (no metatable, no cost);
--   * W.ru_line_en(t): a Russian line → the same line in English (exact UI string, or a RU format with its captures),
--     used at the entry points (ui_be, tooltip lines, objective lines) — the rest of WoWBY then runs its English path;
--   * W.ours(t): "this text is already Belarusian" — on enUS any Cyrillic, on ruRU only і / ў with no и / щ / ъ.
local _, W = ...
W.RU = (GetLocale and GetLocale() == "ruRU") or false
local R = W.RU and WoWBY_RU or nil
W.ru_missing = W.RU and not R                     -- data/ru.lua did not load (TOC condition?) → reported at login
function W.ru_report()                            -- PLAYER_LOGIN step: a ruRU client without data/ru.lua
    if W.ru_missing and WoWBY_DB then
        WoWBY_DB.errors = WoWBY_DB.errors or {}
        table.insert(WoWBY_DB.errors, 1, date("%Y-%m-%d %H:%M ") .. "ruRU: data/ru.lua did not load (TOC condition?)")
    end
end
-- a letter in a guard ("is there a word here?"): Cyrillic counts on ruRU
W.LET = W.RU and "[%a\208\209]" or "%a"

local function has(t, s) return t:find(s, 1, true) ~= nil end
-- our own Belarusian UI words (R666: the map home button's «Свет» = World was read again as Russian «свет» = light →
-- «Святло»): texts with neither і/ў nor и/щ/ъ count as ours when WoWBY ships them as a translation
local BE_WORDS
local function be_word(t)
    if not BE_WORDS then
        BE_WORDS = {}
        for _, tbl in ipairs({ WoWBY_UI, WoWBY_Zones, WoWBY_Factions, WoWBY_POI, WoWBY_Titles, WoWBY_Skills }) do
            for _, v in pairs(type(tbl) == "table" and tbl or {}) do
                if type(v) == "string" and #v < 80 then BE_WORDS[v] = true end
            end
        end
    end
    return BE_WORDS[t] or BE_WORDS[(t:gsub("^|c%x%x%x%x%x%x%x%x(.-)|r$", "%1"))] or false
end
function W.ours(t)
    if type(t) ~= "string" or not t:find("[\208\209]") then return false end
    if not W.RU then return true end
    -- і І ў Ў = Belarusian; и И щ Щ ъ Ъ = Russian
    if has(t, "\208\184") or has(t, "\208\152") or has(t, "\209\137") or has(t, "\208\169") or has(t, "\209\138")
        or has(t, "\208\170") then
        return false
    end
    return has(t, "\209\150") or has(t, "\208\134") or has(t, "\209\158") or has(t, "\208\142") or be_word(t)
end
-- the NPC we talk to, for the gossip harvest: its id on ruRU (R672: Russian lines pair with the English ones by NPC at
-- build time), else its name
function W.npc_key()
    if W.RU then
        local g = W.sid_ok(UnitGUID("npc"))
        local id = type(g) == "string" and tonumber(g:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
        if id then return id end
    end
    return plain(UnitName("npc")) or true
end
local function unstress(t) return t:find("\204\129", 1, true) and t:gsub("\204\129", "") or t end   -- «Небесноро́жденная»

-- the first EN key of a RU text in one domain (or nil)
function W.ru_en(dom, t)
    local m = R and type(t) == "string" and R[dom]
    local en = m and (m[t] or m[unstress(t)])
    if type(en) == "table" then return en[1] end
    return en
end

-- tbl[EN key of a RU text] for the first EN candidate tbl knows (local hand tables of other modules)
function W.ru_get(tbl, dom, t)
    local m = R and type(t) == "string" and R[dom]
    local en = m and (m[t] or m[unstress(t)])
    if type(en) == "string" then return tbl[en] end
    for _, e in ipairs(type(en) == "table" and en or {}) do
        if tbl[e] ~= nil then return tbl[e] end
    end
end
-- lookup table → RU keys fall back to their EN keys (every candidate of each domain, in order)
function W.ru_alias(tbl, ...)
    if not (R and type(tbl) == "table") or getmetatable(tbl) then return tbl end
    local maps = {}
    for _, d in ipairs({ ... }) do if R[d] then maps[#maps + 1] = R[d] end end
    if #maps == 0 then return tbl end
    setmetatable(tbl, { __index = function(t, k)
        if type(k) ~= "string" or W.ours(k) then return nil end    -- our own Belarusian is not Russian (R666)
        k = unstress(k)
        for i = 1, #maps do
            local en = maps[i][k]
            if type(en) == "string" then
                local v = rawget(t, en)
                if v ~= nil then return v end
            elseif type(en) == "table" then
                for _, e in ipairs(en) do
                    local v = rawget(t, e)
                    if v ~= nil then return v end
                end
            end
        end
    end })
    return tbl
end
if R then
    -- the data tables (same objects as W.UI / W.N / W.Z / W.G / W.IE …, which the modules take from these globals)
    local A = W.ru_alias
    A(WoWBY_UI, "ui"); A(WoWBY_Factions, "ui"); A(WoWBY_Skills, "ui")
    A(WoWBY_Names, "names"); A(WoWBY_NamesF, "names")
    A(WoWBY_Titles, "titles", "ui"); A(WoWBY_TitlesF, "titles", "ui")
    A(WoWBY_Zones, "zones"); A(WoWBY_POI, "zones", "ui")
    A(WoWBY_Gossip, "gossip")
    A(WoWBY_ItemsEN, "items")
    A(WoWBY_SpellNamesEN, "spells", "ui"); A(WoWBY_AuraByName, "spells", "ui")
    A(WoWBY_Books, "books")
    A(WoWBY_Objectives, "objectives", "names", "items")
    A(WoWBY_QTitleFV, "quests")
    -- hand tables keyed by EN words (classes, races)
    A(W.CLASSES, "ui"); A(W.CLASSES_FEM, "ui"); A(W.RACES, "ui")
end

-- ---------- a Russian line → the same line in English ----------
local RUF, RUFX = WoWBY_RUF or {}, WoWBY_RUFX or {}
local function en_plural(s)                           -- EN "|4Day:Days;" by the number before it
    return (s:gsub("(%d+)([^|%d]-)|4([^:;]*):([^;]*);", function(n, mid, one, many)
        return n .. mid .. (tonumber(n) == 1 and one or many)
    end))
end
local ru_list
-- RU → EN for a capture: an exact UI word, or a RU format of its own ("4 медные монеты" → "4 Copper"), else kept (the
-- EN path then knows names / zones / items through the aliases)
local function cap_en(c, depth)
    if c == "" or not c:find("[\208\209]") then return c end
    local l = depth < 2 and ru_list(c, depth + 1)
    return l and l[1] or c
end
-- every English reading of a Russian line, most likely first: the exact UI string(s), then each matching RU format
-- (most specific first; a pattern shared by several EN formats gives each)
function ru_list(t, depth)
    depth = depth or 0
    t = unstress(t)
    local out = {}
    local ex = R.ui[t]
    if type(ex) == "string" then out[1] = ex
    elseif type(ex) == "table" then for _, e in ipairs(ex) do out[#out + 1] = e end end
    local hits, idx = {}, {}
    local words = t:gsub("|c%x%x%x%x%x%x%x%x", " "):gsub("|cn[^:|]*:", " "):gsub("|r", " ")
    for w in words:gmatch("[%a\208\209][%a\128-\191\208\209]*") do
        for _, i in ipairs(RUFX[w] or {}) do
            if not hits[i] then hits[i] = true; idx[#idx + 1] = i end
        end
    end
    table.sort(idx)
    local matched = 0
    for _, i in ipairs(idx) do
        local d = RUF[i]
        local caps = { t:match(d[1]) }
        if #caps > 0 then
            for j = 2, #d do
                local s = {}
                for _, p in ipairs(d[j]) do
                    if type(p) == "number" then s[#s + 1] = cap_en(caps[p] or "", depth)
                    else s[#s + 1] = p end
                end
                out[#out + 1] = en_plural(table.concat(s))
            end
            matched = matched + 1
            if matched >= 3 then break end
        end
    end
    return #out > 0 and out or nil
end
function W.ru_lines_en(t)
    if not (R and type(t) == "string" and t ~= "" and t:find("[\208\209]")) or W.ours(t) then return nil end
    -- a whole line in one colour (tooltip lines): the text inside, the colour kept
    -- (formats that carry the colour themselves — «|cff00ff00<Изготовитель: %s>|r», R674 — match the whole line)
    local c, inner, r = t:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
    if inner and not inner:find("|c", 1, true) then
        local l = ru_list(inner) or {}
        for i, e in ipairs(l) do l[i] = c .. e .. r end
        for _, e in ipairs(ru_list(t) or {}) do l[#l + 1] = e end
        return #l > 0 and l or nil
    end
    return ru_list(t)
end
function W.ru_line_en(t)
    local l = W.ru_lines_en(t)
    return l and l[1]
end
-- the line itself when it is not Russian (or no rule knows it)
function W.en_line(t)
    return R and W.ru_line_en(t) or t
end

-- ---------- player class / race in English (UnitClass / UnitRace give Russian, and feminine for women) ----------
local CLASS_FILE = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
                     SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid", DEATHKNIGHT = "Death Knight" }
local RACE_FILE = { Human = "Human", Orc = "Orc", Dwarf = "Dwarf", NightElf = "Night Elf", Scourge = "Undead",
                    Tauren = "Tauren", Gnome = "Gnome", Troll = "Troll", BloodElf = "Blood Elf", Draenei = "Draenei",
                    Goblin = "Goblin" }
function W.player_class_en()
    local name, file = UnitClass("player")
    if not W.RU then return name end
    return CLASS_FILE[file or ""] or W.ru_en("ui", plain(name) or "") or name
end
function W.player_race_en()
    local name, file = UnitRace("player")
    if not W.RU then return name end
    return RACE_FILE[file or ""] or W.ru_en("ui", plain(name) or "") or name
end

-- ---------- spell descriptions: RU patterns into the same BE templates ----------
W.SD_RU = R and WoWBY_SpellDescRU or nil
