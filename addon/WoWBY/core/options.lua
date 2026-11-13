-- WoWBY/core/options.lua — options window, /wowby, tooltip dump, minimap button.
-- Split from core.lua (tools/split_core.py); shared state lives in the addon namespace W.
local _, W = ...
-- ---------- options window (left-click BY / addon compartment / /wowby) ----------
local minimapBtn
local opts
local function update_label()
    if not minimapBtn then return end
    local be = W.is_be()
    minimapBtn.text:SetText(be and "BY" or "EN")
    if be then minimapBtn.text:SetTextColor(1, 0.82, 0) else minimapBtn.text:SetTextColor(0.85, 0.85, 0.85) end
end
local function set_lang(be)
    WoWBY_DB.lang = be and "be" or "en"
    -- R384: to English → every text we swapped in still showing our Belarusian gets its English back first
    if not be and W.restore_en then pcall(W.restore_en) end
    update_label(); W.refresh()
    if opts and opts:IsShown() then opts.sync() end
end
local function toggle_lang()
    set_lang(not W.is_be())
    DEFAULT_CHAT_FRAME:AddMessage("|cff8080ffWoWBY:|r " .. (W.is_be() and "беларуская" or "English"))
end
local AREAS = { { "quests", "Заданні: тэксты, журнал, трэкер" }, { "names", "Імёны і званні NPC" },
                { "zones", "Назвы зон і мясцін" }, { "spells", "Заклёны і прадметы" },
                { "ui", "Меню і інтэрфейс" } }
local function label(parent, text, size)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetFont(W.FONT, size or 12, ""); fs:SetText(text); fs:SetJustifyH("LEFT")
    return fs
