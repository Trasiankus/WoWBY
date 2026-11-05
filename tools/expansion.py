"""Which game each Belarusian entry belongs to (owner 2026-10-22, R719): vanilla / forever / ui / tbc / wotlk / turtle.
translations/ is split into one directory per value (translations/turtle is local only, not in git); the build keeps
shipping vanilla + forever + ui (tools/forever_scope.py parks the rest).

  vanilla  in Classic Era: Questie Classic NPCs / objects / quests / items / NPC titles, the classic world DB lines
           (strings_en "why": classic …), client rows that also exist in the Anniversary client (DB2 status same / changed)
  forever  added by Forever: everything else the Forever client / server shows (wowhead Forever lists, harvest, new rows)
  ui       the client interface (GlobalStrings, skills)
  tbc / wotlk / turtle   parked text (data/be_parked): Questie TBC, then Questie WotLK, else Turtle-only
    from expansion import classify;  classify(domain, key, parked=False) -> one of the above
    python tools/expansion.py      counts per domain (cache: out/expansion_cache.json)"""
import collections, glob, hashlib, json, os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
Q = r"C:\Projects\WoW\Questie"
CACHE = os.path.join(ROOT, "out", "expansion_cache.json")
_p = lambda *a: os.path.join(ROOT, *a)
FLAVORS = ("Classic", "TBC", "Wotlk")


def _db(flavor, kind):
    from questie_names import _table
    name = {"Classic": "classic", "TBC": "tbc", "Wotlk": "wotlk"}[flavor]
    return _table(os.path.join(Q, "Database", flavor, "%s%sDB.lua" % (name, kind.capitalize())), "%sData = [[return {" % kind)


def _tsv(table):
    p = _p("out", "db2", table + ".tsv")
    if not os.path.exists(p): return []
    return [l.split("\t") for l in open(p, encoding="utf-8").read().splitlines()[1:]]


def _zones():
    """Questie zoneLookup: continent 3 = Outland (tbc), 4 = Northrend (wotlk); area ids 3430-4139 on the old continents
    are the TBC zones (Eversong 3430 … Isle of Quel'Danas 4080), higher ones WotLK"""
    txt = open(os.path.join(Q, "Localization", "lookups", "lookupZones.lua"), encoding="utf-8").read()
    txt = txt[txt.index("l10n.zoneLookup = {"):]
    out, cont = {}, None
    for line in txt.splitlines()[1:]:
        m = re.match(r"\s{4}\[(\d+)\]=\{", line)
        if m: cont = int(m.group(1)); continue
        m = re.match(r'\s+\[(\d+)\]="(.*)",?\s*$', line)
        if m and cont is not None:
            aid, name = int(m.group(1)), m.group(2).replace('\\"', '"')
            exp = "tbc" if cont == 3 else "wotlk" if cont == 4 else \
                  ("tbc" if 3430 <= aid < 4140 else "wotlk" if aid >= 4140 else "vanilla")
            prev = out.get(name)
            if prev != "vanilla": out[name] = exp if prev is None else min(prev, exp, key=["vanilla", "tbc", "wotlk"].index)
        if line.startswith("}"): break
    return out


