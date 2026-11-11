local _, W = ...
-- Books, letters, plaques (R138): ItemTextFrame shows one page at a time. Blizzard fills it on ITEM_TEXT_READY
-- (ItemTextPageText:SetText(ItemTextGetText())); our post-hook on the frame's OnEvent puts the BE page in the same
-- frame. Untranslated pages are harvested (kind "books") with the window title and page number.
W.B = WoWBY_Books or {}

-- must match tools/build_addon.py book_key(): CR dropped, line-end spaces cut, trimmed
local function page_key(t)
    t = t:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("[ \t]+\n", "\n")
    return W.strtrim(t)
end
local function esc_pat(s) return (s:gsub("%p", "%%%0")) end

-- the server fills in the player's name / race / class: put $N / $R / $C back (as the source text has them)
local function token_key(k)
    local me = plain(UnitName("player"))
    if me and me ~= "" then k = k:gsub(esc_pat(me), "$N") end
    local race, class = plain((UnitRace("player"))), plain((UnitClass("player")))
    if race and race ~= "" then k = k:gsub(esc_pat(race), "$R") end
    if class and class ~= "" then k = k:gsub(esc_pat(class), "$C") end
    return k
end

-- EN page -> BE page, or nil
function W.book_be(t)
    t = plain(t)
    if not t or t == "" then return nil end
    local k = page_key(t)
    return W.B[k] or W.B[token_key(k)]
end

local function title_be(t)
    t = plain(t)
    if not t or t == "" then return nil end
    return W.IE[t] or W.N[t] or (W.ui_be and W.ui_be(t))
end

local function tr_title(frame)
    local en = plain(ItemTextGetItem and ItemTextGetItem())
    local be = en and title_be(en)
    if be and frame.SetTitle then frame:SetTitle(be) end
end

local function tr_page(frame)
    local en = plain(ItemTextGetText and ItemTextGetText())
    if not en or en == "" then return end
    local be = W.book_be(en)
    if not be then
        W.harvest("books", token_key(page_key(en)), { title = plain(ItemTextGetItem and ItemTextGetItem()) or "",
                                           page = ItemTextGetPage and ItemTextGetPage() or 0 })
        return
    end
    be = W.substitute(be)
    local creator = plain(ItemTextGetCreator and ItemTextGetCreator())
    if creator then be = be .. "\n\n" .. (W.ui_be and W.ui_be(ITEM_TEXT_FROM) or ITEM_TEXT_FROM) .. "\n" .. creator .. "\n" end
    W.swap(ItemTextPageText, be)
    -- same re-measure Blizzard does after its SetText (the BE page is usually longer)
    local sf = ItemTextScrollFrame
    if sf and sf.GetScrollChild and sf:GetScrollChild() then
        sf:GetScrollChild():SetHeight(1)
        sf:UpdateScrollChildRect()
        if floor(sf:GetVerticalScrollRange()) > 0 then
            sf:GetScrollChild():SetHeight(sf:GetHeight() + sf:GetVerticalScrollRange() + 30)
        end
    end
end

-- Prev / Next (R802): text set once in the XML, on an unnamed FontString of each button
local function tr_nav()
    if not (W.on("ui") and W.ui_be) then return end
    for _, b in ipairs({ _G.ItemTextPrevPageButton, _G.ItemTextNextPageButton }) do
        W.each_fs(b, 0, function(fs)
            local be = W.ui_be(plain(fs:GetText()))
            if be then W.swap(fs, be) end
        end)
    end
end

-- DialogueUI's book window (R797): it reads ItemTextGetText through locals captured before WoWBY loads and draws in its own
-- frame, so the ItemTextFrame hook never shows there. Its page cache is an unnamed frame (found by its method, like the
-- tooltips in R784); every page and the title pass through it right before the layout is measured, so the BE text goes in
-- there. Its files stay untouched. d.wowby = done: a re-opened book comes from the same cache and is not measured again.
function W.dui_book_wrap(c)
    local orig = rawget(c, "BeginCalculateTextHeight")
    if type(orig) ~= "function" or rawget(c, "wowby_book") then return end
    c.wowby_book = true
    c.BeginCalculateTextHeight = function(self, ...)
        local d = self.activeData
        if d and not d.wowby and W.on("quests") and W.is_be() then
            d.wowby = true
            d.title = title_be(d.title) or d.title
            for page, raw in ipairs(d.pageTexts or {}) do
                local en = plain(raw)
                if en and en ~= "" then
                    local be = W.book_be(en)
                    if be then
                        d.pageTexts[page] = W.substitute(be)
                    else
                        W.harvest("books", token_key(page_key(en)), { title = plain(ItemTextGetItem and ItemTextGetItem()) or "", page = page })
                    end
                end
            end
        end
        return orig(self, ...)
    end
end
function W.hook_dui_books()
    if not (_G.DUIBookFrame and EnumerateFrames) then return end
    local f = EnumerateFrames()
    while f do
        local ok, found = pcall(function() return not f:IsForbidden() and rawget(f, "CacheCurrentPage") and rawget(f, "BeginCalculateTextHeight") end)
        if ok and found then W.dui_book_wrap(f); return end
        f = EnumerateFrames(f)
    end
end

function W.hook_books()
    local f = _G.ItemTextFrame
    if not f or W.books_hooked then return end
    W.books_hooked = true
    f:HookScript("OnEvent", function(self, event)
        if event == "ITEM_TEXT_READY" then tr_nav() end
        if not W.on("quests") then return end
        if event == "ITEM_TEXT_BEGIN" then
            tr_title(self)
        elseif event == "ITEM_TEXT_READY" then
            tr_title(self)
            tr_page(self)
        end
    end)
end
