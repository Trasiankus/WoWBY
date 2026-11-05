-- WoWBY/core/dialogueui.lua — DialogueUI window words, fonts, translator hook.
-- Split from core.lua (tools/split_core.py); shared state lives in the addon namespace W.
local _, W = ...
-- DialogueUI's own UI words are captured from the globals before WoWBY loads (L["Accept"] = ACCEPT …), so they are
-- swapped where DialogueUI sets them: its frame/mixin methods are plain addon code (no Blizzard security) and are
-- wrapped to pass Belarusian text in. Header title = our quest title, refitted like DialogueUI does.
local DUI_WORDS = { Complete = "Завяршыць", ["Complete Quest"] = "Завяршыць заданне" }   -- button verbs, not «Завершана»
if W.ru_alias then W.ru_alias(DUI_WORDS, "ui") end            -- ruRU client (R665)
local function dui_word(t)
    if not (W.is_be() and W.on("ui")) or type(t) ~= "string" then return t end
    return DUI_WORDS[t] or W.label_be(t) or t
end
-- option buttons (R82): quest titles by the button's quest id (available / active quests in the NPC list), gossip
-- options by EN (W.gossip_be: player name / race / class tokens), else the UI words
local function dui_label(self, t)
    if not (W.is_be() and type(t) == "string") then return t end
    local qid = self and (self.type == "availableQuest" or self.type == "activeQuest") and self.questID
    local be = qid and W.on("quests") and W.be_title(qid)
    if be then return be end
    -- with hotkeys on, DialogueUI puts the number in front first ("1. I want to browse your goods.", SetGossip):
    -- translate the rest, keep the number (2026-10-07: options stayed English in DialogueUI only)
    local key, rest = t:match("^(%d+%. )(.+)$")
    if W.on("quests") then
        be = W.gossip_be(rest or t)
        if be then return (key or "") .. W.substitute(be) end
    end
    if key then
        local w = dui_word(rest)
        if w ~= rest then return key .. w end
    end
    return dui_word(t)
