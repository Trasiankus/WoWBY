"""Classic NPC speech + gossip texts from the local Turtle/vmangos world DB dump (R55, owner 2026-09-29: "source all
the gossip lines, at least the classic ones, from the local classic server files").

    python tools/import_broadcast.py            -> data/broadcast_en.json + counts

Source: C:\\Projects\\custom-wow\\penqle-tortoise\\sql\\base\\tw_world_*.sql (MySQL dumps, read-only):
  broadcast_text (+ locales_broadcast_text loc8 = ruRU): NPC say/yell/emote lines and gossip greetings
  (npc_text rows point at broadcast ids), gossip_menu_option (+ locales loc8): the clickable gossip options.
Server texts use $n/$N (player name), $r/$c (race/class), $g male:female; — kept as they are (the translate
package and the runtime key normalise them). Turtle-only content is kept out by id: vanilla broadcast ids are below
TURTLE_MIN (Turtle's own start far above); gossip options by their menu id the same way.
extract_forever.py merges data/broadcast_en.json into the queue as "gossip:" entries (RU as reference) when the
text is not translated yet (turtle-bel gossip / Forever gossip)."""
import json, os, re, sys, collections

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SQL = r"C:\Projects\custom-wow\penqle-tortoise\sql\base"
TURTLE_MIN = 30000          # broadcast ids from here on are Turtle WoW's own additions (sampled on the dump, 2026-09-29)
TURTLE_MENU_MIN = 10000     # gossip menu ids the same (Turtle menus: 10000+, e.g. 20011 "Access: Discombobulator Ray")


def rows(path, table):
    """Yield the value tuples of every `INSERT INTO `table` VALUES (...),(...);` statement (MySQL dump escapes)."""
    src = open(path, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"INSERT INTO `%s`(?: \([^)]*\))? VALUES " % re.escape(table), src):
        i, n = m.end(), len(src)
        while i < n:
            if src[i] != "(":
                break
            i += 1
            vals, cur, q = [], [], False
            while i < n:
                c = src[i]
                if q:
                    if c == "\\":
                        nx = src[i + 1]
                        cur.append({"n": "\n", "r": "\r", "t": "\t", "0": "\0"}.get(nx, nx)); i += 2; continue
                    if c == "'":
                        q = False
                    else:
                        cur.append(c)
                    i += 1; continue
                if c == "'":
                    q = True; i += 1; continue
                if c in ",)":
                    v = "".join(cur).strip()
                    vals.append(None if v == "NULL" else v)
                    cur = []
                    i += 1
                    if c == ")":
                        break
                    continue
                cur.append(c); i += 1
            yield vals
            if i < n and src[i] == ",":
                i += 1
            else:
                break


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    out = {}                                   # EN text -> {"ru", "kind", "ids"}

    def add(en, ru, kind, ident):
        if not en or not en.strip() or not re.search(r"[A-Za-z]", en):
            return
        e = out.setdefault(en, {"ru": ru or "", "kind": kind, "ids": []})
        if ru and not e["ru"]: e["ru"] = ru
        if len(e["ids"]) < 3: e["ids"].append(ident)

    ru_bt = {}
    for v in rows(os.path.join(SQL, "tw_world_locales_broadcast_text.sql"), "locales_broadcast_text"):
        # entry, male_loc0..8 (9), female_loc0..8 (9)
        ru_bt[int(v[0])] = (v[9] or "", v[18] or "")
    c = collections.Counter()
    for v in rows(os.path.join(SQL, "tw_world_broadcast_text.sql"), "broadcast_text"):
        bid = int(v[0])
        if bid >= TURTLE_MIN:
            c["turtle-only skipped"] += 1; continue
        male, female = v[1], v[2]
        rm, rf = ru_bt.get(bid, ("", ""))
        add(male, rm, "broadcast", bid)
        if female and female != male:
            add(female, rf, "broadcast", bid)
        c["broadcast"] += 1
    ru_go = {}
    for v in rows(os.path.join(SQL, "tw_world_locales_gossip_menu_option.sql"), "locales_gossip_menu_option"):
        ru_go[(v[0], v[1])] = v[2 + 8] if len(v) > 10 else ""
    for v in rows(os.path.join(SQL, "tw_world_gossip_menu_option.sql"), "gossip_menu_option"):
        mid = int(v[0])
        if mid >= TURTLE_MENU_MIN:
            c["turtle-only options skipped"] += 1; continue
        add(v[3], ru_go.get((v[0], v[1]), ""), "option", "%s.%s" % (v[0], v[1]))
        c["options"] += 1
    # R139: quest greetings (QuestFrameGreeting, several quests on one NPC/object), trainer greetings, holiday mails.
    # Turtle's own NPCs start at 60000; object greetings and mails are vanilla except the 1000000+ customs.
    for v in rows(os.path.join(SQL, "tw_world_quest_greeting.sql"), "quest_greeting"):
        eid, typ = int(v[0]), int(v[1])
        if (typ == 0 and eid >= 60000) or eid >= 1000000:
            c["turtle-only greetings skipped"] += 1; continue
        add(v[2], v[10], "quest greeting", eid); c["quest greetings"] += 1
    for v in rows(os.path.join(SQL, "tw_world_npc_trainer_greeting.sql"), "npc_trainer_greeting"):
        if int(v[0]) >= 60000:
            continue
        add(v[1], v[9], "trainer greeting", int(v[0])); c["trainer greetings"] += 1
    for v in rows(os.path.join(SQL, "tw_world_mail_text_template.sql"), "mail_text_template"):
        if re.search(r"(?i)\btest\b", v[1] or ""):
            continue
        add(v[1], "", "holiday mail", int(v[0])); c["mails"] += 1
    # R572: guard directions ("Where is the inn?") put a minimap point named "Razor Hill Inn" (points_of_interest
    # icon_name, RU = locales loc8) → data/poi_en.json; extract_forever queues them as names (the minimap tooltip asks N)
    ru_poi = {v[0]: v[8] for v in rows(os.path.join(SQL, "tw_world_locales_points_of_interest.sql"),
                                       "locales_points_of_interest") if len(v) > 8}
    poi = {}
    for v in rows(os.path.join(SQL, "tw_world_points_of_interest.sql"), "points_of_interest"):
        en = (v[6] or "").strip()
        if en and re.search(r"[A-Za-z]", en) and int(v[0]) < 10000:
            poi.setdefault(en, ru_poi.get(v[0]) or "")
    json.dump(poi, open(os.path.join(ROOT, "data", "poi_en.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0,
              sort_keys=True)
    c["guard poi names"] = len(poi)
    json.dump(out, open(os.path.join(ROOT, "data", "broadcast_en.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    print(dict(c), "->", len(out), "distinct texts, with RU:", sum(1 for e in out.values() if e["ru"]))


if __name__ == "__main__":
    main()
