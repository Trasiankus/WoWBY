-- WoWBY/core/ui.lua — UI dictionary, format strings, panels, menus.
-- Split from core.lua (tools/split_core.py); shared state lives in the addon namespace W.
local _, W = ...
-- ---------- menus & UI panels (WoWPL approach: exact-label FontString swap after the panel builds) ----------
-- WoWBY_UI (data/ui.lua) = TM GlobalStrings EN->BE verified against Forever; hand-picked words below win.
-- Only FontString:SetText (never Button/secure API), deferred out of the build call, skipped in combat.
W.UI = WoWBY_UI or {}
local UI_HAND = {
    ["Return to Game"] = "Вярнуцца ў гульню", ["Continue"] = "Працягнуць", ["Options"] = "Налады",
    ["Settings"] = "Налады", ["System"] = "Сістэма", ["Macros"] = "Макрасы", ["Interface"] = "Інтэрфейс",
    -- spell subtexts (Spell NameSubtext, R380, owner)
    ["Racial"] = "Расавае", ["Elemental Combat"] = "Стыхійны бой", ["Narrator"] = "Апавядальнік", ["Shadow Magic"] = "Магія цемры", ["Racial Passive"] = "Расавае пасіўнае",
    ["Back"] = "Назад",   -- buttons (quest details "Back"); the cloak slot in item tooltips = «Спіна» (tooltip_line_be)
    ["(Alliance Territory)"] = "(Тэрыторыя Альянсу)", ["(Horde Territory)"] = "(Тэрыторыя Арды)",   -- owner
    ["(Contested Territory)"] = "(Спрэчная тэрыторыя)",
    ["AddOns"] = "Дадаткі", ["Addons"] = "Дадаткі", ["Edit Mode"] = "Рэжым рэдагавання",
    ["Ratings"] = "Адзнакі", ["Support"] = "Падтрымка", ["Help"] = "Дапамога",
    ["Log Out"] = "Выйсці да герояў", ["Logout"] = "Выйсці да герояў", ["Exit Game"] = "Выйсці з гульні",
    ["Shop"] = "Крама", ["Store"] = "Крама", ["Game Menu"] = "Меню гульні", ["What's New"] = "Што новага",
    ["Map & Quest Log"] = "Карта і журнал заданняў", ["Sell Price:"] = "Кошт:",
    ["Quests & Zones"] = "Заданні і зоны",                          -- group finder category (R225)
    Cancel = "Скасаваць", Accept = "Прыняць", Close = "Закрыць", Okay = "Добра", Done = "Гатова",
    Yes = "Так", No = "Не", Delete = "Выдаліць", Buy = "Купіць", Sell = "Прадаць", Repair = "Рамонт",   -- owner 2026-09-28 (minimap tracking)
    Shapeshift = "Змена аблічча",                         -- spell subtext (trainer requirements: "Bear Form (Shapeshift)")
    -- container subtypes (ItemSubClass, "4 Slot Leatherworking Bag" = CONTAINER_SLOTS, R298); forms as the bag items
    ["Soul Bag"] = "Торба душ", ["Herb Bag"] = "Торба для траў", ["Enchanting Bag"] = "Торба для зачаравання",
    ["Engineering Bag"] = "Інжынерная торба", ["Mining Bag"] = "Торба для гарняцтва",
    ["Leatherworking Bag"] = "Торба для скур", ["Cooking Bag"] = "Торба для прадуктаў",
    ["Reagent Bag"] = "Торба для рэагентаў", ["Trinket Bag"] = "Торба для аксесуараў",
    ["Tackle Box"] = "Скрыня для рыбацкіх снасцей", ["Ammo Pouch"] = "Падсумак",
    -- Recent Allies card: what you did together (RolodexType DB2 Field_…, server data → not in GlobalStrings, R316)
    ["Fought Together"] = "Біліся разам", ["Traded"] = "Гандлявалі", ["Whispered"] = "Шапталіся",
    ["Completed Dungeon Together"] = "Прайшлі падзямелле разам", ["Raided Together"] = "Хадзілі ў рэйд разам",
    ["Did Arena Together"] = "Біліся на арэне разам", ["Fought in Battleground Together"] = "Біліся на полі бою разам",
    ["Dueled"] = "Біліся на дуэлі", ["PvPed Together"] = "Разам у PvP", ["Legacy Friend"] = "Сябар са старога спісу",
    ["Filled your Crafting Order"] = "Выканаў ваш заказ", ["Filled their Crafting Order"] = "Вы выканалі заказ",
    ["Filled your Public Crafting Order"] = "Выканаў ваш публічны заказ",
    ["Filled their Public Crafting Order"] = "Вы выканалі публічны заказ",
    ["Party Member"] = "Удзельнік групы", ["Raid Member"] = "Удзельнік рэйда",
    -- online-language dropdown (R320; languages are «мова» → feminine, data/be ui)
    ["LatAm Spanish"] = "Іспанская (Лацінская Амерыка)", ["Brazilian Portuguese"] = "Партугальская (Бразілія)",
    ["Repair All"] = "Адрамантаваць усё", Trade = "Абмен", Learn = "Вывучыць", Reset = "Скінуць",
    Apply = "Ужыць", Defaults = "Па змаўчанні", Save = "Захаваць", Create = "Стварыць", Send = "Адправіць",
    Reply = "Адказаць", Inspect = "Агледзець", Invite = "Запрасіць", Ignore = "Ігнараваць",
    Level = "Узровень", Strength = "Сіла", Agility = "Спрытнасць", Stamina = "Вынослівасць",
    Intellect = "Інтэлект", Spirit = "Дух", Armor = "Браня", Health = "Здароўе", Mana = "Мана",
    Reputation = "Рэпутацыя", Skills = "Навыкі", Currency = "Валюта", Titles = "Званні",
    Buyback = "Выкуп", Bank = "Банк", Inbox = "Уваходныя", ["Take All"] = "Узяць усё",
    Beast = "Звер", Dragonkin = "Драканід", Demon = "Дэман", Elemental = "Элементаль",
    Giant = "Волат", Humanoid = "Гуманоід", Critter = "Звярок", Mechanical = "Механізм", Totem = "Татэм",
    Elite = "Эліта", Rare = "Рэдкі", ["Rare Elite"] = "Рэдкая эліта", Boss = "Бос",   -- owner: (Эліта)
    -- Battle.net friend's rich presence (server text, R929): a friend in the launcher app
    ["In App"] = "У праграме",
    -- recent allies tooltip time (SecondsFormatter "< 1 Hour" + "%s ago", R939)
    ["< 1 Hour ago"] = "менш за гадзіну таму", ["< 1 Hour"] = "менш за гадзіну",
    -- Settings > Social "Preferred online language" (engine locale names, not GlobalStrings, R938)
    ["European Spanish"] = "Еўрапейская іспанская", ["Latin American Spanish"] = "Лацінаамерыканская іспанская",
    ["European Portuguese"] = "Еўрапейская партугальская", ["Brazilian Portuguese"] = "Бразільская партугальская",
}
for en, be in pairs(UI_HAND) do W.UI[en] = be end
-- "Must have a Fishing Pole equipped" (SPELL_FAILED_EQUIPPED_ITEM_CLASS*, R918 owner 2026-11-11: «Вы павінны трымаць у
-- руцэ Вуда» read badly): whole lines with the weapon type in the accusative; other types use the format's «…: %s»
local EQUIP_ACC = { ["Fishing Pole"] = "вуду", Axe = "сякеру", Bow = "лук", Gun = "стрэльбу", Mace = "булаву",
    Polearm = "дрэўкавую зброю", Sword = "меч", Staff = "посах", ["Fist Weapon"] = "кісцевую зброю", Dagger = "кінжал",
    Shield = "шчыт", Thrown = "кідальную зброю", Wand = "жазло", Crossbow = "арбалет" }
for en, acc in pairs(EQUIP_ACC) do
    W.UI["Must have a " .. en .. " equipped"] = "Трэба ўзяць у рукі " .. acc
    W.UI["Must have a " .. en .. " equipped in the main hand"] = "Трэба ўзяць у правую руку " .. acc
    W.UI["Must have a " .. en .. " equipped in the offhand"] = "Трэба ўзяць у другую руку " .. acc