end
local function dui_wrap_ui()
    local f = _G.DUIQuestFrame
    if f and f.AcquireAndSetSubHeader then
        local o = f.AcquireAndSetSubHeader
        f.AcquireAndSetSubHeader = function(self, text, ...) return o(self, dui_word(text), ...) end
    end
    if f and f.UpdateQuestTitle then
        hooksecurefunc(f, "UpdateQuestTitle", function(self)
            local title = self.FrontFrame and self.FrontFrame.Header and self.FrontFrame.Header.Title
            local be = title and W.is_be() and W.be_title(self.questID or (GetQuestID and GetQuestID()))
            if not be then return end
            title:SetFontObject("DUIFont_Quest_Title_18")
            W.swap(title, be)
            if title:GetNumLines() > 1 then
                title:SetFontObject("DUIFont_Quest_Title_16")
                if title:GetNumLines() > 1 then title:SetFontObject("DUIFont_Quest_Paragraph") end
            end
        end)
    end
    local ob = _G.DUIDialogOptionButtonMixin                  -- Accept / Decline / Continue … (pooled buttons)
    if ob and ob.SetButtonText then
        local o = ob.SetButtonText
        ob.SetButtonText = function(self, name, ...) return o(self, dui_label(self, name), ...) end
    end
    -- quest difficulty tag above the title (R777): DialogueUI's own locale words, same page walk as the item names
    local DUI_DIFFICULTY = { ["Very Hard"] = "Вельмі цяжкае", Hard = "Цяжкае", Normal = "Звычайнае", Easy = "Лёгкае",
                             ["Low Level"] = "Нізкі ўзровень" }
    -- item buttons that were pooled before our mixin wrap keep DialogueUI's own SetItemName, and names arrive late
    -- (item info loads async) -> after each quest page, swap any FontString that is exactly a known EN item name
    local function walk(fr, depth)
        if not fr or depth > 10 then return end
        for _, r in ipairs({ fr:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" then
                local t = plain(r:GetText())
                -- R643: spell rewards («Вы вывучыце наступнае:» Growl / Maul) — only on reward buttons (they have SetItemName)
                local sp = t and W.on("spells") and fr.SetItemName and W.spell_name_be and W.spell_name_be(t)
                if t and W.on("spells") and (sp or W.IE[t]) then W.swap(r, sp or W.IE[t]) end
                if t and W.on("quests") and DUI_DIFFICULTY[t] then W.swap(r, DUI_DIFFICULTY[t]) end
            end
        end
        for _, c in ipairs({ fr:GetChildren() }) do
            -- option buttons (Accept / Decline …) created before our mixin wrap carry DialogueUI's own copy of
            -- SetButtonText: wrap the instance too, and fix the label already shown
            if c.SetButtonText and c.Name and not c.wowby_btn then
                c.wowby_btn = true
                local o = c.SetButtonText
                c.SetButtonText = function(self, name, ...) return o(self, dui_label(self, name), ...) end
            end
            if c.wowby_btn and c.Name then
                local t = plain(c.Name:GetText())
                local be = t and dui_label(c, t)
                if be and be ~= t then W.swap(c.Name, be) end
            end
            walk(c, depth + 1)
        end
    end
    local function items_later(self)
        if not W.is_be() then return end
        C_Timer.After(0, function() walk(self, 0) end)
        C_Timer.After(0.5, function() walk(self, 0) end)
    end
    -- its translation view inserts the translated TITLE as the first paragraph (font DUIFont_Quest_MultiLanguage), made
    -- for an English header; ours is Belarusian already → the title showed twice (R515): that paragraph is skipped
    if f and f.InsertParagraph then
        local oi = f.InsertParagraph
        f.InsertParagraph = function(self, offsetY, text, fontObject, ...)
            if fontObject == "DUIFont_Quest_MultiLanguage" and W.is_be() and type(text) == "string" then
                local qid = self.questID or (GetQuestID and GetQuestID())
                local be = qid and W.be_title and W.be_title(qid)
                if be and plain(text) == be then return offsetY end
            end
            return oi(self, offsetY, text, fontObject, ...)
        end
    end
    -- progress page objectives (R525): one text of "- 0/10 Prideclaw Pelt" lines (its GetQuestLogProgress) → each
    -- line through obj_line_be; all lines known or the text stays as it is
    if f and f.InsertText then
        local ot = f.InsertText
        f.InsertText = function(self, offsetY, text, ...)
            local t = type(text) == "string" and W.is_be() and W.on("quests") and plain(text)
            if t and t:find("^%- ") then
                local qid = self.questID or (GetQuestID and GetQuestID())
                local out, ok = {}, true
                for line in (t .. "\n"):gmatch("(.-)\n") do
                    local rest = line:match("^%- (.+)$")
                    local be = rest and W.obj_line_be(rest, qid)
                    if not be then ok = false; break end
                    out[#out + 1] = "- " .. be
                end
                if ok then text = table.concat(out, "\n") end
            end
            return ot(self, offsetY, text, ...)
        end
    end
    -- NPC greeting (R82): DialogueUI reads the gossip text through its own copy of C_GossipInfo.GetText (captured before
    -- WoWBY loads) and lays it out with FormatParagraph → translate the whole text there (quest texts are BE already)
    if f and f.FormatParagraph then
        local o = f.FormatParagraph
        f.FormatParagraph = function(self, offsetY, text, ...)
            if type(text) == "string" and W.is_be() and W.on("quests") then
                local t = plain(text)
                local be = t and W.gossip_be(t)
                if not be and t then                           -- "Name: text" when DialogueUI prefixes the NPC name
                    local pre, rest = t:match("^(.-:%s+)(.+)$")
                    local b2 = rest and W.gossip_be(rest)
                    if b2 then be = pre .. b2 end
                end
                if be then text = be end
                -- a miss: our C_GossipInfo.GetText wrapper (which DialogueUI bypasses) harvests the NPC's text (R512:
                -- "Where to begin? Our home is failing…" was never collected while the options were)
                if not be and t and not W.ours(t) and C_GossipInfo and C_GossipInfo.GetText then
                    pcall(C_GossipInfo.GetText)
                end
            end
            return o(self, offsetY, text, ...)
        end
    end
    for _, m in ipairs({ "HandleQuestDetail", "HandleQuestProgress", "HandleQuestComplete", "HandleQuestGreeting",
                         "HandleGossip" }) do
        if f and f[m] then hooksecurefunc(f, m, items_later) end
    end
    local ib = _G.DUIDialogItemButtonMixin                     -- reward / required item names
    if ib and ib.SetItemName then
        local o = ib.SetItemName
        ib.SetItemName = function(self, name, ...)
            if type(name) == "string" and W.is_be() and W.on("spells") then
                -- R643/R644: spell rewards too — a spell name wins ("Maul" the druid ability, not the weapon «Кувалда»)
                name = (W.spell_name_be and W.spell_name_be(name)) or W.IE[name] or name
            end
            return o(self, name, ...)
        end
    end
end
-- DialogueUI's own fonts (Friz/Trajan roman members) have no Cyrillic -> Belarusian labels (REWARD_CHOICES …)
-- drew as boxes. Its DUIFont_* objects get our Friz whenever DialogueUI (re)sets them; ARIALN has і/ў already.
local dui_font_busy = false
local function dui_fix_font(obj)
    if dui_font_busy or not W.is_be() then return end
    local file, size, flags = obj:GetFont()
    if not file or not size or size <= 0 then return end
    local u = file:upper()
    if u:find("ARIALN", 1, true) or u:find("WOWBY", 1, true) then return end
    dui_font_busy = true
    pcall(obj.SetFont, obj, W.by_font(file) or W.FONT, size, flags or "")
    dui_font_busy = false
end
-- DialogueUI's own tooltips (R784): its words live in a private locale table and the tooltip frames have no name, but every
-- line goes through the frame's plain method AddLeftLine, so that is wrapped per frame (found by that method). DialogueUI's
-- files stay untouched.
local DUI_TIP = {
    ["Very Hard"] = "Вельмі цяжкае", Hard = "Цяжкае", Normal = "Звычайнае", Easy = "Лёгкае", ["Low Level"] = "Нізкі ўзровень",
    ["Your Level"] = "Ваш узровень", ["Quest Level"] = "Узровень задання", Translator = "Перакладчык",
    ["Left click to hide the translation."] = "Левы клік: схаваць пераклад.",
    ["Left click to show the translation."] = "Левы клік: паказаць пераклад.",
    ["Right click to hide original texts."] = "Правы клік: схаваць арыгінал.",
    ["Right click to show original texts."] = "Правы клік: паказаць арыгінал.",
}
local function dui_tip_line(text)
    local t = plain(text)
    if not (t and W.is_be() and W.on("ui")) then return text end
    local src = t:match("^Source: (.+)$")
    if src then return "Крыніца: " .. src end
    if DUI_TIP[t] then return DUI_TIP[t] end
    local ok, be = pcall(W.ui_be, t)
    return ok and be or text
end
local function dui_wrap_tooltips()
    if not EnumerateFrames then return end
    local f = EnumerateFrames()
    while f do
        local ok, m = pcall(function() return not f:IsForbidden() and rawget(f, "AddLeftLine") end)
        if ok and type(m) == "function" and not rawget(f, "wowby_tip") then
            f.wowby_tip = true
            f.AddLeftLine = function(self, text, ...) return m(self, dui_tip_line(text), ...) end
        end
        f = EnumerateFrames(f)
    end
end
W.dui_wrap_tooltips = dui_wrap_tooltips
local dui_done = false
function W.hook_dialogueui()
    if dui_done or not _G.DialogueUIAPI then return end
    dui_done = true
    if DialogueUIAPI.SetTranslator then
        DialogueUIAPI.SetTranslator({ name = "WoWBY", font = W.FONT, questDataGetter = W.dui_quest_data })
        -- R777 (owner): Belarusian only, no English paragraphs. Set ONCE: right-clicking DialogueUI's translator icon
        -- brings the English back and stays that way. Skipped while WoWBY's bilingual option is on.
        if WoWBY_DB and not WoWBY_DB.dui_orig_off and type(_G.DialogueUI_DB) == "table" and not (W.dual_on and W.dual_on()) then
            _G.DialogueUI_DB.TranslatorShowOriginalText = false
            WoWBY_DB.dui_orig_off = true
        end
    end
    dui_wrap_ui()
    -- created while DialogueUI loads; one late pass for a frame made on first use
    pcall(dui_wrap_tooltips)
    C_Timer.After(5, function() pcall(dui_wrap_tooltips) end)
    for name, obj in pairs(_G) do
        if type(name) == "string" and name:find("^DUIFont") and type(obj) == "table" and obj.GetObjectType then
            local ok, kind = pcall(obj.GetObjectType, obj)
            if ok and kind == "Font" then
                dui_fix_font(obj)
                hooksecurefunc(obj, "SetFont", dui_fix_font)
            end
        end
    end
end
