-- WoWBY/core/messages.lua — chat, centre messages, cast bar, banners, bags, tracker headers.
-- Split from core.lua (tools/split_core.py); shared state lives in the addon namespace W.
local _, W = ...
-- ---------- system chat lines + the yellow/red centre messages ----------
-- "You receive loot: [Malachite].", "You loot 4 Copper", "Discovered Darnassus: 85 experience gained" are
-- GlobalStrings formats -> ui_be (only fully known lines; item links kept). Chat: message-event filters (display
-- only). Centre (UIErrorsFrame, "Discovered: Warrior's Terrace"): after Blizzard adds the line, its FontString is
-- swapped (WowUkrainizer does the same). Secret texts are skipped (plain()).
local CHAT_EVENTS = { "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_SYSTEM", "CHAT_MSG_COMBAT_XP_GAIN",
                      "CHAT_MSG_COMBAT_FACTION_CHANGE", "CHAT_MSG_SKILL", "CHAT_MSG_TRADESKILLS", "CHAT_MSG_OPENING",
                      "CHAT_MSG_COMBAT_HONOR_GAIN", "CHAT_MSG_CURRENCY", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_PING",
                      "CHAT_MSG_COLLECTED_APPEARANCE", "CHAT_MSG_PET_INFO", "CHAT_MSG_COMBAT_MISC_INFO", "CHAT_MSG_RESTRICTED",
                      "CHAT_MSG_FILTERED", "CHAT_MSG_IGNORED", "CHAT_MSG_BG_SYSTEM_NEUTRAL", "CHAT_MSG_BG_SYSTEM_ALLIANCE",
                      "CHAT_MSG_BG_SYSTEM_HORDE" }
-- emotes ("You let %s know that you were just kidding!", EmotesTextData via translate/emotes): the %s is any
-- character's name, so a short unknown capture is accepted as a name there (W.any_name, read by ui_fmt)
-- R300: system lines whose every %s is a PLAYER (group / guild / friends / trade): "You have invited Corbic War to join
-- your group." — the name is unknown by design, so these EN formats (the client's own globals) also allow any name
local PLAYER_FMT_KEYS = {
    "JOINED_PARTY", "LEFT_PARTY", "ERR_JOINED_GROUP_S", "ERR_LEFT_GROUP_S", "ERR_INVITE_PLAYER_S", "ERR_DECLINE_GROUP_S",
    "ERR_DECLINE_GROUP_REQUEST_S", "ERR_ALREADY_IN_GROUP_S", "ERR_PLAYER_BUSY_S", "ERR_NEW_LEADER_S", "ERR_NEW_LOOT_MASTER_S",
    "ERR_TARGET_NOT_IN_GROUP_S", "ERR_INVITED_TO_GROUP_SS", "ERR_INVITED_ALREADY_IN_GROUP_SS", "ERR_REQUESTED_INVITE_TO_GROUP_SS",
    "ERR_SUGGEST_INVITE_PLAYER_S", "ERR_REQUEST_JOIN_PLAYER_S", "ERR_INFORM_SUGGEST_INVITE_S", "ERR_RAID_MEMBER_ADDED_S",
    "ERR_RAID_MEMBER_REMOVED_S", "ERR_INSTANCE_GROUP_ADDED_S", "ERR_INSTANCE_GROUP_REMOVED_S", "ERR_MEETING_STONE_MEMBER_ADDED_S",
    "ERR_BG_PLAYER_LEFT_S", "ERR_PLAYER_LEFT_BATTLE_D", "ERR_PARTY_LFG_BOOT_VOTE_SUCCEEDED", "ERR_PARTY_LFG_BOOT_VOTE_FAILED",
    "ERR_IGNORE_ALREADY_S", "ERR_IGNORE_ADDED_S", "ERR_IGNORE_REMOVED_S", "ERR_IGNORING_YOU_S", "ERR_FRIEND_ONLINE_SS",
    "ERR_FRIEND_OFFLINE_S", "ERR_FRIEND_ADDED_S", "ERR_FRIEND_REMOVED_S", "ERR_FRIEND_ALREADY_S", "ERR_BN_TARGET_OFFLINE",
    "ERR_GUILD_LEADER_IS_S", "ERR_GUILD_DECLINE_S", "ERR_GUILD_DECLINE_AUTO_S", "ERR_GUILD_LEAVE_S", "ERR_GUILD_REMOVE_SS",
    "ERR_GUILD_DISBAND_S", "ERR_GUILD_LEADER_CHANGED_SS", "ERR_GUILD_LEADER_S", "ERR_GUILD_PLAYER_NOT_IN_GUILD_S",
    "ERR_ALREADY_INVITED_TO_GUILD_S", "ERR_ALREADY_IN_GUILD_S", "ERR_GUILD_JOIN_S", "ERR_GUILD_INVITE_S", "ERR_PETITION_DECLINED_S",
    "ERR_INITIATE_TRADE_S", "ERR_TRADE_REQUEST_S", "ERR_TRADE_BLOCKED_S", "ERR_QUEST_PUSH_DECLINED_S", "ERR_QUEST_PUSH_BUSY_S",
    "ERR_QUEST_SESSION_RESULT_INVALID_OWNER_S", "ERR_QUEST_SESSION_RESULT_OWNER_REFUSED_S", "RAID_SUMMON_FAILED_OFFLINE",
    "RAID_SUMMON_FAILED_RAID_LOCKED", "ERR_RECRUIT_A_FRIEND_SUMMON_OFFLINE", "ERR_BATTLEGROUND_INVITATION_DECLINED_BY",
    -- R309: another player's loot / crafting (CHAT_MSG_LOOT / MONEY): the other captures are item links or money
    "LOOT_ITEM", "LOOT_ITEM_MULTIPLE", "LOOT_ITEM_PUSHED", "LOOT_ITEM_PUSHED_MULTIPLE", "LOOT_ITEM_BONUS_ROLL",
    "LOOT_ITEM_BONUS_ROLL_MULTIPLE", "LOOT_MONEY", "CREATED_ITEM", "CREATED_ITEM_MULTIPLE", "TRADESKILL_LOG_THIRDPERSON",
    "LOOT_ROLL_PASSED", "LOOT_ROLL_WON", "LOOT_ROLL_GREED", "LOOT_ROLL_NEED", "LOOT_ROLL_DISENCHANT",
    "LOOT_ROLL_ROLLED_NEED", "LOOT_ROLL_ROLLED_GREED", "LOOT_ROLL_ROLLED_DE", "LOOT_ROLL_WON_NO_SPAM_NEED",
    "LOOT_ROLL_WON_NO_SPAM_GREED",
    "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT",   -- R808
    "ERR_PLAYER_DIED_S",   -- R819: "Wildu has died."
}
local player_pats
local function is_player_line(t)
    if not player_pats then
        player_pats = {}
        for _, k in ipairs(PLAYER_FMT_KEYS) do
            local en = type(_G[k]) == "string" and _G[k]
            if en then
                -- R808: |3-4(%s) = a Russian declined value (the line itself holds the plain name); %1$s = a numbered value
                local p = en:gsub("|3%-%d+%((.-)%)", "%1"):gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
                    :gsub("%%%%%d+%%%$s", ".+"):gsub("%%%%s", ".+"):gsub("%%%%%d+%%%$d", "%%d+"):gsub("%%%%d", "%%d+")
                player_pats[#player_pats + 1] = "^" .. p .. "$"
            end
        end
    end
    for _, p in ipairs(player_pats) do if t:find(p) then return true end end
    return false
end
-- floating combat text stays ENGLISH, both kinds (owner 2026-10-10, R154/R332): the numbers over enemies are engine text
-- nobody can change, and the self scrolling text (Blizzard_CombatText) is left alone for consistency with them
-- server broadcasts ("[SERVER] Shutdown in 8:00", R331): composed by the client, not a GlobalString format
local SERVER_MSG = { { "^Shutdown in (.+)$", "Выключэнне сервера праз %s" }, { "^Restart in (.+)$", "Перазапуск сервера праз %s" },
                     { "^Shutdown cancelled%.?$", "Выключэнне сервера адменена." },
                     { "^Restart cancelled%.?$", "Перазапуск сервера адменены." } }
local function server_msg_be(t)
    local body = t:match("^%[SERVER%]%s*(.+)$")
    if not body then return nil end
    for _, s in ipairs(SERVER_MSG) do
        local v = body:match(s[1])
        if v or body:find(s[1]) then return "[СЕРВЕР] " .. s[2]:format(v or "") end
    end
    local be = W.ui_be(body)
    return be and be ~= body and ("[СЕРВЕР] " .. be) or nil
end
local function msg_be(t, event)
    t = plain(t)
    if not (t and t ~= "" and W.is_be() and W.on("ui")) then return nil end
    local sv = server_msg_be(t)
    if sv then return sv end
    local emote = event == "CHAT_MSG_TEXT_EMOTE" or event == "CHAT_MSG_PING"   -- pings: "Attack: <player>" (R581)
    -- R819: names there are players, kept; R920: emote / ping names too ("You thank Heal Undead." had become
    -- «Вы дзякуеце Лечым: Наўе.» through the nested UI format "Heal %s")
    W.player_names = emote or is_player_line(t)
    W.emote_names = emote                                                  -- an emote's target may be an NPC (W.N)
    W.any_name = emote or W.player_names
    local ok, be = pcall(W.ui_be, t)
    W.any_name, W.player_names, W.emote_names = false, false, false
    return ok and be ~= t and be or nil
end
W.msg_be = msg_be
-- NPC speech ("Gubber Blump says: Fishing is real easy…"): server text (BroadcastText is not in the client DB2),
-- so it is harvested like gossip (kind "gossip", value = speaker) and translated through the gossip package ->
-- WoWBY_Gossip. The player's own name inside a line is stored as $N. The speaker's name goes through N.
local SPEECH_EVENTS = { "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_WHISPER",
                        "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_MONSTER_PARTY", "CHAT_MSG_RAID_BOSS_EMOTE",
                        "CHAT_MSG_RAID_BOSS_WHISPER" }
local function speech_key(t)
    local me = plain(UnitName("player"))
    if me and me ~= "" then t = t:gsub(me:gsub("%p", "%%%0"), "$N") end
    return t
end
local function speech_be(msg, author)
    msg, author = plain(msg), plain(author)
    if not (msg and msg ~= "" and W.is_be()) then return nil end
    local key = speech_key(msg)
    local b = W.gossip_be(msg) or W.G[key]
    -- R584: NPC speech addresses WHOEVER triggered it ("…ready for you, Toast." — another player): on a miss each
    -- capitalised word (not the first) is tried as $N; the line keeps that player's name
    if not b then
        local first = true
        for word in msg:gmatch("%u[%a'%-]+") do
            if not first then
                local s, e = msg:find(word, 1, true)
                local k2 = s and (msg:sub(1, s - 1) .. "$N" .. msg:sub(e + 1))
                local raw = k2 and (W.G[k2] or W.G[(k2:gsub("%$N", "$n"))])
                if raw then
                    b = raw:gsub("%$[Nn]", (word:gsub("%%", "%%%%")))
                    break
                end
            end
            first = false
        end
    end
    if not b then
        W.harvest("gossip", key, author or true)
        return nil, author and W.on("names") and W.N[author] or nil
    end
    if not W.on("quests") then return nil end
    return W.substitute(b), author and W.on("names") and W.N[author] or nil
end
-- links inside any chat line (R91): only the shown [text] changes, the link data stays → clicking still works.
-- quest: title by id; item: IT by id, else IE; spell: by EN name.
local function links_be(t)
    -- bilingual mode (R369): link names stay English (searchable, what other players type)
    if not (W.is_be() and t and t:find("|H", 1, true)) or W.dual_on() then return nil end
    -- (the link data may start with a GUID: "|Htrade:Player-1-0:333:7411|h[Enchanting]|h", R374)
    local out = t:gsub("(|H(%a+):([^:|]*)([^|]*)|h)%[(.-)%](|h)", function(open, kind, id, _, text, close)
        id = tonumber(id)
        local be
        if kind == "quest" and W.on("quests") then be = W.be_title(id)
        elseif kind == "item" and W.on("spells") then be = W.item_name_be(text, id)   -- R825: random suffixes too
        elseif (kind == "spell" or kind == "enchant" or kind == "trade") and W.on("spells") and W.spell_name_be then
            -- recipe links (R356): "[Enchanting: Enchant Chest - Lesser Stats]" = profession + ": " + spell name
            local prof, nm = text:match("^([^:]+): (.+)$")
            local pb = prof and (W.ui_be(prof) or prof)
            local sb = nm and W.spell_name_be(nm)
            -- a whole profession link "[Enchanting]" (R374) = the profession's UI word
            be = (sb and (pb .. ": " .. sb)) or W.spell_name_be(text) or (kind == "trade" and W.ui_be(text)) or nil
            -- "[Mark of the Wild (Rank 1)]" (learn-a-spell line): the name has no entry with its rank attached (R774)
            -- R949: also the profession level "[Skinning (Journeyman)]" → «[Здзіранне шкур (Падмайстар)]»
            if not be then
                local base, sub = text:match("^(.-) %((.-)%)$")
                local bb = base and W.spell_name_be(base)
                local rank = sub and sub:match("^Rank (%d+)$")
                local sbe = rank and ("Ранг " .. rank) or (sub and W.ui_be(sub))
                if bb and sbe then be = bb .. " (" .. sbe .. ")" end
            end
        end
        if be and be ~= text then return open .. "[" .. be .. "]" .. close end
    end)
    return out ~= t and out or nil
end
W.links_be = links_be
-- player channels (R91): "1. General - Teldrassil" / "Trade (Local) - Darnassus" → base word + zone (Z). The typed text
-- itself stays; only its links are translated.
local CHANNELS = { General = "Агульны", Trade = "Гандаль", ["Trade (Local)"] = "Гандаль (мясцовы)",
                   ["Trade (Services)"] = "Гандаль (паслугі)", Services = "Паслугі", LocalDefense = "Мясцовая абарона",
                   WorldDefense = "Сусветная абарона", LookingForGroup = "Пошук групы", Newcomer = "Навічкі",
                   TradeLocal = "Гандаль (мясцовы)", Empty = "Пуста" }
if W.ru_alias then W.ru_alias(CHANNELS, "ui") end           -- ruRU client: «Общий», «Торговля» (R665)
local function channel_be(c)
    c = plain(c)
    if not (c and c ~= "" and W.is_be() and W.on("ui")) then return nil end
    local num, rest = c:match("^(%d+%.%s*)(.+)$")
    rest = rest or c
    local base, zone = rest:match("^(.-) %- (.+)$")
    base = base or rest
    local b = CHANNELS[base]
    if not b then return nil end
    local SUFFIX = { English = "англійская", Russian = "руская", German = "нямецкая", French = "французская",
                     Spanish = "іспанская", Portuguese = "партугальская", Italian = "італьянская" }
    local z = zone and (W.Z[zone] or SUFFIX[zone] or zone)
    return (num or "") .. b .. (z and (" - " .. z) or "")
end
W.channel_be = channel_be                    -- chat settings channel list "2.General" (ui.lua label_be, R124)
local PLAYER_EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
                        "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD",
                        "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_INSTANCE_CHAT",
                        "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_EMOTE", "CHAT_MSG_CHANNEL_NOTICE",
                        "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM" }