end
-- a page in Blizzard's Settings → AddOns (owner 2026-10-09, R290; was our own window): a canvas frame the Settings
-- panel parents and shows; the minimap button / addon compartment / /wowby open Settings at this page
local category
local function build_options(gname)
    local f = CreateFrame("Frame", gname)
    f:SetSize(400, 592); f:Hide()                  -- +28: the with-bars sub-option (R743); +12: counter on 2 lines (R781); +28: buff timers (R829)
    local title = label(f, "|cff8080ffWoWBY|r — беларускі пераклад", 15); title:SetPoint("TOPLEFT", 24, -16)
    f.page_title = title                           -- the standalone window has it in its header instead

    local lang = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    lang:SetSize(240, 24); lang:SetPoint("TOPLEFT", 24, -50)
    lang:SetScript("OnClick", function() toggle_lang() end)

    local y, boxes = -88, {}
    for _, a in ipairs(AREAS) do
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", 24, y)
        local l = label(f, a[2]); l:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        cb:SetScript("OnClick", function(self)
            WoWBY_DB.off = WoWBY_DB.off or {}
            WoWBY_DB.off[a[1]] = not self:GetChecked() or nil
            W.refresh()
        end)
        boxes[a[1]] = cb; y = y - 28
        if a[1] == "spells" then
            -- R829 (owner 2026-11-08): buff / debuff timers under the icons («40 хв»), a sub-option of spells, on by default
            local bt = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            bt:SetSize(24, 24); bt:SetPoint("TOPLEFT", 56, y)
            local bl = label(f, "Працягласць эфектаў (60 хв)"); bl:SetPoint("LEFT", bt, "RIGHT", 4, 0)
            bt:SetScript("OnClick", function(self) WoWBY_DB.buff_times = self:GetChecked() and true or false end)
            boxes.buff_times = bt; y = y - 28
        end
    end

    local function extra_box(text, get, set, indent)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", 24 + (indent or 0), y)
        local l = label(f, text); l:SetPoint("LEFT", cb, "RIGHT", 4, 0); l:SetWidth(320 - (indent or 0))
        cb:SetScript("OnClick", function(self) if set(self:GetChecked()) == false then self:SetChecked(not self:GetChecked()) end end)
        cb.get = get; y = y - 28
        return cb
    end
    y = y - 6
    local np = extra_box("Беларускія імёны над галовамі",
        function() return WoWBY_DB.nameonly end, function(v) local r = W.set_nameonly(v); f.sync(); return r end)
    -- R743 (owner 2026-10-23): the same labels with Blizzard's health bars kept
    local npb = extra_box("З палоскамі здароўя",
        function() return WoWBY_DB.np_bars end, function(v) W.set_np_bars(v) end, 32)
    -- the same name settings as Blizzard's panel (R27, owner 2026-09-29): while the option is on, Blizzard's own switches
    -- must stay off (they draw English names), so these copies decide what our labels show
    local MODES = { { 1, "NPC_NAMES_DROPDOWN_TRACKED", "NPC для заданняў" }, { 2, "NPC_NAMES_DROPDOWN_HOSTILE", "Варожыя" },
                    { 3, "NPC_NAMES_DROPDOWN_INTERACTIVE", "Варожыя і інтэрактыўныя" },
                    { 4, "NPC_NAMES_DROPDOWN_ALL", "Усе NPC" }, { 5, "NPC_NAMES_DROPDOWN_NONE", "Няма" } }
    local function mode_text(m)
        for _, e in ipairs(MODES) do
            if e[1] == m then
                local en = _G[e[2]]
                return (type(en) == "string" and W.ui_be(en)) or e[3]
            end
        end
    end
    -- a real dropdown like Blizzard's own (R31): Blizzard_Menu radio list
    local ml = label(f, "Імёны NPC:"); ml:SetPoint("TOPLEFT", 56, y - 5)
    local ok_dd, mb = pcall(CreateFrame, "DropdownButton", nil, f, "WowStyle1DropdownTemplate")
    if ok_dd and mb and mb.SetupMenu then
        mb:SetWidth(240); mb:SetPoint("LEFT", ml, "RIGHT", 8, 0)
        mb:SetupMenu(function(_, root)
            for _, e in ipairs(MODES) do
                root:CreateRadio(mode_text(e[1]), function() return (WoWBY_DB.npc_mode or 1) == e[1] end,
                    function() WoWBY_DB.npc_mode = e[1]; W.style_all_plates() end, e[1])
            end
        end)
        mb.refresh = function() mb:GenerateMenu() end
    else                                                      -- no Blizzard_Menu: the cycling button as before
        mb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        mb:SetSize(210, 22); mb:SetPoint("LEFT", ml, "RIGHT", 8, 0)
        mb:SetScript("OnClick", function()
            WoWBY_DB.npc_mode = ((WoWBY_DB.npc_mode or 1) % 5) + 1
            W.style_all_plates(); f.sync()
        end)
        mb.refresh = function() mb:SetText(mode_text(WoWBY_DB.npc_mode or 1) or "?") end
    end
    y = y - 32
    -- «Саюзнікі (гульцы)» and «Цень пад імёнамі» removed (owner 2026-10-07, R224); «Прыслужнікі» / «Жывёлкі» too
    -- (R254, 2026-10-08): players / minions / critters follow Blizzard's own name checkboxes (nameplates.lua R253)
    -- labels R675–R677 (owner 2026-10-20)
    local chb = extra_box("Чат: кажа, крычыць, назвы каналаў",
        function() return WoWBY_DB.chat_be end, function(v) WoWBY_DB.chat_be = v or nil; W.apply_chat_words() end)
    -- R369 (owner idea): EN above, a thin line, BE below in item / spell / aura / quest-link tooltips (names +
    -- descriptions); item / spell / quest names in chat links and the auction list stay English
    local dub = extra_box("Двухмоўная версія: англійская + беларуская мовы ў апісаннях заклёнаў, талентаў і прадметаў",
        function() return WoWBY_DB.dual end, function(v) WoWBY_DB.dual = v or nil end)
    local hvb = extra_box("Збіраць неперакладзены тэкст (дапамагае перакладу)",
        function() return WoWBY_DB.harvest_on end, function(v) WoWBY_DB.harvest_on = v and true or false end)
    local hvc = label(f, "", 11); hvc:SetPoint("TOPLEFT", 52, y + 6); hvc:SetTextColor(0.7, 0.7, 0.7)
    hvc:SetWidth(330)                               -- the counter ran past the window's right edge (R781)
    y = y - 22
    -- R965 (owner 2026-11-13): one button that hands the collected text to the translator — a copy box (addons cannot
    -- reach the internet or the clipboard); the player pastes it where the box says
    local exb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    exb:SetSize(200, 22); exb:SetPoint("TOPLEFT", 52, y + 2); exb:SetText("Адправіць сабранае")
    exb:SetScript("OnClick", function() W.show_harvest_export() end)
    y = y - 28

    local nl = label(f, "Імя вашага героя па-беларуску для тэкстаў заданняў:"); nl:SetPoint("TOPLEFT", 24, y - 10)
    nl:SetWidth(330)
    local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    eb:SetSize(220, 22); eb:SetPoint("TOPLEFT", 32, y - 32); eb:SetAutoFocus(false); eb:SetMaxLetters(40)
    eb:SetFont(W.FONT, 13, "")
    local hint = label(f, "", 11); hint:SetPoint("TOPLEFT", 26, y - 58); hint:SetWidth(330); hint:SetTextColor(0.7, 0.7, 0.7)
    local function save_name()
        local v = W.strtrim(plain(eb:GetText()) or "")
        W.set_my_name_be(v ~= "" and v or nil)
        eb:ClearFocus(); W.refresh(); f.sync()
    end
    eb:SetScript("OnEnterPressed", save_name)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f.sync() end)
    local sv = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    sv:SetSize(90, 22); sv:SetPoint("LEFT", eb, "RIGHT", 8, 0); sv:SetText("Захаваць"); sv:SetScript("OnClick", save_name)

    function f.sync()
        lang:SetText(W.is_be() and "Мова: беларуская  >  English" or "Language: English  >  беларуская")
        for area, cb in pairs(boxes) do
            if area == "buff_times" then
                cb:SetChecked(WoWBY_DB.buff_times ~= false)
                if cb.SetEnabled then cb:SetEnabled(W.on("spells") and true or false) end
            else
                cb:SetChecked(not (WoWBY_DB.off and WoWBY_DB.off[area]))
            end
        end
        np:SetChecked(np.get() and true or false); hvb:SetChecked(hvb.get() and true or false); chb:SetChecked(chb.get() and true or false)
        dub:SetChecked(dub.get() and true or false)
        npb:SetChecked(npb.get() and true or false)
        if npb.SetEnabled then npb:SetEnabled(WoWBY_DB.nameonly and true or false) end
        mb.refresh()
        if mb.SetEnabled then mb:SetEnabled(WoWBY_DB.nameonly and true or false) end; ml:SetTextColor(WoWBY_DB.nameonly and 1 or 0.5, WoWBY_DB.nameonly and 1 or 0.5, WoWBY_DB.nameonly and 1 or 0.5)
        local h, n = WoWBY_DB.harvest and WoWBY_DB.harvest[GetLocale()], {}
        for _, kind in ipairs({ "quests", "names", "objects", "zones", "gossip", "objectives", "books" }) do
            local c = 0; for _ in pairs(h and h[kind] or {}) do c = c + 1 end; n[kind] = c
        end
        -- what is still untranslated (pruned at login once a build translates it, R223 / R677)
        hvc:SetText(("Сабрана: заданняў %d, імёнаў %d, аб'ектаў %d, зон %d, размоў %d, мэт %d, старонак %d"):format(
            n.quests, n.names, n.objects, n.zones, n.gossip, n.objectives, n.books))
        local total = 0; for _, c in pairs(n) do total = total + c end
        if exb.SetEnabled then exb:SetEnabled(total > 0) end
        eb:SetText(W.my_name_be() or "")
        hint:SetText("Калі пустое, выкарыстоўваецца арыгінальнае імя")     -- owner 2026-10-20 (R678)
    end
    f:SetScript("OnShow", f.sync)
    return f
