"""ruRU client support (R665, owner 2026-10-18: "make the addon work on top of RU"): on a Russian client the game hands
WoWBY RUSSIAN text where every runtime lookup is keyed by the ENGLISH text. This writes addon/WoWBY/data/ru.lua (loaded
only on ruRU: TOC [AllowLoadTextLocale ruRU] + a GetLocale guard), read by core/ru.lua:

  WoWBY_RU[domain][ru] = en | {en1, en2…}   RU text -> the EN key(s) of the shipped tables (core/ru.lua: the tables fall
                                             back to these keys through a metatable, so W.N["Плотояд"] = W.N["Gnoll"]…)
  WoWBY_RUF / WoWBY_RUFX                     RU GlobalStrings formats -> the same line in ENGLISH ("%1$s – убито: %2$d/%3$d"
                                             → "0/7 X slain"), indexed by a word; the normal EN path then translates it
  WoWBY_SpellDescRU[key]                     RU spell-description patterns -> the shipped BE template (same keys as SD)
  WoWBY_QReworkRU[qid]                       quests whose Forever EN title differs from the WoWBY source (the EN title guard
                                             cannot run on a ruRU client: the live title is Russian)

    python tools/build_ru.py        (build_addon.py runs it after the other data files; --stats prints domain sizes)

Sources (EN <-> RU pairs): out/globalstrings_keys.tsv, out/db2/*.tsv, the local world DB dump (custom-wow penqle-tortoise
locales_*: creatures, objects, quests, items, pages, broadcast texts, gossip options, greetings, mail, areas, POI), Questie
ruRU lookups (NPCs + titles, objects, items, quests) and the wowhead RU scrape (forever-data/ru: NPCs, objects, quests)."""
import collections, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_addon import (ROOT, OUT, tsv, lua_str, gossip_keys, book_key, FMT_TOKEN, desc_sd, _nl, lua_pattern, be_parts,  # noqa: E402
                         fmt_parts)
from import_broadcast import rows as sql_rows, SQL, TURTLE_MIN  # noqa: E402

QUESTIE = r"C:\Projects\WoW\Questie"
DOMAINS = ("ui", "names", "titles", "zones", "gossip", "items", "spells", "books", "objectives", "quests")
CYR = re.compile(r"[\u0400-\u04FF]")
ENCH_TPL = []            # (EN, RU) enchant name templates, filled by collect()


# ---------- sources ----------
def sql_table(fname, table):
    """Rows of a world-DB dump table as dicts (column names from its CREATE TABLE)."""
    path = os.path.join(SQL, fname)
    if not os.path.exists(path):
        return []
    head = open(path, encoding="utf-8", errors="replace").read(200000)
    m = re.search(r"CREATE TABLE `%s` \((.*?)\n\)" % re.escape(table), head, re.S)
    if not m:
        return []
    cols = re.findall(r"^\s+`([^`]+)`", m.group(1), re.M)
    return [dict(zip(cols, v)) for v in sql_rows(path, table)]


def lua_lookup(path, start):
    """Questie's `loadstring([[return {...}]])` lookup table -> dict."""
    import lupa
    if not os.path.exists(path):
        return {}
    src = open(path, encoding="utf-8").read()
    a = src.index(start) + len(start) - len("return {")
    b = src.index("}]]", a) + 1
    t = lupa.LuaRuntime(unpack_returned_tuples=True).execute(src[a:b])
    return {int(k): v for k, v in t.items()}


class Pairs:
    """domain -> EN -> Counter(RU)."""
    def __init__(self):
        self.d = {k: collections.defaultdict(collections.Counter) for k in DOMAINS}

    def add(self, dom, en, ru, w=1):
        if not en or not ru:
            return
        # (stress marks U+0301 the client shows in a few words — «Небесноро́жденная» — are dropped; core/ru.lua too)
        en, ru = en.replace("\r", ""), ru.replace("\r", "").replace("́", "")
        if en == ru or not ru.strip() or not CYR.search(ru):
            return
        if ru.startswith("[") and ru.endswith("]"):            # wowhead RU: "[English]" = not translated
            return
        self.d[dom][en][ru] += w


def tsv_ids(name):
    """out/cache/<name> (enUS WDB dump, id -> name) as {str id: name}."""
    p = os.path.join(ROOT, "out", "cache", name)
    return {r[0]: r[1] for r in tsv(p) if len(r) > 1 and r[0].isdigit()} if os.path.exists(p) else {}


