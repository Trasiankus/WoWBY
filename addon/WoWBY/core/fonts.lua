-- WoWBY/core/fonts.lua — patching Blizzard font objects.
-- Split from core.lua (tools/split_core.py); shared state lives in the addon namespace W.
local _, W = ...
-- ---------- Cyrillic-capable font for Blizzard's Friz Quadrata font objects ----------
-- The enUS client's FRIZQT__ has no Cyrillic -> translated zone names showed as boxes (map breadcrumbs,
-- dropdowns). FRIZQT_BY.ttf = Forever's own FRIZQT___CYR (Cyrillic + і/ў); size and flags are kept.
local patched_fonts = {}
function W.patch_fonts()
    for _, obj in pairs(_G) do
        if type(obj) == "table" and type(obj.GetObjectType) == "function" then
            local ok, kind = pcall(obj.GetObjectType, obj)
            if ok and kind == "Font" then
                local file, size, flags = obj:GetFont()
                local by = file and W.by_font(file)
                if by and file ~= by then
                    if pcall(obj.SetFont, obj, by, size, flags or "") then patched_fonts[obj] = true end
                end
            end
        end
    end
end
-- Cold client start (not /reload): some labels on patched Font objects rendered BLANK (Esc-menu header, Settings
-- tabs, 2026-09-28) until a reload — the font file was still loading when they were first drawn. A few seconds
-- after the first login every patched Font is nudged (size +1, then back) so its FontStrings re-render.
function W.refresh_fonts()
    for obj in pairs(patched_fonts) do
        local file, size, flags = obj:GetFont()
        if file and size and size > 0 then
            pcall(obj.SetFont, obj, file, size + 1, flags or "")
            pcall(obj.SetFont, obj, file, size, flags or "")
        end
    end
end