end
-- registered at login (PLAYER_LOGIN step): the page must exist before the player opens Settings
function W.register_options()
    if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    opts = opts or build_options("WoWBYOptionsFrame")
    category = Settings.RegisterCanvasLayoutCategory(opts, "WoWBY")
    Settings.RegisterAddOnCategory(category)
end
-- R579 (owner: "don't break Edit Mode"): the minimap button / compartment / /wowby used to call HideUIPanel(SettingsPanel)
-- and Settings.OpenToCategory FROM ADDON CODE — the UI panel manager then held tainted state, and the next Esc → Edit
-- Mode ran tainted (CompactUnitFrame_UpdateHealthColor "compare secret oldR … tainted by WoWBY", R29 / R406 family).
-- Now they open our OWN window (a second copy of the page); the Settings category stays for Blizzard's own path.
-- No Esc key capture (SetPropagateKeyboardInput is blocked in combat): close button / the same toggle.
-- ---------- R965: harvest export (owner 2026-11-13) ----------
-- One line of plain Lua: "WoWBY1 {v=1,loc=…,ver=…,at=…,h={…}}" — tools/import_paste.py reads it back with lupa. "|" is
-- written as \124 (an EditBox would draw |c… colour codes), newlines as \n, so the line survives copy and paste.
local function ser(v)
    local t = type(v)
    if t == "string" then
        return '"' .. v:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", ""):gsub("\n", "\\n"):gsub("|", "\\124") .. '"'
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        local out = {}
        for k, x in pairs(v) do
            local sk, sx = ser(k), ser(x)
            if sk and sx then out[#out + 1] = "[" .. sk .. "]=" .. sx end
        end
        return "{" .. table.concat(out, ",") .. "}"
    end
    return nil                                           -- functions / userdata / secret values: dropped
end
function W.harvest_export_text()
    local loc = GetLocale()
    local h = WoWBY_DB.harvest and WoWBY_DB.harvest[loc]
    if not h or not next(h) then return nil end
    local ver = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("WoWBY", "Version") or "?"
    return "WoWBY1 {v=1,loc=" .. ser(loc) .. ",ver=" .. ser(tostring(ver)) .. ",at=" .. ser(date("%Y-%m-%d %H:%M"))
        .. ",h=" .. ser(h) .. "}"
end
local exp
function W.show_harvest_export()
    local text = W.harvest_export_text()
    if not text then return end
    if not exp then
        exp = CreateFrame("Frame", "WoWBYExportFrame", UIParent, "BasicFrameTemplateWithInset")
        -- one layer above the options window (both were DIALOG: the export opened under it, R972)
        exp:SetSize(520, 340); exp:SetPoint("CENTER"); exp:SetFrameStrata("FULLSCREEN_DIALOG"); exp:SetToplevel(true)
        exp:SetMovable(true); exp:EnableMouse(true); exp:RegisterForDrag("LeftButton")
        exp:SetScript("OnDragStart", exp.StartMoving); exp:SetScript("OnDragStop", exp.StopMovingOrSizing)
        tinsert(UISpecialFrames, "WoWBYExportFrame")       -- Esc closes it
        if exp.TitleText then exp.TitleText:SetFont(W.FONT, 12, ""); exp.TitleText:SetText("WoWBY: сабраны тэкст") end
        local info = label(exp, "1. Націсніце Ctrl+C — тэкст ужо вылучаны.\n"
            .. "2. Устаўце яго ў новае паведамленне: github.com/Trasiankus/WoWBY/issues "
            .. "(або дашліце Трасянкусу іншым спосабам).\n"
            .. "Тут толькі неперакладзены тэкст гульні, без вашага імя.", 12)
        info:SetPoint("TOPLEFT", 14, -32); info:SetWidth(490)
        local sf = CreateFrame("ScrollFrame", nil, exp, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -100); sf:SetPoint("BOTTOMRIGHT", -32, 44)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true); eb:SetMaxLetters(0); eb:SetAutoFocus(false); eb:SetWidth(460)
        eb:SetFont(W.FONT, 11, "")
        eb:SetScript("OnEscapePressed", function() exp:Hide() end)
        eb:SetScript("OnTextChanged", function(self, user)       -- read-only: typing puts the export back
            if user then self:SetText(exp.text or ""); self:HighlightText() end
        end)
        sf:SetScrollChild(eb); exp.eb = eb
        local clr = CreateFrame("Button", nil, exp, "UIPanelButtonTemplate")
        clr:SetSize(220, 22); clr:SetPoint("BOTTOMLEFT", 12, 12); clr:SetText("Адправіў(-ла) — ачысціць")
        clr:SetScript("OnClick", function()
            if WoWBY_DB.harvest then WoWBY_DB.harvest[GetLocale()] = nil end
            exp:Hide()
            if opts and opts:IsShown() and opts.sync then opts.sync() end
        end)
        local cls = CreateFrame("Button", nil, exp, "UIPanelButtonTemplate")
        cls:SetSize(100, 22); cls:SetPoint("BOTTOMRIGHT", -12, 12); cls:SetText(CLOSE or "Close")
        cls:SetScript("OnClick", function() exp:Hide() end)
        if W.ui_be and CLOSE then cls:SetText(W.ui_be(CLOSE) or CLOSE) end
    end
    exp.text = text
    exp:Show(); exp:Raise()
    exp.eb:SetText(text); exp.eb:SetFocus(); exp.eb:HighlightText()