end
for en, be in pairs(W.CLASSES) do W.UI[en] = W.UI[en] or be end
for en, pair in pairs(W.RACES) do W.UI[en] = W.UI[en] or pair[1] end
W.current_tooltip_female = false
-- format strings ("Level %s |c%s%s|r"): patterns from data/ui.lua, looked up by a word of the text;
-- captured values that are themselves UI words (class names, stat names, races) are translated too
local UIF = WoWBY_UIF or {}
local UIFX = WoWBY_UIFX or {}
function W.ui_val(v)                                 -- "Druid" or "|cffff7c0aDruid|r"
    if W.RU then v = W.en_line(v) end                -- ruRU client (R665): «Охотница» → "Hunter"
    if W.current_tooltip_female then
        if W.RACES[v] then return W.RACES[v][2] end
        if W.CLASSES_FEM[v] then return W.CLASSES_FEM[v] end
    end
    if W.player_race_line and W.RACES[v] then return W.RACES[v][1] end
    if W.UI[v] then return W.UI[v] end
    local c, inner, r = v:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
    if inner then
        if W.current_tooltip_female then
            if W.RACES[inner] then return c .. W.RACES[inner][2] .. r end
            if W.CLASSES_FEM[inner] then return c .. W.CLASSES_FEM[inner] .. r end
        end
        if W.UI[inner] then return c .. W.UI[inner] .. r end
    end
    return v
end
-- numbers / punctuation / colour codes only ("33", "(25|cff20ff20+8|r)", "7.6%")
function is_value(v)
    -- coin / currency icons count as part of a number (money "4|T…SilverIcon…|t 85|T…|t", R330)
    local p = v:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return p:find("^[%d%s%p]+$") ~= nil
end
-- WoW's |4one:few:many; plural escape (ruRU strings use it): picked here by the number just before it,
-- Belarusian/Russian rule (1 / 2-4 / 5-20, by the last digits)
local function plural_forms(text)
    return (text:gsub("(%d+)([^|%d]-)|4([^:;]*):([^:;]*):([^;]*);", function(num, mid, one, few, many)
        local n = tonumber(num) % 100
        local d = n % 10
        local w = (n >= 11 and n <= 14) and many or (d == 1 and one) or ((d >= 2 and d <= 4) and few) or many
        return num .. mid .. w
    end):gsub("(%d+)([^|%d]-)|4([^:;]*):([^;]*);", function(num, mid, one, many)   -- 2-form escapes
        return num .. mid .. ((tonumber(num) % 10 == 1 and tonumber(num) % 100 ~= 11) and one or many)
    end))