def ru_cache():
    """The beta's ruRU WDB cache (a session with the client in Russian): NPC / object names and quests by id, merged
    into out/cache/ru.json (cumulative: a new client build empties the cache)."""
    import extract_forever as xf
    p = os.path.join(ROOT, "out", "cache", "ru.json")
    old = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}
    for k in ("creatures", "objects", "quests"):
        old.setdefault(k, {})
    old.setdefault("creatures_f", {})
    # NPC titles: the record's LAST string, after 8+ zero bytes ("…\0\0\0\0\0\0\0\0Guild Master\0"); the enUS cache
    # gives the English one for the same id
    def title(b):
        m = re.search(rb"\x00{8}([^\x00]{3,})\x00$", b)
        try:
            s = m.group(1).decode("utf-8") if m else ""
        except UnicodeDecodeError:
            return ""
        return s if s.isprintable() and re.search(r"[A-Za-zЀ-ѿ]{2}", s) else ""
    for loc, key in (("enUS", "titles_en"), ("ruRU", "titles_ru")):
        old.setdefault(key, {})
        for rid, b in xf.wdb_records("creaturecache", loc):
            t = title(b)
            if t: old[key][str(rid)] = t
    for rid, b in xf.wdb_records("creaturecache", "ruRU"):
        if len(b) > 16:
            nm = xf.cstr(b, 15)
            old["creatures"][str(rid)] = nm
            # the FEMININE form follows the name (Russian names are gendered: «Ал'акетская призывательница бури»)
            try:
                fem = xf.cstr(b, 15 + len(nm.encode("utf-8")) + 1)
            except ValueError:
                fem = ""
            if fem and CYR.search(fem) and fem.isprintable():
                old["creatures_f"][str(rid)] = fem
    for rid, b in xf.wdb_records("gameobjectcache", "ruRU"):
        if len(b) > 9: old["objects"][str(rid)] = xf.cstr(b, 8)
    for rid, b in xf.wdb_records("questcache", "ruRU"):
        q = xf.parse_quest(b)
        if q: old["quests"][str(rid)] = {f: q[f] for f in ("t", "o", "d") if q.get(f)}
    os.makedirs(os.path.dirname(p), exist_ok=True)
    json.dump(old, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=0, sort_keys=True)
    return old


def plural_forms(s):
    """'|4one:few:many;' -> ['one', 'few', 'many'] for a string that is ONLY a plural escape."""
    m = re.fullmatch(r"\|4([^;]*);", s.strip())
    return m.group(1).split(":") if m else None


def unq(s):
    return s.replace('\\"', '"').replace('\\\\', '\\')


