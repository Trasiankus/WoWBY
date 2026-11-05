"""Compound family names (Stormrage, Bloodhoof, Shadowsong…) that got DIFFERENT Belarusian forms.

    python tools/surname_families.py          -> out/surname_families.tsv (+ prints the list)

Sources: turtle-bel names_be.json (WoWBY names), Forever names (data/strings_be.json), and turtle-bel
data/surname_batch.tsv for the Russian client's form. A "family" = the last English word of a person name
("Given Surname") whose Belarusian rendering is capitalized (a name, not a common noun like «татэм").
Units named after a clan ("Moonrage Sentry") are counted but not compared (their BE is a genitive phrase)."""
import csv, json, os, re, sys, collections

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TB = r"C:\Projects\WoW\turtle-bel"


def load_names():
    names = dict(json.load(open(os.path.join(TB, "data", "names_be.json"), encoding="utf-8")))
    sp = os.path.join(ROOT, "data", "strings_be.json")
    if os.path.exists(sp):
        for k, v in json.load(open(sp, encoding="utf-8")).items():
            if k.startswith("name:") and v.get("v"): names[k[5:]] = v["v"]
    return names


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    csv.field_size_limit(10 ** 9)
    names = load_names()
    ru = {}
    for r in csv.reader(open(os.path.join(TB, "data", "surname_batch.tsv"), encoding="utf-8"), delimiter="\t"):
        if len(r) >= 3 and r[0] != "EN": ru[r[0]] = r[2]
    first_count = collections.Counter(en.split()[0] for en in names if len(en.split()) == 2)
    fam = collections.defaultdict(lambda: collections.defaultdict(list))   # surname -> BE form -> [given names]
    ru_forms = collections.defaultdict(set)
    units = collections.Counter()
    for en, be in names.items():
        w, b = en.split(), be.split()
        if len(w) != 2 or len(b) < 2: continue
        given, sur = w
        if len(sur) < 6 or not re.match(r"^[A-Z][a-z']+$", sur): continue
        if first_count[given] >= 3: continue                       # "Young X", "Elder X": descriptors
        form = " ".join(b[1:])
        if not form[:1].isupper(): continue                        # common noun, not a surname
        fam[sur][form].append(given)
        if en in ru: ru_forms[sur].add(" ".join(ru[en].split()[1:]))
    for en in names:                                               # "Moonrage Sentry": clan units
        w = en.split()
        if len(w) >= 2 and w[0] in fam: units[w[0]] += 1
    # English vocabulary from quest texts: a surname that is itself a common word ("sentinel", "spirit") is a role,
    # not a family; a compound surname splits into two such words (storm+rage, blood+hoof)
    vocab = set()
    for p in (os.path.join(TB, "data", "classic", "quests_en.json"), os.path.join(ROOT, "data", "strings_en.json")):
        for v in json.load(open(p, encoding="utf-8")).values():
            for t in (v.values() if isinstance(v, dict) else []):
                if isinstance(t, str): vocab.update(re.findall(r"\b[a-z]{3,}\b", t))

    def compound(s):
        s = s.lower().replace("'", "")
        return any(s[:i] in vocab and (s[i:] in vocab or s[i:].rstrip("s") in vocab) for i in range(3, len(s) - 2))

    def stem(form):                                   # masc/fem/neuter variants of one form count as the same
        out = []
        for w in form.lower().split():
            w = re.sub(r"(ніца|ніц)$", "нік", w)
            w = re.sub(r"(чыха)$", "ч", w)
            out.append(re.sub(r"[аеёіоуыэюяйўь]+$", "", w))
        return " ".join(out)
    rows = []
    for sur, forms in fam.items():
        if sur.lower() in vocab or not compound(sur): continue
        distinct = {stem(f) for f in forms}
        if len(distinct) < 2: continue
        n = sum(len(g) for g in forms.values())
        rows.append((sur, n, units[sur], forms, sorted(ru_forms[sur])))
    rows.sort(key=lambda r: (-r[1] - r[2], r[0]))
    out = os.path.join(ROOT, "out", "surname_families.tsv")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("family\tmembers\tunits\tforms (members)\tru\n")
        for sur, n, u, forms, rus in rows:
            fs = " | ".join("%s (%s)" % (form, ", ".join(g[:4])) for form, g in sorted(forms.items(), key=lambda x: -len(x[1])))
            f.write("%s\t%d\t%d\t%s\t%s\n" % (sur, n, u, fs, " / ".join(rus)))
            print("%-14s %2d+%-2d %s%s" % (sur, n, u, fs, ("   RU: " + " / ".join(rus)) if rus else ""))
    print("\n%d families with more than one form -> %s" % (len(rows), out))


if __name__ == "__main__":
    main()