end

local win
local function standalone()
    if win then return win end
    -- the same bronze frame as the character window (R781, PortraitFrameTemplate)
    local ok, w = pcall(CreateFrame, "Frame", "WoWBYOptionsWindow", UIParent, "PortraitFrameTemplate")
    if not ok then ok, w = pcall(CreateFrame, "Frame", "WoWBYOptionsWindow", UIParent, "BasicFrameTemplateWithInset") end
    win = ok and w or CreateFrame("Frame", "WoWBYOptionsWindow", UIParent)
    -- +28 for the buff-timer row (R829), +44 for the harvest export button (R965)
    win:SetSize(410, 612); win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG"); win:SetClampedToScreen(true)   -- had been swallowed by the comment above (R965)
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
    local HEADER = "WoWBY — беларускі пераклад"
    if win.SetTitle then pcall(win.SetTitle, win, HEADER) elseif win.TitleText then win.TitleText:SetText(HEADER) end
    if win.SetPortraitToAsset then pcall(win.SetPortraitToAsset, win, "Interface\\Icons\\INV_Misc_Book_09") end
    -- the template's close button runs HideUIPanel, which does nothing in combat (R776): our window just hides
    local close = win.CloseButton or _G["WoWBYOptionsWindowCloseButton"]
    if close then close:SetScript("OnClick", function() win:Hide() end) end
    local inner = build_options()
    -- the language button starts below the round portrait; the page's own title line moved to the header
    if inner.page_title then inner.page_title:Hide() end
    inner:SetParent(win); inner:ClearAllPoints(); inner:SetPoint("TOPLEFT", 4, -14); inner:Show()
    win:Hide()
    return win