def collect():
    ENCH_TPL.clear()
    P = Pairs()
    # GlobalStrings (plain strings; formats are WoWBY_RUF below)
    gs = []
    for r in tsv(os.path.join(ROOT, "out", "globalstrings_keys.tsv")):
        if len(r) < 3 or not r[2]:
            continue
        key, en, ru = r[0], unq(_nl(r[1])), unq(_nl(r[2]))
        gs.append((key, en, ru))
        if FMT_TOKEN.search(en) or FMT_TOKEN.search(ru):
            continue
        pe, pr = plural_forms(en), plural_forms(ru)
        if pe and pr:                                      # "|4Minute:Minutes;" vs "мин." / "|4минута:минуты:минут;"
            for i, f in enumerate(pr):
                P.add("ui", pe[0] if i == 0 else pe[-1], f, 2)
            continue
        if pe and not pr:
            P.add("ui", pe[-1], ru, 2)
            continue
        P.add("ui", en, ru, 3)
    # DB2 dump: every localized client string (UI words, classes, races, factions, skills, holidays…)
    zone_tables = {"AreaTable", "WMOAreaTable", "UiMap", "Map", "AreaPOI", "TaxiNodes"}
    for fn in sorted(os.listdir(os.path.join(ROOT, "out", "db2"))):
        tname = fn[:-4]
        for r in tsv(os.path.join(ROOT, "out", "db2", fn)):
            if len(r) < 5 or not r[3] or not r[4]:
                continue
            en, ru = r[3], r[4]
            if tname in zone_tables:
                P.add("zones", en, ru, 2)
            elif tname == "SpellName":
                P.add("spells", en, ru, 2)
            elif tname == "ItemSparse" and r[1] == "Display_lang":
                P.add("items", en, ru, 2)
            elif tname in ("Creature", "GameObjects"):
                P.add("names", en, ru, 2)
            elif tname == "SpellItemEnchantment" and "$" in en:
                ENCH_TPL.append((en, ru))                 # «+$k2 к выносливости и +$k1 к броне» (R673)
            elif tname == "SharedString" and FMT_TOKEN.search(en):
                gs.append(("DB2_SharedString", en, ru))   # Legacy formats (R671: «Следующие награды на ранге %d»)
            elif tname == "BroadcastText":
                for e, rr in zip(gossip_keys(en), gossip_keys(ru) * 2):
                    P.add("gossip", e, rr, 2)
            P.add("ui", en, ru, 1)
    # world DB (vanilla / Turtle; Turtle-only entries are fine too: the EN key decides what is used)
    loc_c = {v["entry"]: v for v in sql_table("tw_world_locales_creature.sql", "locales_creature")}
    for v in sql_table("tw_world_creature_template.sql", "creature_template"):
        l = loc_c.get(v.get("entry"))
        if l:
            P.add("names", v.get("name"), l.get("name_loc8"))
            P.add("titles", v.get("subname"), l.get("subname_loc8"))
    loc_g = {v["entry"]: v for v in sql_table("tw_world_locales_gameobject.sql", "locales_gameobject")}
    for v in sql_table("tw_world_gameobject_template.sql", "gameobject_template"):
        l = loc_g.get(v.get("entry"))
        if l:
            P.add("names", v.get("name"), l.get("name_loc8"))
    loc_i = {v["entry"]: v for v in sql_table("tw_world_locales_item.sql", "locales_item")}
    for v in sql_table("tw_world_item_template.sql", "item_template"):
        l = loc_i.get(v.get("entry"))
        if l:
            P.add("items", v.get("name"), l.get("name_loc8"))
    loc_q = {v["entry"]: v for v in sql_table("tw_world_locales_quest.sql", "locales_quest")}
    quest_en = {}
    for v in sql_table("tw_world_quest_template.sql", "quest_template"):
        quest_en[v.get("entry")] = v.get("Title")
        l = loc_q.get(v.get("entry"))
        if l:
            P.add("quests", v.get("Title"), l.get("Title_loc8"))
    loc_p = {v["entry"]: v for v in sql_table("tw_world_locales_page_text.sql", "locales_page_text")}
    for v in sql_table("tw_world_page_text.sql", "page_text"):
        l = loc_p.get(v.get("entry"))
        if l and v.get("text") and l.get("Text_loc8"):
            for e, rr in zip(gossip_keys(book_key(v["text"])), gossip_keys(book_key(l["Text_loc8"])) * 2):
                P.add("books", e, rr)
    loc_b = {v["entry"]: v for v in sql_table("tw_world_locales_broadcast_text.sql", "locales_broadcast_text")}
    for v in sql_table("tw_world_broadcast_text.sql", "broadcast_text"):
        l = loc_b.get(v.get("entry"))
        if not l:
            continue
        for f in ("male_text", "female_text"):
            en, ru = v.get(f), l.get(f + "_loc8")
            if en and ru:
                for e, rr in zip(gossip_keys(en), gossip_keys(ru) * 2):
                    P.add("gossip", e, rr)
    loc_o = {(v["menu_id"], v["id"]): v for v in sql_table("tw_world_locales_gossip_menu_option.sql",
                                                           "locales_gossip_menu_option")}
    for v in sql_table("tw_world_gossip_menu_option.sql", "gossip_menu_option"):
        l = loc_o.get((v.get("menu_id"), v.get("id")))
        if l:
            for f in ("option_text", "box_text"):
                for e, rr in zip(gossip_keys(v.get(f) or ""), gossip_keys(l.get(f + "_loc8") or "") * 2):
                    P.add("gossip", e, rr)
    for fname, table in (("tw_world_quest_greeting.sql", "quest_greeting"),
                         ("tw_world_npc_trainer_greeting.sql", "npc_trainer_greeting"),
                         ("tw_world_mail_text_template.sql", "mail_text_template")):
        for v in sql_table(fname, table):
            en, ru = v.get("content_default"), v.get("content_loc8")
            if en and ru:
                for e, rr in zip(gossip_keys(en), gossip_keys(ru) * 2):
                    P.add("gossip", e, rr)
                for e, rr in zip(gossip_keys(en.replace("\r\n", "$B").replace("\n", "$B")),
                                 gossip_keys(ru.replace("\r\n", "$B").replace("\n", "$B")) * 2):
                    P.add("gossip", e, rr)
    loc_a = {v["Entry"]: v for v in sql_table("tw_world_locales_area.sql", "locales_area")}
    for v in sql_table("tw_world_area_template.sql", "area_template"):
        l = loc_a.get(v.get("entry"))
        if l:
            P.add("zones", v.get("name"), l.get("NameLoc8"))
    loc_poi = {v["entry"]: v for v in sql_table("tw_world_locales_points_of_interest.sql", "locales_points_of_interest")}
    for v in sql_table("tw_world_points_of_interest.sql", "points_of_interest"):
        l = loc_poi.get(v.get("entry"))
        if l:
            P.add("zones", v.get("icon_name"), l.get("icon_name_loc8"))
    # data/broadcast_en.json (R55 import: EN -> RU of world-DB speech / gossip)
    bp = os.path.join(ROOT, "data", "broadcast_en.json")
    if os.path.exists(bp):
        for en, v in json.load(open(bp, encoding="utf-8")).items():
            for e, rr in zip(gossip_keys(en), gossip_keys(v.get("ru") or "") * 2):
                P.add("gossip", e, rr, 2)
    # Questie ruRU (Classic Era official Russian = what Forever's client most likely shows): weight 3
    lk = os.path.join(QUESTIE, "Localization", "lookups", "Classic")
    try:
        from questie_names import _table
        npc_db = _table(os.path.join(QUESTIE, "Database", "Classic", "classicNpcDB.lua"), "npcData = [[return {")
        ru_n = lua_lookup(os.path.join(lk, "lookupNpcs", "ruRU.lua"), "loadstring([[return {")
        for nid, row in npc_db.items():
            r = ru_n.get(int(nid))
            if r:
                P.add("names", row[1], r[1], 3)
                P.add("titles", row[14], r[2], 3)             # npcKeys.subName = 14
        obj_db = _table(os.path.join(QUESTIE, "Database", "Classic", "classicObjectDB.lua"), "objectData = [[return {")
        ru_o = lua_lookup(os.path.join(lk, "lookupObjects", "ruRU.lua"), "loadstring([[return {")
        for oid, row in obj_db.items():
            P.add("names", row[1], ru_o.get(int(oid)), 3)
        item_db = _table(os.path.join(QUESTIE, "Database", "Classic", "classicItemDB.lua"), "itemData = [[return {")
        ru_i = lua_lookup(os.path.join(lk, "lookupItems", "ruRU.lua"), "loadstring([[return {")
        for iid, row in item_db.items():
            P.add("items", row[1], ru_i.get(int(iid)), 3)
        q_db = _table(os.path.join(QUESTIE, "Database", "Classic", "classicQuestDB.lua"), "questData = [[return {")
        ru_q = lua_lookup(os.path.join(lk, "lookupQuests", "ruRU.lua"), "loadstring([[return {")
        for qid, row in q_db.items():
            r = ru_q.get(int(qid))
            if r:
                P.add("quests", row[1], r[1], 3)
    except Exception as e:  # noqa: BLE001
        print("  ru: Questie lookups skipped:", str(e)[:200])
    # a ruRU session's own text (weight 5: what THIS client shows): the ruRU WDB cache (NPC / object names, quest titles,
    # kept cumulatively in out/cache/ru.json — a new client build empties the cache) and the ruRU harvest (NPC names with
    # the NPC id core/names.lua stores, quests by id) — EN by the same id from the enUS cache dump / wowhead EN lists
    rc = ru_cache()
    en_id = {"creatures": tsv_ids("creatures.tsv"), "objects": tsv_ids("gameobjects.tsv"), "quests": {}}
    for r in tsv(os.path.join(ROOT, "out", "cache", "quests.tsv")) if os.path.exists(
            os.path.join(ROOT, "out", "cache", "quests.tsv")) else []:
        if len(r) > 1 and r[0].isdigit(): en_id["quests"][r[0]] = r[1]
    fd = os.path.join(ROOT, "forever-data")
    for kind, key in (("npcs", "creatures"), ("objects", "objects"), ("quests", "quests")):
        p = os.path.join(fd, "en", kind + ".json")
        if os.path.exists(p):
            for i, e in json.load(open(p, encoding="utf-8")).items():
                nm = isinstance(e, dict) and (e.get("name") or e.get("t"))
                if nm: en_id[key].setdefault(i, nm)
    for k in ("creatures", "creatures_f"):
        for i, ru in rc.get(k, {}).items():
            P.add("names", en_id["creatures"].get(i), ru, 5)
    for i, ru in rc["objects"].items():
        P.add("names", en_id["objects"].get(i), ru, 5)
    for i, ru in rc.get("titles_ru", {}).items():
        P.add("titles", rc.get("titles_en", {}).get(i), ru, 5)
    for i, q in rc["quests"].items():
        P.add("quests", en_id["quests"].get(i), q.get("t"), 5)
    hp = os.path.join(ROOT, "data", "harvest.json")
    h_ru = json.load(open(hp, encoding="utf-8")).get("ruRU", {}) if os.path.exists(hp) else {}
    for ru, v in h_ru.get("names", {}).items():
        if isinstance(v, (int, float)) and not isinstance(v, bool):
            P.add("names", en_id["creatures"].get(str(int(v))), ru, 5)
    for i, q in h_ru.get("quests", {}).items():
        if isinstance(q, dict):
            P.add("quests", en_id["quests"].get(str(i)), q.get("t"), 5)
    # objective lines (tracker / log, WoWBY_Objectives): per quest id, counters / kill verbs cut off; a quest with exactly
    # ONE free-text line on each side pairs them ("0/1 Collect and read the note" ↔ «Возьмите и прочтите записку: 0/1»)
    def free_lines(d):
        by_q = collections.defaultdict(set)
        for line, q in d.items():
            s = re.sub(r"^\d+/\d+\s+|:\s*\d+/\d+$|\s*\((?:Complete|Optional|выполнено|необязательно)\)$", "",
                       line.strip()).strip()
            if s and not re.search(r" slain$| – убито$|^Цель достигнута", s):
                by_q[str(q)].add(s)
        return by_q
    h_en = json.load(open(hp, encoding="utf-8")).get("enUS", {}) if os.path.exists(hp) else {}
    eq, rq = free_lines(h_en.get("objectives", {})), free_lines(h_ru.get("objectives", {}))
    for q, rus in rq.items():
        if len(rus) == 1 and len(eq.get(q, ())) == 1:
            P.add("objectives", next(iter(eq[q])), next(iter(rus)), 5)
    # wowhead RU scrape (Forever's own Russian): NPCs (+ title tag), objects, quests
    for kind, dom in (("npcs", "names"), ("objects", "names")):
        pe, pr = os.path.join(fd, "en", kind + ".json"), os.path.join(fd, "ru", kind + ".json")
        if os.path.exists(pe) and os.path.exists(pr):
            en, ru = json.load(open(pe, encoding="utf-8")), json.load(open(pr, encoding="utf-8"))
            for i, e in en.items():
                r = ru.get(i)
                if isinstance(e, dict) and isinstance(r, dict):
                    P.add(dom, e.get("name"), r.get("name"), 3)
                    P.add("titles", e.get("tag"), r.get("tag"), 3)
    qe, qr = os.path.join(fd, "en", "quests.json"), os.path.join(fd, "ru", "quests.json")
    forever_en_titles = {}
    if os.path.exists(qe):
        en = json.load(open(qe, encoding="utf-8"))
        ru = json.load(open(qr, encoding="utf-8")) if os.path.exists(qr) else {}
        for i, e in en.items():
            if isinstance(e, dict) and e.get("t"):
                forever_en_titles[i] = e["t"]
                r = ru.get(i)
                if isinstance(r, dict):
                    P.add("quests", e["t"], r.get("t"), 4)
    return P, gs, forever_en_titles


