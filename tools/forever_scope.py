"""What Forever can show, for the turtle-bel data (owner 2026-10-22, R718): turtle-bel also carries TBC quests and
Turtle-only / TBC NPC names and places that never appear in Forever. The build ships (and data/be keeps) a tb_quests /
tb_names / tb_zones entry only when it is in scope; the rest is PARKED in data/be_parked/ (corpus.py) and comes back
by itself — hand edits included — once Forever shows it (new client build, wowhead list, WDB cache, harvest).

Scope:
  quests  classic quests (turtle-bel data/classic, incl. vanilla ones Blizzard deleted) + any id the Forever client
          (QuestV2), the beta WDB cache, wowhead's Forever list or the harvest knows
  names   Questie Classic NPC + object names, wowhead's Forever NPC / object lists, the WDB cache, the client
          Creature / GameObjects DB2, harvested names / objects
  zones   the client's place tables (AreaTable, WMOAreaTable, AreaPOI, UiMap, Map, TaxiNodes, Vignette, LFGDungeons)
          + harvested zones / objects
    from forever_scope import scope;  s = scope()   # {"quests": set(str id), "names": set(EN), "zones": set(EN)}
    python tools/forever_scope.py                    # counts; cached in out/forever_scope.json (rebuilt when a source changes)"""
import json, os, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TB = r"C:\Projects\WoW\turtle-bel\data"
CACHE = os.path.join(ROOT, "out", "forever_scope.json")
PLACE_TABLES = ("AreaTable", "WMOAreaTable", "AreaPOI", "UiMap", "Map", "TaxiNodes", "Vignette", "LFGDungeons")
_p = lambda *a: os.path.join(ROOT, *a)
SOURCES = [os.path.join(TB, "classic", "quests_en.json"), _p("out", "questv2_ids.json"), _p("forever-data", "en", "quests.json"),
           _p("forever-data", "en", "npcs.json"), _p("forever-data", "en", "objects.json"), _p("data", "harvest.json"),
           _p("out", "cache", "quests.tsv"), _p("out", "cache", "creatures.tsv"), _p("out", "cache", "gameobjects.tsv"),
           _p("out", "db2", "Creature.tsv"), _p("out", "db2", "GameObjects.tsv")] + \
          [_p("out", "db2", t + ".tsv") for t in PLACE_TABLES] + \
          [os.path.join(r"C:\Projects\WoW\Questie", "Database", "Classic", f) for f in ("classicNpcDB.lua", "classicObjectDB.lua")] + \
          [os.path.abspath(__file__)]                     # a rule change here rebuilds the cache too


def _json(p):
    return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}


def _col(p, col):
    out = set()
    if os.path.exists(p):
        for line in open(p, encoding="utf-8").read().splitlines()[1:]:
            r = line.split("\t")
            if len(r) > col and r[col]: out.add(r[col].strip())
    return out


def _build():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from questie_names import load, _table, Q
    harvest = _json(_p("data", "harvest.json")).get("enUS", {})
    hv = lambda kind: set(harvest.get(kind) or {})
    quests = set(_json(os.path.join(TB, "classic", "quests_en.json")))
    quests |= {str(i) for i in _json(_p("out", "questv2_ids.json"))}
    quests |= set(_json(_p("forever-data", "en", "quests.json"))) | _col(_p("out", "cache", "quests.tsv"), 0) | hv("quests")
    names = {v["en"] for v in load().values()}
    obj = _table(os.path.join(Q, "Database", "Classic", "classicObjectDB.lua"), "objectData = [[return {")
    names |= {row[1] for row in obj.values() if row[1]}
    for f in ("npcs", "objects"):
        names |= {v["name"] for v in _json(_p("forever-data", "en", f + ".json")).values() if isinstance(v, dict) and v.get("name")}
    names |= _col(_p("out", "cache", "creatures.tsv"), 1) | _col(_p("out", "cache", "gameobjects.tsv"), 1)
    names |= _col(_p("out", "db2", "Creature.tsv"), 3) | _col(_p("out", "db2", "GameObjects.tsv"), 3)
    names |= hv("names") | hv("objects")
    zones = set()
    for t in PLACE_TABLES: zones |= _col(_p("out", "db2", t + ".tsv"), 3)
    # flight nodes are "<place>, <zone>": the build composes untranslated ones from the zone corpus ("Elwynn")
    zones |= {x.strip() for n in _col(_p("out", "db2", "TaxiNodes.tsv"), 3) for x in n.split(",")}
    zones |= hv("zones") | hv("objects")
    return {"quests": quests, "names": names, "zones": zones}


_SCOPE = None


def scope():
    global _SCOPE
    if _SCOPE is not None: return _SCOPE
    stamp = max((os.path.getmtime(p) for p in SOURCES if os.path.exists(p)), default=0)
    c = _json(CACHE)
    if c.get("stamp") != stamp:
        _SCOPE = _build()
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        json.dump({"stamp": stamp, **{k: sorted(v) for k, v in _SCOPE.items()}}, open(CACHE, "w", encoding="utf-8"),
                  ensure_ascii=False)
    else:
        _SCOPE = {k: set(c[k]) for k in ("quests", "names", "zones")}
    return _SCOPE


def in_scope(domain, key):
    """tb_quests "<id>.<field>" / tb_names EN / tb_zones EN → shown by Forever? (other domains: always)"""
    s = scope()
    if domain == "tb_quests": return str(key).split(".")[0] in s["quests"]
    if domain == "tb_names": return key in s["names"]
    if domain == "tb_zones": return key.strip() in s["zones"]
    if domain == "books":                              # pages of Turtle-only items / objects (tools/expansion.py)
        from expansion import classify
        return classify("books", key) != "turtle"
    return True


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    s = scope()
    print({k: len(v) for k, v in s.items()})
    for dom in ("tb_quests", "tb_names", "tb_zones"):
        d = _json(_p("data", "be", dom + ".json"))
        k = sum(1 for x in d if in_scope(dom, x))
        print("%s: %d entries, in scope %d, would park %d" % (dom, len(d), k, len(d) - k))
