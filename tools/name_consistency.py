"""Quest text vs entity names (R33, owner 2026-09-29): a quest whose English text names an item / NPC should use
that item's / NPC's own Belarusian name ("Shimmering Frond" item = «Мерхатлівы парастак», quest said «мігатлівае
лісце»). Reports mismatches only — nothing is changed.

    python tools/name_consistency.py            -> out/name_consistency.json + counts

Match: the EN name occurs in the quest's EN field (word boundary, optional plural s/es); the BE field "uses" the BE
name when every content word of it is present by stem (first 4-5 letters, so case endings don't matter).
Fields checked: t (title) and o (objectives) — they name things plainly; descriptions paraphrase too much."""
import json, os, re, sys, collections

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TB = r"C:\Projects\WoW\turtle-bel"
BE = os.path.join(ROOT, "data", "be")
FIELDS = ("t", "o")
STOP = {"і", "з", "у", "ў", "на", "да", "ад", "для", "па", "пад", "над", "аб", "ці", "не", "са", "за"}


def load(p):
    return json.load(open(p, encoding="utf-8"))


def tsv(p):
    return [l.split("\t") for l in open(p, encoding="utf-8").read().splitlines()[1:]] if os.path.exists(p) else []


def fold(s):
    # Belarusian vowel alternation under stress (бягун / бегуна, вада / воды) and ў/у — not a different word
    return s.lower().translate(str.maketrans("яёоўы", "ееаyі".replace("y", "у")))


def stems(be):
    out = []
    for w in re.findall(r"[А-ЯЁІЎа-яёіў'’]+", fold(be)):
        if w in STOP or len(w) < 3:
            continue
        out.append(w[:5] if len(w) > 6 else w[:4] if len(w) > 4 else w[:3])
    return out


def uses(be_text, be_name):
    low = fold(be_text)
    st = stems(be_name)
    return bool(st) and all(s in low for s in st)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    # entities EN -> BE (item names from the shipped corpus + fixes; NPC names from turtle-bel + Forever + fixes)
    it_en = {r[0]: r[1] for r in tsv(os.path.join(TB, "items", "todo.tsv")) if len(r) > 1}
    ents = {}
    for iid, e in load(os.path.join(BE, "items.json")).items():
        if it_en.get(iid) and e.get("be"):
            ents.setdefault(it_en[iid], ("item", e["be"]))
    an = os.path.join(ROOT, "data", "auto_names.json")
    for en, be in (load(an).get("items", {}) if os.path.exists(an) else {}).items():
        ents.setdefault(en, ("item", be))
    for r in tsv(os.path.join(ROOT, "data", "itemnames_fix.tsv")):
        if len(r) > 1: ents[r[0]] = ("item", r[1])
    for en, e in load(os.path.join(BE, "tb_names.json")).items():
        ents.setdefault(en, ("npc", e["be"]))
    for k, e in load(os.path.join(BE, "forever.json")).items():
        if k.startswith("name:"): ents.setdefault(k[5:], ("npc", e["be"]))
    for r in tsv(os.path.join(ROOT, "data", "names_fix.tsv")):
        if len(r) > 1: ents[r[0]] = ("npc", r[1])
    # only specific names: 2+ words or one long word (skip "Wolf", "Iron", "Letter")
    ents = {en: v for en, v in ents.items() if (" " in en or len(en) >= 8) and re.search(r"[A-Za-z]", en) and v[1]}
    by_first = collections.defaultdict(list)
    for en in ents:
        by_first[en.split()[0].lower()].append(en)

    # quests: turtle-bel (qid.f) + Forever (quest:qid.f), EN beside
    q_en = load(os.path.join(TB, "data", "classic", "quests_en.json"))
    s_en = load(os.path.join(ROOT, "data", "strings_en.json"))
    quests = []                                    # (qid, field, en, be, domain)
    for k, e in load(os.path.join(BE, "tb_quests.json")).items():
        qid, _, f = k.partition(".")
        if f in FIELDS and q_en.get(qid, {}).get(f):
            quests.append((qid, f, q_en[qid][f], e["be"], "tb_quests"))
    for k, e in load(os.path.join(BE, "forever.json")).items():
        if k.startswith("quest:"):
            key, _, f = k.rpartition(".")
            en = (s_en.get(key) or {}).get(f)
            if f in FIELDS and en:
                quests.append((key[6:], f, en, e["be"], "forever"))

    found = collections.defaultdict(lambda: {"kind": "", "be": "", "ok": [], "bad": []})
    for qid, f, en, be, dom in quests:
        words = set(w.lower() for w in re.findall(r"[A-Za-z'’]+", en))
        for w in words:
            for name in by_first.get(w, ()):
                if not re.search(r"(?<![A-Za-z])" + re.escape(name) + r"(?:e?s)?(?![A-Za-z])", en, re.I):
                    continue
                kind, nbe = ents[name]
                d = found[name]; d["kind"], d["be"] = kind, nbe
                (d["ok"] if uses(be, nbe) else d["bad"]).append({"q": qid, "f": f, "dom": dom, "be": be[:300], "en": en[:300]})
    out = {n: d for n, d in found.items() if d["bad"]}
    json.dump(out, open(os.path.join(ROOT, "out", "name_consistency.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    c = collections.Counter(d["kind"] for d in out.values())
    print("entities with mismatches: %d (%s); mismatched quest fields: %d" % (
        len(out), dict(c), sum(len(d["bad"]) for d in out.values())))
    print("-> out/name_consistency.json")


if __name__ == "__main__":
    main()