def ru_to_en_index():
    """{domain: {RU text: most common EN}} over every known pair (not only shipped keys) — maps what a ruRU session
    harvested back to EN queue keys (extract_forever.py)."""
    P, _, _ = collect()
    out = {}
    for dom, m in P.d.items():
        best = {}
        for en, rus in m.items():
            for ru, c in rus.items():
                if c > best.get(ru, (0, ""))[0]:
                    best[ru] = (c, en)
        out[dom] = {ru: en for ru, (_, en) in best.items()}
    return out


# ---------- shipped tables (the EN keys each domain may map to) ----------
def shipped():
    import lupa
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute("GetLocale = function() return 'enUS' end")
    L.execute("for _, k in ipairs({'WoWBY_Objectives', 'WoWBY_NamesF', 'WoWBY_TitlesF', 'WoWBY_Gossip', 'WoWBY_QuestOA',"
              " 'WoWBY_QTitleFV', 'WoWBY_Q', 'WoWBY_Names', 'WoWBY_Zones', 'WoWBY_QTitleEN'}) do _G[k] = _G[k] or {} end")
    for f in ("quests.lua", "zones.lua", "gossip.lua", "names.lua", "quest_guard.lua", "forever.lua", "spells_items.lua",
              "ui.lua", "titles.lua", "books.lua"):
        L.execute(open(os.path.join(OUT, "data", f), encoding="utf-8").read())
    G = L.globals()

    def keys(name):
        t = G[name]
        return {k for k in t.keys() if isinstance(k, str)} if t is not None else set()
    core_vocab = set()
    cdir = os.path.join(OUT, "core")
    for fn in os.listdir(cdir):
        src = open(os.path.join(cdir, fn), encoding="utf-8").read()
        for s in re.findall(r'"((?:[^"\\\n]|\\.)*)"', src):
            s = s.replace("\\'", "'")
            core = s[1:] if s.startswith("^") else s
            core = core[:-1] if core.endswith("$") else core
            core = core.replace("%-", "-").replace("%(", "(").replace("%)", ")").replace("%.", ".")
            if re.fullmatch(r"[A-Z][A-Za-z' ,&()\-.:!?]{1,60}", core):
                core_vocab.add(core)
        for s in re.findall(r"[{,\s]([A-Z][A-Za-z]+)\s*=\s*\"", src):
            core_vocab.add(s)
    # enchant names ("Stamina +1 and Armor +8"): the EN path builds them from stat words (ui.lua stat_list_be, R673)
    ench = {r[3] for r in tsv(os.path.join(ROOT, "out", "db2", "SpellItemEnchantment.tsv")) if len(r) > 3 and r[3]}
    T = {
        "ui": keys("WoWBY_UI") | keys("WoWBY_Factions") | keys("WoWBY_Skills") | keys("WoWBY_Holidays") | core_vocab | ench,
        "names": keys("WoWBY_Names") | keys("WoWBY_NamesF"),
        "titles": keys("WoWBY_Titles") | keys("WoWBY_TitlesF"),
        "zones": keys("WoWBY_Zones") | keys("WoWBY_POI"),
        "gossip": keys("WoWBY_Gossip"),
        "items": keys("WoWBY_ItemsEN"),
        "spells": keys("WoWBY_SpellNamesEN") | keys("WoWBY_AuraByName"),
        "books": keys("WoWBY_Books"),
        "objectives": keys("WoWBY_Objectives"),
        "quests": set(G["WoWBY_QTitleEN"].values()) | keys("WoWBY_QTitleFV"),
    }
    qt = {str(k): v for k, v in G["WoWBY_QTitleEN"].items()}
    return T, qt


