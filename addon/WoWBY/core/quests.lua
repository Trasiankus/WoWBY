-- WoWBY/core/quests.lua — quest text, DialogueUI quest data, gossip, objectives, quest frames, quest log, tracker.
-- Split from core.lua (tools/split_core.py); shared state lives in the addon namespace W.
local _, W = ...
-- ---------- quest text getters (QuestInfo / QuestFrame call these globals in mainline) ----------
local orig = {}

-- ---------- text variants by the player's sex / race (R510) ----------
-- A field can come in several versions (842's completion: women get another paragraph) and our sources hold one, so a
-- woman would read the Belarusian of the men's text. WoWBY_QSig (tools/quest_sig.py, split + hash must stay identical)
-- = the English each translation was made from: "h,h;h|h,h", per source (|) per paragraph (;) up to 2 sentence hashes.
-- A source is there when each of its paragraphs has a sentence in the live text. No source there → a real variant: the
-- live English is shown and harvested as field#hash, next to the normal entry. Decided once per quest + field + text.
local QSIG = WoWBY_QSig or {}
local SIG_MOD = 2147483647
local SIG_MIN = 20
local function sig_letters(s) return (s:lower():gsub("[^a-z]", "")) end
local function sent_hash(n)
    local h = 0
    for i = 1, #n do h = (h * 31 + n:byte(i)) % SIG_MOD end
    return h
end
local function sent_set(text)
    local set = {}
    for s in text:gsub("%$[Bb]", "\n"):gmatch("[^%.!%?\r\n]+") do
        local n = sig_letters(s)
        if #n >= SIG_MIN then set[tostring(sent_hash(n))] = true end
    end
    return set
end
local function source_there(src, set)
    for para in src:gmatch("[^;]+") do
        local hit = false
        for h in para:gmatch("%d+") do
            if set[h] then hit = true; break end
        end
        if not hit then return false end
    end
    return true
end
local function sig_differs(sig, text)
    if sig_letters(text) == "" then return false end       -- GetProgressText etc. outside their stage can be empty
    local set = sent_set(text)
    for src in sig:gmatch("[^|]+") do
        if source_there(src, set) then return false end
    end
    return true
end
local variant_seen = {}
-- `harvest` only where the text is sure to be the shown one: outside its stage a getter may hold another quest's text
function W.quest_variant(qid, field, text, harvest)
    local en = GetLocale and GetLocale()
    if W.RU or not (en == "enUS" or en == "enGB") then return false end      -- the sources are English
    local q = qid and QSIG[qid]
    local sig = q and q[field]
    local t = sig and plain(text)
    if not t then return false end
    local key = qid .. field
    local c = variant_seen[key]
    if not c or c.t ~= t then
        c = { t = t, v = sig_differs(sig, t) }
        variant_seen[key] = c
    end
    if c.v and harvest and not c.kept then
        c.kept = true
        local tokens = W.player_tokens and W.player_tokens(t) or t
        W.harvest_quest(qid, field .. "#" .. sent_hash(sig_letters(tokens)), t)
    end
    return c.v
end

local function wrap(name, field)
    orig[name] = _G[name]
    if not orig[name] then return end
    _G[name] = function(...)
        local text = orig[name](...)
        if type(text) == "string" then
            local qid = GetQuestID and GetQuestID()
            if W.needs_harvest(qid, field) then W.harvest_quest(qid, field, text) end
            if W.is_be() then
                local e = W.entry_for(qid)
                if e and e[field] and not W.quest_variant(qid, field, text) then return W.substitute(e[field], qid, text) end
            end
        end
        return text
    end
end
wrap("GetTitleText",     "t")
wrap("GetQuestText",     "d")
wrap("GetObjectiveText", "o")
wrap("GetProgressText",  "p")
wrap("GetRewardText",    "c")

-- the variant harvest (R510) at the stage's own event: the getter holds this quest's text, with or without DialogueUI
local STAGE_FIELD = { QUEST_DETAIL = { "d", "GetQuestText" }, QUEST_PROGRESS = { "p", "GetProgressText" },
                      QUEST_COMPLETE = { "c", "GetRewardText" } }
function W.quest_variant_event(event)
    local st = STAGE_FIELD[event]
    local get = st and orig[st[2]]
    local qid = get and GetQuestID and GetQuestID()
    local e = qid and qid ~= 0 and W.Q[tostring(qid)]
    if e and e[st[1]] then W.quest_variant(qid, st[1], get(), true) end
end

-- ---------- DialogueUI (optional; Peterodox) ----------
-- DialogueUI captures the quest getters before WoWBY loads, so our wraps never reach it. It has an official
-- translator interface instead (DialogueUIAPI.SetTranslator, as WowUkrainizer uses): it shows our text under /
-- instead of the English, with its own toggle button. Everything here is skipped when DialogueUI is absent.
local DUI_FIELDS = { { "title", "t", "GetTitleText" }, { "description", "d", "GetQuestText" },
                     { "objective", "o", "GetObjectiveText" }, { "progress", "p", "GetProgressText" },
                     { "completion", "c", "GetRewardText" } }
function W.dui_quest_data(qid)
    local current = GetQuestID and GetQuestID() == qid
    if current then                                                      -- our wraps harvest untranslated fields
        for _, f in ipairs(DUI_FIELDS) do if _G[f[3]] then pcall(_G[f[3]]) end end
    end
    if not (W.is_be() and W.on("quests")) then return nil end
    local e = W.entry_for(qid)
    if not e then return nil end
    local out = {}
    for _, f in ipairs(DUI_FIELDS) do
        local en = current and orig[f[3]] and orig[f[3]]() or nil
        if e[f[2]] then
            -- no live text (not the quest in the dialog): nothing to compare, the translation stands
            if type(en) == "string" and W.quest_variant(qid, f[2], en) then
                out[f[1]] = en                                   -- R510: DialogueUI shows this field in English
            else
                out[f[1]] = W.substitute(e[f[2]], qid, type(en) == "string" and en or nil)
            end
        end
    end
    return out.title and out or nil
end

-- quest log details / tooltips: GetQuestLogQuestText([questLogIndex]) -> description, objectives
orig.GetQuestLogQuestText = GetQuestLogQuestText
if orig.GetQuestLogQuestText then
    _G.GetQuestLogQuestText = function(idx, ...)
        local desc, obj = orig.GetQuestLogQuestText(idx, ...)
        local qid
        if idx and C_QuestLog.GetQuestIDForLogIndex then qid = C_QuestLog.GetQuestIDForLogIndex(idx) end
        qid = qid or (C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest())
        if W.needs_harvest(qid, "d") then W.harvest_quest(qid, "d", desc) end
        if W.needs_harvest(qid, "o") then W.harvest_quest(qid, "o", obj) end
        if W.is_be() then
            local e = W.entry_for(qid)
            if e then
                if e.d and type(desc) == "string" and not W.quest_variant(qid, "d", desc, true) then
                    desc = W.substitute(e.d, qid, desc)
                end
                if e.o and type(obj) == "string" then obj = W.substitute(e.o, qid, obj) end
                local box = QuestScrollFrame and QuestScrollFrame.SearchBox
                local q = box and box.GetText and plain(box:GetText())
                if q and q ~= "" and type(obj) == "string" and debugstack and (debugstack(2, 2, 0) or ""):find("Matches") then
                    local t = W.be_title(qid) or ""
                    obj = obj .. "\n" .. t .. "\n" .. cyr_lower(t .. " " .. obj .. " " .. (desc or ""))
                end
            end
        end
        return desc, obj
    end
end

-- ---------- gossip (text by EN match; quest titles by questID) ----------
local function tr_gossip(t)
    if type(t) == "string" and t ~= "" then
        local b = W.gossip_be(t)
        if not b then W.harvest("gossip", t, W.npc_key()) end
        if b and W.on("quests") then return W.substitute(b) end
    end
    return t
end
local function tr_gossip_quests(t)
    if W.is_be() and type(t) == "table" then
        for _, q in ipairs(t) do
            local be = q.questID and W.be_title(q.questID)
            if be then q.title = be end
        end
    end
    return t
end
if C_GossipInfo then
    -- options ("The Bank", "The Inn"…): by exact EN in the gossip table (data/gossip_fix.tsv + translations);
    -- misses are harvested like gossip text
    local function tr_gossip_options(t)
        if type(t) ~= "table" then return t end
        for _, o in ipairs(t) do
            local nm = type(o) == "table" and plain(o.name)
            if nm and nm ~= "" then
                local b = W.gossip_be(nm)
                if not b then W.harvest("gossip", nm, W.npc_key()) end
                if b and W.is_be() and W.on("quests") then o.name = W.substitute(b) end
            end
        end
        return t
    end
    for fn, tr in pairs({ GetText = tr_gossip, GetAvailableQuests = tr_gossip_quests, GetActiveQuests = tr_gossip_quests,
                          GetOptions = tr_gossip_options }) do
        local o = C_GossipInfo[fn]
        if o then C_GossipInfo[fn] = function(...) return tr(o(...)) end end
    end
end

-- ---------- objective lines ("0/7 Gnarlpine Mystic slain", "0/1 Tallonkai's Jewel") ----------
-- Server text, so no stable key: split the counter, translate the name via NPC names / item names.
-- Kills: count first like every other line (owner 2026-10-16, R606; before: RU order «X — забіта: 0/1», R322):
-- «0/6 Забіта: Заклінальнік буры Ал'Акет» — the impersonal «Забіта» never has to agree with the NPC's sex or the
-- number. Items / places: «0/1 X».
W.IE = WoWBY_ItemsEN or {}
local OBJ_VERBS = { slain = "Забіта", killed = "Забіта", destroyed = "Знішчана", defeated = "Пераможана",
                    rescued = "Выратавана", freed = "Вызвалена", captured = "Схоплена", burned = "Спалена",
                    cleansed = "Ачышчана", purified = "Ачышчана", banished = "Выгнана",
                    exterminated = "Знішчана", eliminated = "Знішчана",   -- R633: "0/8 Enchanted Skyhopper Exterminated"
                    healed = "Вылечана", saved = "Выратавана", revived = "Ажыўлена", resurrected = "Уваскрэшана",
                    slaughtered = "Забіта", vanquished = "Пераможана", subdued = "Утаймавана", tamed = "Прыручана",
                    calmed = "Супакоена", fed = "Накормлена", awakened = "Абуджана", released = "Вызвалена" }
                    -- R841: "0/5 Injured Deathguard healed"
-- R846: "<action> <name>" objective lines (Lua patterns; longest first where one is a prefix of another)
local OBJ_ACTIONS = { { "Offer aid to", "Дапамагчы" }, { "Talk to", "Паразмаўляць" }, { "Speak to", "Паразмаўляць" },
                      { "Help", "Дапамагчы" }, { "Aid", "Дапамагчы" }, { "Rescue", "Выратаваць" }, { "Free", "Вызваліць" },
                      { "Heal", "Вылечыць" }, { "Comfort", "Суцешыць" }, { "Protect", "Абараніць" }, { "Defend", "Абараніць" },
                      { "Escort", "Суправаджаць" }, { "Locate", "Знайсці" }, { "Inspect", "Агледзець" },
                      { "Examine", "Агледзець" }, { "Investigate", "Даследаваць" }, { "Kill", "Забіць" }, { "Slay", "Забіць" },
                      { "Defeat", "Перамагчы" }, { "Report to", "Далажыць" }, { "Return to", "Вярнуцца" },
                      { "Visit", "Наведаць" }, { "Greet", "Павітаць" }, { "Wake", "Абудзіць" }, { "Awaken", "Абудзіць" } }
local LOC_VOWEL = {}            -- a name ending in a vowel takes «ў» (UTF-8: each Cyrillic letter is 2 bytes)
for v in ("аеёіоуыэюя"):gmatch("[\208\209][\128-\191]") do LOC_VOWEL[v] = true end
local function verb_line(cnt, word, be) return cnt .. " " .. word .. ": " .. be end
local function obj_name(nm)
    -- WoWBY_Objectives: places / things from the translated harvest ("Darnassus Bank" in "0/1 Darnassus Bank")
    return W.N[nm] or W.IE[nm] or (WoWBY_Objectives or {})[nm] or (W.ui_be and W.ui_be(nm)) or nil
end
local obj_be_core
function W.obj_be(t)
    t = plain(t)
    if not (t and t ~= "" and W.on("quests")) then return nil end
    -- ruRU client (R665): «X – убито: 0/7» → "0/7 X slain" (the RU name inside is found through the aliases)
    if W.RU then
        for _, e in ipairs(W.ru_lines_en(t) or {}) do
            local b = obj_be_core(e)
            if b then return b end
        end
    end
    return obj_be_core(t)
end
function obj_be_core(t)
    local cnt, body = t:match("^(%d+/%d+) (.+)$")
    if not cnt then cnt, body = t:match("^(%d+ x) (.+)$") end        -- quest link tooltips: "1 x Ursal the Mauler" (R313)
    if not cnt then body, cnt = t:match("^(.+): (%d+/%d+)$") end
    if not body then return W.ui_be and W.ui_be(t) or nil end      -- "Ready for turn-in", …
    -- R413: other verbs, same impersonal shape («Бурлівы вецер — знішчана: 4/6»); the objective names the target in the
    -- PLURAL ("Roiling Winds") while the NPC is "Roiling Wind" → a miss is retried without the plural -s
    for verb, word in pairs(OBJ_VERBS) do
        local mob = body:match("^(.+) " .. verb .. "$") or body:match("^(.+) " .. verb:sub(1, 1):upper() .. verb:sub(2) .. "$")
        local be = mob and (obj_name(mob) or (mob:find("s$") and obj_name(mob:sub(1, -2))))
        if be then return verb_line(cnt, word, be) end
    end
    local be = obj_name(body)
    -- "0/1 Speak with Rathiril Sunlance" / "… with the Innkeeper" (R503/R504): «0/1 Паразмаўляць: Ратырыл Сонечная Дзіда»
    -- (the name keeps its nominative; «з» + an unknown name's instrumental can't be built)
    local who = not be and body:match("^Speak with (.+)$")
    if who then
        local wb = obj_name(who) or obj_name((who:gsub("^the ", ""))) or obj_name((who:gsub("^the (%l)", string.upper)))
        if wb then return verb_line(cnt, "Паразмаўляць", wb) end
    end
    -- R639: "0/1 Find Fillion Flamebreeze" → «0/1 Знайсці: Філіян Палымяны Брыз» (same shape, name in the nominative)
    local fw = not be and body:match("^Find (.+)$")
    if fw then
        local wb = obj_name(fw) or obj_name((fw:gsub("^the ", "")))
        if wb then return verb_line(cnt, "Знайсці", wb) end
    end
    -- R846: "0/1 Offer aid to the Frightened Paladin" → «0/1 Дапамагчы: Спалоханы паладзін» (same shape)
    if not be then
        for _, v in ipairs(OBJ_ACTIONS) do
            local nm = body:match("^" .. v[1] .. " (.+)$")
            local wb = nm and (obj_name(nm) or obj_name((nm:gsub("^the ", ""))) or obj_name((nm:gsub("^the (%l)", string.upper))))
            if wb then return verb_line(cnt, v[2], wb) end
            -- "Report to Shari Stilwell in Brill" → «Далажыць: Шары Стылвел (Брыл)»
            local n2, zn
            if nm then n2, zn = nm:match("^(.+) in (.+)$") end
            local zb = zn and ((W.Z or {})[zn] or (WoWBY_POI or {})[zn] or obj_name(zn))
            wb = zb and (obj_name(n2) or obj_name((n2:gsub("^the ", ""))))
            if wb then
                -- R854: «Шары Стылвел у Брыле» where the build learned the locative from our texts, else «(Брыл)»
                local zl = (WoWBY_ZoneLoc or {})[zn]
                if zl then
                    local prep = zl[1]
                    if prep == "у" and LOC_VOWEL[wb:sub(-2)] then prep = "ў" end
                    return verb_line(cnt, v[2], wb .. " " .. prep .. " " .. zl[2])
                end
                return verb_line(cnt, v[2], wb .. " (" .. zb .. ")")
            end
        end
    end
    -- "Use Walk on Air: 1/1" (R436): the ability by its spell name, same impersonal shape
    local sp = not be and body:match("^Use (.+)$")
    local spb = sp and W.spell_name_be and W.spell_name_be(sp)
    if spb then return verb_line(cnt, "Выкарыстана", "«" .. spb .. "»") end
    if not be then return nil end
    return cnt .. " " .. be                               -- count first on every line, also from "X: 0/7" (owner R782)
end
local function norm_line(t) return (t:lower():gsub("[%s%.]+$", ""):gsub("%s+", " ")) end
local obj_line_core
function W.obj_line_be(t, qid)
    -- the quest log marks done lines "… (Complete)" (R446/R447): the line without it, then «(выканана)»
    -- (ruRU, R665: «Цель достигнута: …» / «… (необязательно)» are read in their English form)
    local p = plain(t)
    if p and W.RU then p = W.en_line(p) end
    local base = p and p:match("^(.-) %(Complete%)%.?$")
    if base then
        local be = W.obj_line_be(base, qid)                  -- (may still end in "(Optional)")
        return be and (be .. " (выканана)") or nil
    end
    -- R629: optional objectives "0/1 Listen to Alvarion Windfield's Story (Optional)"
    base = p and p:match("^(.-) %(Optional%)%.?$")
    if base then
        local be = obj_line_core(base, qid)
        return be and (be .. " (неабавязкова)") or nil
    end
    return obj_line_core(t, qid)
end
function obj_line_core(t, qid)
    -- whole objective lines the server sends ("Seek out the Great Bear Spirit and learn…"): exact EN -> BE table
    -- (data/objectives_fix.tsv by hand; later the translated harvest)
    local whole = W.on("quests") and plain(t) and (WoWBY_Objectives or {})[plain(t)]
    if whole then return W.substitute(whole, qid) end
    local be = W.obj_be(t)
    if be then return be end
    if qid and W.on("quests") then
        local e = W.entry_for(qid)
        local idx = e and e.o and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(qid)
        local _, en_o = nil, nil
        if idx and orig.GetQuestLogQuestText then _, en_o = orig.GetQuestLogQuestText(idx) end
        if type(en_o) == "string" and norm_line(en_o) == norm_line(t) then return W.substitute(e.o, qid, en_o) end
    end
    local sk, n = t:match("^Raise your (.+) skill to (%d+)%.?$")            -- profession quests
    if sk then
        local title = sk:gsub("(%a)(%a*)", function(a, b) return a:upper() .. b end)
        local nm = W.ui_be and (W.ui_be(title) or W.ui_be(sk))
        if nm then return "Павысьце навык «" .. nm .. "» да " .. n end
    end
end
local obj_en = setmetatable({}, { __mode = "k" })
local function tr_obj_fs(fs, qid)
    local t = fs and fs.GetText and plain(fs:GetText())
    if not t or t == "" then return end
    if W.on("quests") then
        local be = W.obj_line_be(t, qid)
        if be and be ~= t then obj_en[fs] = t; W.set_font(fs); W.swap(fs, be) end
    elseif obj_en[fs] and obj_en[fs] ~= t then
        W.swap(fs, obj_en[fs])
    end
end

-- ---------- quest frame decorations: title in log view, NPC name, section headers, buttons ----------
local function set_header(fs, be, en)
    if fs and fs.SetText then
        W.swap(fs, W.is_be() and be or en)
        if W.is_be() then W.set_font(fs) end
    end
end
local REWARD_MAP = {
    ["You will receive:"]                                = "Вы атрымаеце:",
    ["You will also receive:"]                           = "Вы атрымаеце таксама:",
    ["You will be able to choose one of these rewards:"] = "Вы зможаце выбраць адну з гэтых узнагарод:",
    ["Choose one of these rewards:"]                     = "Выберыце адну з гэтых узнагарод:",
    ["Experience:"]                                      = "Досвед:",
}
if W.ru_alias then W.ru_alias(REWARD_MAP, "ui") end         -- ruRU client: the Russian labels (R665)
local function tr_reward_fs(fs)
    local cur = fs and fs.GetText and plain(fs:GetText())
    if not cur or cur == "" then return end
    if W.is_be() then
        local be = REWARD_MAP[cur] or REWARD_MAP[W.strtrim(cur)]
        if be then fs.wowby_en = fs.wowby_en or cur; W.set_font(fs); W.swap(fs, be) end
    elseif fs.wowby_en then
        W.swap(fs, fs.wowby_en)
    end
end
local function npc_title_fs(fs)
    local be = fs and W.on("names") and W.name_be_unit(plain(fs:GetText()), "npc")
    if be then W.set_font(fs); W.swap(fs, be) end
end
function W.npc_title(frame)       -- QuestFrame / GossipFrame portrait title = NPC name
    if frame and frame.GetTitleText then npc_title_fs(frame:GetTitleText()) end
end
-- R295 (2026-10-09): the title is re-set by Blizzard on every update (SetGossipTitle / MerchantFrame:SetTitle), after
-- our GOSSIP_SHOW timer had run → post-hook the title FontString itself (feminine name for a female NPC)
function W.hook_npc_titles()
    for _, n in ipairs({ "GossipFrame", "MerchantFrame", "QuestFrame" }) do
        local f = _G[n]
        local fs = f and f.GetTitleText and f:GetTitleText()
        if fs then hooksecurefunc(fs, "SetText", function(self) pcall(npc_title_fs, self) end) end
    end
end
local reward_hooked, reward_busy = setmetatable({}, { __mode = "k" }), false   -- R911: reward-name FontString hooks
local function quest_info_post()
    local log = QuestInfoFrame and QuestInfoFrame.questLog
    local qid = log and C_QuestLog.GetSelectedQuest() or (GetQuestID and GetQuestID())
    if log then W.swap_title(_G.QuestInfoTitleHeader, qid) end       -- dialog title comes via GetTitleText
    set_header(_G.QuestInfoObjectivesHeader, "Мэты задання", QUEST_OBJECTIVES or "Quest Objectives")
    set_header(_G.QuestInfoDescriptionHeader, "Апісанне", QUEST_DESCRIPTION or "Description")
    local rf = _G.QuestInfoRewardsFrame
    if rf then
        set_header(rf.Header, "Узнагароды", REWARDS or "Rewards")
        tr_reward_fs(rf.ItemChooseText); tr_reward_fs(rf.ItemReceiveText)
        tr_reward_fs(rf.XPFrame and rf.XPFrame.ReceiveText)      -- static XML label "Experience:"
    end
    if W.is_be() then
        for _, n in ipairs({ "QuestInfoTitleHeader", "QuestInfoDescriptionText", "QuestInfoObjectivesText",
                             "QuestInfoRewardText", "QuestProgressText", "QuestProgressTitleText", "GreetingText" }) do
            W.set_font(_G[n])
        end
    end
    W.npc_title(_G.QuestFrame)
    if W.on("spells") then                       -- item names on the buttons (by EN name, WoWBY_ItemsEN)
        local function tr_btn(btn)
            local fs = btn and (btn.Name or (btn.GetName and btn:GetName() and _G[btn:GetName() .. "Name"]))
            if not fs then return end
            -- R911 (QA screenshot 2026-11-11: «Mining for Dummies» etc. stayed English on the reward buttons): Blizzard
            -- sets the name inside Item:ContinueOnItemLoad, i.e. LATER for an item not cached yet — after this pass. So
            -- each reward / progress name FontString also gets a SetText post-hook (once) that swaps the late name.
            if not reward_hooked[fs] and fs.SetText then
                reward_hooked[fs] = true
                hooksecurefunc(fs, "SetText", function(self)
                    if reward_busy or not (W.is_be() and W.on("spells")) then return end
                    local s = plain(self:GetText()); local b = s and W.IE[s]
                    if b then reward_busy = true; pcall(W.set_font, self); pcall(W.swap, self, b); reward_busy = false end
                end)
            end
            local t = fs.GetText and plain(fs:GetText())
            local be = t and W.IE[t]
            if be then W.set_font(fs); W.swap(fs, be) end
        end
        for i = 1, 8 do tr_btn(_G["QuestProgressItem" .. i]) end
        local rf = QuestInfoFrame and QuestInfoFrame.rewardsFrame
        for _, b in ipairs(rf and rf.RewardButtons or {}) do tr_btn(b) end
    end
    local of = _G.QuestInfoObjectivesFrame
    for _, fs in ipairs(of and of.Objectives or {}) do if fs:IsShown() then tr_obj_fs(fs) end end
end
if _G.QuestInfo_Display then hooksecurefunc("QuestInfo_Display", function(...) pcall(quest_info_post, ...) end) end
-- progress panel (R208): Blizzard fills the required-item buttons and the "Required items:" header (TURN_IN_ITEMS) in
-- QuestFrameProgressItems_Update, after the panel's OnShow hook ran → «Naga Spinefin» and the header stayed English
if _G.QuestFrameProgressItems_Update then
    hooksecurefunc("QuestFrameProgressItems_Update", function()
        if not W.is_be() then return end
        local h = _G.QuestProgressRequiredItemsText
        local ht = h and plain(h:GetText())
        local hb = ht and W.ui_be(ht)
        if hb and hb ~= ht then W.set_font(h); W.swap(h, hb) end
        if not W.on("spells") then return end
        for i = 1, 8 do
            local btn = _G["QuestProgressItem" .. i]
            local fs = btn and (btn.Name or _G["QuestProgressItem" .. i .. "Name"])
            local t = fs and fs.GetText and plain(fs:GetText())
            local be = t and W.IE[t]
            if be then W.set_font(fs); W.swap(fs, be) end
        end
    end)
end
-- spell rewards ("You will learn the following:" headers + Bear Form / Growl buttons): pooled frames filled in
-- QuestInfo_ShowRewards (called through the template's element table, so hooked via QuestInfo_Display, which ends it)
local function tr_spell_rewards_in(rf)
    if not rf or not W.is_be() then return end
    if rf.spellHeaderPool and W.on("ui") then
        for h in rf.spellHeaderPool:EnumerateActive() do
            local t = plain(h:GetText())
            local be = t and W.ui_be(t)
            if be and be ~= t then W.set_font(h); W.swap(h, be) end
        end
    end
    if rf.spellRewardPool and W.on("spells") then
        for f in rf.spellRewardPool:EnumerateActive() do
            local fs = f.Name
            local t = fs and plain(fs:GetText())
            local sid = W.sid_ok(f.rewardSpellID)
            -- R644: by the spell's own EN name (C_Spell), not the label — another pass may already have swapped
            -- "Maul" by the ITEM name («Кувалда», the weapon) before this one runs
            local en = sid and C_Spell and C_Spell.GetSpellName and plain(C_Spell.GetSpellName(sid))
            local be = (sid and W.SN[sid]) or (en and W.spell_name_be(en)) or (t and W.spell_name_be(t))
            if be and be ~= t then W.set_font(fs); W.swap(fs, be) end
        end
    end
end
-- R643: the quest LOG details (world map side panel) fill MapQuestInfoRewardsFrame, not QuestInfoRewardsFrame
local function tr_spell_rewards()
    tr_spell_rewards_in(_G.QuestInfoRewardsFrame)
    tr_spell_rewards_in(_G.MapQuestInfoRewardsFrame)
end
if _G.QuestInfo_Display then hooksecurefunc("QuestInfo_Display", function() pcall(tr_spell_rewards) end) end
if _G.QuestFrameProgressPanel_OnShow then hooksecurefunc("QuestFrameProgressPanel_OnShow", function(...) pcall(quest_info_post, ...) end) end

local BTN = {
    QuestFrameAcceptButton        = { be = "Прыняць",    en = "Accept" },
    QuestFrameDeclineButton       = { be = "Адхіліць",   en = "Decline" },
    QuestFrameCompleteButton      = { be = "Працягнуць", en = "Continue" },
    QuestFrameCompleteQuestButton = { be = "Завяршыць",  en = "Complete Quest" },
    QuestFrameGoodbyeButton       = { be = "Бывай",      en = "Goodbye" },
    QuestFrameGreetingGoodbyeButton = { be = "Бывай",    en = "Goodbye" },
}
function W.apply_buttons()
    for name, t in pairs(BTN) do
        local b = _G[name]
        if b and b.SetText then W.swap(b, W.is_be() and t.be or t.en) end
    end
end
if _G.QuestFrame_OnEvent then hooksecurefunc("QuestFrame_OnEvent", function() pcall(W.apply_buttons); pcall(W.npc_title, _G.QuestFrame) end) end

-- ---------- quest log list (QuestMapFrame side panel) ----------
-- Objective lines (R192): Blizzard measures each line (GetStringHeight) right after its SetText and stacks the rows
-- with that height — swapping the longer BE text afterwards made it run into the next zone header. A SetText post-hook
-- on each pooled line puts the BE text in before the measure (as the tracker's trk_hook). Pool frames are hooked when
-- first seen; that first pass re-runs the update once so the new rows are measured with the hook in place.
local log_obj_hooked, log_obj_busy = {}, false
local function log_obj_hook(ob)
    local fs = ob and ob.Text
    if not fs or log_obj_hooked[fs] then return false end
    log_obj_hooked[fs] = true
    hooksecurefunc(fs, "SetText", function(self)
        if log_obj_busy or not W.is_be() then return end
        log_obj_busy = true
        pcall(tr_obj_fs, self, ob.questID)
        log_obj_busy = false
    end)
    return true
end
local log_rerun = false
-- R811: Forever's row tag "(Dungeon)" (QuestUtilsOverrides.GetQuestTagText: Elite / Dungeon / PvP / Raid in brackets)
function W.quest_tag_be(t)
    local inner = t and t:match("^%((.+)%)$")
    local be = inner and W.ui_be(inner)
    return be and be ~= inner and ("(" .. be .. ")") or nil
end
local function log_list_post()
    if not (W.is_be() and QuestScrollFrame and QuestScrollFrame.titleFramePool) then return end
    local grew = false
    for button in QuestScrollFrame.titleFramePool:EnumerateActive() do
        local tag = button.TagText and button.TagText:IsShown() and W.quest_tag_be(plain(button.TagText:GetText()))
        if tag then W.swap(button.TagText, tag) end
        if button.questID and button.Text and W.be_title(button.questID) then
            local before = button.Text:GetStringHeight() or 0
            W.swap_title(button.Text, button.questID)
            local delta = (button.Text:GetStringHeight() or 0) - before
            if delta > 1 then button:SetHeight(button:GetHeight() + delta); grew = true end
        end
    end
    -- zone headers ("Darnassus"): button:SetText(info.title) bypasses the FontString hooks, so the 1 s ticker swapped
    -- them later → EN/BE blink (R76). Swap here, in the same update.
    if QuestScrollFrame.headerFramePool and W.on("zones") then
        for hb in QuestScrollFrame.headerFramePool:EnumerateActive() do
            local t = hb.GetText and plain(hb:GetText())
            local be = t and t ~= "" and (W.Z[t] or W.ui_be(t))
            if be and be ~= t then W.swap(hb, be) end
        end
    end
    local new_hooks = false
    if QuestScrollFrame.objectiveFramePool then
        for ob in QuestScrollFrame.objectiveFramePool:EnumerateActive() do
            if log_obj_hook(ob) then new_hooks = true end
            tr_obj_fs(ob.Text, ob.questID)
        end
    end
    if grew and QuestScrollFrame.Contents and QuestScrollFrame.Contents.Layout then QuestScrollFrame.Contents:Layout() end
    if new_hooks and not log_rerun then                 -- re-measure once with the new hooks (next frame, not nested)
        log_rerun = true
        C_Timer.After(0, function()
            if QuestMapFrame and QuestMapFrame:IsShown() and QuestLogQuests_Update then QuestLogQuests_Update() end
            log_rerun = false
        end)
    end
end
if _G.QuestLogQuests_Update then hooksecurefunc("QuestLogQuests_Update", function(...) pcall(log_list_post, ...) end) end

-- ---------- objective tracker: quest block headers ----------
-- Hook the live MODULE frames (not the block mixins: ObjectiveTrackerQuestPOIBlockMixin copied SetHeader
-- at Blizzard load time, before we could hook it). LayoutContents runs after every block update;
-- swap_title is idempotent (no EN title left in the text -> no-op).
-- Longer Belarusian lines overlapped the next quest: the tracker measures each line right after SetText, and we
-- swapped only after LayoutContents. So each tracker line / header FontString also gets a SetText post-hook (like
-- the panels): the BE text is in place when Blizzard measures it. The hook remembers the quest id of its block.
local trk_fs = setmetatable({}, { __mode = "k" })       -- FontString -> { qid = , header = bool }
local trk_busy = false
local function trk_set(fs)
    if trk_busy then return end
    local info = trk_fs[fs]
    if not info then return end
    trk_busy = true
    if info.header then pcall(W.swap_title, fs, info.qid) else pcall(tr_obj_fs, fs, info.qid) end
    trk_busy = false
end
local function trk_hook(fs, qid, header)
    if not fs then return end
    local info = trk_fs[fs]
    if not info then
        info = {}
        trk_fs[fs] = info
        pcall(hooksecurefunc, fs, "SetText", trk_set)
    end
    info.qid, info.header = qid, header                   -- pooled lines move between quests: keep current
end
-- R832 (owner 2026-11-08, screenshot: tracker «0/8 Рыла баявога дзіка» while the unit tooltip said 6/8): a looted item
-- did not always redraw the tracker. Every 2 s out of combat each visible tracker objective line is compared with the
-- live leaderboard text (the same getter Blizzard's tracker uses) and re-set when it is behind; our SetText hook then
-- translates it. Display-only: only the FontString's text, never a Blizzard tracker update (taint, R156).
local function trk_refresh()
    if InCombatLockdown() or not (W.is_be() and W.on("quests")) or not GetQuestLogLeaderBoard then return end
    for fs, info in pairs(trk_fs) do
        if not info.header and info.qid and type(info.key) == "number" and fs:IsVisible() then
            local idx = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(info.qid)
            local live = idx and plain((GetQuestLogLeaderBoard(info.key, idx)))
            local cur = plain(fs:GetText())
            -- up to date = the line shows the live English, or our translation of it
            if live and live ~= "" and cur and cur ~= live and obj_en[fs] ~= live then pcall(fs.SetText, fs, live) end
        end
    end
end
C_Timer.NewTicker(2, function() pcall(trk_refresh) end)
local function tracker_post(module)
    if not (W.is_be() and module and module.usedBlocks) then return end
    for _, blocks in pairs(module.usedBlocks) do
        for id, block in pairs(blocks) do
            local qid = type(id) == "number" and id or nil
            if qid and block.HeaderText then trk_hook(block.HeaderText, qid, true); W.swap_title(block.HeaderText, id) end
            for key, line in pairs(block.usedLines or {}) do
                trk_hook(line.Text, qid, false)
                if trk_fs[line.Text] then trk_fs[line.Text].key = key end
                tr_obj_fs(line.Text, qid)
            end
        end
    end
end
-- R889: re-text the tracker after a language switch WITHOUT running Blizzard's tracker update from addon code (that ran
-- the whole update tainted → ShouldShowMawBuffs errored → the quest module was never laid out: finished quests stayed
-- «8/8» without the turn-in line, owner 2026-11-11)
function W.tracker_retext()
    for _, m in ipairs({ _G.QuestObjectiveTracker, _G.CampaignQuestObjectiveTracker }) do pcall(tracker_post, m) end
    if W.tr_tracker_headers then pcall(W.tr_tracker_headers) end
end
for _, m in ipairs({ _G.QuestObjectiveTracker, _G.CampaignQuestObjectiveTracker }) do
    -- pcall (R741, owner screenshot 2026-10-23: an abandoned quest stayed in the tracker until the language switch):
    -- an error here propagates into Blizzard's module Update, which then skips EndLayout — where unused blocks are freed
    if m and m.LayoutContents then hooksecurefunc(m, "LayoutContents", function(mod) pcall(tracker_post, mod) end) end
end

-- ---------- quest log details pane: buttons + "Rewards" header (exact-label swap) ----------
local DETAILS_TR = { Back = "Назад", Abandon = "Адмовіцца", Share = "Падзяліцца", Track = "Адсочваць",
                     Untrack = "Не адсочваць", Rewards = "Узнагароды", ["Show Map"] = "Паказаць карту" }
if W.ru_alias then W.ru_alias(DETAILS_TR, "ui") end
local details_en = setmetatable({}, { __mode = "k" })
local function retext_detail_fs(r)
    local t = plain(r:GetText())
    if W.is_be() then
        local be = t and DETAILS_TR[t]
        if be then details_en[r] = t; W.set_font(r); W.swap(r, be) end
    elseif details_en[r] and t == DETAILS_TR[details_en[r]] then
        W.swap(r, details_en[r])
    end
end
function W.details_post()
    local df = QuestMapFrame and QuestMapFrame.DetailsFrame
    if df and df:IsShown() then W.each_fs(df, 8, retext_detail_fs) end
end
if _G.QuestMapFrame_UpdateQuestDetailsButtons then hooksecurefunc("QuestMapFrame_UpdateQuestDetailsButtons", function(...) pcall(W.details_post, ...) end) end
if _G.QuestInfo_Display then hooksecurefunc("QuestInfo_Display", function(...) pcall(W.details_post, ...) end) end
