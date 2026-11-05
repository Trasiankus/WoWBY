-- WoWBY/core/events.lua — event wiring.
-- Split from core.lua (tools/split_core.py); shared state lives in the addon namespace W.
local _, W = ...
-- ---------- events ----------
local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "GOSSIP_SHOW", "ADDON_LOADED",
                     "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_FOCUS_CHANGED", "QUEST_LOG_UPDATE",
                     "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING",
                     "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
    f:RegisterEvent(e)
end
pcall(f.RegisterUnitEvent, f, "UNIT_NAME_UPDATE", "target", "focus")
pcall(f.RegisterUnitEvent, f, "UNIT_TARGET", "target", "focus")
f:SetScript("OnEvent", function(_, event, arg1)
    if not WoWBY_DB then WoWBY_DB = { lang = "be" } end
    if event == "NAME_PLATE_UNIT_ADDED" then
        W.plate_added(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        W.plate_removed(arg1)
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" or event == "UNIT_NAME_UPDATE"
        or event == "UNIT_TARGET" then
        if event == "PLAYER_TARGET_CHANGED" and WoWBY_DB.nameonly then W.style_all_plates() end
        W.target_name(); C_Timer.After(0.1, W.target_name)   -- ToT is refreshed by Blizzard after UNIT_TARGET too
        if event == "PLAYER_TARGET_CHANGED" then W.unit_static_labels() end
    elseif event == "QUEST_LOG_UPDATE" then
        W.scan_quest_log()
    elseif event == "ADDON_LOADED" and arg1 == "WoWBY" then
        W.patch_fonts()
    elseif event == "ADDON_LOADED" then
        W.hook_panels()                                  -- load-on-demand Blizzard panels (spellbook, …)
        W.safe("hook_tutorial_pointers")                 -- tutorial hint boxes (load-on-demand tutorial addons, R689)
        W.safe("hook_damage_meter")                      -- damage meter window titles (Blizzard_DamageMeter, R702)
        W.hook_tooltips()
        if arg1 == "DialogueUI" then C_Timer.After(0, W.hook_dialogueui) end
        if arg1 == "Blizzard_PlayerSpells" then W.hook_spellbook() end
        if arg1 == "Blizzard_TrainerUI" then W.hook_trainer() end
        if arg1 == "Blizzard_AuctionHouseUI" then W.safe("hook_auction") end
        if arg1 == "Blizzard_Subtitles" then W.safe("hook_subtitles") end
        if arg1 == "Blizzard_DeathRecap" then W.safe("hook_deathrecap") end
        if arg1 == "Blizzard_Calendar" then W.safe("hook_calendar") end
        W.safe("hook_books")                             -- ItemTextFrame may come with a load-on-demand panel addon
    elseif event == "PLAYER_LOGIN" then
        -- each step on its own: one failing step (Lua errors are hidden by default) must not skip the rest —
        -- the chat filter (hook_messages) came last and silently never registered (R5, 2026-09-29)
        W.hook_messages()
        for _, step in ipairs({ "apply_labels", "apply_standings", "patch_fonts", "create_minimap_button", "hook_panels",
                               "hook_tooltips", "hook_tracker", "hook_bags", "hook_dialogueui", "hook_spellbook",
                               "hook_trainer", "hook_toasts", "hook_castbar", "hook_mail", "hook_loot", "hook_mirror", "hook_merchant", "hook_skills", "hook_auction", "hook_zones", "hook_popups", "hook_shard", "hook_books", "hook_chat_header", "apply_chat_words", "unit_static_labels", "hook_calendar", "hook_bubbles", "hook_subtitles", "hook_helptips", "hook_tutorial_pointers", "hook_damage_meter", "harvest_default", "prune_harvest", "hook_tabs", "hook_recipe_toast", "hook_loot_toast", "apply_search_boxes", "apply_chat_tabs", "hook_achievement_toast", "hook_cinematic", "hook_deathrecap", "hook_bag_search", "hook_recipe_tracker", "hook_npc_titles", "register_options", "register_emote_cmds", "ru_report" }) do
            W.safe(step)
        end
        WoWBY_DB.np_players, WoWBY_DB.np_shadow = nil, nil   -- options removed (R224): defaults = labels on, no shadow
        C_Timer.After(1, W.tr_tracker_headers)
        C_Timer.After(2, W.refresh_fonts); C_Timer.After(8, W.refresh_fonts)
        -- re-apply the name-only CVars every login: settings added after the option was switched on
        -- (nameplateMinScale) would otherwise never reach clients that had it on already
        if WoWBY_DB.nameonly and not InCombatLockdown() then W.set_nameonly(true) end
        W.start_np_ticker()
        -- no counts (owner 2026-10-07, R222: "destroys the magic a bit")
        DEFAULT_CHAT_FRAME:AddMessage("|cff8080ffWoWBY:|r /wowby — налады")
    elseif event == "GOSSIP_SHOW" then
        C_Timer.After(0, function() W.npc_title(_G.GossipFrame) end)
    else
        W.apply_buttons()
        C_Timer.After(0, W.tr_zone_text)
        pcall(W.quest_variant_event, event)              -- R510: harvest a live quest text our sources don't have
    end
end)