# ---------- RU formats -> EN line ----------
def ru_fmt_pattern(ru):
    """RU format string -> (anchored Lua pattern, #captures, {arg: capture}). Like build_addon.fmt_pattern, but RU
    declension wrappers |3-N(%s) are dropped (the client declines the value; the capture takes the declined form) and
    a plural escape with no common stem is any non-space run (Lua's %a has no Cyrillic)."""
    ru = re.sub(r"\|3-\d+\((%[^)]*)\)", r"\1", ru)
    out, n, pos, argmap = ["^"], 0, 0, {}
    for m in FMT_TOKEN.finditer(ru):
        lit = ru[pos:m.start()]
        out.append(esc_lit_ru(lit))
        pos = m.end()
        if m.group(0) == "%%":
            out.append("%%"); continue
        n += 1
        argmap[int(m.group(1)) if m.group(1) else n] = n
        if lit.endswith("|c") and m.group(0).endswith("s"):
            out.append("(%x%x%x%x%x%x%x%x)")
        elif m.group(0)[-1] in "di":
            out.append("(%-?[%d,%.]+)")
        elif m.group(0)[-1] == "c":
            out.append("([%+%-])")
        else:
            out.append("(.-)")
    out.append(esc_lit_ru(ru[pos:]))
    return "".join(out) + "$", n, argmap


