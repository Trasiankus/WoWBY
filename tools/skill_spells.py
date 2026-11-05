"""Spells players learn, by skill category (R132, 2026-09-30) — the spell names worth a re-translation.

    python tools/skill_spells.py      -> out/skill_spells.json  {SkillLine CategoryID: [spell ids]}

Reads the beta's SkillLineAbility.db2 (skill line -> spell) and SkillLine.db2 (CategoryID: 7 class, 6 weapon,
9 secondary: cooking / first aid / fishing, 11 professions, …). prepare_translate queues the shipped names of
categories 6/7/9 as "spellnames_redo"."""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from item_context import table  # noqa: E402
from wow_casc import Casc, build_key_for, load_listfile  # noqa: E402
import forever_client                    # newest Forever build installed (R687)

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    beta = Casc(build_key_for(forever_client.product()))
    lf = {v.split("/")[-1][:-4]: k for k, v in load_listfile(r"^dbfilesclient/(skilllineability|skillline)\.db2$").items()}
    sla = table(beta, lf, "SkillLineAbility", {"SkillLine", "Spell"})
    sl = table(beta, lf, "SkillLine", {"CategoryID"})
    out = {}
    for r in sla.values():
        c = (sl.get(r["SkillLine"]) or {}).get("CategoryID")
        out.setdefault(str(c), set()).add(r["Spell"])
    json.dump({c: sorted(s) for c, s in out.items()}, open(os.path.join(ROOT, "out", "skill_spells.json"), "w"))
    print(" ".join("%s:%d" % (c, len(s)) for c, s in sorted(out.items())), "-> out/skill_spells.json")


if __name__ == "__main__":
    main()