def _build():
    c = {}
    for fl in FLAVORS:
        npc, obj, quest, item = _db(fl, "npc"), _db(fl, "object"), _db(fl, "quest"), _db(fl, "item")
        c[fl] = {"names": sorted({r[1] for r in list(npc.values()) + list(obj.values()) if r[1]}),
                 "quests": sorted(str(k) for k in quest.keys()),
                 "items": sorted(str(k) for k in item.keys()),
                 "titles": sorted({r[14] for r in npc.values() if r[14]})}
    st = {}
    for t, f in (("ItemSparse", "Display_lang"), ("SpellName", "Name_lang"), ("AreaTable", "AreaName_lang"),
                 ("AreaPOI", "Name_lang"), ("WMOAreaTable", "AreaName_lang"), ("Faction", "Name_lang")):
        old = {"id": set(), "en": set()}
        for r in _tsv(t):
            if len(r) > 6 and r[1] == f and r[6] != "new": old["id"].add(r[0]); old["en"].add(r[3].strip())
        st[t] = {k: sorted(v) for k, v in old.items()}
    desc_old = set()
    for r in _tsv("Spell"):
        if len(r) > 6 and r[1] in ("Description_lang", "AuraDescription_lang") and r[6] != "new":
            desc_old.add(hashlib.md5(r[3].encode("utf-8")).hexdigest()[:8])
    c["db2_old"], c["desc_old"], c["zones"] = st, sorted(desc_old), _zones()
    item_en = collections.defaultdict(set)
    for r in _tsv("ItemSparse"):
        if len(r) > 3 and r[1] == "Display_lang": item_en[r[3]].add(r[0])
    c["item_en"] = {k: sorted(v) for k, v in item_en.items()}
    s = json.load(open(_p("data", "strings_en.json"), encoding="utf-8"))
    c["why"] = {k: str(v.get("why", "")) for k, v in s.items() if isinstance(v, dict)}
    c["books_forever"] = sorted(json.load(open(_p("out", "books_forever.json"), encoding="utf-8"))) \
        if os.path.exists(_p("out", "books_forever.json")) else []
    c["book_openers"] = _book_openers()
    return c


def _book_openers():
    """page key -> item / object ids that open the book it belongs to (classic world DB, as export_review.book_titles)"""
    from import_broadcast import rows, SQL
    from build_addon import book_key
    text, nxt = {}, {}
    for v in rows(os.path.join(SQL, "tw_world_page_text.sql"), "page_text"):
        pid = int(v[0]); text[pid] = book_key(v[1] or ""); nxt[pid] = int(v[2] or 0)
    starts = []
    for v in rows(os.path.join(SQL, "tw_world_item_template.sql"), "item_template"):
        if len(v) > 108 and int(v[108] or 0): starts.append(("i" + v[0], int(v[108])))
    for v in rows(os.path.join(SQL, "tw_world_gameobject_template.sql"), "gameobject_template"):
        t = int(v[1] or 0)
        pid = int(v[7] or 0) if t == 9 else (int(v[14] or 0) if t == 10 and len(v) > 14 else 0)
        if pid: starts.append(("o" + v[0], pid))
    out = collections.defaultdict(set)
    for opener, pid in starts:
        guard = set()
        while pid and pid in text and pid not in guard:
            guard.add(pid); out[text[pid]].add(opener); pid = nxt.get(pid, 0)
    return {k: sorted(v) for k, v in out.items()}


_C = None


def data():
    global _C
    if _C is None:
        srcs = glob.glob(os.path.join(Q, "Database", "*", "*.lua")) + glob.glob(_p("out", "db2", "*.tsv")) + \
               [_p("data", "strings_en.json"), _p("out", "books_forever.json"), os.path.abspath(__file__)]
        stamp = max(os.path.getmtime(p) for p in srcs if os.path.exists(p))
        c = json.load(open(CACHE, encoding="utf-8")) if os.path.exists(CACHE) else {}
        if c.get("stamp") != stamp:
            c = _build(); c["stamp"] = stamp
            json.dump(c, open(CACHE, "w", encoding="utf-8"), ensure_ascii=False)
        _C = _sets(c)
    return _C


def _sets(c):
    S = {"why": c["why"], "zones": c["zones"], "item_en": c["item_en"], "book_openers": c["book_openers"]}
    for fl in FLAVORS:
        S[fl] = {k: set(v) for k, v in c[fl].items()}
    S["db2_old"] = {t: {k: set(v) for k, v in d.items()} for t, d in c["db2_old"].items()}
    S["desc_old"], S["books_forever"] = set(c["desc_old"]), set(c["books_forever"])
    # Classic book openers: Questie Classic item ids, object names (objects are matched by id in the world DB)
    return S