def esc_lit_ru(lit):
    def plural(p):
        forms = p[2:-1].split(":")
        stem = os.path.commonprefix(forms)
        if len(stem) < 2:
            # only the letters of the escape's own forms (R667: a lazy any-run let «52 сек.» match the DAYS format
            # «%d |4день:дня:дней;» → «Засталося 52 дні»)
            return "[" + "".join(sorted(set(magic_set(c) for c in "".join(forms)))) + "]+"
        rest = "".join(sorted(set("".join(f[len(stem):] for f in forms))))
        return magic(stem) + ("[" + magic(rest) + "]-" if rest else "")
    return "".join(plural(p) if p.startswith("|4") else magic(p) for p in re.split(r"(\|4[^;]*;)", lit))


def magic(s):
    return re.sub(r"([\^\$\(\)%\.\[\]\*\+\-\?])", r"%\1", s)


def magic_set(c):
    """One character inside a Lua [set]."""
    return "%" + c if c in "^]-%[" else c


WORD_RX = re.compile(r"[A-Za-z\u0400-\u047F]{3,}")


def index_words(ru):
    """The words the runtime looks a RU line up by: the longest literal word; a format that is only a number + a plural
    escape ("%d |4\u043C\u0435\u0434\u043D\u0430\u044F \u043C\u043E\u043D\u0435\u0442\u0430:\u043C\u0435\u0434\u043D\u044B\u0435 \u043C\u043E\u043D\u0435\u0442\u044B:\u043C\u0435\u0434\u043D\u044B\u0445 \u043C\u043E\u043D\u0435\u0442;") by each plural form's longest word."""
    lit = FMT_TOKEN.sub(" ", re.sub(r"\|3-\d+\((%[^)]*)\)", " ", ru))
    lit = re.sub(r"\|c\w{8}|\|cn[^:]*:|\|r|\|H[^|]*\|h|\|h|\|T[^|]*\|t|\|A[^|]*\|a|\|n", " ", lit)
    words = sorted(WORD_RX.findall(re.sub(r"\|4[^;]*;", " ", lit)), key=len, reverse=True)
    if words:
        return [words[0]]
    out = []
    for esc in re.findall(r"\|4([^;]*);", lit):
        for form in esc.split(":"):
            ws = sorted(WORD_RX.findall(form), key=len, reverse=True)
            if ws and ws[0] not in out: out.append(ws[0])
    return out


