"""Read what WoWBY collected in-game (untranslated quests / names / zones / gossip / objective lines).

    python tools/import_harvest.py            # -> data/harvest.json + counts
    (then python tools/extract_forever.py merges it into the translation queue)

Source: the beta client's SavedVariables, written on /reload or logout:
  C:\\Games\\World of Warcraft\\_classic_beta_\\WTF\\Account\\<ACCOUNT>\\SavedVariables\\WoWBY.lua
WoWBY_DB.harvest[<locale>] = { quests = {[id] = {t,d,o,p,c}}, names = {[EN] = true}, zones = {...},
                               gossip = {[text] = npc}, objectives = {[text] = questID} }
A quest can also hold "<field>#<hash>" = a live text that differs from our source (R510); merged like any field, each
hash its own key, so a variant never overwrites the normal entry.
Play with the enUS client for source text; a ruRU session adds Russian references."""
import glob, json, os, sys
import lupa

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
# every Forever install: the beta and (2026-10-21) the stress-test client `_forever_` (product wowf)
SV_GLOBS = [r"C:\Games\World of Warcraft\_classic_beta_\WTF\Account\*\SavedVariables\WoWBY.lua",
            r"C:\Games\World of Warcraft\_forever_\WTF\Account\*\SavedVariables\WoWBY.lua"]


def to_py(v):
    if lupa.lua_type(v) == "table":
        return {(int(k) if isinstance(k, float) and k.is_integer() else k): to_py(x) for k, x in v.items()}
    return v


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    files = [f for g in SV_GLOBS for f in glob.glob(g)]
    if not files:
        print("No WoWBY SavedVariables yet. Play the beta with WoWBY on, then /reload or log out."); return
    merged = {}
    for f in files:
        L = lupa.LuaRuntime(unpack_returned_tuples=True)
        L.execute(open(f, encoding="utf-8").read())
        db = L.globals().WoWBY_DB
        h = to_py(db["harvest"]) if db and db["harvest"] else {}
        for loc, kinds in h.items():
            m = merged.setdefault(loc, {})
            for kind, items in kinds.items():
                d = m.setdefault(kind, {})
                for k, v in items.items():
                    if kind == "quests":
                        d.setdefault(str(k), {}).update(v)
                    else:
                        d[str(k)] = v
    merge(merged)


def merge(merged):
    """Accumulate {locale: {kind: {key: value}}} into data/harvest.json (also used by tools/import_paste.py, R965)."""
    out = os.path.join(ROOT, "data", "harvest.json")
    old = json.load(open(out, encoding="utf-8")) if os.path.exists(out) else {}
    for loc, kinds in merged.items():                     # accumulate across sessions / resets
        for kind, items in kinds.items():
            d = old.setdefault(loc, {}).setdefault(kind, {})
            for k, v in items.items():
                if kind == "quests" and isinstance(d.get(k), dict):
                    d[k].update(v)
                else:
                    d[k] = v
    json.dump(old, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
    for loc, kinds in sorted(old.items()):
        print("%s: " % loc + ", ".join("%s %d" % (k, len(v)) for k, v in sorted(kinds.items())))
    print("-> %s. Next: python tools/extract_forever.py" % out)


if __name__ == "__main__":
    main()