end
W.plural_forms = plural_forms
-- (W.qtitle_be declared in the namespace)                  -- set once the quest-log helpers exist: EN quest title -> BE ("Quest accepted: %s")
-- formats whose capture is a name the PLAYER chose (chat tab "%s Tab": «Укладка General», owner 2026-10-07): the capture
-- is kept verbatim (never translated, any text accepted) — except Blizzard's two default tab names (owner R238)
local RAW_FMT = { ["^(.-) Tab$"] = true }
-- a capture that is a list of names ("Requires %s" = "Bear Form, Dire Bear Form", R288): every piece must be a known
-- spell / item / UI name, else nil (the line stays English)
-- R923: profession tool links have no [ ]: "|HSpellFocusRequirement|hForge|h" (Totem / Area requirements too), one or
-- a ", " list, each maybe in red → every shown name swapped (UI word / item / spell / zone), else nil
function W.req_links_be(c)
    local miss = false
    local out = c:gsub("(|H%a+Requirement[^|]*|h)([^|]+)(|h)", function(a, nm, b)
        local be = W.UI[nm] or (W.on("spells") and (W.IE[nm] or W.spell_name_be(nm))) or (W.on("zones") and W.Z[nm])
        if not be then miss = true; return nil end
        return a .. be .. b
    end)
    if miss or out == c then return nil end
    -- nothing else but colours and ", " may remain outside the links
    local rest = out:gsub("|H.-|h.-|h", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", "")
    return rest:find("^[%s,]*$") and out or nil
end
local function name_list_be(c)
    if not c:find(", ", 1, true) or c:find("|", 1, true) then return nil end
    local parts = {}
    for piece in (c .. ", "):gmatch("(.-), ") do
        local b = (W.on("spells") and (W.IE[piece] or W.spell_name_be(piece))) or W.UI[piece]
        if not b then return nil end
        parts[#parts + 1] = b
    end
    return table.concat(parts, ", ")
end
-- an enchant's name made of stats ("Stamina +1 and Armor +8", "+5 Agility", R364): every "stat +N" piece must be a
-- known UI word, else nil
local function stat_list_be(c)
    if c:find("|", 1, true) or not c:find("[%+%-]%d") then return nil end
    local parts = {}
    for piece in (c .. " and "):gmatch("(.-) and ") do
        local stat, num = piece:match("^(.-) ([%+%-]%d+%%?)$")
        if not stat then num, stat = piece:match("^([%+%-]%d+%%?) (.+)$") end
        local b = stat and W.UI[stat]
        if not b then return nil end
        parts[#parts + 1] = b .. " " .. num
    end
    return table.concat(parts, " і ")
end
W.CHAT_TAB_BE = { General = "Агульнае", ["Combat Log"] = "Журнал бою", Voice = "Голас",
                  -- R912 (QA 2026-11-11): a character created on a Russian client keeps the Russian default tab names
                  -- in its saved chat settings, also after switching to enUS → translate those too
                  ["Общий"] = "Агульнае", ["Общее"] = "Агульнае", ["Журнал боя"] = "Журнал бою", ["Голос"] = "Голас" }
if W.ru_alias then W.ru_alias(W.CHAT_TAB_BE, "ui") end      -- ruRU client: «Общий», «Журнал боя» (R665)
-- SecondsToTime text, every unit known or nil: "54 Min 29 Sec", on a ruRU client "4 мин. 46 с."
local DURATION = { sec = "сек.", secs = "сек.", min = "хв.", mins = "хв.", hr = "гадз.", hrs = "гадз.", hour = "гадз.", hours = "гадз.",
                   day = "д", days = "д", c = "сек.", ["с"] = "сек.", ["сек"] = "сек.", ["мин"] = "хв.", ["ч"] = "гадз.", ["час"] = "гадз.",
                   ["д"] = "д", ["дн"] = "д" }
function W.duration_be(s)
    local rest, out = s:gsub("\194\160", " "), {}
    while rest ~= "" do
        local n, u, tail = rest:match("^(%d+) ([^%d%s%.]+)%.?%s*(.*)$")
        local b = u and (DURATION[u] or DURATION[u:lower()])
        if not b then return nil end
        out[#out + 1] = n .. " " .. b
        rest = tail
    end
    return #out > 0 and table.concat(out, " ") or nil
end
local ui_fmt
function ui_fmt(t, depth)
    depth = depth or 0
    -- R645: index words are taken with colour codes removed — "|cFFFFFFFFCritically Hit|r" read as ONE word
    -- "cFFFFFFFFCritically", so every format whose key word sat right after a colour code never matched (weapon-skill
    -- detail lines, many stat tooltips)
    local words = t:gsub("|c%x%x%x%x%x%x%x%x", " "):gsub("|cn[^:|]*:", " "):gsub("|r", " ")
    for w in words:gmatch("[%a']+") do
        local list = #w >= 3 and UIFX[w]
        if list then
            for _, i in ipairs(list) do
                local d = UIF[i]
                local caps = { t:match(d[1]) }
                -- Only translate a line we fully know (owner 2026-09-25): every captured value must be a number,
                -- a colour, already Belarusian, a UI word, or a known NPC/zone name. Otherwise the pattern matched
                -- something else ("%s Damage" on a player called "Vertessa Damage", "%s and %s" on a greeting)
                -- and the line stays English.
                local vals, known = {}, #caps > 0
                local raw = RAW_FMT[d[1]]
                for i, c in ipairs(caps) do
                    if type(c) ~= "string" then c = tostring(c) end
                    -- R819: a line whose names are only ever PLAYERS (messages PLAYER_FMT_KEYS): a name is kept even
                    -- when an NPC has it (a player "Bob" had become «Карэ»); money / links have digits or "|"
                    local pname = W.player_names and depth == 0 and c:find("^%u") and #c <= 48 and not c:find("[|%d]")
                        and not c:find("%s%S+%s%S+%s")
                    local v = pname and c or raw and (W.CHAT_TAB_BE[c] or c) or W.ui_val(c)
                    if v == c then
                        -- already Belarusian = Cyrillic and NO Latin words: a half-translated capture
                        -- («Патрабуецца: Bear Form, Dire Bear» on the 2nd tooltip pass) is not "known" (R18)
                        if pname then
                            v = (W.emote_names and W.on("names") and W.N[c]) or c   -- "You wave at Guard Roberts."
                        elseif c == "" or is_value(c) or c:find("^%x%x%x%x%x%x%x%x$")
                            or (W.ours(c) and not c:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|[rHhT][^|]*", ""):find("[A-Za-z][A-Za-z]")) then
                            v = c
                        elseif W.N[c] or W.Z[c] then
                            v = W.N[c] or W.Z[c]
                        elseif (WoWBY_Factions or {})[c] then
                            v = WoWBY_Factions[c]                      -- "Reputation with High Order increased by 100." (R454)
                        elseif c:find("Requirement[^|]*|h") and W.req_links_be(c) then
                            v = W.req_links_be(c)                      -- "Anvil, Blacksmith Hammer" tool links (R923)
                        elseif c:find("^|c.-|H.-|h.-|h|r$") or c:find("^|H.-|h.-|h$") then
                            -- item/spell link (colour may be |cffRRGGBB or the new |cnIQ1:): kept; the item's shown
                            -- name inside [ ] is swapped when we know it (display only, the link data is untouched)
                            v = c:gsub("(|h%[)(.-)(%]|h)", function(a, nm, b)
                                local be = W.on("spells") and W.IE[nm]
                                return be and (a .. be .. b) or nil
                            end)
                            v = W.req_links_be(v) or v
                        -- exact names BEFORE nested formats (R742: "Choker of the Fire Lord" in the destroy popup was
                        -- read as TITLE_TEMPLATE "%s of the %s" → «Choker з Fire Lord»)
                        elseif W.qtitle_be and W.qtitle_be(c) then
                            v = W.qtitle_be(c)                         -- a quest title we have
                        elseif W.on("spells") and (W.IE[c] or W.spell_name_be(c)) then
                            -- plain item / spell / recipe name ("You have learned how to create a new item: %s.", R24)
                            v = W.IE[c] or W.spell_name_be(c)
                        elseif WoWBY_Skills and WoWBY_Skills[c] then
                            v = WoWBY_Skills[c]                        -- "Your skill in Riding has increased to 75." (R803)
                        elseif depth < 2 and ui_fmt(c, depth + 1) then
                            v = ui_fmt(c, depth + 1)                 -- "4 Copper" inside "You loot %s"
                        elseif name_list_be(c) then
                            v = name_list_be(c)                        -- "Bear Form, Dire Bear Form" (R288)
                        elseif (function()
                                -- a name in one colour: "Requires |cffff2020Runed Truesilver Rod|r" (R375), also the
                                -- named-colour form "|cnRED_FONT_COLOR:Cooking Fire|r" (profession tools, R501)
                                local cc, inner, rr = c:match("^(|c%x%x%x%x%x%x%x%x)([^|]+)(|r)$")
                                if not cc then cc, inner, rr = c:match("^(|cn[%w_]+:)([^|]+)(|r)$") end
                                local b = inner and (W.UI[inner] or W.N[inner] or W.Z[inner]
                                    or (W.on("spells") and (W.IE[inner] or W.spell_name_be(inner))))
                                if b then v = cc .. b .. rr end
                                return b
                            end)() then
                        elseif c:find("^%u[%u%d]*%-[%-%u%d]+$") or c:find("^F%d%d?$") then
                            v = c                                      -- a key binding "SHIFT-C", "F6" (R366)
                        elseif stat_list_be(c) then
                            v = stat_list_be(c)                        -- enchant "Stamina +1 and Armor +8" (R364)
                        elseif ((W.any_name and depth == 0) or d[1]:find("ollowing", 1, true) or d[1]:find("stop moving to attack", 1, true))
                            and #c <= 48 and not c:find("|", 1, true) and not c:find("%s%S+%s%S+%s") and not c:find("^%l") then
                            v = c                                      -- emote: a player's name, kept as is
                        else
                            known = false; break
                        end
                    end
                    vals[i] = v
                end
                if known then
                    local out = {}
                    for _, p in ipairs(d[2]) do
                        if type(p) == "number" then out[#out + 1] = vals[p] or ""
                        else out[#out + 1] = p end
                    end
                    return plural_forms(table.concat(out))
                end
            end
        end
    end
end
-- a whole label keeps the English capital: "Fire:" -> "Агонь:" even if the shared translation is "агонь"
-- (same EN string used mid-sentence elsewhere). Only standalone matches, never text inside format strings.
local UPPER = {}
do
    local lo, up = "абвгдеёжзійклмнопрстуўфхцчшыьэюя", "АБВГДЕЁЖЗІЙКЛМНОПРСТУЎФХЦЧШЫЬЭЮЯ"
    local l, u = {}, {}
    for ch in lo:gmatch("[\192-\255][\128-\191]*") do l[#l + 1] = ch end
    for ch in up:gmatch("[\192-\255][\128-\191]*") do u[#u + 1] = ch end
    for i = 1, #l do UPPER[l[i]] = u[i] end
    UPPER["ў"] = "У"                                   -- ў never starts a sentence: «Узровень»
end
local function cap_like(en, be)
    if not (en and be) or not en:find("^%s*%u") then return be end
    local lead, first, rest = be:match("^(%s*)([\192-\255][\128-\191]*)(.*)$")
    if first and UPPER[first] then return lead .. UPPER[first] .. rest end
    return be
end
W.cap_like = cap_like
local RESIST_DAT = { Fire = "агню", Frost = "марозу", Nature = "прыродзе", Shadow = "цемры", Arcane = "аркане",
                     Holy = "святлу" }
local ui_be_core
local function ui_be_one(t)
    t = plain(t)
    if not t or t == "" then return nil end
    -- ruRU client (R665): each English reading of the Russian line through the English rules, then the line itself
    if W.RU then
        for _, e in ipairs(W.ru_lines_en(t) or {}) do
            local b = ui_be_core(e)
            if b then return b end
        end
    end
    return ui_be_core(t)
end
function ui_be_core(t)
    local be = W.UI[t] or W.UI[W.strtrim(t)] or (t:find("\r", 1, true) and W.UI[(t:gsub("\r", ""))])   -- DB2 texts keep \r\n
    -- R607: faction names where they are SHOWN (reputation rows / detail title) — the C_Reputation wraps are gone
    if not be and W.on("ui") then be = (WoWBY_Factions or {})[t] end
    -- … and zone names (map nav bar, zone dropdown, area label) — the C_Map wraps are gone too
    if not be and W.on("zones") then be = W.Z[t] or W.Z[W.strtrim(t)] end
    if be then return cap_like(t, be) end
    -- R863 (owner screenshot: trainer «Цюлень з Крыжак»): a whole spell name wins over the format templates — TITLE_TEMPLATE
    -- "%s of the %s" + the UI word Seal (the animal) had built it before the trainer hook could set «Пячатка крыжака»
    if W.spell_name_be and W.on("spells") and t:find(" ", 1, true) then
        local sb = W.spell_name_be(t)
        if sb then return sb end
        local base, rk = t:match("^(.-) %(Rank (%d+)%)$")
        sb = base and W.spell_name_be(base)
        if sb then return sb .. " (ранг " .. rk .. ")" end
    end
    -- item resistance line "+8 Fire Resistance" (ITEM_RESIST_SINGLE builds it from a bare school word) -> the school in
    -- the DATIVE like the stat names: «+8 да супраціўлення агню» (owner 2026-10-01; was «… супраціўлення: агонь»)
    local sign, school, close = t:match("^([%+%-]%d+) (%a+) Resistance(|?r?)$")
    if not sign then
        local col
        col, sign, school, close = t:match("^(|c%x%x%x%x%x%x%x%x)([%+%-]%d+) (%a+) Resistance(|r)$")
        if col and RESIST_DAT[school] then return col .. sign .. " да супраціўлення " .. RESIST_DAT[school] .. close end
    elseif RESIST_DAT[school] then
        return sign .. " да супраціўлення " .. RESIST_DAT[school] .. (close or "")
    end
    -- exit / logout countdown (QUIT_TIMER / CAMP_TIMER "%d %s until exit"): the %s is the unit word, not a known
    -- capture, and Belarusian needs the plural agreeing with the number («20 секунд», «2 секунды») — 2026-10-07
    local n, unit, what = t:match("^(%d+) (%a+) until (%a+)$")
    if not n then                          -- spirit healer AREA_SPIRIT_HEAL "Resurrection in %d %s" (R737, owner screenshot)
        n, unit = t:match("^Resurrection in (%d+) (%a+)$")
        what = n and "resurrect"
    end
    local forms = unit and ({ second = { "секунду", "секунды", "секунд" }, minute = { "хвіліну", "хвіліны", "хвілін" } })
                  [unit:lower():gsub("s$", "")]
    if forms and (what == "exit" or what == "logout" or what == "release" or what == "resurrect") then
        local k, m10, m100 = tonumber(n), tonumber(n) % 10, tonumber(n) % 100
        local w = (m10 == 1 and m100 ~= 11) and forms[1]
                  or (m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14)) and forms[2] or forms[3]
        -- death popup DEATH_RELEASE_TIMER "6 Minutes until release" (R403)
        return ({ exit = "Выхад з гульні праз ", logout = "Выхад да выбару персанажа праз ",
                  release = "Душа вызваліцца праз ", resurrect = "Уваскрашэнне праз " })[what] .. k .. " " .. w
                  -- душа, not дух (owner R405)
    end
    -- item cooldown "Cooldown remaining: 54 Min 29 Sec" (R215): a composite of units, not one format capture
    local rest = t:match("^Cooldown remaining: (.+)$")
    local dur = rest and W.duration_be(rest)
    if dur then return "Да аднаўлення: " .. dur end
    -- quest timer (R810): the log's "Time Remaining: 4 Min 49 Sec", the timer box's bare "4 Min 46 Sec"; both redrawn all the time
    local label = _G.TIME_REMAINING
    if type(label) == "string" and t:sub(1, #label + 1) == label .. " " then
        dur = W.duration_be(t:sub(#label + 2))
        if dur then return "Засталося часу: " .. dur end
    end
    if t:find("^%d+ %S+ %d+ %S") then
        dur = W.duration_be(t)
        if dur then return dur end
    end
    -- "<place>, <zone>" (flight map nodes the build had no text for, e.g. new Forever zones): both parts known zones
    local pa, pb = t:match("^([^,]+), ([^,]+)$")
    if pa and W.Z[pa] and W.Z[pb] then return W.Z[pa] .. ", " .. W.Z[pb] end
    local base = t:match("^(.-):%s*$")                   -- "Health:" -> "Здароўе:"
    if base and W.UI[base] then return cap_like(base, W.UI[base]) .. ":" end
    -- "Attack Power 26", "Critical Strike 7.6%": a known label + a value (checked before the format patterns,
    -- or "Attack %s" would turn it into «Атакуем: Power 26»)
    -- a known label + a value part that is only numbers / punctuation / colour codes ("Stamina 33 (25|cff20ff20+8|r)",
    -- WowUkrainizer's PaperDollStatTooltip approach: translate the label, keep the rest)
    local label, sep, val = t:match("^(.-)(:?%s+)([%d%(%+%-|].*)$")
    -- a label followed by a NUMBER can mean something else than the bare label: "Rank 2" (spell rank) = «Ранг 2»,
    -- while the guild column "Rank" = «Званне» (owner 2026-09-26)
    local LV = { Rank = "Ранг" }
    if label and (LV[label] or W.UI[label]) and is_value(val) then
        return cap_like(label, LV[label] or W.UI[label]) .. sep .. val
    end
    local c, inner, r, rest = t:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)(%s+[%d%.,%%%-%+/ ]+)$")
    if inner and W.UI[inner] then return c .. cap_like(inner, W.UI[inner]) .. r .. rest end
    local c2, whole = t:match("^(|c%x%x%x%x%x%x%x%x)(.-)|r$")      -- the whole line in one colour
    if whole and whole ~= "" then                                  -- (nested colours allowed: "Stamina 33 (25|cff…+8|r)")
        local b = W.ui_be(whole)
        if b then return c2 .. b .. "|r" end
    end
    return ui_fmt(t)
end
-- texts Blizzard joins with a blank line ("%s\n\n%s": the Spirit tooltip + SPIRIT_STANDING_WARNING, R535): when the
-- whole text is unknown, each split at a "\n\n" is tried — the left part known, the right part known (it may split again)
local KEY_WORDS = { Tab = "Tab", Space = "Прабел", Spacebar = "Прабел", Enter = "Enter", Escape = "Escape",
    Backspace = "Backspace", Delete = "Delete", Insert = "Insert", Home = "Home", End = "End" }
function W.ui_be(t, depth)
    -- R932: "Level 7 Undead (Player)" — the word is the player's RACE (Навец / Наўка), not the creature type «Наўе»
    local prl = W.player_race_line
    if type(t) == "string" and not prl then W.player_race_line = t:find("(Player)", 1, true) ~= nil end
    local be = ui_be_one(t)
    W.player_race_line = prl
    if be or type(t) ~= "string" then return be end
    depth = depth or 0
    local p = depth < 4 and plain(t)
    -- R961 (owner 2026-11-13): a label with its key binding, "Interact With Target (Z)", "Show nameplates for enemy units
    -- (V)", "World Map (M)": the label translates, the key stays as the keyboard has it (Space = «Прабел», R779)
    local base, key
    -- cheap guard first: ui_be runs on every label / tooltip line miss, and the lazy pattern backtracks on long texts
    if p and #p < 120 and p:byte(-1) == 41 then base, key = p:match("^(.-) %(([^()]+)%)$") end
    if base and (key:find("^[%u%d][%u%d%-]*$") or KEY_WORDS[key]) then
        local b = ui_be_one(base)
        if b then return b .. " (" .. (KEY_WORDS[key] or key) .. ")" end
    end
    if not (p and p:find("\n\n", 1, true)) then return nil end
    local pos = 1
    while true do
        local s = p:find("\n\n", pos, true)
        if not s then return nil end
        local a = ui_be_one(p:sub(1, s - 1))
        local b = a and W.ui_be(p:sub(s + 2), depth + 1)
        if b then return a .. "\n\n" .. b end
        pos = s + 2
    end
end
local ui_en = setmetatable({}, { __mode = "k" })       -- FontString -> original EN (for switching back)
function W.label_be(t)                               -- UI string, else an exact zone name (map nav bar)
    local be = W.ui_be(t) or (W.on("zones") and W.Z[t])
        or (W.channel_be and t:find("^%d+%.") and W.channel_be(t)) or nil
    if be then return be end
    -- an icon before the label: friends status menu "|T…StatusIcon-Online.tga:16:16:0:0|t Online" (R929)
    local icon, rest = t:match("^(|[TA].-|[ta]%s*)(.+)$")
    local rb = rest and W.ui_be(rest)
    return rb and (icon .. rb) or nil
end
-- inside the profession window only (owner 2026-09-28): recipe / item names, reagent lines "0/1 Soul Dust",
-- "Requires: Runed Silver Rod", "Light Armor Kit [2]", the recipe description (by the selected recipe's spell id).
-- Names only here: elsewhere a label that happens to equal a spell or item name must stay as it is.
local IE_ = WoWBY_ItemsEN or {}
local function item_or_spell(n)
    local c, inner, r = n:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
    local core = inner or n
    local be = (W.on("spells") and IE_[core]) or W.spell_name_be(core)
    return be and (c and (c .. be .. r) or be) or nil
end
-- colour codes (|cffRRGGBB, the new |cnNAME: form), |r, quality atlases |A…|a and icons |T…|t stripped: the words only
local function bare(t)
    return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", ""):gsub("|A.-|a", ""):gsub("|T.-|t", "")
             :gsub("^%s+", ""):gsub("%s+$", ""))
end
local function prof_be(t)
    local be = item_or_spell(t)
    if be then return be end
    if W.RU then t = W.en_line(t) end                -- «Требуется: X» → "Requires: X" (R665)
    local cnt, name = t:match("^(%d+/%d+) (.+)$")                      -- reagent "0/1 Soul Dust"
    if cnt then be = item_or_spell(name); if be then return cnt .. " " .. be end end
    -- same inside markup ("|cnGRAY_FONT_COLOR:0/1 Linen Cloth|r", a quality atlas after the name, R36): swap the
    -- plain name where it stands, keep everything around it
    local b = bare(t)
    local bname = b:match("^%d+/%d+ (.+)$") or b
    local bbe = bname ~= t and item_or_spell(bname)
    if bbe then
        local s, e = t:find(bname, 1, true)
        if s then return t:sub(1, s - 1) .. bbe .. t:sub(e + 1) end
    end
    if cnt then return nil end
    local nm, num = t:match("^(.-) (%[%d+%])$")                        -- "Light Armor Kit [2]"
    if nm then be = item_or_spell(nm); return be and (be .. " " .. num) or nil end
    local req = t:match("^Requires: (.+)$")
    if req then
        local parts = {}
        for piece in (req .. ", "):gmatch("(.-), ") do
            local b = item_or_spell(piece) or W.ui_be(piece)
            if not b then return nil end
            parts[#parts + 1] = b
        end
        return (W.ui_be("Requires:") or "Requires:") .. " " .. table.concat(parts, ", ")
    end
    -- coloured label ("|cffffd100Requires:|r Forge", R923) / pieces in red when the tool is missing
    if W.req_list_be then
        local rq = W.req_list_be(t)
        if rq then return rq end
    end
    local sf = _G.ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
    local info = sf and (sf.currentRecipeInfo or (sf.GetRecipeInfo and sf:GetRecipeInfo()))
    local rid = info and W.sid_ok(info.recipeID)
    local key = rid and (WoWBY_SpellDescKey or {})[rid]
    return key and W.render_desc(key, t) or nil
end
-- tracked recipes (R526): the objective tracker's Profession module — recipe header and "9/1 Light Leather" reagent
-- lines, named as in the profession window. Each FontString gets a SetText post-hook when first seen, so later
-- updates are Belarusian before the tracker measures them.
local rec_fs = setmetatable({}, { __mode = "k" })
local rec_busy = false
local function rec_swap(fs)
    if rec_busy or not (W.is_be() and W.on("spells")) then return end
    local t = plain(fs:GetText())
    local be = t and t ~= "" and prof_be(t)
    if be and be ~= t then rec_busy = true; W.swap(fs, be); rec_busy = false end
end
local function rec_hook(fs)
    if not fs then return end
    if not rec_fs[fs] then rec_fs[fs] = true; hooksecurefunc(fs, "SetText", rec_swap) end
    rec_swap(fs)
end
function W.hook_recipe_tracker()
    local m = _G.ProfessionsRecipeTracker
    if not (m and m.AddRecipe) then return end
    hooksecurefunc(m, "AddRecipe", function(self)
        for _, blocks in pairs(self.usedBlocks or {}) do
            for _, block in pairs(blocks) do
                rec_hook(block.HeaderText)
                for _, line in pairs(block.usedLines or {}) do rec_hook(line.Text) end
            end
        end
    end)
end
-- chat language menu (R110): languages as adjectives of «мова» (owner: Оркская, Траліная); menus only, because the same
-- EN words are races elsewhere ("Troll" = «Троль»)
local LANG = { Orcish = "Орцкая", Darnassian = "Дарнаская", Taurahe = "Таўраэ", Dwarvish = "Дварфійская",
               Common = "Агульная", Demonic = "Дэманічная", Titan = "Тытанічная", Thalassian = "Талаская",
               Draconic = "Драконавая", Kalimag = "Калімаг", Gnomish = "Гномская", Troll = "Траліная",
               Gutterspeak = "Наўская", Pandaren = "Пандарэнская", ["Shen'dorei"] = "Шэн'дарайская" }
if W.ru_alias then W.ru_alias(LANG, "ui") end         -- ruRU client: Russian language names (R665)
W.LANG = LANG                                         -- also the "You are fluent in…" spell lists (tooltips, R387)
-- auction house words that differ from the same EN elsewhere (R945, owner: "Deposit" here is the fee, glossary R790
-- «заклад»; the bank button "Deposit" stays «Пакласці»)
local AH_LABELS = { Deposit = "Заклад" }
local fs_ctx = setmetatable({}, { __mode = "k" })     -- FontString -> "prof" (profession window) / "names" (Legacy window)
-- recipe list rows (R654): ProfessionsRecipeListRecipeMixin:Init sizes the Label to the text it just set; rows made on
-- the first open are hooked only after that → the label kept the EN width («Простае вог…»). Re-measure as Init does.
local function fit_recipe_label(fs)
    local p = fs:GetParent()
    if not (p and p.Label == fs and p.SkillUps and p.Count and p.GetWidth) then return end
    local cw = p.Count:IsShown() and p.Count:GetStringWidth() or 0
    local rw = p.LockedIcon and p.LockedIcon:IsShown() and p.LockedIcon:GetWidth() or 0
    local width = p:GetWidth() - (rw + cw + 10 + p.SkillUps:GetWidth())
    fs:SetWidth(p:GetWidth())
    fs:SetWidth(math.min(width, fs:GetStringWidth()))
end
-- Legacy reward-track cards (R671): the reward name (RenownLevelMixin.RewardName, 120 px wide, no height) wraps onto two
-- lines when Blizzard sets a long name, but our swap of a short EN name kept the one-line height → «Гербавая накідка фр…».
-- Height re-fitted to the Belarusian text (a plain addon frame, not secure).
local function fit_reward_name(fs)
    local p = fs:GetParent()
    if not (p and p.RewardName == fs and fs.GetStringHeight) then return end
    if fs.SetMaxLines then fs:SetMaxLines(3) end
    fs:SetHeight(fs:GetStringHeight() + 1)
end
-- Key names in the keybinding list (R779, owner): Space and the mouse words translate; letters and keyboard names stay as
-- the keyboard has them. The shared UI words are wrong here: "Enter" = «Увайсці», "Delete" = «Выдаліць», "B" = «МЛРД».
local function is_key_button(fs)
    local ok, p = pcall(fs.GetParent, fs)
    if not ok or not p or not p.GetParent then return false end
    local ok2, row = pcall(p.GetParent, p)
    return ok2 and row and row.Buttons and (row.Button1 == p or row.Button2 == p) or false
end
local function key_be(t)
    if t:find("Mouse", 1, true) or t == _G.NOT_BOUND then return W.label_be(t) end
    local out = t:gsub("Spacebar", "Прабел"):gsub("%f[%a]Space%f[%A]", "Прабел")
    return out ~= t and out or nil
end
function W.retext_fs(fs, no_font)                    -- no_font: menu regions (SetFont is forbidden there)
    local t = plain(fs:GetText())
    if not t or t == "" then return end
    if t:find("^%a$") then return end                 -- a lone letter is a key name, never the "B" = billion abbreviation
    if W.on("ui") and is_key_button(fs) then
        local be = key_be(t)
        if be and be ~= t then ui_en[fs] = t; pcall(W.swap, fs, be) end
        return
    end
    if W.on("ui") then
        -- character sheet "Level 3 Druid" of a female character → «Друідка» (owner 2026-10-12, R442)
        W.current_tooltip_female = fs == _G.CharacterLevelText and UnitSex("player") == 3
        local be = (no_font and LANG[t]) or (fs_ctx[fs] == "ah" and AH_LABELS[t]) or W.label_be(t)
            or (fs_ctx[fs] == "prof" and prof_be(t))
            or (fs_ctx[fs] == "names" and item_or_spell(t))      -- Legacy window: reward items, tree talents (R273)
            -- Collections (R698): mount / pet / toy names in the lists and the detail header — mounts and toys are spell /
            -- item names, battle pets NPC names («Міні-Дыябла»)
            or (fs_ctx[fs] == "collections" and (item_or_spell(t) or (W.on("names") and W.N[t])))
        W.current_tooltip_female = false
        -- friends / recent allies rows (R927, owner): "Level 32 Shaman" was cut to «Узр.... Шаман» → «Узр. 32 Шаман»
        if be and (fs_ctx[fs] == "friends" or W.friend_row_fs == fs) then be = be:gsub("^Узровень (%d)", "Узр. %1") end
        if be and be ~= t then
            ui_en[fs] = t
            if not no_font then W.set_font(fs) end
            pcall(W.swap, fs, be)
            if fs_ctx[fs] == "prof" then pcall(fit_recipe_label, fs) end
            if fs_ctx[fs] == "names" then
                pcall(fit_reward_name, fs)
                C_Timer.After(0, function() pcall(fit_reward_name, fs) end)   -- the card may lay out after us
            end
        end
    elseif ui_en[fs] and t == W.label_be(ui_en[fs]) then
        pcall(fs.SetText, fs, ui_en[fs])
    end
end
-- No blink (owner 2026-09-25): every panel FontString gets a post-hook on SetText / SetFormattedText, so the
-- Belarusian text replaces Blizzard's English in the same call, before the frame is drawn. hooksecurefunc keeps
-- Blizzard's own calls secure; `fs_busy` stops our SetText from re-entering the hook.
local fs_hooked = setmetatable({}, { __mode = "k" })
local fs_busy = false
local function on_fs_set(fs)
    if fs_busy then return end
    fs_busy = true
    pcall(W.retext_fs, fs)
    fs_busy = false
end
-- R703 (owner: "Unwrap" in the collections window turned Belarusian a second late): Button:SetText writes the button's
-- label in C, past the FontString's own SetText hook, so only the 1 s panel ticker caught it → hook the BUTTON's
-- SetText too. Never on protected buttons (secure action buttons: a hooked method key there taints their clicks).
local btn_hooked = setmetatable({}, { __mode = "k" })
local function hook_fs(fs)
    if fs_hooked[fs] then return end
    fs_hooked[fs] = true
    pcall(hooksecurefunc, fs, "SetText", on_fs_set)
    pcall(hooksecurefunc, fs, "SetFormattedText", on_fs_set)
    local ok, p = pcall(fs.GetParent, fs)
    if ok and p and not btn_hooked[p] and p.GetFontString and p.SetText and p.IsProtected then
        local ok2, own = pcall(p.GetFontString, p)
        local ok3, prot = pcall(p.IsProtected, p)
        if ok2 and own == fs and ok3 and not prot then
            btn_hooked[p] = true
            pcall(hooksecurefunc, p, "SetText", function() on_fs_set(fs) end)
        end
    end
end
-- Settings → AddOns pages of OTHER addons (Wowhead Looter…) live under this canvas: left as their authors wrote
-- them (R289; a word-by-word swap left them half Belarusian). Our own page is Belarusian already.
local function other_addon_canvas(frame)
    local sp = _G.SettingsPanel
    return sp and sp.Container and frame == sp.Container.SettingsCanvas
end
local function retext_tree(frame, ctx)
    W.each_fs(frame, 12, function(r)
        if ctx then fs_ctx[r] = ctx end
        hook_fs(r)
        fs_busy = true; W.retext_fs(r); fs_busy = false
    end, other_addon_canvas)
end
-- (GameMenuFrame is not here: own hook-free pass, hook_game_menu — R29)
-- tab-system tabs (talent window Primary / Secondary, R225): the tab keeps its EN in self.tabText and UpdateTabText
-- re-applies it on every update → post-hook Init / UpdateTabText (mixin methods: the talent window loads after WoWBY)
-- plural = «таленты» (owner 2026-10-09, R277; were the singular «спецыялізацыя» forms)
local TAB_WORDS = { Primary = "Асноўныя", Secondary = "Дадатковыя" }
-- a disabled tab's red reason (TALENT_SPEC_LOCKED "Locked") in the tab's own tooltip; elsewhere "Locked" stays
-- «Заблакаваная» (lockboxes); the tab state is the neuter «Заблакавана» (owner 2026-10-09, R294: like «Магчымасць»)
local TAB_REASON = { Locked = "Заблакавана" }
if W.ru_alias then W.ru_alias(TAB_WORDS, "ui"); W.ru_alias(TAB_REASON, "ui") end
local tabs_hooked = false
function W.hook_tabs()
    local M = _G.TabSystemButtonMixin
    if tabs_hooked or not M then return end
    tabs_hooked = true
    local function fix(self)
        if not (W.is_be() and W.on("ui")) then return end
        local en = plain(self.tabText)
        local be = en and (TAB_WORDS[en] or W.ui_be(en))
        if not (be and be ~= en and self.Text) then return end
        if self.IsForceDisabled and self:IsForceDisabled() then be = DISABLED_FONT_COLOR:WrapTextInColorCode(be) end
        W.set_font(self.Text); W.swap(self.Text, be)
        if self.UpdateTabWidth then pcall(self.UpdateTabWidth, self) end
    end
    for _, m in ipairs({ "Init", "UpdateTabText" }) do
        if M[m] then hooksecurefunc(M, m, function(self) pcall(fix, self) end) end
    end
    if M.OnEnter then
        hooksecurefunc(M, "OnEnter", function(self)
            if not (W.is_be() and W.on("ui")) then return end
            local en = plain(self.errorReason)
            local be = en and TAB_REASON[en]
            local fs = be and _G.GameTooltipTextLeft1
            if fs and GameTooltip:IsShown() and GameTooltip:GetOwner() == self then
                local t = plain(fs:GetText())
                if t == en or t == W.ui_be(en) then W.swap(fs, be); GameTooltip:Show() end
            end
        end)
    end
end
local PANELS = { "SettingsPanel", "CharacterFrame", "FriendsFrame", "MerchantFrame", "ChatConfigFrame",
                 "MailFrame", "OpenMailFrame", "BankFrame", "QuestMapFrame", "WorldMapFrame.BorderFrame", "WorldMapFrame.NavBar",
                 -- (NOT AddonList: its Reload button got "Interface action failed because of an AddOn" — ReloadUI is
                 -- protected, 2026-09-28)
                 "PlayerSpellsFrame", "SpellBookFrame", "ProfessionsBookFrame", "CommunitiesFrame", "PVEFrame",
                 "CollectionsJournal", "AchievementFrame", "EncounterJournal", "TradeFrame", "HelpFrame",
                 "MacroFrame", "GossipFrame", "ContainerFrameCombinedBags", "LootFrame", "TaxiFrame",
                 "GuildRegistrarFrame", "TabardFrame",           -- R638: guild charter / tabard (strings were in the dict)
                 "GuildInviteFrame",                         -- R892: guild invite popup (Join Guild / Decline Invitation)
                 "ClassTrainerFrame", "InspectFrame", "GuildBankFrame", "AuctionHouseFrame", "CalendarFrame",
                 "TimeManagerFrame", "StopwatchFrame",                       -- clock settings (load-on-demand)
                 "ProfessionsFrame",                         -- crafting window (load-on-demand; names via prof_be)
                 "LFGParentFrame",                           -- group finder (Forever vanilla-style, R225)
                 "ChannelFrame",                             -- Chat Channels window (Blizzard_Channels, R249)
                 "LegacySystemFrame",                        -- Legacy challenges / tree / reward track (R273)
                 "SocialUIFrame",                            -- new social window: Friends / Recent Allies / Requests / Raid (R316)
                 "CombatLogQuickButtonFrame_Custom",         -- combat log filter tabs «Мае дзеянні» … (Blizzard_CombatLog, R333)
                 -- new-player tutorial (R684, owner screenshot from the stress-test client): "Position your hands and
                 -- click Okay", "Played World of Warcraft before?" + Skip Tutorial, movement / key hints — the strings
                 -- were in the UI dictionary, the frames were never walked (ResizeLayoutFrames: the per-string SetText
                 -- hooks swap before they measure)
                 "TutorialKeyboardMouseFrame_Frame", "TutorialWalk_Frame", "TutorialMainFrame_Frame",
                 "TutorialSingleKey_Frame", "TutorialDoubleKey_Frame", "NPE_TutorialMainFrame_Frame",
                 "NPE_TutorialKeyboardMouseFrame_Frame", "NPE_TutorialInterfaceHelp",
                 "PingSystemTutorial",                       -- R701: "Press the Ping key…" tutorial window
                 "ActionStatus",                             -- R712: "Screen Captured" (screenshot notice)
                 "QuestTimerFrame", "QuestInfoTimerFrame",   -- R810: the timer box above the tracker, "Time Remaining:" in the log
                 -- R740: barbershop (load-on-demand): option labels "Hair Style" / "Beard" and the selected style name
                 -- (ChrCustomization* / BarberShopStyle via the UI dictionary; the style lists are Blizzard_Menu rows)
                 "BarberShopFrame", "CharCustomizeFrame",
                 -- (NOT CommunitiesAddDialog: a FORBIDDEN frame — HookScript / IsShown raised errors, R243)
                 }
function W.resolve(path)
    local o = _G
    for part in path:gmatch("[^%.]+") do o = o and o[part] end
    return o
end
function W.run_panel(frame, hidden_ok)               -- walks the tree: hooks new FontStrings, translates them
    local ctx = frame and (frame == _G.ProfessionsFrame and "prof" or frame == _G.LegacySystemFrame and "names"
                           or frame == _G.CollectionsJournal and "collections"
                           or frame == _G.FriendsFrame and "friends"
                           or frame == _G.AuctionHouseFrame and "ah") or nil
    if frame and frame.IsForbidden and frame:IsForbidden() then return end          -- R243: forbidden frames
    if frame and (hidden_ok or frame:IsShown()) and not InCombatLockdown() then retext_tree(frame, ctx) end
end
W.hooked = {}
local tickers = {}
-- world map title + nav bar home button (owner 2026-09-29: "Map & Quest Log", "World" stayed English although the
-- BorderFrame/NavBar trees are in PANELS): direct post-hooks, as WowUkrainizer (SetTitle, NavBar:Refresh)
local map_hooked = false
local function map_retext()
    local bf = _G.WorldMapFrame and WorldMapFrame.BorderFrame
    local tt = bf and bf.GetTitleText and bf:GetTitleText()
    if tt then W.retext_fs(tt) end
    local nb = WorldMapFrame and WorldMapFrame.NavBar
    local hb = nb and nb.homeButton
    if hb and hb.text then W.retext_fs(hb.text) end
    -- R607: the breadcrumb buttons (continent > zone) — names came translated from the C_Map wraps before
    for _, b in ipairs(nb and nb.navList or {}) do
        local fs = b ~= hb and (b.text or (b.GetFontString and b:GetFontString()))
        if fs then W.retext_fs(fs) end
    end
    -- the hover area label at the top of the map ("Durotar" / "Razor Hill" + level range)
    if W.hook_area_label then W.hook_area_label() end
end
local function hook_worldmap()
    if map_hooked or not (_G.WorldMapFrame and WorldMapFrame.BorderFrame) then return end
    map_hooked = true
    if WorldMapFrame.BorderFrame.SetTitle then hooksecurefunc(WorldMapFrame.BorderFrame, "SetTitle", map_retext) end
    if WorldMapFrame.NavBar and WorldMapFrame.NavBar.Refresh then hooksecurefunc(WorldMapFrame.NavBar, "Refresh", map_retext) end
    WorldMapFrame:HookScript("OnShow", function() C_Timer.After(0, map_retext) end)   -- not mid secure path (R29)
    map_retext()
end
-- Esc menu (R29 follow-up, 2026-09-29): Edit Mode is opened from here, and entering it still errored in the party
-- frames "tainted by WoWBY" after the deferral. So the game menu gets NO per-FontString hooks, no InitButtons hook,
-- no keys of ours at all: after it shows (next frame) each button's text is swapped with a plain Button:SetText.
local game_menu_hooked = false
local function tr_game_menu()
    local gm = _G.GameMenuFrame
    if not (gm and gm:IsShown() and W.is_be() and W.on("ui")) then return end
    for _, b in ipairs({ gm:GetChildren() }) do
        local t = b.GetText and b:GetObjectType() == "Button" and plain(b:GetText())
        local be = t and t ~= "" and W.ui_be(t)
        if be and be ~= t then pcall(b.SetText, b, be) end
    end
    local h = gm.Header and gm.Header.Text
    local ht = h and plain(h:GetText())
    local hbe = ht and W.ui_be(ht)
    if hbe and hbe ~= ht then pcall(h.SetText, h, hbe) end
end
local function hook_game_menu()
    if game_menu_hooked or not _G.GameMenuFrame then return end
    game_menu_hooked = true
    GameMenuFrame:HookScript("OnShow", function() C_Timer.After(0, tr_game_menu) end)
end
-- profession Create / Create All buttons (R34): Blizzard sets them with Button:SetTextToFit, which bypasses our
-- FontString hooks, so only the 1 s panel ticker swapped them back → slow EN/BE blinking. Post-hook the page's own
-- ValidateControls (it sets both) and swap in the same frame (SetTextToFit keeps the button fitted to the text).
local prof_btn_hooked = false
local function tr_prof_buttons(page)
    if not (W.is_be() and W.on("ui")) then return end
    for _, k in ipairs({ "CreateButton", "CreateAllButton" }) do
        local b = page and page[k]
        local t = b and b.GetText and plain(b:GetText())
        local be = t and t ~= "" and W.ui_be(t)
        if be and be ~= t then
            if b.SetTextToFit then pcall(b.SetTextToFit, b, be) else pcall(b.SetText, b, be) end
        end
    end
end
local function hook_prof_buttons()
    local page = _G.ProfessionsFrame and ProfessionsFrame.CraftingPage
    if prof_btn_hooked or not (page and page.ValidateControls) then return end
    prof_btn_hooked = true
    hooksecurefunc(page, "ValidateControls", function(self) pcall(tr_prof_buttons, self) end)
    -- R924 (owner: the "special tool" tooltip over «Патрабуецца: Крэмень і трут» vanished at once): Blizzard re-sets
    -- the tools line on every Update; EN → our BE is a text change, the engine drops the hovered link (OnHyperlinkLeave
    -- → tooltip hidden). The form is a plain frame: re-open the tooltip next frame while the mouse is still on that line.
    local sf = page.SchematicForm
    if sf and sf.HookScript and sf.OnHyperlinkEnter then
        local last
        sf:HookScript("OnHyperlinkEnter", function(_, ...) last = { ... } end)
        sf:HookScript("OnHyperlinkLeave", function(self)
            local a = last
            if not a then return end
            C_Timer.After(0, function()
                local fs, left, width = a[3], tonumber(a[4]), tonumber(a[6])
                local over = fs and fs.IsMouseOver and fs:IsVisible() and fs:IsMouseOver()
                if over and left and width and fs:GetLeft() then
                    -- still on the LINK part (not the «Патрабуецца:» label): a real leave must not re-open it
                    local x = GetCursorPosition() / fs:GetEffectiveScale() - fs:GetLeft()
                    over = x >= left - 2 and x <= left + width + 2
                end
                if over and not GameTooltip:IsShown() then
                    pcall(self.OnHyperlinkEnter, self, unpack(a))
                else
                    last = nil
                end
            end)
        end)
    end
    -- linked profession title "Enchanting |cffffffff[Nitamina]|r" (R373): TRADE_SKILL_TITLE + the player's name in white
    -- → the profession part swapped, the name kept
    if ProfessionsFrame.SetTitle then
        hooksecurefunc(ProfessionsFrame, "SetTitle", function(self)
            local fs = self.TitleContainer and self.TitleContainer.TitleText or (self.GetTitleText and self:GetTitleText())
            local t = W.is_be() and fs and fs.GetText and plain(fs:GetText())
            if not t then return end
            -- (two captures: never "t and t:match(…)" — an `and` keeps only the first value; the colour may be absent)
            local head, tail = t:match("^(.-)( [^%[]*%[.+%].*)$")
            local be = head and tail and W.ui_be(head)
            if be and be ~= head then W.swap(fs, be .. tail) end
        end)
    end
end
-- tutorial hint boxes with an arrow ("You died. Click Release Spirit to continue.", R689): TutorialPointerFrame /
-- NPE_TutorialPointerFrame (plain Lua tables of the tutorial addons) :Show sets the text and sizes the box from it in
-- the same call → post-hook: swap the text, then size the box exactly as Show does (max width 200 or overrideWidth)
local pointer_hooked = {}
local function fit_pointer(f, max_w)
    local t = f.Content.Text
    t:SetWidth(max_w)
    local w = math.min(t:GetStringWidth(), max_w) + 40
    f.Content:SetHeight(t:GetHeight() + 40)
    f.Content:SetWidth(w)
end
function W.hook_tutorial_pointers()
    for _, name in ipairs({ "TutorialPointerFrame", "NPE_TutorialPointerFrame" }) do
        local M = _G[name]
        if type(M) == "table" and M.Show and M.InUseFrames and not pointer_hooked[name] then
            pointer_hooked[name] = true
            hooksecurefunc(M, "Show", function(self, content, _, _, _, _, _, _, override_w)
                if not (W.is_be() and W.on("ui")) then return end
                local f = self.InUseFrames and self.NextID and self.InUseFrames[self.NextID - 1]
                local t = f and f.Content and f.Content.Text
                local en = t and plain(t:GetText())
                local be = en and en ~= "" and W.ui_be(en)
                if be and be ~= en then
                    W.set_font(t); W.swap(t, be)
                    pcall(fit_pointer, f, override_w or 200)
                end
            end)
        end
    end
end
-- world map coordinates "Cursor: 39.5, 51.1" / "Player: 45.0, 45.4 (Zone)" (R700): WorldMapCoordsPanel rewrites its labels
-- every frame with SetFormattedText; the panel is an unnamed map overlay → found among the map's children by its keys
local coords_hooked = false
local function hook_map_coords()
    local wm = _G.WorldMapFrame
    if coords_hooked or not (wm and wm.GetChildren) then return end
    local panel
    for _, c in ipairs({ wm:GetChildren() }) do
        if c.PlayerCoords and c.CursorCoords then panel = c; break end
    end
    if not panel then return end
    coords_hooked = true
    local busy = false
    local function swap(fs)
        if busy or not (W.is_be() and W.on("ui")) then return end
        local t = plain(fs:GetText())
        local be = t and t ~= "" and W.ui_be(t)
        if be and be ~= t then busy = true; pcall(fs.SetText, fs, be); busy = false end
    end
    for _, k in ipairs({ "PlayerCoords", "CursorCoords" }) do
        local l = panel[k] and panel[k].Label
        if l then
            hooksecurefunc(l, "SetFormattedText", swap)
            hooksecurefunc(l, "SetText", swap)
        end
    end
end
-- damage meter window titles ("Damage Done" → «…», R702): DamageMeter is an Edit Mode system frame — no hooks on it
-- (R607); a 1 s ticker out of combat swaps each session window's type name with plain SetText, like the Target names
local dm_ticker
function W.hook_damage_meter()
    local dm = _G.DamageMeter
    if dm_ticker or not (dm and dm.ForEachSessionWindow) then return end
    dm_ticker = C_Timer.NewTicker(1, function()
        if InCombatLockdown() or not (W.is_be() and W.on("ui")) or not dm:IsShown() then return end
        pcall(dm.ForEachSessionWindow, dm, function(w)
            local fs = w.GetDamageMeterTypeName and w:GetDamageMeterTypeName()
            local t = fs and plain(fs:GetText())
            local be = t and t ~= "" and W.ui_be(t)
            if be and be ~= t then W.swap(fs, be) end
        end)
    end)
end
function W.hook_panels()
    pcall(hook_map_coords)
    hook_worldmap()
    hook_prof_buttons()
    for _, path in ipairs(PANELS) do
        local fr = not W.hooked[path] and W.resolve(path)
        if fr and fr.IsForbidden and fr:IsForbidden() then fr = nil end              -- R243
        if fr and fr.HookScript then
            W.hooked[path] = true
            W.run_panel(fr, true)                           -- pre-scan while hidden: first open is already Belarusian
            fr:HookScript("OnShow", function(self)
                -- NOT synchronously (R29, 2026-09-29): panels are shown from secure paths too (Edit Mode exit hides
                -- its panel → UIParentPanelManager re-shows others → our walk hooked/wrote FontStrings mid-path and
                -- the party frames then compared secret colours "tainted by WoWBY"). Next frame = outside that path;
                -- the hidden pre-scan and the per-string SetText hooks keep the first draw Belarusian.
                C_Timer.After(0, function() W.run_panel(self) end)
                if tickers[path] then tickers[path]:Cancel() end
                -- new rows only (scroll lists, tabs built later); hooked strings translate themselves
                tickers[path] = C_Timer.NewTicker(1, function() W.run_panel(self) end)
            end)
            fr:HookScript("OnHide", function() if tickers[path] then tickers[path]:Cancel(); tickers[path] = nil end end)
        end
    end
    hook_game_menu()
end

-- bag window titles (owner 2026-09-26): ContainerFrameMixin:UpdateName sets the title from the bag's item name
-- ("Small Brown Pouch") or a UI word ("Backpack", combined "Bags"). Post-hook each bag window: item by ID
-- (WoWBY_Items), then by EN name (WoWBY_ItemsEN), then the UI dictionary. Display only.

-- confirmation popups (R162): "Abandon "Vanquish the Betrayers"?" + Yes / No. Post-hook on the GLOBAL StaticPopup_Show
-- (no fields written into the dialog; no re-layout call, so protected OnAccept actions stay untainted). A quest title
-- inside the text is swapped to Belarusian first (quest log), then the whole line goes through ui_be.
-- countdown popups (exit / logout «20 секунд», R337): Blizzard rewrites the text EVERY frame (StaticPopup_OnUpdate →
-- GetExpirationText) → a script hook on each pooled dialog (once, tracked here; no Lua field written into the frame)
-- re-translates the text right after the rewrite, only when it changed
local popup_tick = setmetatable({}, { __mode = "k" })
local function hook_popup_tick(dialog)
    if popup_tick[dialog] or not dialog.HookScript then return end
    popup_tick[dialog] = { last = nil }
    dialog:HookScript("OnUpdate", function(self)
        if not (W.is_be() and W.on("ui")) then return end
        -- buttons too (R403: the DEATH popup re-sets «Release Spirit» in its own OnUpdate, after our show-time swap)
        for _, b in ipairs(self.GetButtons and self:GetButtons() or {}) do
            local bt = b.GetText and plain(b:GetText())
            if bt and bt ~= "" and not W.ours(bt) then
                local bb = W.ui_be(bt)
                if bb and bb ~= bt then W.swap(b, bb) end
            end
        end
        local fs = self.GetTextFontString and self:GetTextFontString()
        local t = fs and plain(fs:GetText())
        if not t or t == "" or t == popup_tick[self].last then return end
        W.any_name = true
        local ok, be = pcall(W.ui_be, t)
        W.any_name = false
        be = ok and be or nil
        if be and be ~= t then W.set_font(fs); W.swap(fs, be); popup_tick[self].last = be else popup_tick[self].last = t end
    end)
end
local function tr_popup(which, data)
    if not (W.is_be() and W.on("ui") and StaticPopup_FindVisible) then return end
    -- dialogs that can show several at once (GENERIC_CONFIRMATION: the sell-all-junk question, R456) match by data
    local dialog = StaticPopup_FindVisible(which) or StaticPopup_FindVisible(which, data)
    if not dialog then return end
    hook_popup_tick(dialog)
    local fs = dialog.GetTextFontString and dialog:GetTextFontString()
    local t = fs and plain(fs:GetText())
    if t and t ~= "" then
        local t2 = t
        if W.on("quests") and C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
            for i = 1, C_QuestLog.GetNumQuestLogEntries() do
                local info = C_QuestLog.GetInfo(i)
                local en = info and not info.isHeader and info.questID and plain(info.title)
                if en and #en > 3 then
                    local s, e = t2:find(en, 1, true)
                    if s then t2 = t2:sub(1, s - 1) .. W.be_title(info.questID) .. t2:sub(e + 1) end
                end
            end
        end
        -- a player's name inside ("%s invites you to a group.", R556) is accepted as a name capture
        W.any_name = true
        local ok, be = pcall(W.ui_be, t2)
        W.any_name = false
        be = (ok and be) or (t2 ~= t and t2) or nil
        if be and be ~= t then W.set_font(fs); W.swap(fs, be) end
    end
    for _, b in ipairs(dialog.GetButtons and dialog:GetButtons() or {}) do
        local bt = b.GetText and plain(b:GetText())
        local be = bt and bt ~= "" and W.ui_be(bt)
        if be and be ~= bt then W.swap(b, be) end
    end
end
local popup_hooked = false
-- ping wheel (R582): PingFrame is a FORBIDDEN frame ("Attempt to access forbidden object" on HookScript at every
-- login, 2026-10-15) → addons cannot touch it; its labels stay English
function W.hook_popups()
    if popup_hooked or not _G.StaticPopup_Show then return end
    popup_hooked = true
    hooksecurefunc("StaticPopup_Show", function(which, _, _, data) pcall(tr_popup, which, data) end)
end

-- world refresh / shard transfer (R168): the corner notice (ShardTransferImminentFrame) and the countdown popup
-- (SHARD_TRANSFER_IMMINENT_EVENT) rewrite their English text every frame → HookScript("OnUpdate") on those frames
-- (a script hook, no Lua fields written) swaps it right after. Units after «праз» take the accusative plural rules.
local function units_acc(n, raw)
    local sec = raw:find("Second") ~= nil
    local m10, m100 = n % 10, n % 100
    local i = (m10 == 1 and m100 ~= 11) and 1 or ((m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14)) and 2 or 3)
    return sec and ({ "секунду", "секунды", "секунд" })[i] or ({ "хвіліну", "хвіліны", "хвілін" })[i]
end
function W.shard_be(t)
    t = plain(t)
    if t and W.RU then t = W.en_line(t) end
    if not (t and W.is_be() and W.on("ui")) then return nil end
    if t:find("^Refreshing your world at any time") then
        return "Свет вакол вас абнаўляецца. Персанажы і істоты побач могуць змяніцца."
    end
    -- the corner toast (SHARD_TRANSFER_REFRESH_MESSAGE "World refresh in %s %s", R221)
    local wn, wunit = t:match("^World refresh in (%d+) (%a+)$")
    if wn then return "Абнаўленне свету праз " .. wn .. " " .. units_acc(tonumber(wn), wunit) end
    local n, unit, rest = t:match("^The world around you will refresh in (%d+) (.-)([%.]?%s*Make sure.*)$")
    if not n then n, unit = t:match("^The world around you will refresh in (%d+) (.+)$") end
    if not n then return nil end
    local be = "Свет вакол вас абновіцца праз " .. n .. " " .. units_acc(tonumber(n), unit)
    if rest then be = be .. ". Пераканайцеся, што вы не ў баі і ў бяспечным месцы, або абнавіце свет зараз." end
    return be
end
local shard_hooked = false
function W.hook_shard()
    if shard_hooked then return end
    shard_hooked = true
    local toast = _G.ShardTransferImminentFrame
    if toast and toast.HookScript then
        toast:HookScript("OnUpdate", function(self)
            local fs = self.Text
            local be = fs and W.shard_be(fs:GetText())
            if be then W.swap(fs, be); self:SetHeight(fs:GetStringHeight() + 20) end
        end)
    end
    for i = 1, 4 do
        local d = _G["StaticPopup" .. i]
        if d and d.HookScript then
            d:HookScript("OnUpdate", function(self)
                if self.which ~= "SHARD_TRANSFER_IMMINENT_EVENT" and self.which ~= "SHARD_TRANSFER_IMMEDIATE" then return end
                local fs = self.GetTextFontString and self:GetTextFontString()
                local be = fs and W.shard_be(fs:GetText())
                if be then W.set_font(fs); W.swap(fs, be) end
            end)
        end
    end
end
