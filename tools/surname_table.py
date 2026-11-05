"""All compound family surnames: EN · race · RU (Questie) · current BE forms · suggested BE.

    python tools/surname_table.py     -> out/surname_table.json (for the review page) + out/surname_table.tsv

Suggested form: owner decision (data/surname_fixes.tsv, "ok" rows or your edits) > my proposal there >
the only / most-used current form (ties marked)."""
import csv, json, os, re, sys, collections

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from questie_names import load as questie  # noqa: E402
from surname_families import load_names  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TB = r"C:\Projects\WoW\turtle-bel"
RACE = {12: "human", 11: "human", 123: "human", 1078: "human", 84: "human",
        55: "dwarf", 57: "dwarf", 1216: "dwarf", 875: "gnome", 64: "gnome",
        80: "night elf", 79: "night elf", 124: "night elf",
        104: "tauren", 105: "tauren",
        29: "orc", 85: "orc", 65: "orc", 125: "orc", 1215: "orc",
        126: "troll", 877: "troll",
        68: "undead", 71: "undead", 83: "undead",
        120: "goblin", 121: "goblin", 474: "goblin", 69: "goblin", 637: "goblin", 1735: "goblin"}
BATCH_RACE = {"night elf": "night elf", "tauren": "tauren", "orc/troll": "orc", "dwarf/gnome": "dwarf"}


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    csv.field_size_limit(10 ** 9)
    names = load_names()
    q = questie()
    by_en = {}
    for v in q.values():
        by_en.setdefault(v["en"], v)
    batch = {}
    for r in csv.reader(open(os.path.join(TB, "data", "surname_batch.tsv"), encoding="utf-8"), delimiter="\t"):
        if len(r) >= 5 and r[0] != "EN": batch[r[0]] = (r[2], r[4])
    fixes = {}
    fp = os.path.join(ROOT, "data", "surname_fixes.tsv")
    for r in list(csv.reader(open(fp, encoding="utf-8"), delimiter="\t"))[1:]:
        if len(r) >= 3: fixes[r[0]] = (r[1], r[2], r[3] if len(r) > 3 else "")

    vocab = set()
    for p in (os.path.join(TB, "data", "classic", "quests_en.json"), os.path.join(ROOT, "data", "strings_en.json")):
        for v in json.load(open(p, encoding="utf-8")).values():
            for t in (v.values() if isinstance(v, dict) else []):
                if isinstance(t, str): vocab.update(re.findall(r"\b[a-z]{3,}\b", t))

    def compound(s):
        s = s.lower().replace("'", "")
        return any(s[:i] in vocab and (s[i:] in vocab or s[i:].rstrip("s") in vocab) for i in range(3, len(s) - 2))

    # only names Forever can show: Classic NPCs (Questie) + Forever's own new names (turtle-bel also has Turtle-only NPCs)
    forever_names = set()
    sp = os.path.join(ROOT, "data", "strings_be.json")
    if os.path.exists(sp):
        forever_names = {k[5:] for k in json.load(open(sp, encoding="utf-8")) if k.startswith("name:")}
    names = {en: be for en, be in names.items() if en in by_en or en in forever_names}
    first_count = collections.Counter(en.split()[0] for en in names if len(en.split()) == 2)
    fam = collections.defaultdict(lambda: {"forms": collections.defaultdict(list), "ru": collections.Counter(),
                                           "race": collections.Counter()})
    for en, be in names.items():
        w, b = en.split(), be.split()
        if len(w) != 2 or len(b) < 2: continue
        given, sur = w
        if len(sur) < 6 or not re.match(r"^[A-Z][a-z']+$", sur) or first_count[given] >= 3: continue
        if sur.lower() in vocab or not compound(sur): continue
        if given.lower() in vocab or compound(given): continue      # "Iceblood Warmaster": a place + a role
        if sur in ("Copyright",): continue
        form = " ".join(b[1:])
        if not form[:1].isupper(): continue
        f = fam[sur]
        f["forms"][form].append(given)
        qv = by_en.get(en)
        ru = (qv or {}).get("ru") or (batch.get(en, ("", ""))[0])
        if ru and len(ru.split()) >= 2: f["ru"][" ".join(ru.split()[1:])] += 1
        race = RACE.get((qv or {}).get("faction")) or BATCH_RACE.get(batch.get(en, ("", ""))[1])
        if race: f["race"][race] += 1
    rows = []
    for sur, f in fam.items():
        forms = sorted(f["forms"].items(), key=lambda kv: -len(kv[1]))
        n = sum(len(g) for _, g in forms)
        top = forms[0][0]
        tie = len(forms) > 1 and len(forms[1][1]) == len(forms[0][1])
        if sur in fixes:
            sug, status, why = fixes[sur]
            basis = "you" if status == "ok" else "proposal"
        elif f["ru"] and next(iter(f["ru"]))[:1].islower():                 # RU lowercase = a role, not a family
            sug = " ".join(w[:1].lower() + w[1:] if w[:1].isupper() else w for w in top.split())
            basis, why = "role", "the Russian writes it lowercase: a role, lowercase inside the name"
        else:
            sug, why = top, ""
            basis = "only form" if len(forms) == 1 else ("tie" if tie else "most used")
        rows.append({"family": sur, "race": (f["race"].most_common(1)[0][0] if f["race"] else "?"),
                     "members": n, "ru": " / ".join(k for k, _ in f["ru"].most_common(2)),
                     "forms": [{"be": be, "who": g} for be, g in forms], "suggested": sug, "basis": basis,
                     "why": why, "inconsistent": len(forms) > 1,
                     "changes": any(be != sug.split(" / ")[0] and be != sug.split(" / ")[-1] for be, _ in forms)})
    rows.sort(key=lambda r: (not (r["inconsistent"] or r["changes"]), r["race"] == "?", r["race"], -r["members"], r["family"]))
    json.dump(rows, open(os.path.join(ROOT, "out", "surname_table.json"), "w", encoding="utf-8"), ensure_ascii=False)
    with open(os.path.join(ROOT, "out", "surname_table.tsv"), "w", encoding="utf-8", newline="\n") as f:
        f.write("family\trace\tmembers\tru\tsuggested\tbasis\tcurrent forms\n")
        for r in rows:
            f.write("%s\t%s\t%d\t%s\t%s\t%s\t%s\n" % (r["family"], r["race"], r["members"], r["ru"], r["suggested"], r["basis"],
                    " | ".join("%s (%s)" % (x["be"], ", ".join(x["who"][:3])) for x in r["forms"])))
    c = collections.Counter(r["race"] for r in rows)
    print("families:", len(rows), "| inconsistent:", sum(r["inconsistent"] for r in rows), "| would change:",
          sum(r["changes"] for r in rows), "| with RU:", sum(1 for r in rows if r["ru"]))
    print(dict(c))


if __name__ == "__main__":
    main()