def ru_formats(gs):
    """[(pattern, [EN parts\u2026], index words)] most specific first. One RU pattern can stand for several EN formats
    (\u00AB\u0412\u0430\u0448\u0430 \u0434\u043E\u0431\u044B\u0447\u0430: %s.\u00BB = "You receive loot: %s" and "You loot %s"): the runtime tries each."""
    by_pat = {}
    for key, en, ru in gs:
        if not FMT_TOKEN.search(en) or en == ru or key.startswith(("SLASH_", "DEBUG")):
            continue
        if not CYR.search(ru):
            continue
        pat, n, argmap = ru_fmt_pattern(ru)
        if n == 0:
            continue
        parts = fmt_parts(en, n, argmap)
        ws = index_words(ru)
        if parts is None or not ws:
            continue
        e = by_pat.setdefault(pat, [[], ws])
        if parts not in e[0]:
            e[0].append(parts)
    # enchant name templates ($k1 / $123s2 tokens, filled in by the client): RU → EN by token
    for en, ru in ENCH_TPL:
        pat, toks = lua_pattern(ru.replace("\r", ""))
        parts = be_parts(en, toks)
        ws = index_words(re.sub(r"\$\S+", " ", ru))
        if parts is None or not toks or not ws or "$" in pat.replace("%$", "")[:-1]:
            continue
        e = by_pat.setdefault(pat, [[], ws])
        if parts not in e[0]:
            e[0].append(parts)
    out = []
    for pat, (alts, ws) in by_pat.items():
        spec = len(re.sub(r"\(\.-\)|\(%[^)]*\)|\[\^%s\]-", "", pat))
        out.append((spec, pat, alts, ws))
    out.sort(key=lambda x: (-x[0], x[1]))
    return [(p, alts, ws) for _, p, alts, ws in out]


# ---------- writer ----------
def emit_map(lines, var, m, chunk=4000):
    """Assignments in closures of `chunk` lines: Lua 5.1 caps one function's constants at 2^18."""
    items = sorted(m.items())
    for i in range(0, len(items), chunk):
        lines.append(";(function() local M = %s" % var)
        for ru, ens in items[i:i + chunk]:
            v = lua_str(ens[0]) if len(ens) == 1 else "{%s}" % ",".join(lua_str(e) for e in ens)
            lines.append("M[%s]=%s" % (lua_str(ru), v))
        lines.append("end)()")


# Russian race names for WOMEN (unit tooltips «Небеснорожденная из Высшего ордена 10-го уровня», R669): not in the dumps
RACES_F = {"Ночная эльфийка": "Night Elf", "Дворфийка": "Dwarf", "Гномка": "Gnome", "Орчиха": "Orc", "Троллиха": "Troll",
           "Тауренка": "Tauren", "Дренейка": "Draenei", "Гоблинша": "Goblin", "Эльфийка крови": "Blood Elf",
           "Небеснорожденная из Высшего ордена": "High Order Skyborne",
           "Небеснорожденная из Ваятелей ветра": "Windshaper Skyborne"}
# one Russian word for several English ones: the reading the client shows most (R666 «Мир» on the map home button,
# R668 «Персональный предмет» = Soulbound far more often than "No Drop")
PREFER = {"Персональный предмет": "Soulbound", "Мир": "World"}


def pair_gossip_by_npc(P, hp):
    """Forever gossip has no Russian source: a ruRU session harvests the lines it could not translate with the NPC (id
    on ruRU, core/ru.lua W.npc_key); the enUS harvest has the same NPC's English lines. An NPC with ONE Russian line and
    ONE English line whose Russian is still unknown pairs them (R672: «Добро пожаловать в таверну "Спокойный бриз"…»)."""
    if not os.path.exists(hp):
        return 0
    h = json.load(open(hp, encoding="utf-8"))
    en_g, ru_g = h.get("enUS", {}).get("gossip", {}), h.get("ruRU", {}).get("gossip", {})
    if not ru_g:
        return 0
    known = set(P.d["gossip"])                                 # EN lines that already have a Russian form
    by_npc_en = collections.defaultdict(set)
    for text, npc in en_g.items():
        if isinstance(npc, str) and text not in known:
            by_npc_en[npc].add(text)
    names_best = {}
    for en, rus in P.d["names"].items():
        for ru, c in rus.items():
            if c > names_best.get(ru, (0, ""))[0]: names_best[ru] = (c, en)
    ids = tsv_ids("creatures.tsv")
    p = os.path.join(ROOT, "forever-data", "en", "npcs.json")
    for i, e in (json.load(open(p, encoding="utf-8")).items() if os.path.exists(p) else []):
        if isinstance(e, dict) and e.get("name"): ids.setdefault(i, e["name"])
    by_npc_ru = collections.defaultdict(set)
    for text, npc in ru_g.items():
        if isinstance(npc, (int, float)) and not isinstance(npc, bool):
            en_npc = ids.get(str(int(npc)))
        elif isinstance(npc, str):
            en_npc = names_best.get(npc.replace("́", ""), (0, None))[1] or (npc if npc in by_npc_en else None)
        else:
            en_npc = None
        if en_npc: by_npc_ru[en_npc].add(text)
    n = 0
    for npc, rus in by_npc_ru.items():
        ens = by_npc_en.get(npc, set())
        if len(rus) == 1 and len(ens) == 1:
            en, ru = next(iter(ens)), next(iter(rus))
            for e, rr in zip(gossip_keys(en), gossip_keys(ru) * 2):
                P.add("gossip", e, rr, 5)
            n += 1
    return n