end
local function toggle_options()
    local w = standalone()
    if w:IsShown() then w:Hide() else w:Show() end
end
function WoWBY_OnCompartmentClick() toggle_options() end   -- ## AddonCompartmentFunc (TOC)

SLASH_WOWBY1 = "/wowby"
local function aura_report()                          -- R59: the aura-button tooltip, printed LAST (chat shows the end)
    local any = false
    for n, f in pairs(W.aura_tips and W.aura_tips() or {}) do
        local okf, forb = pcall(function() return f.IsForbidden and f:IsForbidden() end)
        local oks, shown = pcall(function() return f:IsShown() end)
        DEFAULT_CHAT_FRAME:AddMessage(("|cff8080ffWoWBY aura:|r %s forbidden=%s shown=%s"):format(n,
            okf and tostring(forb) or "ERR", oks and tostring(shown) or "ERR"))
        if oks and shown and W.aura_lines then
            any = true
            local L = W.aura_lines(f)
            DEFAULT_CHAT_FRAME:AddMessage("    read via: " .. tostring(L.via))
            for i = 1, 6 do
                if L.Left[i] or L.Right[i] then
                    DEFAULT_CHAT_FRAME:AddMessage(("    %d %s  ||  %s"):format(i, tostring(L.Left[i]), tostring(L.Right[i])))
                end
            end
            local e = L.Left[1] and (WoWBY_AuraByName or {})[L.Left[1]]
            DEFAULT_CHAT_FRAME:AddMessage("    BE entry: " .. (e and tostring(e[1]) or "none"))
        end
    end
    if not any then DEFAULT_CHAT_FRAME:AddMessage("|cff8080ffWoWBY aura:|r no aura tooltip shown") end
    return any