function W.hook_messages()
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or _G.ChatFrame_AddMessageEventFilter
    if add then
        local function filter(_, event, msg, ...)
            local be = msg_be(msg, event)
            local lk = links_be(be or plain(msg))
            be = lk or be
            if be then return false, be, ... end
        end
        -- args after msg: author, language, channelString (a4), target, flags, zoneID, channelNumber, channelBaseName (a9)
        local function player(_, _, msg, a2, a3, a4, a5, a6, a7, a8, a9, ...)
            local ok, lk = pcall(links_be, plain(msg))
            local chat_on = WoWBY_DB and WoWBY_DB.chat_be            -- channel names only with the option (R127)
            local ok4, c4 = chat_on and pcall(channel_be, a4)
            local ok9, c9 = chat_on and pcall(channel_be, a9)
            lk, c4, c9 = ok and lk or nil, ok4 and c4 or nil, ok9 and c9 or nil
            local l3 = W.lang_be and W.lang_be(a3)
            if lk or c4 or c9 or l3 then
                return false, lk or msg, a2, l3 or a3, c4 or a4, a5, a6, a7, a8, c9 or a9, ...
            end
        end
        for _, e in ipairs(PLAYER_EVENTS) do pcall(add, e, player) end
        for _, e in ipairs(CHAT_EVENTS) do pcall(add, e, filter) end
        -- chat language tag «[Darnassian] …» (the event's language arg, owner R555): feminine adjective = «мова»
        local LANG = { Common = "Агульная", Darnassian = "Дарнаская", Orcish = "Арчыная", Dwarvish = "Дварфійская",
                       Gnomish = "Гномская", Taurahe = "Таўрахэ", Thalassian = "Таласійская", Troll = "Тролья",
                       Gutterspeak = "Наўская", Draconic = "Драконавая", Demonic = "Дэманічная", Titan = "Мова тытанаў",
                       Kalimag = "Калімаг", Pandaren = "Пандарэнская", ["Shen'dorei"] = "Шэн'дарай" }
        if W.ru_alias then W.ru_alias(LANG, "ui") end      -- ruRU client: «Всеобщий» (R665)
        local function lang_be(l)
            l = plain(l)
            return l and W.is_be() and W.on("ui") and LANG[l] or nil
        end
        W.lang_be = lang_be                                           -- players' chat lines use it too
        local function speech(_, _, msg, author, lang, ...)
            -- R694: the speaker's sex ($S) from the event's GUID (arg 12) when a unit token shows that NPC
            local okg, sex = pcall(W.guid_sex, (select(9, ...)))
            sex = okg and sex or nil
            local ok, be, abe = pcall(W.as_speaker, sex, speech_be, msg, author)
            local lb = lang_be(lang)
            if ok and (be or abe) or lb then
                return false, (ok and be) or msg, (ok and abe) or author, lb or lang, ...
            end
        end
        for _, e in ipairs(SPEECH_EVENTS) do pcall(add, e, speech) end
    end
    local ef = _G.UIErrorsFrame
    if ef and ef.AddMessage then
        hooksecurefunc(ef, "AddMessage", function(self, msg, r, g, b, a, id)
            -- quest progress ("Bloodfeather Belt: 4/6", "Gnarlpine Mystic slain: 3/7") = objective lines (R19)
            -- R838: whole objective lines too, with "(Complete)" ("Cleanse the Winterhoof Water Well (Complete)")
            local p = plain(msg)
            local be = msg_be(msg) or (p and W.is_be() and W.obj_line_be and W.obj_line_be(p)) or nil
            if not be then return end
            local function swap()
                local fs = id and self.GetFontStringByID and self:GetFontStringByID(id)
                if fs and plain(fs:GetText()) == msg then W.swap(fs, be); return end
                -- R884 (owner screenshot: «4/7 Мяса…» translated, "Plainstrider Feather: 5/7" under it not): two quest-progress
                -- lines in one moment share the message id (or have none), so the id finds only one of them — find the line by
                -- its text among the frame's FontStrings
                if W.each_fs then
                    W.each_fs(self, 1, function(f)
                        if plain(f:GetText()) == msg then W.swap(f, be) end
                    end)
                end
            end
            swap(); C_Timer.After(0, swap)
        end)
    end
    -- system lines Blizzard writes straight into a chat frame (R536: "You gained: 1s 58c" money receipt, crafting
    -- orders…): ChatFrameUtil.DisplaySystemMessageInPrimary / InCurrent → AddMessage, no event, no filter. Post-hook:
    -- the line just added is rewritten in that frame's history (display only, like the level-up line below)
    local CFU = _G.ChatFrameUtil
    for fn, frame in pairs({ DisplaySystemMessageInPrimary = "DEFAULT_CHAT_FRAME", DisplaySystemMessageInCurrent = "SELECTED_CHAT_FRAME" }) do
        if CFU and type(CFU[fn]) == "function" then
            hooksecurefunc(CFU, fn, function(msg)
                if not (W.is_be() and W.on("ui")) or type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
                local be = W.ui_be(msg)
                local cf = _G[frame]
                if not (be and be ~= msg and cf and cf.TransformMessages) then return end
                pcall(cf.TransformMessages, cf, function(e)
                    local m = type(e) == "table" and e.message or e
                    return type(m) == "string" and not (issecretvalue and issecretvalue(m)) and m == msg
                end, function(_, ...) return be, ... end)
            end)
        end
    end
    -- /help, /macrohelp, /chat and the login "Type '/help'…" hint (R775): the same straight AddMessage, one line per global
    -- *_LINE1, *_LINE2… The lines just added are rewritten in that frame's history.
    local function help_lines()
        local set = {}
        if type(_G.HELP_TEXT_SIMPLE) == "string" then set[_G.HELP_TEXT_SIMPLE] = true end
        for _, base in ipairs({ "HELP_TEXT_LINE", "MACRO_HELP_TEXT_LINE", "CHAT_HELP_TEXT_LINE" }) do
            local i = 1
            while type(_G[base .. i]) == "string" do
                set[_G[base .. i]] = true
                i = i + 1
            end
        end
        return set
    end
    local function rewrite_help(cf)
        if not (cf and cf.TransformMessages and W.is_be() and W.on("ui")) then return end
        local set = help_lines()
        pcall(cf.TransformMessages, cf, function(e)
            local m = plain(type(e) == "table" and e.message or e)
            return m and set[m] and W.ui_be(m) ~= nil
        end, function(msg, ...) return (W.ui_be(msg) or msg), ... end)
    end
    W.rewrite_help = rewrite_help
    for _, fn in ipairs({ "DisplayHelpTextSimple", "DisplayHelpText", "DisplayMacroHelpText", "DisplayChatHelp" }) do
        if CFU and type(CFU[fn]) == "function" then hooksecurefunc(CFU, fn, rewrite_help) end
    end
    -- level-up chat line (R460): Blizzard formats LEVEL_UP and AddMessage's it straight into the chat frames (no event,
    -- no filter) → right after PLAYER_LEVEL_UP the line already in each chat frame's history is rewritten
    -- (ScrollingMessageFrame:TransformMessages, display only; no globals or Blizzard functions replaced).
    -- The engine writes the stat lines the same way ("Your Agility increases by 1.", "You have gained 17 hit points and
    -- 29 mana.", owner 2026-10-16) → every LEVEL_UP_* format is matched, twice (the lines may land after the event)
    local LV_KEYS = { "LEVEL_UP", "LEVEL_UP_NO_LINK", "LEVEL_UP_STAT", "LEVEL_UP_HEALTH_MANA", "LEVEL_UP_HEALTH",
                      "LEVEL_UP_CHAR_POINTS", "LEVEL_UP_SKILL_POINTS" }
    local lv_pats
    local function is_levelup(m)
        if not lv_pats then
            lv_pats = {}
            for _, k in ipairs(LV_KEYS) do
                local en = type(_G[k]) == "string" and _G[k]
                if en then
                    local p = en:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"):gsub("|4[^;]*;", ".-")
                    p = p:gsub("%%%%s", ".+"):gsub("%%%%d", "%%d+")
                    lv_pats[#lv_pats + 1] = "^" .. p .. "$"
                end
            end
        end
        for _, p in ipairs(lv_pats) do if m:find(p) then return true end end
        return false
    end
    local function lv_rewrite()
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local cf = _G["ChatFrame" .. i]
            if cf and cf.TransformMessages then
                pcall(cf.TransformMessages, cf, function(e)
                    local m = type(e) == "table" and e.message or e
                    return type(m) == "string" and not (issecretvalue and issecretvalue(m)) and is_levelup(m)
                end, function(msg, ...) return (W.ui_be(msg) or msg), ... end)
            end
        end
    end
    local lv = CreateFrame("Frame")
    lv:RegisterEvent("PLAYER_LEVEL_UP")
    lv:SetScript("OnEvent", function()
        if not (W.is_be() and W.on("ui")) then return end
        C_Timer.After(0.3, lv_rewrite)
        C_Timer.After(1.5, lv_rewrite)
    end)
end
-- mail (R28): NPC senders by name (players are never in N), NPC letters by exact EN body via WoWBY_Gossip (misses
-- harvested as gossip, spoken by the sender); subjects of NPC mail too. Labels/buttons come from PANELS (OpenMailFrame).
local mail_hooked = false
local function mail_text_be(t, sender)
    t = plain(t)
    if not (t and t ~= "" and W.is_be()) then return nil end
    -- letters come with real line breaks (CRLF); the keys (mail_text_template) use $B
    local b = W.gossip_be(t) or W.gossip_be((t:gsub("\r", ""):gsub("\n", "$B")))
    if not b and sender and W.N[sender] then W.harvest("gossip", t, sender) end
    return b and W.on("quests") and W.substitute(b) or nil
end
-- system mail senders (R178): not NPCs, not GlobalStrings — server names of the auction houses
local MAIL_SENDERS = { ["Horde Auction House"] = "Аўкцыён Арды", ["Alliance Auction House"] = "Аўкцыён Альянсу",
                       ["Neutral Auction House"] = "Нейтральны аўкцыён" }
if W.ru_alias then W.ru_alias(MAIL_SENDERS, "ui", "names") end
local function days_be(n)
    local m10, m100 = n % 10, n % 100
    if m10 == 1 and m100 ~= 11 then return n .. " дзень" end
    if m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14) then return n .. " дні" end
    return n .. " дзён"
end
-- invoice lines "Item Sold: Copper Ore" / "Purchased By: Flash Point" (label .. " " .. value in Blizzard's code):
-- label via the UI dictionary, an item name via IE, a player name kept
local function tr_invoice()
    if not (W.is_be() and W.on("ui")) then return end
    -- the labels in the client's own language (ITEM_SOLD_COLON / PURCHASED_BY_COLON; Russian on ruRU, R665)
    for _, pair in ipairs({ { _G.OpenMailInvoiceItemLabel, W.RU and _G.ITEM_SOLD_COLON or "Item Sold:", true },
                            { _G.OpenMailInvoicePurchaser, W.RU and _G.PURCHASED_BY_COLON or "Purchased By:", false } }) do
        local fs, label, is_item = pair[1], pair[2], pair[3]
        local t = fs and label and plain(fs:GetText())
        local rest = t and t:sub(1, #label) == label and t:sub(#label + 2)
        local lb = rest and W.ui_be(label)
        if lb and lb ~= label then
            local v = is_item and W.on("spells") and (W.IE[rest] or rest) or rest
            W.set_font(fs); W.swap(fs, lb .. " " .. v)
        end
    end
end
local function tr_open_mail()
    pcall(tr_invoice)
    local s = _G.OpenMailSender and OpenMailSender.Name
    -- the EN sender from Blizzard's own field: the label may already show the BE name (then the NPC check failed and
    -- the letter stayed English, 2026-10-07)
    local en = (InboxFrame and plain(InboxFrame.openMailSender)) or (s and plain(s:GetText()))
    if en and MAIL_SENDERS[en] and W.on("ui") then W.set_be(s, MAIL_SENDERS[en]) end
    local npc = en and W.N[en] and en                         -- only NPC mail: player names stay (Reply reads this text)
    if not npc then return end
    if W.on("names") then W.set_be(s, W.N[npc]) end
    local body = _G.OpenMailBodyText and InboxFrame and InboxFrame.openMailID and GetInboxText(InboxFrame.openMailID)
    local be = mail_text_be(body, npc)
    if be then W.swap(OpenMailBodyText, be, true) end
    local subj = _G.OpenMailSubject and plain(OpenMailSubject:GetText())
    local sbe = subj and subj ~= "" and mail_text_be(subj, npc)
    if sbe then W.set_font(OpenMailSubject); W.swap(OpenMailSubject, sbe) end
end
local function tr_inbox()
    if not W.is_be() then return end
    for i = 1, (INBOXITEMS_TO_DISPLAY or 7) do
        local fs = _G["MailItem" .. i .. "Sender"]
        local en = fs and plain(fs:GetText())
        if en and W.on("names") and W.N[en] then W.set_be(fs, W.N[en])
        elseif en and W.on("ui") and MAIL_SENDERS[en] then W.set_be(fs, MAIL_SENDERS[en]) end
        -- expiry "|cff..30 Days |r" (DAYS_ABBR with a |4 plural) -> «30 дзён» with Belarusian plurals (R178)
        local ex = W.on("ui") and _G["MailItem" .. i .. "ExpireTime"]
        local et = ex and plain(ex:GetText())
        -- the colour may be a |c code or set with SetTextColor ("23 Days" plain, 2026-10-07)
        local col, n, close
        if et then col, n, close = et:match("^(|c%x%x%x%x%x%x%x%x)(%d+) Days?%s*(|r)$") end
        if not n and et then col, close = "", ""; n = et:match("^%s*(%d+) Days?%s*$") end
        -- ruRU client (R665): DAYS_ABBR «30 д.»
        if not n and et and W.RU then
            col, n, close = et:match("^(|c%x%x%x%x%x%x%x%x)(%d+) д%.?%s*(|r)$")
            if not n then col, close = "", ""; n = et:match("^%s*(%d+) д%.?%s*$") end
        end
        if n then W.swap(ex, col .. days_be(tonumber(n)) .. close)
        elseif et and et ~= "" then
            local be = W.ui_be(et)
            if be and be ~= et then W.swap(ex, be) end
        end
    end
end
-- Loot window rows (R57): LootFrameElementMixin:Init sets the EN name; swap it by the slot's item id, else EN name.
local function tr_loot_row(row)
    if not (W.on("ui") and row and row.Text and row.GetSlotIndex) then return end
    local t = plain(row.Text:GetText())
    if not t or t == "" then return end
    local ok, slot = pcall(row.GetSlotIndex, row)
    local link = ok and slot and GetLootSlotLink(slot)
    local id = link and tonumber(link:match("item:(%d+)"))
    local be = (id and W.IT[id]) or W.IE[t]
    if be and be ~= t then W.swap(row.Text, be) end
end
function W.hook_loot()
    if not LootFrameElementMixin then return end
    hooksecurefunc(LootFrameElementMixin, "Init", tr_loot_row)
    -- rows made before the hook keep the old Init: re-walk the list after each open
    local f = CreateFrame("Frame")
    f:RegisterEvent("LOOT_OPENED")
    f:RegisterEvent("LOOT_SLOT_CHANGED")
    f:SetScript("OnEvent", function()
        C_Timer.After(0, function()
            local sb = LootFrame and LootFrame.ScrollBox
            if sb and sb.ForEachFrame then sb:ForEachFrame(tr_loot_row) end
        end)
    end)
end
-- Merchant window rows (R81): MerchantFrame_UpdateMerchantInfo / _UpdateBuybackInfo write the EN item names into
-- MerchantItemNName → swap by the item id of the row's link (W.IT), else the EN name (W.IE).
local function item_be(link, t)
    local id = link and tonumber(link:match("item:(%d+)"))
    return (id and W.IT[id]) or W.IE[t]
end
local function tr_merchant(buyback)
    if not (W.on("ui") and MerchantFrame and MerchantFrame:IsShown()) then return end
    local per = buyback and (BUYBACK_ITEMS_PER_PAGE or 12) or (MERCHANT_ITEMS_PER_PAGE or 10)
    for i = 1, per do
        local fs = _G["MerchantItem" .. i .. "Name"]
        local t = fs and plain(fs:GetText())
        if t and t ~= "" then
            local ok, link
            if buyback then ok, link = pcall(GetBuybackItemLink, i)
            else ok, link = pcall(GetMerchantItemLink, ((MerchantFrame.page or 1) - 1) * per + i) end
            local be = item_be(ok and link or nil, t)
            if be and be ~= t then W.set_font(fs); W.swap(fs, be) end
        end
    end
    -- the last-sold slot under the list («Выкуп», R97): MerchantBuyBackItemName = the newest buyback item
    local fs = not buyback and _G.MerchantBuyBackItemName
    local t = fs and plain(fs:GetText())
    if t and t ~= "" then
        local ok, n = pcall(GetNumBuybackItems)
        local ok2, link = pcall(GetBuybackItemLink, ok and n or 0)
        local be = item_be(ok2 and link or nil, t)
        if be and be ~= t then W.set_font(fs); W.swap(fs, be) end
    end
end
function W.hook_merchant()
    if _G.MerchantFrame_UpdateMerchantInfo then
        hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function() tr_merchant(false) end)
    end
    if _G.MerchantFrame_UpdateBuybackInfo then
        hooksecurefunc("MerchantFrame_UpdateBuybackInfo", function() tr_merchant(true) end)
    end
end
-- Skills window (R99, camelot SkillsFrame): names / categories / descriptions from SkillLine DB2 → WoWBY_Skills (its own
-- table: "Mail" is mail armor here, «Пошта» elsewhere). Rows: post-hooks on the row mixins (rows are created on first
-- show, after this hook); detail pane: after Refresh, title + description text re-set.
local function skill_be(t)
    t = plain(t)
    return t and t ~= "" and WoWBY_Skills and WoWBY_Skills[t] or nil
end
function W.hook_skills()
    -- the EN comes from the row's own data (elementData / skill info): the panel FontString hook may already have
    -- swapped the drawn text with a generic UI word ("Mail" → «Пошта», R104)
    local function row(fs, en)
        local be = fs and W.on("ui") and skill_be(en)
        if be then W.set_font(fs); W.swap(fs, be) end
    end
    if SkillsEntryMixin and SkillsEntryMixin.Initialize then
        hooksecurefunc(SkillsEntryMixin, "Initialize", function(self)
            row(self.Content and self.Content.Name, self.elementData and self.elementData.name)
        end)
    end
    if SkillsHeaderMixin and SkillsHeaderMixin.Initialize then
        hooksecurefunc(SkillsHeaderMixin, "Initialize", function(self)
            row(self.Name, self.elementData and self.elementData.name)
        end)
    end
    -- detail pane (R191): Blizzard registers the ORIGINAL Refresh for "SkillsFrame.NewSkillLineSelected"
    -- (AddStaticEventMethod), so a Refresh hook only ran on OnShow — picking another skill and back showed English.
    -- Refresh calls SetPaneTitle / SetDescription by name on every path: hook those.
    local d = SkillsFrame and SkillsFrame.SkillDetailFrame
    if d and d.SetPaneTitle and d.SetDescription then
        hooksecurefunc(d, "SetPaneTitle", function(self, title)
            if W.on("ui") then row(self.Title, title) end
        end)
        hooksecurefunc(d, "SetDescription", function(self, description)
            local be = W.on("ui") and skill_be(description)
            local desc = self.Description
            if be and desc and desc.SetText then pcall(desc.SetText, desc, be) end
        end)
    end
end
-- Chat input header (R121): "Say: ", "[3. Trade - English]: " — set by the edit box's UpdateHeader right before it
-- measures the width for the text insets → a SetText / SetFormattedText post-hook on the header swaps it first.
-- «Перакладаць чат» (R125/R127, owner 2026-09-30: opt-in, OFF by default): the chat frame builds "X says:", "[Guild]",
-- "Joined Channel:" from GLOBAL strings at print time → only way is to overwrite them. Player messages can be secret
-- values and chat code that read our globals counts as tainted, so this stays an explicit choice; off = originals back.
local CHAT_GET = {
    CHAT_SAY_GET = "%s кажа: ", CHAT_MONSTER_SAY_GET = "%s кажа: ",
    CHAT_YELL_GET = "%s крычыць: ", CHAT_MONSTER_YELL_GET = "%s крычыць: ",
    CHAT_WHISPER_GET = "%s шэпча: ", CHAT_MONSTER_WHISPER_GET = "%s шэпча: ", CHAT_BN_WHISPER_GET = "%s шэпча: ",
    CHAT_WHISPER_INFORM_GET = "Для %s: ", CHAT_BN_WHISPER_INFORM_GET = "Для %s: ",
    CHAT_GUILD_GET = "|Hchannel:GUILD|h[Гільдыя]|h %s: ", CHAT_OFFICER_GET = "|Hchannel:OFFICER|h[Афіцэры]|h %s: ",
    CHAT_PARTY_GET = "|Hchannel:PARTY|h[Група]|h %s: ", CHAT_MONSTER_PARTY_GET = "|Hchannel:PARTY|h[Група]|h %s: ",
    CHAT_PARTY_LEADER_GET = "|Hchannel:PARTY|h[Лідар групы]|h %s: ",
    CHAT_PARTY_GUIDE_GET = "|Hchannel:PARTY|h[Праваднік]|h %s: ",
    CHAT_RAID_GET = "|Hchannel:RAID|h[Рэйд]|h %s: ", CHAT_RAID_LEADER_GET = "|Hchannel:RAID|h[Лідар рэйду]|h %s: ",
    CHAT_RAID_WARNING_GET = "[Аб'ява рэйду] %s: ",
    CHAT_INSTANCE_CHAT_GET = "|Hchannel:INSTANCE_CHAT|h[Падзямелле]|h %s: ",
    CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:INSTANCE_CHAT|h[Лідар падзямелля]|h %s: ",
    CHAT_AFK_GET = "%s адышоў:", CHAT_DND_GET = "%s просіць не турбаваць: ",
    CHAT_CHANNEL_JOIN_GET = "%s далучыўся да канала.", CHAT_CHANNEL_LEAVE_GET = "%s пакінуў канал.",
    CHAT_YOU_JOINED_NOTICE = "Далучыліся да канала: |Hchannel:%d|h[%s]|h",
    CHAT_YOU_LEFT_NOTICE = "Пакінулі канал: |Hchannel:%d|h[%s]|h",
    CHAT_YOU_CHANGED_NOTICE = "Змянілі канал: |Hchannel:%d|h[%s]|h",
    CHAT_SUSPENDED_NOTICE = "Пакінулі канал: |Hchannel:%d|h[%s]|h",
}
local chat_orig = {}
function W.apply_chat_words()
    local on = W.is_be() and WoWBY_DB and WoWBY_DB.chat_be
    for k, be in pairs(CHAT_GET) do
        if chat_orig[k] == nil then chat_orig[k] = _G[k] or false end
        if on then _G[k] = be elseif chat_orig[k] then _G[k] = chat_orig[k] end
    end
end
local hdr_hooked = {}
function W.hook_chat_header()
    local function tr(fs)
        if not (W.is_be() and W.on("ui") and WoWBY_DB and WoWBY_DB.chat_be) then return end
        local t = plain(fs:GetText())
        if not t or t == "" then return end
        local inner, tail = t:match("^%[(.-)%](.*)$")
        local be
        if inner then
            local c = channel_be(inner)
            if c then be = "[" .. c .. "]" .. tail end
        else
            local core, sp = t:match("^(.-)(%s*)$")
            local b = W.ui_be(core)
            if b and b ~= core then be = b .. sp end
        end
        if be and be ~= t then W.swap(fs, be) end
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local h = _G["ChatFrame" .. i .. "EditBoxHeader"]
        if h and not hdr_hooked[h] then                  -- own table: no fields written on Blizzard frames
            hdr_hooked[h] = true
            hooksecurefunc(h, "SetText", tr)
            hooksecurefunc(h, "SetFormattedText", tr)
        end
    end
end
-- Chat tabs (R238, owner 2026-10-08): only Blizzard's two default names («Агульнае», «Журнал бою») are translated; a name
-- the player typed stays as typed. Display only: tab:SetText after FCF_SetWindowName (no resize call from our code —
-- the dock lays the tabs out in a secure path).
local tabs_hooked = false
local function chat_tab(frame)
    local tab = frame and frame.GetName and _G[(frame:GetName() or "") .. "Tab"]
    local name = frame and plain(frame.name)
    local be = name and W.CHAT_TAB_BE[name]
    if not (tab and be) then return end
    W.swap(tab, (W.is_be() and W.on("ui")) and be or name)
    -- FCF_SetWindowName measured the ENGLISH name before our swap → «Агуль…» until a click re-measured it (R518):
    -- re-measure like it does, and keep the width the dock uses later (tab.textWidth)
    if _G.PanelTemplates_TabResize and tab.Text then
        PanelTemplates_TabResize(tab, tab.sizePadding or 0)
        tab.textWidth = tab.Text:GetWidth()
    end
end
function W.apply_chat_tabs()
    if not tabs_hooked and _G.FCF_SetWindowName then
        tabs_hooked = true
        hooksecurefunc("FCF_SetWindowName", function(frame) pcall(chat_tab, frame) end)
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do pcall(chat_tab, _G["ChatFrame" .. i]) end
end
-- Auction house category list (R115): AuctionHouseFilterButton_SetUp → button:SetText(info.name) bypasses the FontString
-- hooks, so the 1 s ticker swapped it late → slow EN/BE blink on every click. Swap in the same call.
-- Belarusian search (R368): the server matches EN names only → a query with Cyrillic is turned into EN after
-- Blizzard sent it (that one finds nothing): the item names whose BE contains the query (IE), then the EN word
-- most of them share ("мурлац" → "Murloc"), or the full EN name for a single / exact match; re-searched once
local function ah_term(q)
    local ql = cyr_lower(W.strtrim(q))
    if #ql < 4 then return nil end
    local hits, exact = {}, nil
    -- a typed stem may end in a letter the names change («мурлац» vs «мурлака»): drop up to 2 letters if nothing hit
    for _ = 0, 2 do
        for en, be in pairs(W.IE or {}) do
            local bl = cyr_lower(be)
            if bl == ql then exact = en; break end
            if bl:find(ql, 1, true) then hits[#hits + 1] = en end
        end
        if exact or #hits > 0 or #ql <= 8 then break end           -- ≤ 4 Cyrillic letters left: stop
        ql = ql:gsub("[\192-\255][\128-\191]*$", "")
    end
    -- ruRU client (R665): the server matches RUSSIAN names → the hits' Russian names (WoWBY_RU.items read backwards)
    if W.RU and WoWBY_RU and WoWBY_RU.items then
        if not W.ah_ru then
            W.ah_ru = {}
            for ru, en in pairs(WoWBY_RU.items) do
                for _, e in ipairs(type(en) == "table" and en or { en }) do W.ah_ru[e] = W.ah_ru[e] or ru end
            end
        end
        local list = {}
        for _, en in ipairs(exact and { exact } or hits) do
            if W.ah_ru[en] then list[#list + 1] = W.ah_ru[en] end
        end
        if #list <= 1 then return list[1] end
        local cnt, best, bn = {}, nil, 1
        for _, ru in ipairs(list) do
            local seen = {}
            for w in cyr_lower(ru):gmatch("[%a\208\209][%a\128-\191\208\209]*") do
                if #w > 5 and not seen[w] then seen[w] = true; cnt[w] = (cnt[w] or 0) + 1 end
            end
        end
        for w, n in pairs(cnt) do
            if n > bn or (n == bn and best and #w > #best) then best, bn = w, n end
        end
        return best or list[1]
    end
    if exact then return exact end
    if #hits == 0 then return nil end
    if #hits == 1 then return hits[1] end
    local cnt = {}
    for _, en in ipairs(hits) do
        local seen = {}
        for w in en:lower():gmatch("[%a']+") do
            if #w > 2 and not seen[w] and w ~= "of" and w ~= "the" then seen[w] = true; cnt[w] = (cnt[w] or 0) + 1 end
        end
    end
    local best, bn = nil, 1
    for w, n in pairs(cnt) do
        if n > bn or (n == bn and best and #w > #best) then best, bn = w, n end
    end
    return best
end
W.ah_term = ah_term
-- bag / bank search in Belarusian (R519): the engine matches EN item names → after Blizzard's own SetItemSearch, a query
-- with Cyrillic is re-sent as its EN word («слаб» → "minor"); English queries are left alone
local bagsearch_hooked = false
function W.hook_bag_search()
    if bagsearch_hooked then return end
    bagsearch_hooked = true
    -- the boxes' XML binds OnTextChanged to the ORIGINAL BagSearch_OnTextChanged (a function reference), so a global
    -- hook never ran (R529) → hook each box's script; the bank / guild bank boxes when their addons load
    -- R533 (owner: "any item, at least name starts"): a Cyrillic query is matched by US against every item's BE name
    -- (or EN name); the engine search is cleared (nothing dimmed by Blizzard) and non-matching slots get our own dark
    -- texture. Blizzard's buttons are never written to (no SetMatchesSearch: a field write on a bag button = taint).
    local bag_q                                            -- lower-case Cyrillic query, nil = Blizzard's search
    local dim = setmetatable({}, { __mode = "k" })         -- item button -> our overlay texture
    local function mark(btn, bag, slot)
        local show = false
        if bag_q and bag and slot then
            local id = C_Container.GetContainerItemID(bag, slot)
            if id then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local en = info and plain(info.hyperlink)
                en = en and en:match("%[(.-)%]")
                local be = W.IT[id] or (en and W.IE[en])
                -- (the link name is the CLIENT's: Russian on ruRU → cyr_lower, R665)
                show = not ((be and cyr_lower(be):find(bag_q, 1, true)) or (en and cyr_lower(en):find(bag_q, 1, true)))
            end
        end
        local tx = dim[btn]
        if show and not tx then
            tx = btn:CreateTexture(nil, "OVERLAY", nil, 7)
            tx:SetColorTexture(0, 0, 0, 0.8)
            tx:SetAllPoints(btn.icon or btn)
            dim[btn] = tx
        end
        if tx then tx:SetShown(show) end
    end
    local function post_bags(frame)
        if not (frame and frame.EnumerateValidItems) then return end
        for _, btn in frame:EnumerateValidItems() do pcall(mark, btn, btn:GetBagID(), btn:GetID()) end
    end
    local function post_bank(panel)
        if not (panel and panel.EnumerateValidItems) then return end
        for btn in panel:EnumerateValidItems() do pcall(mark, btn, btn:GetBankTabID(), btn:GetContainerSlotID()) end
    end
    local function all_frames(fn)
        local frames = { _G.ContainerFrameCombinedBags }
        for _, f in ipairs(_G.ContainerFrameContainer and ContainerFrameContainer.ContainerFrames or {}) do frames[#frames + 1] = f end
        for _, f in ipairs(frames) do fn(f) end
    end
    all_frames(function(f) if f.UpdateSearchResults then hooksecurefunc(f, "UpdateSearchResults", post_bags) end end)
    if _G.BankPanel and BankPanel.UpdateSearchResults then hooksecurefunc(BankPanel, "UpdateSearchResults", post_bank) end
    local function refresh()
        all_frames(function(f) if f:IsShown() then post_bags(f) end end)
        if _G.BankPanel and BankPanel:IsShown() then post_bank(BankPanel) end
    end
    local function on_text(self)
        if not (self and self.GetText) then return end
        local q = plain(self:GetText())
        q = q and W.strtrim(q)
        if q and q:find("[\208\209]") and W.is_be() and W.on("spells") then
            bag_q = cyr_lower(q)
            if C_Container and C_Container.SetItemSearch then pcall(C_Container.SetItemSearch, "") end
        else
            bag_q = nil
        end
        refresh()
    end
    local ev = CreateFrame("Frame")                         -- items moved / looted while a query is typed
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    ev:SetScript("OnEvent", function() if bag_q then C_Timer.After(0, refresh) end end)
    local done = {}
    local function hook_boxes()
        for _, n in ipairs(_G.ITEM_SEARCHBAR_LIST or { "BagItemSearchBox", "BankItemSearchBox", "GuildItemSearchBox" }) do
            local b = _G[n]
            if b and not done[b] and b.HookScript then done[b] = true; b:HookScript("OnTextChanged", on_text) end
        end
    end
    hook_boxes()
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("BANKFRAME_OPENED")
    f:SetScript("OnEvent", hook_boxes)
end
local ah_hooked = false
function W.hook_auction()
    if ah_hooked or not _G.AuctionHouseFilterButton_SetUp then return end
    ah_hooked = true
    -- category names here are GROUPS (plural), while the same EN words elsewhere are one item's subtype ("Reagent" on a
    -- tooltip) → AH-only table first (R358, owner 2026-10-11: Элементальнае, Рэагенты, Святы, Гадаванцы)
    local AH_WORDS = { Elemental = "Элементальнае", Reagent = "Рэагенты", Holiday = "Святы", Pet = "Гадаванцы",
                       Mount = "Транспарт", Scrolls = "Скруткі", Permanent = "Пастаянныя", Temporary = "Часовыя",
                       ["Metal & Stone"] = "Метал і камень", Herb = "Травы", Arrow = "Стрэлы", Bullet = "Кулі",
                       Book = "Кнігі", Junk = "Хлам", Other = "Іншае", Miscellaneous = "Рознае",
                       -- armour types (R365: "Mail" = «Пошта» elsewhere — the mailbox)
                       Plate = "Латы", Mail = "Кальчуга", Leather = "Скура", Cloth = "Тканіна",
                       Shields = "Шчыты", Librams = "Лібрамы", Idols = "Ідалы", Totems = "Татэмы", Relic = "Рэліквіі" }
    if W.ru_alias then W.ru_alias(AH_WORDS, "ui") end       -- ruRU client (R665)
    hooksecurefunc("AuctionHouseFilterButton_SetUp", function(button)
        if not (W.on("ui") and button and button.GetText) then return end
        local t = plain(button:GetText())
        local be = t and t ~= "" and (AH_WORDS[t] or W.ui_be(t))
        if be and be ~= t then W.swap(button, be) end
    end)
    -- item name cells (R357): UpdateDisplay writes "<name>[ (10)][ quality icon]" → the EN name part is swapped by item id
    -- (IT), else by EN name (IE); the stack count / icon / colour around it stay. The panel walk only knew UI words.
    local function cell_post(self, itemKey, info)
        if not (W.is_be() and W.on("spells") and self.Text and info) or W.dual_on() then return end
        local en = plain(info.itemName)
        local t = plain(self.Text:GetText())
        if not (en and en ~= "" and t) then return end
        local be = (itemKey and W.sid_ok(itemKey.itemID) and W.IT[itemKey.itemID]) or W.IE[en]
        if not be or be == en then return end
        local s, e = t:find(en, 1, true)
        if not s then return end
        W.swap(self.Text, t:sub(1, s - 1) .. be .. t:sub(e + 1))
        if self.HandleItemNameTruncation then self:HandleItemNameTruncation() end
    end
    -- bottom tabs «Купіць / Прадаць / Аўкцыёны» (R359): sized for the EN word at OnShow → cut to «Купі…». Next frame
    -- (after our label swap): BE text, then Blizzard's own PanelTemplates_TabResize (AH = plain addon frame)
    local ahf = _G.AuctionHouseFrame
    if ahf and ahf.HookScript and _G.PanelTemplates_TabResize then
        -- R362: on the FIRST open the BE font may not be loaded yet → GetStringWidth measured short; re-measure later too
        local function fit_tabs(f)
            if not (W.is_be() and f:IsShown()) then return end
            for _, key in ipairs({ "BuyTab", "SellTab", "AuctionsTab" }) do
                local tab = f[key]
                local fs = tab and tab.Text
                local t = fs and plain(fs:GetText())
                local be = t and t ~= "" and W.ui_be(t)
                if be and be ~= t then W.swap(fs, be) end
                if fs then pcall(PanelTemplates_TabResize, tab, 0) end
            end
        end
        ahf:HookScript("OnShow", function(f)
            for _, d in ipairs({ 0, 0.3, 1 }) do C_Timer.After(d, function() fit_tabs(f) end) end
        end)
    end
    local bar = ahf and ahf.SearchBar
    if bar and bar.StartSearch then
        local busy = false
        hooksecurefunc(bar, "StartSearch", function(self)
            if busy or not (W.is_be() and W.on("spells")) then return end
            local q = plain(self.SearchBox:GetText())
            if not (q and q:find("[\208\209]")) then return end
            local en = ah_term(q)
            if not en then return end
            C_Timer.After(0.3, function()                  -- after the first (empty) query's throttle
                busy = true
                self.SearchBox:SetText(en)                 -- deliberate English (the server query), not recorded
                pcall(self.StartSearch, self)
                busy = false
            end)
        end)
    end
    for _, m in ipairs({ "AuctionHouseTableCellItemDisplayMixin", "AuctionHouseTableCellAuctionsItemDisplayMixin" }) do
        local mx = _G[m]
        if mx and mx.UpdateDisplay then hooksecurefunc(mx, "UpdateDisplay", cell_post) end
    end
    -- the big item box of the Sell / Buy panels (R946, owner screenshot "Small Egg"): SetItemInternal writes the
    -- (coloured) name → swap the EN name part by item id. Those boxes exist already (made with the AH frame), so each
    -- instance is hooked, not the mixin.
    local function display_post(self)
        if not (W.is_be() and W.on("spells") and self.Name) or W.dual_on() then return end
        local t = plain(self.Name:GetText())
        local link = self.itemLink or (self.GetItemLink and self:GetItemLink())
        local iid = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        local en = type(link) == "string" and link:match("|h%[(.-)%]|h")
        if not (t and en and en ~= "") then return end
        local be = W.item_name_be(en, iid)
        if not be or be == en then return end
        local s, e = t:find(en, 1, true)
        if s then W.swap(self.Name, t:sub(1, s - 1) .. be .. t:sub(e + 1)) end
    end
    local seen_disp = {}
    local function hook_displays(f, depth)
        if not f or depth > 4 or seen_disp[f] then return end
        seen_disp[f] = true
        if f.SetItemInternal and f.Name then hooksecurefunc(f, "SetItemInternal", display_post) end
        for _, c in ipairs({ f:GetChildren() }) do hook_displays(c, depth + 1) end
    end
    if ahf then pcall(hook_displays, ahf, 0) end
end
-- Mirror timer bars (R67: "Breath", "Fatigue", feign death): the label comes with MIRROR_TIMER_START and is set once in
-- MirrorTimerMixin:Setup. MirrorTimerContainer is an Edit Mode system frame → no hooks on it: OUR event handler, next
-- frame, plain SetText on each bar's Text.
-- NPC speech bubbles (R142/R213): the chat line was swapped, the bubble over the head stayed English. As WowUkrainizer:
-- after an NPC speaks, scan C_ChatBubbles next frames and swap a bubble whose text we know. Bubbles in instances are
-- forbidden (IsForbidden) and stay English.
-- tutorial help tips (R411: "Focus on a quest by clicking its icon" = TUTORIAL_SUPERTRACK_STEP_1): HelpTip frames set
-- their text in ApplyText and measure the box height right after → post-hook ApplyText (the mixin for frames made later,
-- each pooled frame for frames made before us) and swap there, so the height fits the Belarusian text
local helptip_hooked = setmetatable({}, { __mode = "k" })
local function helptip_text(self)
    if not (W.is_be() and W.on("ui")) then return end
    local fs = self and self.Text
    local t = fs and plain(fs:GetText())
    local be = t and t ~= "" and W.ui_be(t)
    if be and be ~= t then W.set_font(fs); W.swap(fs, be) end
end
-- boxes made before our hook copied the original ApplyText: hook them, then let their own Layout run once (it calls
-- ApplyText and sizes the box from the text). R697: the menu-bar alert "You have unopened items in your collection." pops
-- at login BEFORE hook_helptips, and HelpTip:Show never re-sets a box that is already showing → it stayed English
local function helptip_scan()
    local pool = HelpTip and HelpTip.framePool
    if not (pool and pool.EnumerateActive) then return end
    for f in pool:EnumerateActive() do
        if not helptip_hooked[f] and f.ApplyText then
            helptip_hooked[f] = true
            if f.ApplyText ~= HelpTipTemplateMixin.ApplyText then hooksecurefunc(f, "ApplyText", helptip_text) end
            if f.Layout then pcall(f.Layout, f) else pcall(helptip_text, f) end
        end
    end
end
function W.hook_helptips()
    if not (_G.HelpTip and HelpTipTemplateMixin and HelpTipTemplateMixin.ApplyText) then return end
    if not helptip_hooked[HelpTipTemplateMixin] then
        helptip_hooked[HelpTipTemplateMixin] = true
        hooksecurefunc(HelpTipTemplateMixin, "ApplyText", helptip_text)
        hooksecurefunc(HelpTip, "Show", function() pcall(helptip_scan) end)
        -- boxes already on screen (login alerts) + the ones Blizzard shows a moment after login
        pcall(helptip_scan)
        C_Timer.After(3, function() pcall(helptip_scan) end)
        C_Timer.After(10, function() pcall(helptip_scan) end)
    end
end
-- login safety notice "Remember to act responsibly … Code of Conduct on <link>" (R706): Blizzard_CodeOfConduct adds it
-- with ChatFrameUtil.AddSystemMessage at the first PLAYER_ENTERING_WORLD — past every chat filter. The line already in
-- each chat window's history is rewritten (ScrollingMessageFrame:TransformMessages); the translation keeps the
-- |HurlIndex:…|h link, so it stays clickable
local function tr_safety_notice()
    local en = plain(_G.ONLINE_SAFETY_NOTICE)
    local be = en and W.is_be() and W.on("ui") and W.ui_be(en)
    if not be or be == en then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.TransformMessages then
            pcall(cf.TransformMessages, cf, function(t) return plain(t) == en end, function(_, ...) return be, ... end)
        end
        if W.rewrite_help then W.rewrite_help(cf) end           -- "Type '/help'…" shown before our hooks were in place (R775)
    end
end
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(_, _, initial)
        if initial then
            C_Timer.After(1, tr_safety_notice); C_Timer.After(4, tr_safety_notice)
        end
    end)
end
-- other lines Blizzard writes straight into chat with ChatFrameUtil.AddSystemMessage (R948, owner screenshot "Auction
-- created." = ERR_AUCTION_STARTED from the auction house): past the chat filters → after the call, the line just added
-- to the default chat window is rewritten (same TransformMessages way as the safety notice)
if _G.ChatFrameUtil and ChatFrameUtil.AddSystemMessage then
    hooksecurefunc(ChatFrameUtil, "AddSystemMessage", function(msg)
        local en = plain(msg)
        if not (en and en ~= "" and W.is_be() and W.on("ui")) or W.ours(en) then return end
        local be = W.ui_be(en)
        local cf = _G.DEFAULT_CHAT_FRAME
        if be and be ~= en and cf and cf.TransformMessages then
            pcall(cf.TransformMessages, cf, function(t) return plain(t) == en end, function(_, ...) return be, ... end)
        end
    end)
end
-- cinematic / movie subtitles (R398): SubtitlesFrame (Blizzard_Subtitles, a plain frame) writes each SHOW_SUBTITLE
-- line ("message" or "Sender: message", SUBTITLE_FORMAT) into its Subtitles FontStrings and sizes the background from
-- the text right after → a SetText post-hook per FontString swaps before the measure. Lookup = NPC speech (W.gossip_be:
-- BroadcastText lines in gossip_fix / the gossip tables); misses are harvested as gossip.
-- Buff / debuff timers under the icons (R51, owner trial 2026-11-05; shipped R829 as the option «Працягласць эфектаў (60 хв)»
-- under «Заклёны і прадметы», WoWBY_DB.buff_times, on unless false): "40 m" → «40 хв». Blizzard writes them every frame with
-- SetFormattedText; the post-hook swaps in the same call, so no blink. A secret text in combat stays English (plain = nil).
-- EXPERIMENT: a per-object hook on these frames is what R29 warned about. If Edit Mode / action bars break, remove this block
-- + "hook_buff_times" in events.lua.
-- The owner saw «60 m» stay after a fight: the button keeps its aura data from combat, so the time stays secret and GetText
-- gives nothing. The format arrives plain, though, with only the number secret: Blizzard's own format is swapped and the
-- value passed on untouched, never read (widgets take secret values). Works in combat too, if the client allows it.
local buff_fmt, buff_busy
local function buff_time_set(fs, fmt, ...)
    if buff_busy or not (W.is_be() and W.on("spells")) or WoWBY_DB.buff_times == false or W.RU or issecretvalue and issecretvalue(fmt) then return end
    if not buff_fmt then
        buff_fmt = {}
        for k, be in pairs({ DAY_ONELETTER_ABBR = "%d д", HOUR_ONELETTER_ABBR = "%d г", MINUTE_ONELETTER_ABBR = "%d хв",
                             SECOND_ONELETTER_ABBR = "%d с" }) do
            if type(_G[k]) == "string" then buff_fmt[_G[k]] = be end
        end
    end
    local be = buff_fmt[fmt]
    if be then
        buff_busy = true
        pcall(fs.SetFormattedText, fs, be, ...)
        buff_busy = false
    end
end
local buff_times_hooked = false
function W.hook_buff_times()
    if buff_times_hooked then return end
    for _, c in ipairs({ _G.BuffFrame, _G.DebuffFrame }) do
        for _, b in ipairs(c and c.auraFrames or {}) do
            -- R855: auraFrames also holds the PrivateAuraAnchors, whose Duration is no FontString (logged an error at
            -- every login since R827)
            if b.Duration and type(b.Duration.SetFormattedText) == "function" then
                buff_times_hooked = true
                hooksecurefunc(b.Duration, "SetFormattedText", buff_time_set)
            end
        end
    end
end
local subs_hooked = false
function W.hook_subtitles()
    local sf = _G.SubtitlesFrame
    if subs_hooked or not (sf and sf.Subtitles) then return end
    subs_hooked = true
    local busy = false
    local function on_set(fs)
        if busy or not (W.is_be() and W.on("quests")) then return end
        local t = plain(fs:GetText())
        if not t or t == "" then return end
        local sender, msg = t:match("^(.-): (.+)$")
        local bracket = false
        if not sender then                                -- movies: "[Narrator] Our home." (R480; as WoWPL reads it)
            sender, msg = t:match("^%[(.-)%] (.+)$")
            bracket = sender ~= nil
        end
        local body = W.gossip_be(t)
        local out
        if body then out = body
        elseif sender then
            local mb = W.gossip_be(msg)
            local sb = W.on("names") and (W.N[sender] or W.ui_be(sender)) or sender
            if mb then out = bracket and ("[" .. sb .. "] " .. mb) or (sb .. ": " .. mb) end
        end
        if not out then W.harvest("gossip", msg or t, sender or true); return end
        busy = true
        W.set_font(fs); W.swap(fs, W.substitute(out))
        busy = false
    end
    -- the subtitle speaker is no unit: $S (R694) = masculine, never the gossip NPC that may still be open
    for _, fs in ipairs(sf.Subtitles) do hooksecurefunc(fs, "SetText", function(s) W.as_speaker(0, on_set, s) end) end
end
local bubbles_hooked = false
W.bubble_sex = {}                                     -- R694: bubble text -> speaker's sex (from the chat event)
local function scan_bubbles()
    if not (W.is_be() and W.on("quests") and C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then return end
    for _, b in pairs(C_ChatBubbles.GetAllChatBubbles() or {}) do
        if not (b.IsForbidden and b:IsForbidden()) then
            local inner = b.GetChildren and select(1, b:GetChildren())
            for i = 1, (inner and inner:GetNumRegions() or 0) do
                local r = select(i, inner:GetRegions())
                if r and r.GetObjectType and r:GetObjectType() == "FontString" then
                    local t = plain(r:GetText())
                    local be = t and t ~= "" and W.as_speaker(W.bubble_sex[t], W.gossip_be, t)
                    if be then W.set_font(r); W.swap(r, W.substitute(be)) end
                end
            end
        end
    end
end
function W.hook_bubbles()
    if bubbles_hooked then return end
    bubbles_hooked = true
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_PARTY" }) do f:RegisterEvent(e) end
    f:SetScript("OnEvent", function(_, _, msg, ...)
        -- R694: the speaker's sex by the event's GUID (arg 12), for the bubble showing this text
        local ok, sex = pcall(W.guid_sex, (select(11, ...)))
        msg = plain(msg)
        if msg then W.bubble_sex[msg] = ok and sex or nil end
        C_Timer.After(0.01, function() pcall(scan_bubbles) end)
        C_Timer.After(0.15, function() pcall(scan_bubbles) end)
    end)
end
function W.hook_mirror()
    local f = CreateFrame("Frame")
    f:RegisterEvent("MIRROR_TIMER_START")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function()
        C_Timer.After(0, function()
            local c = MirrorTimerContainer
            if not (W.on("ui") and c and c.mirrorTimers) then return end
            for _, tf in ipairs(c.mirrorTimers) do
                local t = tf.Text and plain(tf.Text:GetText())
                local be = t and t ~= "" and W.ui_be(t)
                if be and be ~= t then W.swap(tf.Text, be) end
            end
        end)
    end)
end
function W.hook_mail()
    if mail_hooked or not (_G.OpenMailFrame and OpenMailFrame.Update and _G.InboxFrame and InboxFrame.Update) then return end
    mail_hooked = true
    hooksecurefunc(OpenMailFrame, "Update", function() pcall(tr_open_mail) end)
    hooksecurefunc(InboxFrame, "Update", function() pcall(tr_inbox) end)
    -- tab "Send Mail" (R651): the shared SENDMAIL word «Адпраўка пошты» (also the send-page title) is cut to
    -- «Адпраўка...» on the tab → the verb «Адправіць», re-measured next frame (like the AH tabs)
    -- R695: both tabs, and once more 0.3 s later — on the FIRST open the BE font may not be loaded when measured (the
    -- AH tabs had the same, R362), so the tab kept a short width
    local tab = _G.MailFrameTab2
    if _G.MailFrame and MailFrame.HookScript and tab and tab.Text and _G.PanelTemplates_TabResize then
        local function fit()
            if not (W.is_be() and W.on("ui") and MailFrame:IsShown()) then return end
            if plain(tab.Text:GetText()) ~= "Адправіць" then W.swap(tab.Text, "Адправіць") end
            for _, t in ipairs({ _G.MailFrameTab1, tab }) do
                if t and t.Text then pcall(PanelTemplates_TabResize, t, 0) end
            end
        end
        MailFrame:HookScript("OnShow", function()
            C_Timer.After(0, fit)
            C_Timer.After(0.3, fit)
        end)
    end
end
local castbar_hooked = false                                -- local flag: never write keys on Blizzard frames
function W.hook_castbar()
    local bar = _G.PlayerCastingBarFrame or _G.CastingBarFrame
    if not (bar and bar.HookScript and bar.Text) or castbar_hooked then return end
    castbar_hooked = true
    local function swap(self)
        if not (W.is_be() and W.on("spells")) then return end
        local name, _, _, _, _, _, _, _, sid = UnitCastingInfo("player")
        if not name then name, _, _, _, _, _, _, sid = UnitChannelInfo("player") end
        sid, name = W.sid_ok(sid), plain(name)
        local be = (sid and W.SN[sid]) or (name and ((WoWBY_AuraByName or {})[name] or {})[1]) or
                   (name and (WoWBY_SpellNamesEN or {})[name])
        local cur = plain(self.Text:GetText())
        if be and cur and cur ~= be and (cur == name or not name) then W.swap(self.Text, be); return end
        -- "Interrupted" / "Failed" (UI words the bar shows after a cast, R48)
        local ui = cur and cur ~= name and W.on("ui") and W.ui_be(cur)
        if ui and ui ~= cur then W.swap(self.Text, ui) end
    end
    bar:HookScript("OnEvent", swap)
    bar:HookScript("OnShow", swap)
end
-- big centre banners (EventToastManagerFrame: "You've Reached / Level 10", zone/scenario toasts): after a toast is
-- shown, its FontStrings are swapped (exact UI strings or known formats; others stay English)
local toast_hooked = false
-- "New Recipe Learned!" toast (R234): the alert system stored the ORIGINAL setup function at load (setUpFunction) →
-- hook that table field; title via the UI words, recipe name by spell id / EN name / item name
local recipe_hooked = false
function W.hook_recipe_toast()
    local sys = _G.NewRecipeLearnedAlertSystem
    if recipe_hooked or not (sys and type(sys.setUpFunction) == "function") then return end
    recipe_hooked = true
    hooksecurefunc(sys, "setUpFunction", function(frame, recipeID)
        if not (W.is_be() and frame) then return end
        local tt = frame.Title and plain(frame.Title:GetText())
        local tb = tt and W.ui_be(tt)
        if tb and tb ~= tt then W.set_font(frame.Title); W.swap(frame.Title, tb) end
        local n = frame.Name and plain(frame.Name:GetText())
        local en, rest
        if n then en, rest = n:match("^(.-)(%s*|T.*)$") end
        en = en or n
        local nb = en and W.on("spells") and ((recipeID and W.SN[recipeID]) or W.spell_name_be(en) or W.IE[en])
        if nb then W.set_font(frame.Name); W.swap(frame.Name, nb .. (rest or "")) end
    end)
end
-- Legacy challenge toast (R273): Forever's achievements = Legacy challenges. Same stored-setUpFunction case as the recipe
-- toast: heading «Выпрабаванне спадчыны пройдзена» (ACHIEVEMENT_UNLOCKED) + the challenge name, swapped right after setup.
local ach_hooked = false
function W.hook_achievement_toast()
    local sys = _G.AchievementAlertSystem
    if ach_hooked or not (sys and type(sys.setUpFunction) == "function") then return end
    ach_hooked = true
    hooksecurefunc(sys, "setUpFunction", function(frame)
        if not (W.is_be() and W.on("ui") and frame) then return end
        for _, fs in ipairs({ frame.Unlocked, frame.Name }) do
            local t = fs and plain(fs:GetText())
            local be = t and t ~= "" and W.ui_be(t)
            if be and be ~= t then W.set_font(fs); W.swap(fs, be) end
        end
    end)
end
-- loot toast (R735, owner screenshot 2026-10-23: "You received / Medallion of Steadfast Might" English): same stored
-- setUpFunction case — label via the UI words, item name by the link's id / EN name
local loot_hooked = false
function W.hook_loot_toast()
    local sys = _G.LootAlertSystem
    if loot_hooked or not (sys and type(sys.setUpFunction) == "function") then return end
    loot_hooked = true
    hooksecurefunc(sys, "setUpFunction", function(frame, link)
        if not (W.is_be() and frame) then return end
        local lt = frame.Label and plain(frame.Label:GetText())
        local lb = lt and W.on("ui") and W.ui_be(lt)
        if lb and lb ~= lt then W.set_font(frame.Label); W.swap(frame.Label, lb) end
        local n = frame.ItemName and plain(frame.ItemName:GetText())
        local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        local nb = n and W.on("spells") and (W.IE[n] or (id and W.IT[id]))
        if nb then W.set_font(frame.ItemName); W.swap(frame.ItemName, nb) end
    end)
end
function W.hook_toasts()
    local f = _G.EventToastManagerFrame
    if not f or toast_hooked then return end
    toast_hooked = true
    local function walk(fr)
        W.each_fs(fr, 6, function(r)
            local t = plain(r:GetText())
            local be = t and t ~= "" and W.ui_be(t)
            if be and be ~= t then W.set_font(r); W.swap(r, be) end
        end)
    end
    local function later() if W.is_be() and W.on("ui") then C_Timer.After(0, function() walk(f, 0) end) end end
    f:HookScript("OnShow", later)
    -- NO hooksecurefunc(f, "DisplayToast"): a hooked method key on the toast manager made Blizzard's level-up toast run
    -- tainted → Edit Mode anchor callbacks → "GetAuraDataByIndex … tainted by WoWBY" at every level-up (R459). The next
    -- toasts while the frame stays shown are caught by a light poll instead (reads + SetText on its FontStrings only).
    local acc = 0
    CreateFrame("Frame"):SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc < 0.25 then return end
        acc = 0
        if f:IsShown() and W.is_be() and W.on("ui") then walk(f, 0) end
    end)
end
-- "Are you sure you want to cancel this cinematic?" + Yes / No (R477): the in-game cinematic's and the movie's close
-- dialogs are plain frames with XML texts → swapped when shown (script hook, next frame like the panels, R29)
local cine_hooked = false
function W.hook_cinematic()
    if cine_hooked then return end
    cine_hooked = true
    local function tr(fs)
        local t = plain(fs:GetText())
        local be = t and t ~= "" and W.ui_be(t)
        if be and be ~= t then W.set_font(fs); W.swap(fs, be) end
    end
    for _, d in ipairs({ _G.CinematicFrameCloseDialog, _G.MovieFrame and _G.MovieFrame.CloseDialog }) do
        if d and d.HookScript then
            d:HookScript("OnShow", function(self)
                C_Timer.After(0, function() if W.is_be() and W.on("ui") then W.each_fs(self, 4, tr) end end)
            end)
        end
    end
end
-- Death Recap (R508): entries (ScrollBox pool, DeathRecapEntryMixin:Init sets Caster / Name) + the frame's own labels
local recap_hooked = false
function W.hook_deathrecap()
    local M, f = _G.DeathRecapEntryMixin, _G.DeathRecapFrame
    if recap_hooked or not (M and M.Init and f) then return end
    recap_hooked = true
    hooksecurefunc(M, "Init", function(self)
        if not W.is_be() then return end
        local si = self.GetSpellInfo and self:GetSpellInfo()
        local nm = si and si.Name and plain(si.Name:GetText())
        local nb = nm and ((W.on("spells") and W.spell_name_be(nm)) or W.ui_be(nm))
        if nb and nb ~= nm then W.swap(si.Name, nb) end
        local c = si and si.Caster and plain(si.Caster:GetText())
        local cb = c and W.on("names") and W.N[c]
        if cb then W.swap(si.Caster, cb) end
    end)
    f:HookScript("OnShow", function(self)
        C_Timer.After(0, function()
            if not (W.is_be() and W.on("ui")) then return end
            W.each_fs(self, 3, function(fs)
                local t = plain(fs:GetText())
                local be = t and t ~= "" and W.ui_be(t)
                if be and be ~= t then W.set_font(fs); W.swap(fs, be) end
            end)
        end)
    end)
end
-- static «Dead» / «Unconscious» labels over the Target/Focus/ToT health bars (XML text="DEAD"; Blizzard only
-- shows/hides them). Plain SetText out of combat — no hooks or fields on the secure unit frames (taint rule).
local DEAD_M, DEAD_F = "Мёртвы", "Мёртвая"
function W.unit_static_labels()
    if not W.on("ui") or InCombatLockdown() then return end
    local conts = {}                                              -- { container, unit }
    for _, p in ipairs({ { _G.TargetFrame, "target" }, { _G.FocusFrame, "focus" } }) do
        local fr = p[1]
        local c = fr and fr.TargetFrameContent and fr.TargetFrameContent.TargetFrameContentMain
        if c and c.HealthBarsContainer then conts[#conts + 1] = { c.HealthBarsContainer, p[2] } end
    end
    for _, p in ipairs({ { _G.TargetFrameToT, "targettarget" }, { _G.FocusFrameToT, "focustarget" } }) do
        if p[1] and p[1].HealthBar then conts[#conts + 1] = { p[1].HealthBar, p[2] } end
    end
    for _, cu in ipairs(conts) do
        local c, u = cu[1], cu[2]
        for _, k in ipairs({ "DeadText", "UnconsciousText" }) do
            local fs = c[k]
            local cur = fs and plain(fs:GetText())
            -- «Мёртвы» / «Мёртвая» by the unit's sex (R32, owner 2026-09-29); our own earlier text counts as "Dead"
            local t = (cur == DEAD_M or cur == DEAD_F) and "Dead" or (cur and W.RU and W.en_line(cur)) or cur
            local be = t and W.label_be(t)
            if be and t == "Dead" then be = (UnitExists(u) and UnitSex(u) == 3) and DEAD_F or DEAD_M end
            if be and be ~= cur then pcall(fs.SetText, fs, be) end
        end
    end
end
local function tr_bag_title(frame)
    if not (W.on("ui") and frame and frame.GetTitleText) then return end
    local fs = frame:GetTitleText()
    local t = fs and plain(fs:GetText())
    if not t or t == "" then return end
    local be
    local bag = frame.GetBagID and frame:GetBagID()
    if bag and bag > 0 and C_Container and C_Container.ContainerIDToInventoryID then
        local ok, inv = pcall(C_Container.ContainerIDToInventoryID, bag)
        local id = ok and inv and GetInventoryItemID("player", inv)
        be = id and W.IT[id]
    end
    be = be or W.IE[t] or W.ui_be(t)
    if be and be ~= t then W.swap(fs, be) end
end
local bags_hooked = false
function W.hook_bags()
    if bags_hooked then return end
    local frames = {}
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do frames[#frames + 1] = _G["ContainerFrame" .. i] end
    frames[#frames + 1] = _G.ContainerFrameCombinedBags
    for _, f in ipairs(frames) do
        if f and f.UpdateName then
            hooksecurefunc(f, "UpdateName", tr_bag_title)
            bags_hooked = true
        end
    end
end
W.hook_bags()

-- trade window item names (R915, QA 2026-11-11: "Pellet Rifle" stayed English): TradeFrame_UpdatePlayerItem /
-- UpdateTargetItem set the name FontString with the EN name → swap by item id (display only, global post-hook)
local function tr_trade_item(prefix, info, id)
    if not (W.on("spells") and type(id) == "number" and id ~= TRADE_ENCHANT_SLOT) then return end
    local fs = _G[prefix .. id .. "Name"]
    local t = fs and plain(fs:GetText())
    if not t or t == "" then return end
    local ok, _, _, _, _, a5, a6, a7, a8 = pcall(info, id)
    local iid = ok and (prefix == "TradePlayerItem" and a8 or a7)
    local be = W.item_name_be(t, W.sid_ok(iid) and iid or nil)
    if be and be ~= t then W.swap(fs, be) end
end
local trade_hooked = false
function W.hook_trade()
    if trade_hooked or not _G.TradeFrame_UpdatePlayerItem then return end
    trade_hooked = true
    hooksecurefunc("TradeFrame_UpdatePlayerItem", function(id) tr_trade_item("TradePlayerItem", GetTradePlayerItemInfo, id) end)
    hooksecurefunc("TradeFrame_UpdateTargetItem", function(id) tr_trade_item("TradeRecipientItem", GetTradeTargetItemInfo, id) end)
end
W.hook_trade()

-- group loot roll frames (R944, owner screenshot "Malachite"): GroupLootFrame_SetupItemDisplay sets Name from
-- GetLootRollItemInfo → swap by the roll's item link id (plain text swap, no fields on the frame)
local function tr_loot_roll(self)
    if not (self and self.rollID and self.Name and W.on("names")) then return end
    local en = plain(self.Name:GetText())
    if not en or en == "" or W.ours(en) then return end
    local link = GetLootRollItemLink and GetLootRollItemLink(self.rollID)
    local iid = link and tonumber(link:match("item:(%d+)"))
    local be = W.item_name_be(en, iid)
    if be and be ~= en then W.set_font(self.Name); W.swap(self.Name, be) end
end
local roll_hooked = false
local function hook_loot_roll()
    if roll_hooked or not _G.GroupLootFrame_SetupItemDisplay then return end
    roll_hooked = true
    hooksecurefunc("GroupLootFrame_SetupItemDisplay", tr_loot_roll)
end
hook_loot_roll()
if not roll_hooked then                     -- Blizzard_UIPanels_Game may load after us
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN"); f:RegisterEvent("START_LOOT_ROLL")
    f:SetScript("OnEvent", function(self)
        hook_loot_roll()
        if roll_hooked then self:UnregisterAllEvents() end
    end)
end

-- friends / recent allies rows (R930, owner: "first open waits, then updates in a sec or two"): rows come from scroll-box
-- pools, so the panel walk only met them on its 1 s ticker → swap each row's texts right when Blizzard fills it
local function tr_row(button)
    if not (button and W.on("ui")) then return end
    W.each_fs(button, 3, function(fs)
        W.friend_row_fs = fs                                        -- retext_fs shortens «Узровень» here (R927)
        pcall(W.retext_fs, fs)
        W.friend_row_fs = nil
    end)
    -- recent allies (R939, owner screenshot "Уз…"): SetCharacterLevel sized the Level string to the ENGLISH text; refit
    local lv = button.CharacterData and button.CharacterData.Level
    if lv and lv.GetUnboundedStringWidth then pcall(lv.SetWidth, lv, lv:GetUnboundedStringWidth() + 1) end
end

-- recent-ally tooltip (R939): "Fought Together - Durotar" (RECENT_ALLY_TOOLTIP_INTERACTION_WITH_CONTEXT_FORMAT "%s - %s",
-- both parts known) and "< 1 Hour ago" on the right
local function tr_ally_tooltip()
    local tt = GameTooltip
    if not (W.on("ui") and tt and tt:IsShown()) then return end
    for i = 1, tt:NumLines() do
        for _, side in ipairs({ "Left", "Right" }) do
            local fs = _G["GameTooltipText" .. side .. i]
            local t = fs and plain(fs:GetText())
            if t and t ~= "" and not W.ours(t) then
                local be = W.ui_be(t)
                if not be then
                    local a, b = t:match("^(.-) %- (.+)$")
                    local ba = a and W.ui_be(a)
                    local bb = b and (W.Z[b] or W.ui_be(b))
                    if ba and bb then be = ba .. " — " .. bb end
                end
                if be then fs:SetText(be) end
            end
        end
    end
    tt:Show()
end
local friends_hooked, allies_hooked = false, false
function W.hook_friend_rows()
    if not friends_hooked and _G.FriendsFrame_UpdateFriendButton then
        friends_hooked = true
        hooksecurefunc("FriendsFrame_UpdateFriendButton", tr_row)
    end
    if not allies_hooked and _G.RecentAlliesEntryMixin and RecentAlliesEntryMixin.Initialize then
        allies_hooked = true
        hooksecurefunc(RecentAlliesEntryMixin, "Initialize", tr_row)
        if RecentAlliesEntryMixin.ShowTooltip then hooksecurefunc(RecentAlliesEntryMixin, "ShowTooltip", tr_ally_tooltip) end
    end
end
W.hook_friend_rows()
if _G.FriendsFrame then FriendsFrame:HookScript("OnShow", function() W.hook_friend_rows() end) end

-- swing timer bars (R931, owner): "Main Hand" / "Off Hand" / "Ranged" labels, set once by InitializeBarPresentation.
-- Edit Mode systems (R607: never hook them or write fields) → plain text swap from our own events, out of combat
local function tr_swing()
    if not W.on("ui") or InCombatLockdown() then return end
    for _, n in ipairs({ "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }) do
        local f = _G[n]
        local fs = f and f.GetTypeLabel and f:GetTypeLabel()
        local t = fs and plain(fs:GetText())
        local be = t and t ~= "" and W.ui_be(t)
        if be and be ~= t then W.swap(fs, be) end
    end
end
do
    local sf = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_EQUIPMENT_CHANGED" }) do
        pcall(sf.RegisterEvent, sf, e)
    end
    sf:SetScript("OnEvent", function() C_Timer.After(0.5, tr_swing) end)
end

-- party / raid manager panel (R919, owner 2026-11-11: "Party", "Unit / Ground", "Restrict Pings To:", "Leave Party"):
-- the panel holds secure raid-marker buttons, so NO per-FontString hooks and no fields on its frames — only a plain
-- text swap from our own event handler / a next-frame timer, out of combat (the R914 unit-menu taint came from running
-- inside Blizzard's own call path). Blizzard re-sets the labels on roster updates; we swap again after each one.
-- words whose shared UI translation means something else here (Ground = «Наземны транспарт» in the mount journal)
local RM_WORDS = { Unit = "На цэль", Ground = "На зямлю", ["Restrict Pings To:"] = "Сігналы толькі ад:",
                   ["Leave Instance Group"] = "Пакінуць групу падзямелля" }
local function tr_raid_manager()
    local m = _G.CompactRaidFrameManager
    if not (m and m.displayFrame and W.on("ui")) or InCombatLockdown() then return end
    W.each_fs(m.displayFrame, 5, function(fs)
        local t = plain(fs:GetText())
        if t and t ~= "" and not t:find("^[%d%s/]+$") then
            local be = RM_WORDS[t] or W.ui_be(t)
            if be and be ~= t then W.swap(fs, be) end
        end
    end)
end
local function tr_raid_manager_later() C_Timer.After(0, tr_raid_manager) end
do
    local rf = CreateFrame("Frame")
    rf:RegisterEvent("GROUP_ROSTER_UPDATE")
    rf:RegisterEvent("PLAYER_ENTERING_WORLD")
    rf:RegisterEvent("PLAYER_REGEN_ENABLED")
    rf:SetScript("OnEvent", tr_raid_manager_later)
    if _G.CompactRaidFrameManager_Expand then hooksecurefunc("CompactRaidFrameManager_Expand", tr_raid_manager_later) end
end
do
    local tf = CreateFrame("Frame")
    tf:RegisterEvent("TRADE_SHOW")
    tf:SetScript("OnEvent", function() W.hook_trade() end)
end

-- objective tracker headers ("All Objectives", "Quests", "Achievements"…): set once at init and by modules
-- (SetHeader) — swapped after every tracker update (display only; quest titles/lines are done in tracker_post)
function W.tr_tracker_headers()
    local c = _G.ObjectiveTrackerFrame
    if not (c and W.on("ui")) then return end
    if c.Header and c.Header.Text then W.retext_fs(c.Header.Text) end
    for _, m in ipairs(c.modules or {}) do
        local fs = m.Header and m.Header.Text
        if fs then
            local zb = W.zone_be and W.zone_be(fs:GetText())    -- zone-widget / scenario header = zone name (R156)
            if zb then W.set_font(fs); W.swap(fs, zb) else W.retext_fs(fs) end
        end
    end
end
local tracker_hooked = false
function W.hook_tracker()                            -- the tracker may be created after WoWBY loads
    if tracker_hooked or not (_G.ObjectiveTrackerFrame and ObjectiveTrackerFrame.Update) then return end
    tracker_hooked = true
    hooksecurefunc(ObjectiveTrackerFrame, "Update", function() pcall(W.tr_tracker_headers) end)   -- R741: never break the update
    W.tr_tracker_headers()
end
W.hook_tracker()

-- Belarusian emote commands (R576, owner: "/смех" from the chat menu did nothing): the chat menu shows the emote
-- commands translated («/смех», «/дзякую»), so each translated EMOTEn_CMDm is registered as our own slash command that
-- performs the same emote token. Our own SlashCmdList entries only (no Blizzard table written).
W.EMOTE_LABEL = {}
function W.register_emote_cmds()
    local U = WoWBY_UI or {}
    if not (SlashCmdList and MAXEMOTEINDEX) then return end
    local perform = (C_ChatInfo and C_ChatInfo.PerformEmote) or _G.DoEmote
    if not perform then return end
    local seen, n = {}, 0
    for i = 1, MAXEMOTEINDEX do
        local token = _G["EMOTE" .. i .. "_TOKEN"]
        local j, cmd = 1, _G["EMOTE" .. i .. "_CMD1"]
        while token and cmd do
            local be = U[cmd]
            if type(be) == "string" and be:find("^/[^%s]+$") and be:find("[89]") and not seen[be] then
                seen[be] = true
                -- chat menu label like the chat-type list (owner R576): «Смех  /laugh» = meaning + the English command
                local lab = W.cap_like("A", be:sub(2)) .. "  |cff9d9d9d" .. cmd .. "|r"
                W.EMOTE_LABEL[cmd], W.EMOTE_LABEL[be] = lab, lab
                n = n + 1
                local key = "WOWBY_EMOTE" .. n
                SlashCmdList[key] = function(msg) perform(token, msg) end
                _G["SLASH_" .. key .. "1"] = be
            end
            j = j + 1
            cmd = _G["EMOTE" .. i .. "_CMD" .. j]
        end
    end
end
