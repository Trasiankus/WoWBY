"""Race + sex of Forever NPCs from their model (2026-10-01): forever_scraper --npc-details gives each humanoid NPC's
displayId; the client's CreatureDisplayInfo -> CreatureDisplayInfoExtra (DisplayRaceID, DisplaySexID) gives race/sex.
Faction is NOT enough (Nez'raz: faction Orgrimmar, model goblin).

    python tools/npc_race.py      -> out/npc_race.json  {EN name: {"race": "Orc", "sex": "m"|"f"|"mf" (both), "faction": …, "ids": […]}}

Use: surname families (race decides the Belarusian surname form), feminine names / titles, speaker gender."""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from item_context import table  # noqa: E402
from wow_casc import Casc, build_key_for, load_listfile  # noqa: E402
import forever_client                    # newest Forever build installed (R687)
from db2 import DB2, load_dbd  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    en = os.path.join(ROOT, "forever-data", "en")
    names = json.load(open(os.path.join(en, "npcs.json"), encoding="utf-8"))
    det = json.load(open(os.path.join(en, "npc_details.json"), encoding="utf-8"))
    beta = Casc(build_key_for(forever_client.product()))
    lf = {v.split("/")[-1][:-4]: k for k, v in
          load_listfile(r"^dbfilesclient/(creaturedisplayinfo|creaturedisplayinfoextra|chrraces)\.db2$").items()}
    cdi = table(beta, lf, "CreatureDisplayInfo", {"ExtendedDisplayInfoID", "Gender"})
    ext = table(beta, lf, "CreatureDisplayInfoExtra", {"DisplayRaceID", "DisplaySexID"})
    dbd, real = load_dbd("ChrRaces")
    race_name = {}
    for rid, field, _i, txt in DB2(beta.read_fdid(lf["chrraces"], "enUS"), real).strings(dbd):
        if field == "Name_lang":
            race_name.setdefault(rid, txt)
    out, n = {}, 0
    for i, d in det.items():
        r = cdi.get(d.get("display_id")) or {}
        e = ext.get(r.get("ExtendedDisplayInfoID")) or {}
        name = (names.get(i) or {}).get("name")
        if not name or not e:
            continue
        sex = "f" if (e.get("DisplaySexID") or r.get("Gender")) == 1 else "m"
        row = out.setdefault(name, {"race": race_name.get(e.get("DisplayRaceID"), str(e.get("DisplayRaceID"))),
                                    "sex": sex, "faction": d.get("faction", ""), "ids": []})
        row["ids"].append(int(i)); n += 1
        if row["sex"] != sex: row["sex"] = "mf"          # R545: models of both sexes share the name -> masculine default
    # every classic NPC too (2026-10-13, QA names: Scrimshank had no race): the local world DB's creature_template
    # display ids (modelid1-4) through the same client tables; kept only when all its humanoid models agree
    try:
        from import_broadcast import rows, SQL
        for v in rows(os.path.join(SQL, "tw_world_creature_template.sql"), "creature_template"):
            if len(v) < 7 or not v[6] or v[6] in out: continue
            got = set()
            for did in v[1:5]:
                r = cdi.get(int(did)) if did and did != "0" else None
                e = ext.get((r or {}).get("ExtendedDisplayInfoID")) or {}
                if e:
                    got.add((race_name.get(e.get("DisplayRaceID"), str(e.get("DisplayRaceID"))),
                             "f" if (e.get("DisplaySexID") or r.get("Gender")) == 1 else "m"))
            if len({g[0] for g in got}) == 1 and got:
                if len(got) > 1: got = {(next(iter(got))[0], "mf")}
                race, sex = got.pop()
                out[v[6]] = {"race": race, "sex": sex, "faction": "", "ids": [int(v[0])]}; n += 1
    except Exception as ex:
        print("world DB skipped:", ex)
    json.dump(out, open(os.path.join(ROOT, "out", "npc_race.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("%d NPCs with a model race -> %d names -> out/npc_race.json" % (n, len(out)))


if __name__ == "__main__":
    main()