end
local function dump_tooltip()
    local tt = GameTooltip
    if not tt:IsShown() then return aura_report() end
    local data = tt.GetPrimaryTooltipData and tt:GetPrimaryTooltipData()
    DEFAULT_CHAT_FRAME:AddMessage(("|cff8080ffWoWBY tt:|r shown=%s type=%s id=%s lines=%d"):format(
        tostring(tt:IsShown()), tostring(data and data.type), tostring(data and W.sid_ok(data.id)), tt:NumLines()))
    -- R59: who owns it, is it marked secret, can the owner's aura / icon be read
    local sec = issecretvalue or function() return false end
    local o = tt.GetOwner and tt:GetOwner()
    local on = o and o.GetName and plain(o:GetName())
    local aid = o and o.auraInstanceID
    local ic = o and (o.Icon or o.icon)
    local tex = ic and ic.GetTexture and ic:GetTexture()
    DEFAULT_CHAT_FRAME:AddMessage(("  owner=%s parent=%s secretTip=%s aura=%s%s icon=%s%s combat=%s"):format(
        tostring(on), tostring(o and o.GetParent and o:GetParent() and plain(o:GetParent():GetName())),
        tostring(W.TIP.secret[tt] and true or false),
        sec(aid) and "SECRET" or tostring(aid), o and o.buttonInfo and " buttonInfo" or "",
        sec(tex) and "SECRET" or tostring(tex),
        o and o.unit and (" unit=" .. tostring(plain(o.unit))) or "", tostring(InCombatLockdown())))
    -- R146: quest lookup for map/quest tooltips — owner id, the log match by the raw first line, its BE title
    local l1 = plain(_G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText())
    local logq
    for i = 1, (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or 0 do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and plain(info.title) == l1 then logq = info.questID break end
    end
    DEFAULT_CHAT_FRAME:AddMessage(("  quest: ownerQ=%s updTip=%s logQ=%s be=%s quests_on=%s"):format(
        tostring(o and W.sid_ok(o.questID)), tostring(o and o.UpdateTooltip ~= nil), tostring(logq),
        tostring(logq and W.be_title(logq)), tostring(W.on("quests"))))
    -- R383: the dump is also SAVED (WoWBY_DB.tt_dump, read after /reload): drawn text, the data line's own text, the
    -- bilingual copy's text and what our "Use:" rule makes of the data text
    local dump = { time = date("%H:%M:%S"), type = data and data.type, id = data and W.sid_ok(data.id), lines = {} }
    local copy = W.TIP.dual and W.TIP.dual[tt]
    for i = 1, tt:NumLines() do
        local l, r = _G[tt:GetName() .. "TextLeft" .. i], _G[tt:GetName() .. "TextRight" .. i]
        local lraw = l and l:GetText()
        local lt, rt = l and plain(lraw), r and r:IsShown() and plain(r:GetText())
        local ld = data and data.lines and data.lines[i]
        DEFAULT_CHAT_FRAME:AddMessage(("  %d [%s]%s %s%s"):format(i, tostring(ld and ld.type),
            sec(lraw) and " SECRET" or "",
            (lt or ""):gsub("|", "||"), rt and ("  ||  " .. rt:gsub("|", "||")) or ""))
        local dt = ld and plain(ld.leftText)
        local cl = copy and copy.lines and copy.lines[i]
        local ok, use = pcall(function() return dt and W.use_line_be(dt) end)
        dump.lines[i] = { drawn = lt, right = rt or nil, ltype = ld and ld.type, data = dt,
                          copy = cl and plain(cl.leftText) or nil, use_rule = ok and use or ("ERR " .. tostring(use)) }
    end
    -- R971 (minimap quest blips went secret): every field of the tooltip data and of its lines, secret or not —
    -- is there a quest id / anything readable to rebuild the text from?
    local function fields(tbl, prefix, depth)
        if type(tbl) ~= "table" or depth > 2 then return end
        for k, v in pairs(tbl) do
            local ks = sec(k) and "<secret key>" or tostring(k)
            local vs
            if sec(v) then vs = "SECRET(" .. type(v) .. ")"
            elseif type(v) == "table" then vs = "{…}"
            else vs = tostring(v):gsub("|", "||"):sub(1, 60) end
            dump.fields = dump.fields or {}
            dump.fields[#dump.fields + 1] = prefix .. ks .. " = " .. vs
            if type(v) == "table" and not sec(v) then fields(v, prefix .. ks .. ".", depth + 1) end
        end
    end
    if data then pcall(fields, data, "", 0) end
    for _, s in ipairs(dump.fields or {}) do DEFAULT_CHAT_FRAME:AddMessage("  · " .. s) end
    if WoWBY_DB then WoWBY_DB.tt_dump = dump end
    aura_report()
end
-- R969 (owner 2026-11-13: screenshots for the QA chat): /wowby demo plants a few sample entries in the harvest so the
-- counter and the export window show something; /wowby demo off takes exactly those out again.
local DEMO = {
    names = { ["Thistlefur Shaman"] = true, ["Grimtotem Raider"] = true },
    objects = { ["Ancient Cache"] = true },
    zones = { ["Windshear Hold"] = true },
    gossip = { ["The winds whisper of trouble to the north, $c. Tread carefully."] = 3441 },
    objectives = { ["0/6 Thistlefur Shaman slain"] = 1061 },
    quests = { ["99901"] = { c = "You did well, $N. The spirits are pleased." } },
}
local function demo_harvest(on)
    WoWBY_DB.harvest = WoWBY_DB.harvest or {}
    local loc = GetLocale()
    local h = WoWBY_DB.harvest[loc] or {}
    WoWBY_DB.harvest[loc] = h
    for kind, items in pairs(DEMO) do
        h[kind] = h[kind] or {}
        for k, v in pairs(items) do h[kind][k] = on and v or nil end
    end
    print(on and "|cff33ff99WoWBY|r: дададзены прыклады ў «Сабрана» (/wowby demo off — прыбраць)"
        or "|cff33ff99WoWBY|r: прыклады прыбраныя")
    if opts and opts:IsShown() and opts.sync then opts.sync() end
end

SlashCmdList["WOWBY"] = function(msg)
    msg = W.strtrim((msg or ""):lower())
    if msg == "demo" or msg == "demo off" then demo_harvest(msg == "demo"); return end
    -- R975 (owner 2026-11-13: stutters while moving / questing): which WoWBY functions eat the CPU. Needs the game's
    -- script profiler: /console scriptProfile 1 → /reload → play a few minutes → /wowby perf (saved to WoWBY_DB.perf).
    -- Switch the profiler off afterwards (/console scriptProfile 0 + /reload): it slows every addon down.
    -- R977: this client's script profiler gives 0 ms; Blizzard's addon profiler (C_AddOnProfiler, always on) counts
    -- the frames where an addon took over 1 / 5 / 10 / 50 / 100 ms = the stutters → WoWBY vs the top addons
    if msg == "perf" and C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric then
        local out = {}
        local function line(s) print("  " .. s); out[#out + 1] = s end
        print("|cff33ff99WoWBY perf|r (" .. ("%.0f"):format(GetTime()) .. " s, addon profiler):")
        local names = {}
        for k, v in pairs(Enum.AddOnProfilerMetric) do names[#names + 1] = { k, v } end
        table.sort(names, function(a, b) return a[2] < b[2] end)
        for _, m in ipairs(names) do
            local ok, mine = pcall(C_AddOnProfiler.GetAddOnMetric, "WoWBY", m[2])
            local ok2, all = pcall(C_AddOnProfiler.GetOverallMetric, m[2])
            if ok then line(("%-22s WoWBY %10.2f   all addons %10.2f"):format(m[1], mine or 0, ok2 and all or 0)) end
        end
        if C_AddOnProfiler.GetTopKAddOnsForMetric and Enum.AddOnProfilerMetric.RecentAverageTime then
            local ok, top = pcall(C_AddOnProfiler.GetTopKAddOnsForMetric, Enum.AddOnProfilerMetric.RecentAverageTime, 5)
            if ok and type(top) == "table" then
                for i, r in ipairs(top) do
                    line(("top %d: %s %.3f ms"):format(i, tostring(r.addOnName or r.name or r[1]), tonumber(r.metricValue or r.value or r[2]) or 0))
                end
            end
        end
        WoWBY_DB.perf = out
        return
    end
    if msg == "perf" then
        if not (GetCVarBool and GetCVarBool("scriptProfile")) then
            print("|cff33ff99WoWBY|r: спачатку /console scriptProfile 1 і /reload, потым пагуляйце некалькі хвілін")
            return
        end
        UpdateAddOnCPUUsage()
        local rows = {}
        for name, fn in pairs(W) do
            if type(fn) == "function" then
                local ok, ms, calls = pcall(GetFunctionCPUUsage, fn, true)
                if ok and ms and ms > 0 then rows[#rows + 1] = { name, ms, calls or 0 } end
            end
        end
        table.sort(rows, function(a, b) return a[2] > b[2] end)
        local total = GetAddOnCPUUsage("WoWBY")
        local out = { ("total %.0f ms over %.0f s of play"):format(total, GetTime()) }
        print("|cff33ff99WoWBY perf|r: " .. out[1])
        for i = 1, math.min(15, #rows) do
            local s = ("%2d. %-28s %8.1f ms %7d calls"):format(i, rows[i][1], rows[i][2], rows[i][3])
            print("  " .. s); out[#out + 1] = s
        end
        WoWBY_DB.perf = out
        return
    end
    if msg == "np blizz" or msg == "np label" then       -- compare: Blizzard's own name vs our label
        WoWBY_DB.np_mode = msg == "np blizz" and "blizz" or nil
        W.style_all_plates()
        print("WoWBY np:", WoWBY_DB.np_mode == "blizz" and "Blizzard's own name (no title)" or "WoWBY label (name + title)")
        return
    end
    if msg == "cmpdebug" then                             -- R347: log the comparison tooltips frame by frame
        W.cmp_debug = not W.cmp_debug
        if W.cmp_debug then WoWBY_DB.cmp_log = {} end
        print("WoWBY cmpdebug:", W.cmp_debug and "ON — hover an item with comparison, then /wowby cmpdebug + /reload"
              or ("OFF, " .. #(WoWBY_DB.cmp_log or {}) .. " lines in WoWBY_DB.cmp_log"))
        return
    end
    if msg == "np" then                                   -- where does the target's name label hang?
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
        local f = plate and W.np_label[plate]
        print("WoWBY np:", plate and "plate ok" or "no plate for target", f and ("label parent = " .. tostring(f.kind)) or "no label",
              "| nameplateMinScale =", C_CVar and C_CVar.GetCVar("nameplateMinScale") or "?")
        return
    end
    if msg == "np cvars" then                             -- every nameplate/name CVar the client has -> chat + SavedVariables
        local out, n = {}, 0
        for _, c in ipairs(ConsoleGetAllCommands and ConsoleGetAllCommands() or {}) do
            local name = c.command or ""
            local l = name:lower()
            if l:find("nameplate") or l:find("unitname") or l:find("namescale") or l:find("worldtext") then
                local ok, v, d = pcall(C_CVar.GetCVarInfo, name)
                if ok and v ~= nil then
                    n = n + 1
                    out[name] = tostring(v) .. " (default " .. tostring(d) .. ")"
                    if l:find("scale") or l:find("dist") or l:find("size") then print(name, "=", v, "default", d) end
                end
            end
        end
        WoWBY_DB.cvar_dump = out
        print("WoWBY np cvars:", n, "saved; type /reload so Claude can read them")
        return
    end
    if msg == "np watch" then                             -- does anything change scale with distance? 1 line/s, 15 s
        local cv = function(k) return C_CVar and C_CVar.GetCVar(k) or "nil" end
        print("WoWBY np watch: min/max scale", cv("nameplateMinScale"), cv("nameplateMaxScale"), "| min/max dist",
              cv("nameplateMinScaleDistance"), cv("nameplateMaxScaleDistance"), "| global", cv("nameplateGlobalScale"),
              "| selected", cv("nameplateSelectedScale"))
        local n = 0
        C_Timer.NewTicker(1, function()
            n = n + 1
            local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
            if not plate then print(n, "no plate for target"); return end
            local function sc(fr)
                if not fr then return "-" end
                local ok1, a = pcall(fr.GetScale, fr)
                local ok2, e = pcall(fr.GetEffectiveScale, fr)
                return ("%s/%s"):format(ok1 and a and ("%.2f"):format(a) or "?", ok2 and e and ("%.2f"):format(e) or "?")
            end
            local lbl = W.np_label[plate]
            local near = CheckInteractDistance and (CheckInteractDistance("target", 4) and "<28y" or ">28y") or "?"
            print(n, near, "plate", sc(plate), "uf", sc(plate.UnitFrame), "label", sc(lbl))
        end, 15)
        return
    end
    if msg == "fs" then          -- blank labels: type it, then within 3 s open the ESC menu / hover a blank tab
        local function dump(tag, fs)
            local file, size, flags = fs:GetFont()
            local fo = fs.GetFontObject and fs:GetFontObject()
            local r, g, b, a = fs:GetTextColor()
            print(("%s [%s] font=%s size=%s obj=%s"):format(tag, tostring(plain(fs:GetText())), tostring(file), tostring(size),
                  tostring(fo and fo.GetName and fo:GetName())))
            print(("   shown=%s vis=%s alpha=%.2f w=%.0f h=%.0f strW=%.0f rgba=%.1f,%.1f,%.1f,%.1f"):format(tostring(fs:IsShown()),
                  tostring(fs:IsVisible()), fs:GetAlpha() or -1, fs:GetWidth() or -1, fs:GetHeight() or -1,
                  fs:GetStringWidth() or -1, r or -1, g or -1, b or -1, a or -1))
        end
        C_Timer.After(3, function()
            local h = GameMenuFrame and GameMenuFrame:IsShown() and GameMenuFrame.Header
            if h and h.Text then dump("ESC header", h.Text) end
            local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
            local f = foci and foci[1]
            if f and f.GetRegions then
                for _, r in ipairs({ f:GetRegions() }) do
                    if r.GetObjectType and r:GetObjectType() == "FontString" then pcall(dump, "hover " .. tostring(f:GetName()), r) end
                end
            end
        end)
        return
    end
    if msg == "tt" then
        C_Timer.After(3, dump_tooltip)       -- 3 s to hover the thing you want to inspect
        DEFAULT_CHAT_FRAME:AddMessage("|cff8080ffWoWBY:|r навядзіце мыш на патрэбную рэч — праз 3 с выведу падказку ў чат.")
        return
    end
    if msg == "lang" or msg == "en" or msg == "by" or msg == "be" then toggle_lang() else toggle_options() end
end

-- ---------- minimap button: left = options, right = quick EN/BY switch, drag = move along the rim ----------
local function place_minimap_btn()
    -- on the rim like other minimap icons (LibDBIcon rule: half the minimap width + a small offset);
    -- Forever's modern minimap is larger than the classic one, so never hard-code the radius
    local a = math.rad(WoWBY_DB.minimapAngle or 210)
    local r = (Minimap:GetWidth() or 140) / 2 + 10
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", r * math.cos(a), r * math.sin(a))
end
function W.create_minimap_button()
    if minimapBtn or not Minimap then return end
    local b = CreateFrame("Button", "WoWBYMinimapButton", Minimap)
    minimapBtn = b
    b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b:RegisterForDrag("LeftButton")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(22, 22); bg:SetPoint("CENTER"); bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetVertexColor(0.25, 0.25, 0.25)
    local txt = b:CreateFontString(nil, "ARTWORK")
    txt:SetFont(W.FONT, 11, ""); txt:SetPoint("CENTER"); txt:SetShadowColor(0, 0, 0, 1); txt:SetShadowOffset(1, -1)
    b.text = txt
    -- the ring's hole is off-centre in its texture (measured: 17 / 16.5 px of 53 from the top left), so shift the ring
    -- to put the hole on the button's centre; everything else then simply anchors to CENTER
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53); border:SetPoint("TOPLEFT", -1.5, 1); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    b:SetScript("OnClick", function(_, button) if button == "RightButton" then toggle_lang() else toggle_options() end end)
    b:SetScript("OnDragStart", function()
        b:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            WoWBY_DB.minimapAngle = math.deg(math.atan2(py / s - my, px / s - mx))
            place_minimap_btn()
        end)
    end)
    b:SetScript("OnDragStop", function() b:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(b, "ANCHOR_LEFT")
        GameTooltip:AddLine("WoWBY")
        GameTooltip:AddLine("ЛКМ — налады.", 1, 1, 1)
        GameTooltip:AddLine("ПКМ — пераключыць мову (EN/BY).", 1, 1, 1)
        GameTooltip:AddLine("Перацягніце, каб перасунуць.", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    place_minimap_btn(); update_label()
end