def _parked(kind, value):
    """tbc / wotlk / turtle for text Forever cannot show"""
    S = data()
    if kind == "zone":
        z = S["zones"].get(value.strip())
        return z if z in ("tbc", "wotlk") else "turtle"
    for fl, exp in (("TBC", "tbc"), ("Wotlk", "wotlk")):
        if value in S[fl][kind]: return exp
    return "turtle"


def _name(en):
    return "vanilla" if en in data()["Classic"]["names"] else "forever"


def _item_id(i):
    """vanilla item id: Questie Classic (quest items only), also in the Anniversary client, or a classic-range id
    (Forever's own items start at ~190000; Turtle's custom ones at 40000+)"""
    S = data()
    return i in S["Classic"]["items"] or i in S["db2_old"]["ItemSparse"]["id"] or (i.isdigit() and int(i) < 30000)


def _item_name(en):
    ids = data()["item_en"].get(en, [])
    if ids: return "vanilla" if any(_item_id(i) for i in ids) else "forever"
    return _old("ItemSparse", en)


def _old(table, en):
    return "vanilla" if en.strip() in data()["db2_old"][table]["en"] else "forever"


def _gossip(en):
    why = data()["why"].get("gossip:" + en, "")
    return "forever" if why and not why.startswith("classic") else "vanilla"


def classify(domain, key, parked=False):
    S = data()
    key = str(key)
    if parked:
        if domain == "tb_quests": return _parked("quests", key.split(".")[0])
        if domain == "tb_names": return _parked("names", key)
        if domain in ("tb_zones", "poi", "wmo"): return _parked("zone", key)
        if domain == "books": return "turtle"
        return "turtle"
    if domain in ("ui", "ui_fmt"): return "ui"
    if domain in ("tb_quests", "tb_gossip"): return "vanilla"
    if domain == "tb_names": return _name(key)
    if domain == "tb_zones": return _old("AreaTable", key) if _old("AreaTable", key) == "vanilla" else \
        _old("WMOAreaTable", key)
    if domain == "poi": return _old("AreaPOI", key)
    if domain == "wmo": return _old("WMOAreaTable", key)
    if domain == "factions": return _old("Faction", key)
    if domain == "items": return "vanilla" if _item_id(key) else "forever"
    if domain == "item_names": return _item_name(key)
    if domain == "spell_names": return "vanilla" if key in S["db2_old"]["SpellName"]["id"] else "forever"
    if domain == "spell_names_en": return _old("SpellName", key)
    if domain == "spell_desc": return "vanilla" if key in S["desc_old"] else "forever"
    if domain in ("titles", "titles_f"): return "vanilla" if key in S["Classic"]["titles"] else "forever"
    if domain == "books":
        if key in S["books_forever"]: return "forever"
        op = S["book_openers"].get(key, [])
        if any(o[0] == "i" and _item_id(o[1:]) for o in op): return "vanilla"
        if any(o[0] == "o" for o in op) and not any(o[0] == "i" for o in op): return "vanilla"   # plaques: by object
        return "forever" if not op else "turtle"
    kind, _, rest = key.partition(":")
    if domain == "hand":
        if kind == "name": return _name(rest)
        if kind == "itemname": return _item_name(rest)
        if kind == "spellname": return _old("SpellName", rest)
        if kind == "gossip": return _gossip(rest)
        if kind == "skill": return "ui"
        return "vanilla" if S["why"].get(key, "").startswith("classic") else "forever"
    if domain == "forever":
        if kind == "quest":
            return "forever"
        if kind == "gossip": return _gossip(rest)
        why = S["why"].get(key, "")
        if why.startswith("classic"): return "vanilla"
        if kind == "name": return _name(rest)
        if kind == "zone": return _old("AreaTable", rest)
        return "forever"
    return "vanilla"


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    for d in ("be", "be_parked"):
        for p in sorted(glob.glob(_p("data", d, "*.json"))):
            dom = os.path.basename(p)[:-5]
            c = collections.Counter(classify(dom, k, parked=(d == "be_parked")) for k in json.load(open(p, encoding="utf-8")))
            print("%-10s %-15s %s" % (d, dom, dict(c.most_common())))
