"""Review page data (R33) -> out/review/names/data.json.
Only the names Claude marked H (hard) in data/name_unify.tsv go to the owner; each row carries Claude's note
(what the conflict is) plus the quest lines. The rest was decided in data/name_unify.tsv (tools/name_unify.py)."""
import hashlib, json, os, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    d = json.load(open(os.path.join(ROOT, "out", "name_consistency.json"), encoding="utf-8"))
    hard = {}
    for l in open(os.path.join(ROOT, "data", "name_unify.tsv"), encoding="utf-8").read().splitlines()[1:]:
        r = l.split("\t")
        if len(r) >= 2 and r[1] == "H":
            hard[r[0]] = r[3] if len(r) > 3 else ""
    rows = []
    for en, note in hard.items():
        e = d.get(en, {"kind": "", "be": "", "ok": [], "bad": []})
        rows.append({"id": hashlib.md5(en.encode("utf-8")).hexdigest()[:10], "en": en, "kind": e["kind"] or "item",
                     "be": e["be"], "note": note, "ok": len(e["ok"]),
                     "bad": [{"q": b["q"], "f": b["f"], "be": b["be"], "en": b["en"]} for b in e["bad"]]})
    rows.sort(key=lambda r: (r["kind"] != "item", r["en"]))
    od = os.path.join(ROOT, "out", "review", "names")
    os.makedirs(od, exist_ok=True)
    json.dump(rows, open(os.path.join(od, "data.json"), "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    print(len(rows), "hard names ->", os.path.join(od, "data.json"))


if __name__ == "__main__":
    main()