def build(ru_desc=None, stats=False):
    P, gs, fv_titles = collect()
    T, qt = shipped()
    for ru, en in RACES_F.items():
        P.add("ui", en, ru, 9)
    pair_gossip_by_npc(P, os.path.join(ROOT, "data", "harvest.json"))
    # item flavor texts are shown in quotes ("\"A small glowing stone…\""), the DB2 pairs have none (R670)
    for en in [e for e in T["ui"] if len(e) > 2 and e[0] == e[-1] == '"']:
        for ru, c in list(P.d["ui"].get(en[1:-1], {}).items()):
            P.add("ui", en, '"%s"' % ru, c)
    L = ["-- WoWBY ruRU support (R665) — GENERATED by tools/build_ru.py; loaded only on a ruRU client",
         "if GetLocale and GetLocale() ~= \"ruRU\" then return end",
         "WoWBY_RU = { %s }" % ", ".join("%s = {}" % d for d in DOMAINS)]
    counts = {}
    for dom in DOMAINS:
        want = T[dom]
        m = collections.defaultdict(collections.Counter)
        for en, rus in P.d[dom].items():
            if en not in want:
                continue
            for ru, c in rus.items():
                if ru not in want or dom != "ui":          # an RU text that is itself an EN key stays as it is
                    m[ru][en] += c
        res = {ru: [e for e, _ in sorted(c.items(), key=lambda kv: (-kv[1], kv[0]))][:4] for ru, c in m.items()}
        for ru, en in PREFER.items():
            if dom == "ui" and en in res.get(ru, []):
                res[ru] = [en] + [e for e in res[ru] if e != en]
        emit_map(L, "WoWBY_RU.%s" % dom, res)
        counts[dom] = len(res)
    fm = ru_formats(gs)
    L.append("WoWBY_RUF, WoWBY_RUFX = {}, {}")
    for i in range(0, len(fm), 3000):
        L.append(";(function() local F, X = WoWBY_RUF, WoWBY_RUFX")
        for j, (pat, alts, ws) in enumerate(fm[i:i + 3000], i + 1):
            L.append("F[%d]={%s,%s}" % (j, lua_str(pat), ",".join("{%s}" % ",".join(p) for p in alts)))
            for w in ws:
                L.append("X[%s]=X[%s] or {}; X[%s][#X[%s]+1]=%d" % ((lua_str(w),) * 4 + (j,)))
        L.append("end)()")
    counts["formats"] = len(fm)
    L.append("WoWBY_SpellDescRU = {}")
    nd = 0
    items = sorted((ru_desc or {}).items())
    for i in range(0, len(items), 3000):
        L.append(";(function() local SDR = WoWBY_SpellDescRU")
        for k, body in items[i:i + 3000]:
            L.append("SDR[%s]={%s}" % (lua_str(k), body)); nd += 1
        L.append("end)()")
    counts["descriptions"] = nd
    # quests reworked in Forever: its EN title (wowhead / WDB cache) differs from the title the WoWBY text was made from
    cache_titles = {}
    cp = os.path.join(ROOT, "out", "cache", "quests.tsv")
    if os.path.exists(cp):
        for r in tsv(cp):
            if len(r) > 1 and r[0].isdigit() and r[1]:
                cache_titles[r[0]] = r[1]
    rework = sorted(int(q) for q, t in qt.items()
                    if (cache_titles.get(q) or fv_titles.get(q)) and
                    (cache_titles.get(q) or fv_titles.get(q)).strip().lower() != t.strip().lower())
    L.append("WoWBY_QReworkRU = {%s}" % ",".join("[%d]=true" % q for q in rework))
    counts["reworked quests"] = len(rework)
    body = "\n".join(L) + "\n"
    open(os.path.join(OUT, "data", "ru.lua"), "w", encoding="utf-8", newline="\n").write(body)
    print("ru.lua: %s (%.1f MB)" % (", ".join("%s %d" % kv for kv in counts.items()), len(body.encode("utf-8")) / 1e6))
    return counts


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    import build_addon
    # descriptions need the BE templates the main build uses: run its spells step for them (no files written there)
    _, _ = build_addon.spells_items_lua()
    build(build_addon.RU_DESC, "--stats" in sys.argv)
