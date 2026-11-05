"""R510: signatures of the English a quest translation was made from.

A quest field (d / p / c) can differ by the player's sex or race; our sources hold one variant. core/quests.lua
W.quest_variant shows the live English when a whole paragraph of the source is not in the live text.

Signature of one source text: per paragraph, the hashes of its 2 longest signable sentences. A paragraph counts as there
when the live text has either one (one fixed typo in a sentence must not turn a quest English); the source matches when
every paragraph is there. A field ships one such list per distinct source (wowhead, strings_en, turtle-bel): matching any
of them is enough. Encoded "h,h;h|h,h": ';' between paragraphs, '|' between sources.

Not signable: sentences with a $ token or <...>, or with a word naming the player's sex / race / class. Wowhead's progress and
completion texts come from a player's client, so $R / $g can stand there as "this troll" / "dear boy" (8413, 9120).

The split and the hash must stay identical to core/quests.lua (sent_set / sent_hash)."""
import json, os, re

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TB_EN = r"C:\Projects\WoW\turtle-bel\data\classic\quests_en.json"
SPLIT = re.compile(r"[.!?\r\n]+")
BREAK = re.compile(r"\$[Bb]")
PARA = re.compile(r"(?:\r?\n|\$[Bb])+")
PLAYER_WORD = re.compile(r"\b(?:man|woman|boy|girl|lad|lass|laddie|lassie|sir|madam|lady|lord|mister|miss|brother|sister|son|"
                         r"daughter|male|female|gentleman|hero|heroine|master|mistress|warrior|paladin|hunter|rogue|priest|"
                         r"priestess|shaman|mage|warlock|druid|human|orc|dwarf|gnome|troll|tauren|undead|forsaken|elf|"
                         r"night elf|goblin|draenei)\b", re.I)
MIN_LETTERS = 20
MOD = 2147483647
FIELDS = ("d", "p", "c")
PER_PARA = 2


def letters(s):
    return re.sub(r"[^a-z]", "", s.lower())


def sent_hash(norm):
    h = 0
    for b in norm.encode("ascii"):
        h = (h * 31 + b) % MOD
    return h


def sentences(text):
    return SPLIT.split(BREAK.sub("\n", text or ""))


def live_hashes(text):
    """Every sentence of a live text, as the runtime sees it."""
    return {sent_hash(n) for n in map(letters, sentences(text)) if len(n) >= MIN_LETTERS}


def signable(sentence):
    return not ("$" in sentence or "<" in sentence or ">" in sentence or PLAYER_WORD.search(sentence))


def source_sig(text):
    """[[hash, hash], ...]: one list per paragraph that has a signable sentence."""
    out = []
    for p in PARA.split(text or ""):
        sents = {letters(s) for s in SPLIT.split(p) if signable(s)}
        best = sorted((n for n in sents if len(n) >= MIN_LETTERS), key=lambda n: (-len(n), n))[:PER_PARA]
        if best:
            out.append([sent_hash(n) for n in best])
    return out


def field_sig(texts):
    """The distinct source signatures of one field."""
    out = []
    for t in texts:
        s = source_sig(t)
        if s and s not in out:
            out.append(s)
    return out


def encode(sig):
    return "|".join(";".join(",".join(map(str, para)) for para in src) for src in sig)


def source_there(src, hashes):
    return all(any(h in hashes for h in para) for para in src)


def is_variant(sig, live):
    """Python twin of core W.quest_variant's decision (r510_check compares them)."""
    if not sig or not letters(live or ""):
        return False
    hashes = live_hashes(live)
    return not any(source_there(src, hashes) for src in sig)


def load_sources():
    """(wowhead, strings_en, turtle-bel EN, shipped {(qid, field)}). wowhead is the nearest the live game."""
    wh = json.load(open(os.path.join(ROOT, "forever-data", "en", "quests.json"), encoding="utf-8"))
    wh = {k: dict(v) for k, v in wh.items() if v.get("status") == "ok" and not v.get("placeholder")}
    # as extract_forever (R543): player names wowhead's captures carry where the game says $N
    pn = os.path.join(ROOT, "data", "player_names.tsv")
    for line in (open(pn, encoding="utf-8") if os.path.exists(pn) else []):
        if line.startswith("#") or not line.strip():
            continue
        qid, f, name = line.rstrip("\n").split("\t")[:3]
        if wh.get(qid, {}).get(f):
            wh[qid][f] = re.sub(r"(?<![\w'’])%s(?![\w'’])" % re.escape(name), "$N", wh[qid][f])
    s = json.load(open(os.path.join(ROOT, "data", "strings_en.json"), encoding="utf-8"))
    se = {k[6:]: v for k, v in s.items() if k.startswith("quest:")}
    tb = json.load(open(TB_EN, encoding="utf-8"))
    shipped = set()
    for k in json.load(open(os.path.join(ROOT, "data", "be", "tb_quests.json"), encoding="utf-8")):
        q, _, f = k.partition(".")
        if f in FIELDS:
            shipped.add((q, f))
    for k, v in json.load(open(os.path.join(ROOT, "data", "strings_be.json"), encoding="utf-8")).items():
        if k.startswith("quest:"):
            shipped.update((k[6:], f) for f in FIELDS if v.get(f))
    return wh, se, tb, shipped


def all_signatures():
    """{quest id: {field: signature}} for every shipped field that has one."""
    wh, se, tb, shipped = load_sources()
    out = {}
    for q, f in shipped:
        sig = field_sig(d[q][f] for d in (wh, se, tb) if d.get(q, {}).get(f))
        if sig:
            out.setdefault(q, {})[f] = sig
    return out


def signatures_lua():
    sigs = all_signatures()
    lines = ["-- WoWBY quest text signatures (R510) — GENERATED by tools/build_addon.py from tools/quest_sig.py",
             "WoWBY_QSig = {}", "local S = WoWBY_QSig"]
    n = 0
    for q in sorted(sigs, key=int):
        parts = ['%s="%s"' % (f, encode(sigs[q][f])) for f in FIELDS if f in sigs[q]]
        lines.append("S[%d]={%s}" % (int(q), ",".join(parts)))
        n += len(parts)
    return "\n".join(lines) + "\n", n
