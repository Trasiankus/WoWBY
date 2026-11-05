"""EN + RU NPC names (and faction template) from the local Questie clone — reference data for name reviews.

    from questie_names import load;  npcs = load()   # {npc_id: {"en", "ru", "faction"}}"""
import os, re
import lupa

Q = r"C:\Projects\WoW\Questie"


def _table(path, start):
    src = open(path, encoding="utf-8").read()
    a = src.index(start) + len(start) - len("return {")
    b = src.index("}]]", a) + 1
    return lupa.LuaRuntime(unpack_returned_tuples=True).execute(src[a:b])


def load(flavor="Classic"):
    db = _table(os.path.join(Q, "Database", flavor, flavor.lower() + "NpcDB.lua"), "npcData = [[return {")
    ru = _table(os.path.join(Q, "Localization", "lookups", flavor, "lookupNpcs", "ruRU.lua"), "loadstring([[return {")
    out = {}
    for nid, row in db.items():
        en = row[1]
        if not en: continue
        r = ru[nid]
        out[int(nid)] = {"en": en, "ru": (r[1] if r else "") or "", "faction": row[12] or 0,
                         "quests": bool(row[10] or row[11]),            # starts or ends a quest
                         "spawned": bool(row[7])}                        # placed in the world (QA scope)
    return out


if __name__ == "__main__":
    import sys, collections
    sys.stdout.reconfigure(encoding="utf-8")
    n = load()
    print(len(n), "npcs;", sum(1 for v in n.values() if v["ru"]), "with RU")
    c = collections.Counter(v["faction"] for v in n.values() if len(v["en"].split()) == 2)
    for f, k in c.most_common(40):
        ex = [v["en"] for v in n.values() if v["faction"] == f and len(v["en"].split()) == 2][:4]
        print(f, k, ex)
