"""Apply the R33 name decisions (data/name_unify.tsv, owner 2026-09-29: "decide most yourself, give me only the hard ones").

    python tools/name_unify.py

data/name_unify.tsv: en, decision, be, note —
  R  = the item / NPC is renamed to `be` (items -> data/itemnames_fix.tsv, NPCs -> data/names_fix.tsv)
  F  = fine as is (quest paraphrases, different thing)            H = hard: owner decides (review page)
  every other mismatched name from out/name_consistency.json = its own name wins (E).
For E and R, each quest title / objective that still words the thing differently goes to the translate re-pass
package "quests_unify" (out/name_unify_repass.json -> prepare_translate): the agent rewrites the field with the
final name, declined to fit, changing nothing else; import writes it into data/be/ like quests_address."""
import json, os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from name_consistency import fold, STOP  # noqa: E402

W = re.compile(r"[А-ЯЁІЎа-яёіў'’-]+")


def tsv(p):
    return [l.split("\t") for l in open(p, encoding="utf-8").read().splitlines()[1:]] if os.path.exists(p) else []


def uses(text, name):
    st = [w[:4] for w in W.findall(fold(name)) if w not in STOP and len(w) >= 3]
    low = fold(text)
    return bool(st) and all(s in low for s in st)


def append_fix(path, rows, note):
    have = {r[0] for r in tsv(path)}
    new = [(en, be) for en, be in rows if en not in have]
    if new:
        with open(path, "a", encoding="utf-8", newline="\n") as f:
            for en, be in new:
                f.write("%s\t%s\t%s\n" % (en, be, note))
    return len(new)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    dec = {}
    for r in tsv(os.path.join(ROOT, "data", "name_unify.tsv")):
        if len(r) >= 2:
            dec[r[0]] = (r[1], r[2] if len(r) > 2 else "")
    nc = json.load(open(os.path.join(ROOT, "out", "name_consistency.json"), encoding="utf-8"))
    items = [(en, be) for en, (d, be) in dec.items() if d == "R" and nc.get(en, {}).get("kind") == "item" and be]
    npcs = [(en, be) for en, (d, be) in dec.items() if d == "R" and nc.get(en, {}).get("kind") == "npc" and be]
    ni = append_fix(os.path.join(ROOT, "data", "itemnames_fix.tsv"), items, "R33 name check (unified with quests)")
    nn = append_fix(os.path.join(ROOT, "data", "names_fix.tsv"), npcs, "R33 name check (unified with quests)")

    fields = {}                                   # (domain, qid) -> {"keys": {f: key}, "fix": set()}
    for en, e in nc.items():
        d, be = dec.get(en, ("E", ""))
        if d in ("F", "H"):
            continue
        final = be if d == "R" and be else e["be"]
        for b in e["bad"]:
            if uses(b["be"], final):
                continue
            dom = "tb_quests" if b.get("dom", "tb_quests") == "tb_quests" else "forever"
            key = ("%s.%s" % (b["q"], b["f"])) if dom == "tb_quests" else ("quest:%s.%s" % (b["q"], b["f"]))
            g = fields.setdefault((dom, b["q"]), {"keys": {}, "fix": set()})
            g["keys"][b["f"]] = key
            g["fix"].add("%s \"%s\" = «%s» — use this name (decline it to fit the sentence)" % (e["kind"], en, final))
    out = [{"domain": dom, "qid": qid, "keys": g["keys"], "fix": sorted(g["fix"])} for (dom, qid), g in sorted(fields.items())]
    json.dump(out, open(os.path.join(ROOT, "out", "name_unify_repass.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("renamed: %d items, %d NPCs (new fix rows); quest re-pass: %d quests, %d fields -> out/name_unify_repass.json"
          % (ni, nn, len(out), sum(len(g["keys"]) for g in out)))


if __name__ == "__main__":
    main()
