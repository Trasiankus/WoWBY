"""Item context for the translation queue: what kind of thing each Forever item is.

    python tools/item_context.py      -> out/item_context.json  {item_id: "Armor · Cloth · Chest · Uncommon"}

Reads the beta's Item.db2 (class, subclass, inventory type), ItemSparse.db2 (quality) and ItemSubClass.db2
(subclass names). Flavor text (ItemSparse Description_lang) is added by prepare_translate from out/db2."""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wow_casc import Casc, build_key_for, load_listfile  # noqa: E402
import forever_client                    # newest Forever build installed (R687)
from db2 import DB2, load_dbd  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
CLASS = {0: "Consumable", 1: "Container", 2: "Weapon", 3: "Gem", 4: "Armor", 5: "Reagent", 6: "Projectile",
         7: "Trade goods", 8: "Item enhancement", 9: "Recipe", 11: "Quiver", 12: "Quest item", 13: "Key",
         15: "Miscellaneous", 16: "Glyph", 17: "Battle pet", 18: "WoW token", 19: "Profession"}
INV = {1: "Head", 2: "Neck", 3: "Shoulder", 4: "Shirt", 5: "Chest", 6: "Waist", 7: "Legs", 8: "Feet", 9: "Wrist",
       10: "Hands", 11: "Finger", 12: "Trinket", 13: "One-hand", 14: "Shield", 15: "Ranged (bow)", 16: "Back",
       17: "Two-hand", 18: "Bag", 19: "Tabard", 20: "Robe", 21: "Main hand", 22: "Off hand", 23: "Held in off-hand",
       24: "Ammo", 25: "Thrown", 26: "Ranged (gun/wand)", 28: "Relic"}
QUALITY = {0: "Poor", 1: "Common", 2: "Uncommon", 3: "Rare", 4: "Epic", 5: "Legendary", 6: "Artifact", 7: "Heirloom"}


def table(casc, lf, name, want):
    dbd, real = load_dbd(name)
    return DB2(casc.read_fdid(lf[name.lower()], "enUS"), real).ints(dbd, want)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    beta = Casc(build_key_for(forever_client.product()))
    lf = {v.split("/")[-1][:-4]: k for k, v in load_listfile(r"^dbfilesclient/(item|itemsparse|itemsubclass)\.db2$").items()}
    item = table(beta, lf, "Item", {"ClassID", "SubclassID", "InventoryType"})
    sparse = table(beta, lf, "ItemSparse", {"OverallQualityID", "InventoryType"})
    dbd, real = load_dbd("ItemSubClass")
    sc_db = DB2(beta.read_fdid(lf["itemsubclass"], "enUS"), real)
    sc_ids = sc_db.ints(dbd, {"ClassID", "SubClassID"})
    sc_name = {}
    for rid, field, _i, txt in sc_db.strings(dbd):
        if field == "DisplayName_lang" and rid in sc_ids:
            sc_name[(sc_ids[rid]["ClassID"], sc_ids[rid]["SubClassID"])] = txt
    out = {}
    for iid, r in item.items():
        c, sc = r.get("ClassID"), r.get("SubclassID")
        inv = r.get("InventoryType") or (sparse.get(iid) or {}).get("InventoryType")
        parts = [CLASS.get(c, "class %s" % c)]
        sub = sc_name.get((c, sc))
        if sub and sub.lower() != parts[0].lower() and "obsolete" not in sub.lower(): parts.append(sub)
        if inv in INV and c in (2, 4, 1): parts.append(INV[inv])
        q = (sparse.get(iid) or {}).get("OverallQualityID")
        if q in QUALITY: parts.append(QUALITY[q])
        out[iid] = " · ".join(parts)
    os.makedirs(os.path.join(ROOT, "out"), exist_ok=True)
    json.dump(out, open(os.path.join(ROOT, "out", "item_context.json"), "w", encoding="utf-8"), ensure_ascii=False)
    print("items: %d (Item.db2 %d, ItemSparse %d, subclasses %d)" % (len(out), len(item), len(sparse), len(sc_name)))


if __name__ == "__main__":
    main()
