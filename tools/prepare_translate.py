"""Build/refresh the self-contained translation workspace  translate/  for an external agent
(Antigravity + Gemini). Re-runnable: chunks that already have a done/ file are never regenerated.

    python tools/prepare_translate.py

Packages (priority order): quests_gender, quests, zones, names, gossip, ui, items, spellnames, spelldesc, auras,
stylefix, ui_later, ui_unused.
Everything already translated (WoWBY vanilla, turtle-bel spells/items/UI with identical Forever EN) is
excluded; Blizzard placeholders / test junk go to translate/skipped.tsv instead of the queue."""
import csv, glob, hashlib, json, os, re, shutil, sys
from collections import Counter

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TB = r"C:\Projects\WoW\turtle-bel"
OUT = os.path.join(ROOT, "translate")

# Chunk size = characters only (owner 2026-10-17): MAX_CHARS of the whole item JSON the agent reads (EN + context:
# ru, similar, be_current, desc…), MAX_ITEMS only as a safety cap. Before: per-package item caps + 18000 EN chars;
# the caps kept missing when text got shorter (gossip 43% on 10-07, the short wowhead quotes ~50% on 10-17).
# 45000 = the payload of the tested big chunks (quests_natural / gossip_natural / gossip medians 38–47k).
MAX_CHARS = 45000
MAX_ITEMS = 600
# (EN limit 7000 until 2026-09-30: each sub-agent reads ~62 KB of rules per chunk, so bigger chunks save budget; long
# help texts are split so no chunk is >~3x the median)
ORDER = ["itemsets", "enchants", "suffixes", "quests", "objectives", "zones", "names", "titles", "chartitles", "factions", "focus", "ui_prof", "ui", "gossip", "items", "spellnames", "auras", "spelldesc", "flavor", "item_text", "db2_misc", "barber", "emotes", "achievements", "books", "quests_gender", "quests_namefix", "quests_address", "quests_unify", "quests_itemfix", "quests_speaker", "ui_termfix", "items_redo", "items_hidden", "spellnames_redo", "quests_update", "quests_classic_update", "spellnames_redo2", "spelldesc_redo", "stylefix", "quests_capfix", "names_qa", "zones_qa", "quests_natural", "gossip_natural", "ui_later", "ui_unused"]
UI_PKGS = ("ui", "ui_later", "ui_unused", "emotes", "ui_prof")        # one id space (md5 of EN): a string done in any of them is done
# UI strings never displayed (typed chat commands, debug) -> skipped; retail-only features Forever probably never
# shows (housing, shop, garrisons, covenants, …) + PTR/voice/audio-alert lines -> "ui_later" at the end.
UI_SKIP = re.compile(r"^SLASH_|DEBUG")
UI_LATER = re.compile(r"HOUSING|HOUSE_|DECOR|NEIGHBORHOOD|DELVE|PLUNDER|WOWLABS|GARRISON|ORDER_HALL|ADVENTURE_|FOLLOWER|"
                      r"COVENANT|SOULBIND|TORGHAST|ANIMA|RENOWN|AZERITE|ARTIFACT|ESSENCE|WARBAND|TIMERUNNING|REMIX|"
                      r"STORE|BOOST|CATALOG|PERKS|TRADING_POST|^PTR_|^CAA_|VOICEMACRO")
# Keys Forever's own UI code never references (tools/ui_usage.py) -> "ui_unused", the very last package.
# wowhead renders $Gmale:female; as "<male/female>" -> back to the token (the addon picks by player sex)
GPAIR = re.compile(r"<([^<>/\n]{1,40})/([^<>/\n]{1,40})>")


def gender_tokens(s):
    return GPAIR.sub(r"$G\1:\2;", s) if s else s


def tsv(path):
    csv.field_size_limit(10 ** 9)
    un = lambda s: s.replace("\\n", "\n").replace("\\r", "").replace("\\t", "\t").replace("\\\\", "\\")
    rows = list(csv.reader(open(path, encoding="utf-8"), delimiter="\t", quoting=csv.QUOTE_NONE))
    return [[un(c) for c in r] for r in rows[1:]]


def md5(s, n=8):
    return hashlib.md5(s.encode("utf-8")).hexdigest()[:n]


def ru_ok(en, ru):
    return ru if ru and ru != en and re.search(r"[А-Яа-яЁё]", ru) else ""


# R569 (owner: "more than 32 signs?"): the old single JUNK pattern was case-INsensitive, so \bOLD\b / \btest\b / \bdev\b also hit real text —
# "Old Coast Road", "Old Fire-Eye", "The Old Champ", 35 gossip lines with "old" / "test" were never queued (144+).
# Now: markers (<NYI>, [DNT]…) any case; marker WORDS only in capitals (OLD, TEST, NYI…); names / titles also Title-case
# test words ("Test Boss", "Placeholder"); prose (gossip, quest titles, objectives) only markers + capitals.
JUNK_MARK = re.compile(r"<\s*(nyi|txt|dnt|unused|test|deprecated|placeholder|ph)\s*>|\[(dnt|ph|nyi|test|unused|deprecated|"
                       r"never used|pvp|reuse)\]|\((dnt|dnd|nyi|old|test|temp disabled)\)|monster -|^\s*(zz|z_)|^\s*\*|test (gossip|spirit healer)|tool by developers|exists to test", re.I)
JUNK_CAPS = re.compile(r"\b(QA|TEST|DEV|DEBUG|ZZOLD|ZZ|NYI|OLD|DNT|DND|TMP|TEMP|UNUSED|DEPRECATED|PLACEHOLDER)\b")
JUNK_NAMEW = re.compile(r"\b([Tt]est|[Dd]ebug|[Pp]laceholder|[Dd]eprecated|[Uu]nused|[Dd]o [Nn]ot [Uu]se|zzold)\b|^Debug "
                        r"|^Temp |^\d+\.\d+\.\d+ - |\bexists to test\b")


def junk(en, prose=None):
    en = en or ""
    if not re.search(r"[A-Za-z]", en): return True
    if JUNK_MARK.search(en) or JUNK_CAPS.search(en) or re.match(r"\s*Debug\b", en): return True
    if prose is None:                                   # a sentence ("…a test of your strength.") vs a name ("Test Boss")
        prose = len(en.split()) >= 10 or bool(re.search(r"[.!?…]['\"»)]?\s*$", en))
    return not prose and bool(JUNK_NAMEW.search(en))


def collect():
    pk = {k: [] for k in ORDER}
    skipped = []
    s = json.load(open(os.path.join(ROOT, "data", "strings_en.json"), encoding="utf-8"))
    qtitle_be = {q: v.get("t", "") for q, v in json.load(open(os.path.join(TB, "data", "classic", "quests_be.json"),
                                                               encoding="utf-8")).items()}
    # gossip (R325): keys hold the FULL text now, queue ids stay the old 80-char prefix (finished done/ files match them);
    # a second text with the same prefix gets "#<md5[:6]>" — the text that owns the prefix id in a finished chunk keeps it
    g_owner = {}
    for qf in glob.glob(os.path.join(OUT, "queue", "gossip", "*.json")):
        if os.path.exists(os.path.join(OUT, "done", "gossip", os.path.basename(qf))):
            for it in json.load(open(qf, encoding="utf-8")).get("items", []):
                g_owner[it["id"]] = it.get("en")
    g_used = {}
    # 2026-10-17: wowhead quotes repeat lines we already translated with only $n/$N case or spacing changed (wowhead
    # collapses the double space after "."); the runtime lookup matches those already (gossip_keys upper-cases $n) → skip
    g_norm = lambda t: re.sub(r"\s+", " ", re.sub(r"\$[nrcbNRCB]", lambda m: m.group(0).upper(), t)).strip()
    g_done, g_exact, g_hand = set(), set(), set()     # g_hand: data/gossip_fix.tsv lines (hand BE, R715)
    for dom in ("tb_gossip", "forever", "hand"):
        p = os.path.join(ROOT, "data", "be", dom + ".json")
        if os.path.exists(p):
            for k in json.load(open(p, encoding="utf-8")):
                if dom == "tb_gossip" or k.startswith("gossip:"):
                    t = k[len("gossip:"):] if k.startswith("gossip:") else k
                    g_done.add(g_norm(t)); g_exact.add(t)
                    if dom == "hand": g_hand.add(t)

    def gossip_id(en):
        pid = en[:80]
        if g_owner.get(pid, en) == en and g_used.get(pid, en) == en:
            g_used[pid] = en
            return pid
        return pid + "#" + md5(en, 6)
    for key, v in s.items():
        kind, _, ident = key.partition(":")
        if kind == "gossip":
            ident = gossip_id(v.get("v", ident))
        if kind == "quest":
            # raw line breaks (WDB cache text) -> WoW's $B token, like every other quest text
            en = {f: gender_tokens(v[f].replace("\r\n", "$B").replace("\n", "$B")) for f in ("t", "o", "d", "p", "c") if v.get(f)}
            if not en or junk(en.get("t", "")): skipped.append(("quests", ident, en.get("t", ""))); continue
            pk["quests"].append({"id": ident, "en": en, "ru": {f: gender_tokens(r) for f, r in (v.get("ru") or {}).items() if r}})
        elif kind == "title":                        # NPC titles from wowhead lists ("Bowyer"), 2026-10-01
            en = v.get("v", "")
            if junk(en): skipped.append(("titles", ident, en)); continue
            pk["titles"].append({"id": md5(en, 10), "en": en, "ru": ru_ok(en, v.get("ru", "")),
                                 "note": "NPC title shown as <Title> under the name (profession / role)"})
        elif kind in ("zone", "name", "gossip"):
            en = v.get("v", "")
            if junk(en): skipped.append((kind + "s", ident, en)); continue
            if kind == "gossip" and en in g_hand:
                skipped.append(("gossip (hand line in gossip_fix.tsv)", ident, en)); continue
            if kind == "gossip" and v.get("alias"):        # R711: game line of a translated race intro sentence
                skipped.append(("gossip (alias of " + v["alias"][:40] + ")", ident, en)); continue
            if kind == "gossip" and g_norm(en) in g_done and en not in g_exact:
                skipped.append(("gossip (already translated, spacing / $n case only)", ident, en)); continue
            item = {"id": ident, "en": en, "ru": ru_ok(en, v.get("ru", ""))}
            if kind == "name": item["note"] = v.get("why", "")
            if kind == "gossip" and v.get("npc"): item["note"] = "spoken by " + v["npc"]
            pk[kind + "s" if kind != "gossip" else "gossip"].append(item)
        elif kind == "objective":                    # quest objective line / place from the tracker (harvest)
            en = v.get("v", "")
            if junk(en): skipped.append(("objectives", ident, en)); continue
            q = v.get("quest", "")
            pk["objectives"].append({"id": ident, "en": en, "ru": "",
                                     "note": "quest objective line (tracker / quest log) of quest %s%s" % (
                                         q, (": " + qtitle_be.get(q, "")) if qtitle_be.get(q) else "")})
    # UI strings: Forever GlobalStrings not in the TM / not identical; dedupe by EN (runtime matches EN)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from ui_usage import classifier
    ui_used = classifier()
    hand = {r[0] for r in tsv(os.path.join(ROOT, "data", "ui_be.tsv"))}
    by_en = {}
    for key, en, ru, st in tsv(os.path.join(ROOT, "out", "diff_ui_globalstrings.tsv")):
        if key in hand or junk(en) or len(en) > 600: continue
        d = by_en.setdefault(en, {"id": md5(en, 10), "en": en, "ru": ru_ok(en, ru), "keys": []})
        if len(d["keys"]) < 4: d["keys"].append(key)
    for d in sorted(by_en.values(), key=lambda d: (len(d["en"]), d["en"])):
        if all(UI_SKIP.search(k) for k in d["keys"]):
            skipped.append(("ui", d["id"], d["en"])); continue
        if all(UI_LATER.search(k) for k in d["keys"]): pk["ui_later"].append(d)
        elif not any(ui_used(k) for k in d["keys"]): pk["ui_unused"].append(d)
        else: pk["ui"].append(d)
    # /emote chat lines (EmotesTextData DB2: "You let %s know that you were just kidding!"), shown in chat via
    # CHAT_MSG_TEXT_EMOTE; nothing in turtle-bel covers them. %s = a character name (player or NPC), shown as is
    emo = {}
    for r in tsv(os.path.join(ROOT, "out", "db2", "EmotesTextData.tsv")):
        if len(r) < 5 or r[1] != "Text_lang" or not r[3].strip() or junk(r[3]) or r[3] in by_en: continue
        emo.setdefault(r[3], {"id": md5(r[3], 10), "en": r[3], "ru": ru_ok(r[3], r[4]),
                              "note": "chat emote; %s = a character's name, keep it in the nominative (no case ending)"})
    pk["emotes"] = sorted(emo.values(), key=lambda d: d["en"])
    # profession window recipe-list headers ("Bandages", "Everyday Meals": TradeSkillCategory DB2, R35) — shown as
    # plain UI labels; nothing sourced them before
    cats = {}
    for r in tsv(os.path.join(ROOT, "out", "db2", "TradeSkillCategory.tsv")):
        if len(r) < 5 or r[1] != "Name_lang" or not r[3].strip() or junk(r[3]) or r[3] in by_en or r[3] in emo: continue
        if re.search(r"NYI|UNCATEGORIZED|/ PH", r[3]): continue
        cats.setdefault(r[3], {"id": md5(r[3], 10), "en": r[3], "ru": ru_ok(r[3], r[4]),
                               "note": "profession window: a recipe category header (cooking, first aid, tailoring…)"})
    pk["ui_prof"] = sorted(cats.values(), key=lambda d: d["en"])
    # spells / items not covered by turtle-bel (same EN check as build_addon.py)
    tm_spell = {r[0]: r[1] for r in tsv(os.path.join(TB, "data", "tm", "dbc", "Spell.tsv")) if len(r) > 2 and r[2]}
    names = {}
    for r in tsv(os.path.join(ROOT, "out", "db2", "SpellName.tsv")):
        if tm_spell.get(r[0]) == r[3] or junk(r[3]): continue
        d = names.setdefault(r[3], {"id": md5(r[3], 10), "en": r[3], "ru": ru_ok(r[3], r[4]), "spells": []})
        if len(d["spells"]) < 3: d["spells"].append(int(r[0]))
    pk["spellnames"] = sorted(names.values(), key=lambda d: d["en"])
    desc_be = json.load(open(os.path.join(TB, "spelldesc", "be.json"), encoding="utf-8"))
    fixp = os.path.join(ROOT, "data", "spelldesc_fix.tsv")
    fixed = {r[0] for r in tsv(fixp)} if os.path.exists(fixp) else set()
    seen = set()
    for field, pkg in (("Description_lang", "spelldesc"), ("AuraDescription_lang", "auras")):
        for r in tsv(os.path.join(ROOT, "out", "db2", "Spell.tsv")):
            if r[1] != field or junk(r[3]): continue
            k = md5(r[3])
            if k in desc_be or k in fixed or k in seen: continue
            seen.add(k)
            pk[pkg].append({"id": k, "en": r[3], "ru": ru_ok(r[3], r[4]), "spell": int(r[0])})
    it_be = json.load(open(os.path.join(TB, "items", "be.json"), encoding="utf-8"))
    it_en = {r[0]: r[1] for r in tsv(os.path.join(TB, "items", "todo.tsv"))}
    covered = {it_en[i] for i, b in it_be.items() if b and i in it_en}
    items = {}
    for r in tsv(os.path.join(ROOT, "out", "db2", "ItemSparse.tsv")):
        if r[1] != "Display_lang" or r[3] in covered or junk(r[3]): continue
        d = items.setdefault(r[3], {"id": md5(r[3], 10), "en": r[3], "ru": ru_ok(r[3], r[4]), "items": []})
        if len(d["items"]) < 3: d["items"].append(int(r[0]))
    # R734: items whose client row is encrypted (new Forever items), harvested in game {id: {n, d}} → names here (shipped
    # by EN name through auto_names), their Use / Equip / flavour lines in package item_text (exact lines → auto_ui)
    for iid, v in sorted(harvest_items().items()):
        en = v.get("n") if isinstance(v, dict) else None
        if not en or en in covered or junk(en) or re.search("[Ѐ-ӿ]", en): continue
        d = items.setdefault(en, {"id": md5(en, 10), "en": en, "ru": "", "items": []})
        if len(d["items"]) < 3 and int(iid) not in d["items"]: d["items"].append(int(iid))
    pk["items"] = sorted(items.values(), key=lambda d: d["en"])
    # style re-pass: existing turtle-bel descriptions that break data/STYLE_RULES.md
    ru_by_key = {}                                        # client RU for the same EN text (md5 keyspace)
    for r in tsv(os.path.join(ROOT, "out", "db2", "Spell.tsv")):
        if r[1] in ("Description_lang", "AuraDescription_lang"):
            ru_by_key.setdefault(md5(r[3]), ru_ok(r[3], r[4]))
    cand = json.load(open(os.path.join(ROOT, "data", "style_candidates.json"), encoding="utf-8"))
    todo = {r[0]: r[1] for r in tsv(os.path.join(TB, "spelldesc", "todo.tsv"))}
    for k in cand:
        if k in todo and k in desc_be and k not in fixed:
            pk["stylefix"].append({"id": k, "en": todo[k], "ru": ru_by_key.get(k, ""), "be_current": desc_be[k]})
    pk["quests_gender"] = gender_repass()
    pk["quests_namefix"] = namefix_repass()
    pk["quests_address"] = address_repass()
    pk["quests_unify"] = unify_repass()
    # R206: objectives naming a REQUIRED item (quest_template ReqItemId) differently from the item (review/quest_items.py)
    pk["quests_itemfix"] = unify_repass("name_unify_repass2.json")
    pk["quests_speaker"] = speaker_repass()
    pk["items_redo"] = items_redo(it_be, it_en)
    pk["items_hidden"] = items_hidden()
    pk["spellnames_redo"] = spellnames_redo()
    pk["quests_update"] = quests_update(pk["quests"])
    pk["quests_classic_update"] = quests_classic_update()
    for name, fn in (("spellnames_redo2", spellnames_redo2), ("spelldesc_redo", spelldesc_redo), ("itemsets", itemsets), ("enchants", enchants), ("suffixes", suffixes), ("quests_capfix", quests_capfix),
                     ("names_qa", names_qa), ("zones_qa", zones_qa), ("quests_natural", quests_natural), ("gossip_natural", gossip_natural), ("flavor", flavor), ("achievements", achievements), ("chartitles", chartitles), ("factions", factions), ("focus", focus),
                     ("tips", tips), ("books", books), ("item_text", item_text), ("db2_misc", db2_misc), ("barber", barber)):
        pk[name] = fn()
    pk["ui_termfix"] = term_repass()
    enrich(pk)
    return pk, skipped


# ---------------------------------------------------------------- context + similar finished translations
SPEAKER_F = re.compile(r"(?<![А-Яа-яЁё])[Яя]\s+(?:[а-яё]+\s+){0,2}?[а-яё]{2,}(?:ла|лась)(?![а-яё])")
SPEAKER_M = re.compile(r"(?<![А-Яа-яЁё])[Яя]\s+(?:[а-яё]+\s+){0,2}?[а-яё]{2,}(?:ал|ил|ел|ыл|ял|ался|ился|ялся)(?![а-яё])")
SIM_WORD = re.compile(r"\$\{[^}]*\}|\$[a-zA-Z0-9/;@?<>]+|\d+(?:[.,]\d+)?|[a-z']+")


def speaker(ru):
    t = " ".join(v for v in (ru or {}).values() if v)
    f, m = bool(SPEAKER_F.search(t)), bool(SPEAKER_M.search(t))
    return "female" if f and not m else "male" if m and not f else None


def sim_words(en):
    return {("#" if w[0] in "$0123456789" else w) for w in SIM_WORD.findall(en.lower())}


class Similar:
    """Top-k finished EN->BE pairs by word-set Jaccard (numbers and $-tokens folded to #)."""
    def __init__(self, pairs, min_score):
        self.pairs, self.min = pairs, min_score
        self.sets = [sim_words(en) for en, _ in pairs]
        self.index = {}
        for i, ws in enumerate(self.sets):
            for w in ws: self.index.setdefault(w, []).append(i)
        n = len(pairs)
        self.common = {w for w, ix in self.index.items() if len(ix) > max(200, n // 20)}

    def top(self, en, k=2):
        q = sim_words(en)
        cnt = {}
        for w in q - self.common:
            for i in self.index.get(w, ()): cnt[i] = cnt.get(i, 0) + 1
        best = []
        for i in sorted(cnt, key=cnt.get, reverse=True)[:60]:
            sc = len(q & self.sets[i]) / len(q | self.sets[i])
            if sc >= self.min and self.pairs[i][0] != en: best.append((sc, i))
        best.sort(reverse=True)
        out, seen = [], []
        for _, i in best:                                 # skip near-duplicates (ranks of one spell)
            if any(self.sets[i] == self.sets[j] for j in seen): continue
            seen.append(i); out.append(list(self.pairs[i]))
            if len(out) == k: break
        return out


def enrich(pk):
    """Adds per-item context the translator can't see otherwise, and up to 2 similar finished translations
    (turtle-bel WoWBY corpus, owner term fixes applied) for formulaic packages."""
    from build_addon import fix_terms
    # spell names (EN/RU from the beta, BE from turtle-bel), spell descriptions for spell-name context
    sname, sname_ru, sdesc = {}, {}, {}
    for r in tsv(os.path.join(ROOT, "out", "db2", "SpellName.tsv")):
        sname[r[0]] = r[3]; sname_ru[r[0]] = r[4]
    for r in tsv(os.path.join(ROOT, "out", "db2", "Spell.tsv")):
        if r[1] == "Description_lang": sdesc.setdefault(r[0], r[3])
    tm_spell = [(r[1], r[2]) for r in tsv(os.path.join(TB, "data", "tm", "dbc", "Spell.tsv")) if len(r) > 2 and r[2]]
    sname_be = {}
    for r in tsv(os.path.join(TB, "data", "tm", "dbc", "Spell.tsv")):
        if len(r) > 2 and r[2]: sname_be[r[0]] = fix_terms(r[2])
    for pkg in ("spelldesc", "auras"):
        for it in pk[pkg]:
            sid = str(it.get("spell", ""))
            if sname.get(sid):
                it["name"] = sname[sid] + (" = " + sname_be[sid] if sid in sname_be else "")
    for it in pk["spellnames"] + pk["spellnames_redo"] + pk["spellnames_redo2"]:
        d = sdesc.get(str((it.get("spells") or [0])[0]), "")
        if d: it["desc"] = d[:220]
    # NPC names: race + sex from the model (tools/npc_race.py, wowhead displayId -> client DB2) — the surname form follows
    # the race (decisions.md), the endings follow the sex («Вартавая», «Шукальніца»)
    rp = os.path.join(ROOT, "out", "npc_race.json")
    races = json.load(open(rp, encoding="utf-8")) if os.path.exists(rp) else {}
    for it in pk["names"] + pk.get("names_qa", []):
        r = races.get(it["en"])
        if r:
            it["race"] = "%s, %s" % (r["race"], "female" if r["sex"] == "f" else "male")
    # items: kind / slot / quality + flavor text
    ctx_p = os.path.join(ROOT, "out", "item_context.json")
    ictx = json.load(open(ctx_p, encoding="utf-8")) if os.path.exists(ctx_p) else {}
    iflav = {r[0]: r[3] for r in tsv(os.path.join(ROOT, "out", "db2", "ItemSparse.tsv")) if r[1] == "Description_lang"}
    for it in pk["items"] + pk["items_redo"] + pk["items_hidden"]:
        iid = str((it.get("items") or [0])[0])
        if ictx.get(iid): it["kind"] = ictx[iid]
        if iflav.get(iid): it["flavor"] = iflav[iid][:200]
    # quests: speaker gender from the Russian first person ("я сделала")
    for pkg in ("quests", "quests_gender"):
        for it in pk[pkg]:
            sp = speaker(it.get("ru"))
            if sp: it["speaker"] = sp + " (from the Russian first person)"
    # similar finished translations
    desc_be = json.load(open(os.path.join(TB, "spelldesc", "be.json"), encoding="utf-8"))
    desc_en = {r[0]: r[1] for r in tsv(os.path.join(TB, "spelldesc", "todo.tsv"))}
    # examples = the SHIPPED text (data/be: owner rules, hand fixes, sentence case) where the corpus has the entry,
    # else turtle-bel through fix_terms (2026-10-13: raw turtle-bel examples showed wording the game no longer has)
    def ship(dom):
        p = os.path.join(ROOT, "data", "be", dom + ".json")
        return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}
    s_desc, s_items, s_spells = ship("spell_desc"), ship("items"), ship("spell_names")
    d_pairs = [(desc_en[k], (s_desc.get(k) or {}).get("be") or fix_terms(b)) for k, b in desc_be.items() if b and k in desc_en]
    it_be = json.load(open(os.path.join(TB, "items", "be.json"), encoding="utf-8"))
    it_en = {r[0]: r[1] for r in tsv(os.path.join(TB, "items", "todo.tsv"))}
    pool = set(str(x) for x in pool_items())            # R65: the free-model item names are no example
    i_pairs = sorted({(it_en[i], (s_items.get(i) or {}).get("be") or fix_terms(b))
                      for i, b in it_be.items() if b and i in it_en and i not in pool})
    shipped_sn = {}
    for e in s_spells.values():
        if e.get("en") and e.get("be"): shipped_sn.setdefault(e["en"], e["be"])
    n_pairs = sorted({(en, shipped_sn.get(en, be)) for en, be in tm_spell if "(OLD)" not in en})
    isim = Similar(i_pairs, 0.5)
    sims = {"spelldesc": Similar(d_pairs, 0.45), "auras": Similar(d_pairs, 0.45), "items": isim, "items_redo": isim, "items_hidden": isim,
            "spellnames": Similar([(en, fix_terms(be)) for en, be in n_pairs], 0.5)}
    for pkg, sim in sims.items():
        for it in pk[pkg]:
            ex = sim.top(it["en"])
            if ex: it["similar"] = ex


# Owner term decisions that finished UI strings must be re-done for (package "ui_termfix"; each item says which)
TERM_REPASS = [
    (re.compile(r"(%(?:\d\$)?[sd]|\d+)-(?:ы|га|м|му|і|ым|ага|аму|ю)\s+[ўу]зро[вў]", re.I),
     "Level N = «узровень N» (number after the noun): «Узровень %d», «Патрабуецца ўзровень %d», «на ўзроўні %d»; Rank N = «ранг N»"),
    (re.compile(r"абшук|абыск", re.I),
     "loot = здабыча; to loot / looting = збіраць здабычу / збор здабычы (never абшук / абыск): "
     "Loot Key = «Клавіша збору здабычы», Auto Loot = «Аўтаматычны збор здабычы», Auto Loot Key = «Клавіша аўтазбору здабычы»"),
    (re.compile(r"(?<![А-ЯЁІЎа-яёіў])[Нн][Іі][Пп]|неігра[вў]", re.I),
     "NPC stays «NPC» (indeclinable: «Імёны NPC», «Усе NPC»); spelled out = «негульнявы персанаж», never НІП / неігравы"),
]
LEVEL_ORD = TERM_REPASS[0][0]


def term_repass():
    """Finished UI strings (translate/done) + WoWBY TM strings Forever shows that break an owner term decision."""
    out, seen = [], set()

    def add(item_id, en, ru, keys, be):
        fixes = [note for rx, note in TERM_REPASS if rx.search(be)]
        if fixes and en not in seen:
            seen.add(en)
            out.append({"id": "tf" + md5(en, 8), "en": en, "ru": ru, "keys": keys, "be_current": be, "fix": fixes})
    for pkg in UI_PKGS:
        for df in sorted(glob.glob(os.path.join(OUT, "done", pkg, "*.json"))):
            qf = os.path.join(OUT, "queue", pkg, os.path.basename(df))
            if not os.path.exists(qf): continue
            done = json.load(open(df, encoding="utf-8")).get("items", {})
            for it in json.load(open(qf, encoding="utf-8"))["items"]:
                be = done.get(it["id"])
                if isinstance(be, str): add(it["id"], it["en"], it.get("ru", ""), it.get("keys", []), be)
    forever_en = {r[1] for r in tsv(os.path.join(ROOT, "out", "globalstrings_keys.tsv")) if len(r) > 1}
    hand = {r[0] for r in tsv(os.path.join(ROOT, "data", "ui_be.tsv"))}
    for r in tsv(os.path.join(TB, "data", "tm", "ui_globalstrings.tsv")):
        if len(r) > 2 and r[2] and r[0] not in hand and r[1] in forever_en:
            add(None, r[1], "", [r[0]], r[2])
    return out


def namefix_repass():
    """Quests (WoWBY vanilla + finished Forever ones) that mention an NPC whose surname the owner changed
    (out/surname_renames.tsv from tools/apply_surnames.py): the agent re-declines the new name in context."""
    rp = os.path.join(ROOT, "out", "surname_renames.tsv")
    if not os.path.exists(rp): return []
    renames = [r for r in tsv(rp) if len(r) >= 4]
    pats = []
    for fam, given, old, new in renames:
        g = re.escape(given[:max(3, len(given) - 2)])
        o = re.escape(old.split()[0][:max(3, len(old.split()[0]) - 2)])
        pats.append((re.compile(g + r"[а-яёіўА-ЯЁІЎ']*\s+" + o), "%s %s → %s %s" % (given, old, given, new)))
    texts = {}                                                  # qid -> (en fields, be fields)
    q_en = json.load(open(os.path.join(TB, "data", "classic", "quests_en.json"), encoding="utf-8"))
    q_be = json.load(open(os.path.join(TB, "data", "classic", "quests_be.json"), encoding="utf-8"))
    for qid, be in q_be.items():
        if qid in q_en:
            texts[qid] = ({f: q_en[qid][f] for f in "todpc" if q_en[qid].get(f)}, {f: be[f] for f in "todpc" if be.get(f)})
    for pkg in ("quests", "quests_gender"):                      # finished Forever quests (gender re-pass wins)
        for df in sorted(glob.glob(os.path.join(OUT, "done", pkg, "*.json"))):
            qf = os.path.join(OUT, "queue", pkg, os.path.basename(df))
            if not os.path.exists(qf): continue
            done = json.load(open(df, encoding="utf-8")).get("items", {})
            for it in json.load(open(qf, encoding="utf-8"))["items"]:
                if it["id"] in done: texts[it["id"]] = (it["en"], done[it["id"]])
    out = []
    for qid, (en, be) in sorted(texts.items(), key=lambda kv: int(kv[0]) if kv[0].isdigit() else 0):
        blob = " ".join(v for v in be.values() if isinstance(v, str))
        fixes = sorted({note for rx, note in pats if rx.search(blob)})
        if fixes:
            out.append({"id": qid, "en": en, "be_current": be, "fix": fixes})
    return out


# «ты знайшоў», «ты павінен» … a masculine-only past verb right after «ты» (up to 3 words between), no $G on it.
ADDR = re.compile(r"(?<![а-яёіўА-ЯЁІЎ$])[Тт]ы\s+(?:[а-яёіў]+\s+){0,3}?([а-яёіў]{2,}[аеоыіуэя]ў)(?![а-яёіў])")
ADDR_NOT = {"зноў", "духаў", "лагераў", "даспехаў", "выпрабаванняў", "шчасліўчыкаў", "прадметаў", "ворагаў"}


def pool_items():
    p = os.path.join(ROOT, "data", "pool_items.json")            # tools/pool_items.py
    return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else []


def items_redo(it_be, it_en):
    """R65: shipped item names turtle-bel got from the opencode free-model pool (data/pool_items.json). Re-translated from
    scratch; `be_current` = the weak draft (reference only). Only items Forever ships (its EN = turtle-bel's EN).
    import -> data/auto_items_redo.json {item id: BE}; the build ships it for those ids."""
    fitem = {r[0]: r[3] for r in tsv(os.path.join(ROOT, "out", "db2", "ItemSparse.tsv")) if r[1] == "Display_lang"}
    fru = {r[0]: r[4] for r in tsv(os.path.join(ROOT, "out", "db2", "ItemSparse.tsv")) if r[1] == "Display_lang"}
    corp = json.load(open(os.path.join(ROOT, "data", "be", "items.json"), encoding="utf-8"))   # shipped text (rules applied)
    out = []
    for iid in pool_items():
        iid = str(iid)
        be, en = it_be.get(iid), it_en.get(iid)
        if not be or not en or fitem.get(iid) != en:
            continue
        be = (corp.get(iid) or {}).get("be") or be
        out.append({"id": iid, "en": en, "ru": ru_ok(en, fru.get(iid, "")), "be_current": be, "items": [int(iid)],
                    "fix": ["be_current is a weak machine draft: translate the name anew (glossary + decisions win); "
                            "keep it only where it is already right"]})
    return out


def items_hidden():
    """R726: vanilla items whose rows Forever's client does not carry yet (future-phase loot: Blackrock Depths, Dire Maul,
    Naxxramas…; wowhead's Forever DB lacks them too) and nobody translated: review/hidden_items_untranslated.py (EN =
    Anniversary client = pfQuest 1.12 = Turtle DB). import -> data/auto_items_redo.json {item id: BE}; the build ships
    them by EN name (the live English name is the check)."""
    p = os.path.join(ROOT, "review", "hidden_items_untranslated.json")
    if not os.path.exists(p): return []
    junk = re.compile(r"^(Monster - |Test |TEST|zz|\[PH\]|Deprecated|OLD)|\b(DEPRECATED|Placeholder|UNUSED|NYI)\b")
    return [{"id": iid, "en": en, "items": [int(iid)]} for iid, en in sorted(json.load(open(p, encoding="utf-8")).items(),
                                                                          key=lambda kv: int(kv[0])) if not junk.search(en)]


def spellnames_redo():
    """R132: shipped spell names players learn (class / weapon / secondary skills, out/skill_spells.json from
    tools/skill_spells.py) came from a bulk Sonnet pass in turtle-bel (Faerie Fire = «Крыкса») — re-translated by EN
    name; `be_current` = the most common shipped name. import -> data/auto_spellnames_redo.json {EN: BE}; the build
    ships it for every spell id with that EN (data/be hand edits and spellnames_fix.tsv still win)."""
    sp = os.path.join(ROOT, "out", "skill_spells.json")
    if not os.path.exists(sp): return []
    ids = {str(i) for c in ("6", "7", "9") for i in json.load(open(sp, encoding="utf-8")).get(c, [])}
    corp = json.load(open(os.path.join(ROOT, "data", "be", "spell_names.json"), encoding="utf-8"))
    ru = {r[0]: r[4] for r in tsv(os.path.join(ROOT, "out", "db2", "SpellName.tsv"))}
    by_en = {}
    for sid in sorted(ids, key=int):
        e = corp.get(sid)
        if not e or junk(e["en"]) or re.search(r"\((?:OLD|NYI|DND|Disabled)\)|\bTEST\b", e["en"]): continue
        d = by_en.setdefault(e["en"], {"id": md5(e["en"], 10), "en": e["en"], "ru": ru_ok(e["en"], ru.get(sid, "")),
                                       "be_forms": Counter(), "spells": []})
        d["be_forms"][e["be"]] += 1
        if len(d["spells"]) < 3: d["spells"].append(int(sid))
    out = []
    for d in sorted(by_en.values(), key=lambda d: d["en"]):
        d["be_current"] = d.pop("be_forms").most_common(1)[0][0]
        d["fix"] = ["be_current is a weak machine draft: give the spell a natural Belarusian name (glossary + decisions win; "
                    "sentence case; the same English word = the same Belarusian word across spells, e.g. Arcane = "
                    "аркановы); keep it only where it is already right"]
        out.append(d)
    return out


# ---- R135-R143 (owner 2026-09-30: "add all to Gemini, re-translation ones too; books the lowest priority") ----------
STAT_NOTE = ("stat words exactly as on our item tooltips: Stamina = Целабудова, Strength = Сіла, Agility = Спрытнасць, "
             "Intellect = Інтэлект, Spirit = Дух, Defense = Абарона, Armor = Браня, Attack Power = Сіла атакі, "
             "Spell Damage = урон ад заклёнаў, Healing = лячэнне, Fire/Frost/Nature/Shadow/Arcane/Holy Resistance = "
             "супраціўленне агню / марозу / прыродзе / цемры / аркане / святлу, mana per 5 sec. = маны за 5 сек.; "
             "form «+5 Целабудова», «+2% да ўхілення»")


def db2_texts(table, fields, skip=None):
    """{EN: RU} of one out/db2 table's fields (first RU seen), junk and skip-pattern rows left out."""
    out = {}
    for r in tsv(os.path.join(ROOT, "out", "db2", table + ".tsv")):
        if len(r) < 5 or r[1] not in fields or not r[3].strip() or junk(r[3]): continue
        if skip and skip.search(r[3]): continue
        out.setdefault(r[3], ru_ok(r[3], r[4]))
    return out


def tm_be(table):
    return {r[1]: r[2] for r in tsv(os.path.join(TB, "data", "tm", "dbc", table + ".tsv")) if len(r) > 2 and r[2].strip()}


def label_pkg(texts, note, draft=None, extra=None):
    out = []
    for en, ru in sorted(texts.items()):
        d = {"id": md5(en, 10), "en": en, "ru": ru, "note": note}
        if draft and draft.get(en):
            d["be_current"] = fix_terms_lazy(draft[en])
            d["fix"] = ["be_current is an old machine draft: keep it only where it is right and consistent with the glossary"]
        if extra: d.update(extra(en) or {})
        out.append(d)
    return out


def fix_terms_lazy(s):
    from build_addon import fix_terms
    return fix_terms(s)


def itemsets():
    return label_pkg(db2_texts("ItemSet", {"Name_lang"}),
                     "an item SET name (tooltip line «Name (2/5)»); sentence case except proper names", tm_be("ItemSet"))


def enchants():
    skip = re.compile(r"(?i)test|^MH|^QA|deprecated|zz|\bDND\b|^\d+$")
    return label_pkg(db2_texts("SpellItemEnchantment", {"Name_lang"}, skip),
                     "a permanent/temporary enchantment line on an item tooltip; " + STAT_NOTE, tm_be("SpellItemEnchantment"))


def suffixes():
    """Random item suffixes ("of the Bear") — EN keys + Ukrainian from ClassicUA entries/item_suffix.lua."""
    src = open(r"C:\Projects\WoW\ClassicUA\entries\item_suffix.lua", encoding="utf-8").read()
    out = []
    for en, ua in re.findall(r'\["(of [^"]+)"\]\s*=\s*"([^"]*)"', src):
        out.append({"id": md5(en, 10), "en": en, "ua": ua,
                    "note": "random item SUFFIX added after an item name («Бандыцкі пояс» + this = one name); the "
                            "Belarusian must read naturally after ANY item name (e.g. «… мядзведзя», «… з чарамі сілы»); "
                            "ua = the Ukrainian mod's choice for reference"})
    return out


def flavor():
    texts = db2_texts("ItemSparse", {"Description_lang"})
    return label_pkg(texts, "item FLAVOR text (the gold quoted line on the tooltip): short, literary, keep the tone")


def achievements():
    t = db2_texts("Achievement", {"Title_lang", "Description_lang", "Reward_lang"})
    t.update(db2_texts("Achievement_Category", {"Name_lang"}))
    t.update(db2_texts("CriteriaTree", {"Description_lang"}))
    return label_pkg(t, "achievement / statistics UI (titles, descriptions, categories, criteria)")


def chartitles():
    return label_pkg(db2_texts("CharTitles", {"Name_lang", "Name1_lang"}),
                     "player TITLE; %s = the character's name (keep it, nominative); PvP ranks as in the glossary")


def factions():
    t = db2_texts("Faction", {"Description_lang"})
    # renown rewards on the reputation pane ("Faction Tabard", "Battle Standard Unlocked", 2026-10-07)
    t.update(db2_texts("RenownRewards", {"Name_lang", "Description_lang", "ToastDescription_lang"}))
    return label_pkg(t, "reputation pane: a faction's description, or a renown REWARD name / unlock toast / its "
                        "description (short UI label); faction / place names as in the glossary")


def focus():
    """R218: spell focus objects — what a recipe / spell needs nearby ("Requires: Cooking Fire", Forge, Anvil)."""
    return label_pkg(db2_texts("SpellFocusObject", {"Name_lang"}),
                     "a thing or place a recipe / spell needs nearby, shown after «Патрабуецца:» (nominative, short; "
                     "Cooking Fire = вогнішча для гатавання, Forge = кузня, Anvil = кавадла)")


def harvest_items():
    """R734: data/harvest.json enUS "items" = {item id: {"n": EN name, "d": [tooltip lines that stayed English]}}"""
    p = os.path.join(ROOT, "data", "harvest.json")
    return json.load(open(p, encoding="utf-8")).get("enUS", {}).get("items", {}) if os.path.exists(p) else {}


def item_text():
    """R734: Use / Equip / Chance on hit / flavour lines of harvested encrypted items, translated as whole lines"""
    lines = {}
    for v in harvest_items().values():
        d = v.get("d") if isinstance(v, dict) else None
        if isinstance(d, dict): d = [d[k] for k in sorted(d, key=int)]       # a Lua array comes back as {"1": …}
        for t in d or []:
            if t and not re.search("[Ѐ-ӿ]", t): lines[t] = ""
    return label_pkg(lines, "a whole item tooltip line: «Ужыць: …» (Use:), «Калі на персанажы: …» (Equip:), «Магчымы эфект "
                            "пры трапленні: …» (Chance on hit:) or a quoted flavour text; numbers and times as in English")


MISC_TABLES = (   # R739: client tables Forever shows in game whose text nothing else queued (review/db2_coverage.py)
    ("PlayerCondition", "Failure_description_lang", "a requirement line in a tooltip / vendor (Requires X - Exalted)"),
    ("ItemNameDescription", "Description_lang", "a short green line under an item name (Raid Unique (3))"),
    ("ItemClass", "ClassName_lang", "an item class word"),
    ("ItemSubClass", "DisplayName_lang", "an item type word (tooltip / auction house)"),
    ("ItemSubClass", "VerboseName_lang", "an item type word (tooltip / auction house)"),
    ("ItemBagFamily", "Name_lang", "what a special bag holds"),
    ("ItemPetFood", "Name_lang", "hunter pet diet word"),
    ("PetLoyalty", "Name_lang", "hunter pet loyalty level"),
    ("SpellDispelType", "Name_lang", "dispel type in aura tooltips (Magic, Curse)"),
    ("SpellMechanic", "StateName_lang", "a control state (stunned, disoriented), lower case"),
    ("SpellRange", "DisplayName_lang", "spell range name"),
    ("SpellRange", "DisplayNameShort_lang", "spell range name, short"),
    ("TotemCategory", "Name_lang", "a tool a recipe needs (Requires: Mining Pick)"),
    ("LockType", "Name_lang", "what opening a lock / node needs"),
    ("LockType", "ResourceName_lang", "a gathering node kind"),
    ("LockType", "Verb_lang", "the verb for opening / gathering"),
    ("CurrencyTypes", "Name_lang", "currency name"),
    ("CurrencyTypes", "Description_lang", "currency description"),
    ("CurrencyCategory", "Name_lang", "currency list header"),
    ("Languages", "Name_lang", "an in-game language (chat [Dwarvish])"),
    ("ChatChannels", "Name_lang", "a chat channel name (%s = the zone)"),
    ("ServerMessages", "Text_lang", "a server notice (%s = time)"),
    ("AreaPOI", "Description_lang", "map point state"),
    ("AreaPOIState", "Description_lang", "map point state"),
    ("UiWidgetStringSource", "Value_lang", "battleground status widget line (keep %NNNNw tokens)"),
    ("PVPScoreboardColumnHeader", "Name_lang", "battleground scoreboard column"),
    ("PVPScoreboardColumnHeader", "Tooltip_lang", "battleground scoreboard column tooltip"),
    ("PVPStat", "Description_lang", "battleground stat"),
    ("BattlemasterList", "Name_lang", "battleground name"),
    ("BattlemasterList", "ShortDescription_lang", "battleground description"),
    ("BattlemasterList", "LongDescription_lang", "battleground description"),
    ("Map", "MapDescription0_lang", "battleground description (Alliance side)"),
    ("Map", "MapDescription1_lang", "battleground description (Horde side)"),
    ("Map", "PvpShortDescription_lang", "battleground objective, short"),
    ("Map", "PvpLongDescription_lang", "battleground objectives list (keep the line breaks)"),
    ("MapDifficulty", "Message_lang", "dungeon entry requirement message"),
    ("MapDifficultyXCondition", "FailureDescription_lang", "dungeon / raid not available message"),
    ("GroupFinderActivity", "FullName_lang", "dungeon finder activity"),
    ("GroupFinderActivity", "ShortName_lang", "dungeon finder activity, short"),
    ("DungeonEncounter", "Name_lang", "a dungeon / raid boss encounter"),
    ("AuctionHouse", "Name_lang", "auction house name"),
    ("CreatureType", "Name_lang", "creature type (Beast, Humanoid)"),
    ("HolidayDescriptions", "Description_lang", "holiday description (calendar)"),
    ("CriteriaTree", "Description_lang", "a legacy challenge (achievement) criterion"),
    ("MailTemplate", "Body_lang", "an NPC letter body"),
    ("SpellFlyout", "Name_lang", "spell flyout (portal / teleport list) name"),
    ("SpellFlyout", "Description_lang", "spell flyout description"),
)
MISC_JUNK = re.compile(r"\bDNT\b|\bDND\b|\bNYI\b|UNUSED|OBSOLETE|REUSE|\btest\b|\[PH\]|^\d+$|Bigfoot|MeetingStone|Shadowlands|"
                       r"Vulpera|Warglaive", re.I)   # (race names were for the barbershop: "Forsaken and Worgen" is a real BG text)


BARBER_JUNK = re.compile(MISC_JUNK.pattern + r"|Pandaren|Worgen|Draenei", re.I)   # races Forever has no barber for


def barber():
    """R740: barbershop labels — option ("Hair Style", "Beard"), category ("Face (Undead)") and choice names ("Bald",
    "Braids"); BarberShopStyle is the retired pre-8.0 barbershop table, not shown"""
    out, known = {}, known_ui("barber")
    for table, note in (("ChrCustomizationOption", "a barbershop option label (Hair Style, Beard), nominative"),
                        ("ChrCustomizationCategory", "a barbershop category tab"),
                        ("ChrCustomizationChoice", "a barbershop style / colour name in the option's list, nominative")):
        for en, ru in db2_texts(table, {"Name_lang", "CategoryName_lang"}, BARBER_JUNK).items():
            if en in known: continue
            out.setdefault(en, {"id": md5(en, 10), "en": en, "ru": ru, "note": note})
    return sorted(out.values(), key=lambda d: d["en"])


def known_ui(own):
    """English texts the shipped data already translates — minus the package's OWN queued texts, which reach auto_ui /
    memory once imported (else a re-run would drop the finished items from their own package)"""
    known = set()
    for r in tsv(os.path.join(ROOT, "translate", "rules", "memory.tsv")):
        if r: known.add(r[0])
    for p in ("auto_ui.tsv", "ui_be.tsv", "holidays_be.tsv"):
        fp = os.path.join(ROOT, "data", p)
        if os.path.exists(fp): known |= {r[0].replace("\\n", "\n") for r in tsv(fp) if r}
    known |= set(json.load(open(os.path.join(ROOT, "data", "be", "ui.json"), encoding="utf-8")))
    for p in glob.glob(os.path.join(ROOT, "translate", "queue", own, "*.json")):
        known -= {it["en"] for it in json.load(open(p, encoding="utf-8"))["items"]}
    return known


def db2_misc():
    """R739: one package for the small client tables above; texts the shipped data already covers are skipped"""
    known = known_ui("db2_misc")
    out = {}
    for table, field, note in MISC_TABLES:
        for en, ru in db2_texts(table, {field}, MISC_JUNK).items():
            if en in known or en.replace("\r", "") in known or en in out: continue
            out[en] = {"id": md5(en, 10), "en": en, "ru": ru, "note": "%s (%s)" % (note, table)}
    return sorted(out.values(), key=lambda d: d["en"])


# not in ORDER: the loading screen (GameTips) is drawn by the engine, no Lua frame an addon could reach (R739)
def tips():
    return label_pkg(db2_texts("GameTips", {"Text_lang"}), "loading-screen tip; keep |c…|r colour codes and <Control>-style key names")


def books():
    """Readable books / letters / plaques (page_text, R138) from the local vanilla world DB; one item = one page
    (id = page id, `next` = the following page). RU = locales_page_text loc8. Turtle's own pages (>= 5000) skipped."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from import_broadcast import rows, SQL
    ru = {int(v[0]): v[9] or "" for v in rows(os.path.join(SQL, "tw_world_locales_page_text.sql"), "locales_page_text")}
    out, seen = [], set()
    for v in rows(os.path.join(SQL, "tw_world_page_text.sql"), "page_text"):
        pid = int(v[0])
        en = (v[1] or "").replace("\r\n", "\n").replace("\r", "\n")
        if pid >= 5000 or not en.strip() or junk(en) or en in seen or en.strip() == "Missing Text": continue
        seen.add(en)
        out.append({"id": md5(en, 10), "en": en, "ru": ru_ok(en, (ru.get(pid) or "").replace("\r", "")), "page": pid,
                    "next": int(v[2] or 0),
                    "note": "a page of an in-game book / letter / note / plaque; keep line breaks and $N/$B tokens"})
    # Forever pages the vanilla DB lacks: harvested from the reading window + the game's page cache
    # (extract_forever -> out/books_forever.json); matched like the addon does (build_addon book_key)
    def key(t):
        t = re.sub(r"\$[Bb]", "\n", t.replace("\r\n", "\n").replace("\r", "\n"))
        return "\n".join(l.rstrip(" \t") for l in t.split("\n")).strip()
    have = {key(it["en"]) for it in out}
    fp = os.path.join(ROOT, "out", "books_forever.json")
    for k, b in (json.load(open(fp, encoding="utf-8")).items() if os.path.exists(fp) else []):
        en = b.get("en") or k
        if key(en) in have or junk(en): continue
        have.add(key(en))
        out.append({"id": md5(en, 10), "en": en, "ru": "", "title": b.get("title", ""),
                    "note": "a page of an in-game book / letter / note / plaque (new in WoW Forever); keep line breaks and $N"})
    return out


def names_qa():
    """R135: NPC names never got a MEANING check in turtle-bel ("Field Repair Bot" → «Польскі рамонтны бот»). Every
    turtle-bel name of an NPC Questie knows for Classic (= can appear in Forever); siblings sorted together (by the
    last English word). Import writes the answer into data/be/tb_names.json."""
    from questie_names import load
    ru = {}
    for v in load().values():
        ru.setdefault(v["en"], v["ru"])
    corp = json.load(open(os.path.join(ROOT, "data", "be", "tb_names.json"), encoding="utf-8"))
    out = []
    for en, e in corp.items():
        if en not in ru or junk(en): continue
        out.append({"id": md5(en, 10), "en": en, "ru": ru_ok(en, ru[en]), "be_current": e["be"],
                    "fix": ["CHECK the meaning against the English (and Russian): fix only real errors — mistranslation "
                            "(Field ≠ Polish), nonsense calque, Russianism, wrong gender/case, a word rendered differently "
                            "from its siblings in this chunk or from the glossary. Otherwise return be_current UNCHANGED."],
                    "target": {"domain": "tb_names", "keys": {"v": en}}})
    out.sort(key=lambda d: (d["en"].split()[-1].lower(), d["en"]))
    return out


def zones_qa():
    """R210 (owner 2026-10-07, «Бухта Гострарука»): zone / place names from turtle-bel were only checked for CAPITALS
    (zone review 10-03), never for meaning. Every tb_zones name Forever's client uses (review/zone_set.py →
    out/zones_forever.json), RU from the client DB2. Import writes the answer into data/be/tb_zones.json."""
    p = os.path.join(ROOT, "out", "zones_forever.json")
    if not os.path.exists(p): return []
    ru = {}
    for t in ("AreaTable", "WMOAreaTable", "AreaPOI", "UiMap", "Map"):
        tp = os.path.join(ROOT, "out", "db2", t + ".tsv")
        if not os.path.exists(tp): continue
        for r in csv.reader(open(tp, encoding="utf-8"), delimiter="\t", quoting=csv.QUOTE_NONE):
            if len(r) > 4 and r[1] in ("AreaName_lang", "Name_lang", "MapName_lang"):
                ru.setdefault(r[3].strip(), r[4])
    corp = json.load(open(os.path.join(ROOT, "data", "be", "tb_zones.json"), encoding="utf-8"))
    out = []
    for en in json.load(open(p, encoding="utf-8")):
        if en not in corp: continue
        out.append({"id": md5(en, 10), "en": en, "ru": ru.get(en.strip(), ""), "be_current": corp[en]["be"],
                    "fix": ["CHECK the meaning against the English (and Russian): fix only real errors — mistranslation, "
                            "Russian words (гостры → востры), nonsense calque, a name part rendered differently from the "
                            "NPC / faction it is named after (Bladefist Bay = Бухта Лязакулака, after Kargath "
                            "«Лязакулак»; lookup.py), wrong case/gender. Keep the capitals as they are (owner-reviewed). "
                            "Otherwise return be_current UNCHANGED."]})
    out.sort(key=lambda d: (d["en"].split()[-1].lower(), d["en"]))
    return out


CAP_OBJ = re.compile(r"(?<![А-ЯЁІЎа-яёіў])\d+ (?:[А-ЯЁІЎ][а-яёіў'-]+ ?){1,}")


def quests_capfix():
    """R136: quest objectives with Capitalised Common Nouns after a number («Прынясіце 12 Таблічак»)."""
    q_en = json.load(open(os.path.join(TB, "data", "classic", "quests_en.json"), encoding="utf-8"))
    corp = json.load(open(os.path.join(ROOT, "data", "be", "tb_quests.json"), encoding="utf-8"))
    out = []
    for k, e in sorted(corp.items()):
        qid, f = k.rsplit(".", 1)
        if f != "o" or not CAP_OBJ.search(e["be"]): continue
        out.append({"id": "tb:" + qid, "en": {"o": (q_en.get(qid) or {}).get("o", "")}, "be_current": {"o": e["be"]},
                    "fix": ["Belarusian capitalises only proper names: lower-case common nouns and adjectives "
                            "(«12 таблічак», «4 крывазубых ваўкоў»); keep NPC / place / faction / item proper names as they "
                            "are (check the English: a capital there on a generic word is only EN title style). Change "
                            "nothing else."],
                    "target": {"domain": "tb_quests", "keys": {"o": k}}})
    return out


SPELL_JUNK = re.compile(r"\((?:OLD|NYI|DND|Disabled|TEST|L\d)\)|\bTEST\b|\bQA\b|\bDEBUG\b|zz|Deprecated|\[PH\]")


def quests_update(pk_quests):
    """Re-scraped quests (owner 2026-10-01): a quest already translated is "done" by id, so fields the scraper found
    LATER (progress / completion) or whose English CHANGED since translation never reached the agent. One item per
    quest with only those fields; `be_context` = the quest's other Belarusian fields (names, tone), `be_current` = the
    old Belarusian of a changed field. Import MERGES the fields into the quest (strings_be.json)."""
    from wowhead_parse import strip_page_labels

    def same(a, b):
        # 2026-10-17: a re-scrape that only dropped the "Provided item:" heading or changed spacing / $B runs is not a change
        # (73 of 123 queued quests were just that)
        # R713 (2026-10-21): nor is wowhead rendering the objective-amount token as a number ("$2oa Iridescent Hammer" →
        # "1 Iridescent Hammer", 101 of 108 queued quests): the addon fills $Noa from the live text anyway
        n = lambda s: re.sub(r"\$\d*oa\b|\b\d+\b", "#", re.sub(r"\s+", " ", re.sub(r"(\$[Bb])+", " ", strip_page_labels(s))).strip())
        return n(a) == n(b)

    sbe = json.load(open(os.path.join(ROOT, "data", "strings_be.json"), encoding="utf-8"))
    was = {}                                                  # EN each done quest had when it was queued
    for f in glob.glob(os.path.join(OUT, "queue", "quests", "*.json")):
        if not os.path.exists(f.replace(os.sep + "queue" + os.sep, os.sep + "done" + os.sep)):
            continue
        for it in json.load(open(f, encoding="utf-8"))["items"]:
            was[it["id"]] = it.get("en") or {}
    out = []
    for q in pk_quests:
        be = sbe.get("quest:" + q["id"])
        if not be or q["id"] not in was:
            continue
        old = was[q["id"]]
        todo = {f: v for f, v in q["en"].items() if not be.get(f) or (f in old and not same(old[f], v))}
        if not todo:
            continue
        item = {"id": q["id"], "en": todo, "ru": {f: r for f, r in q.get("ru", {}).items() if f in todo},
                "be_context": {f: v for f, v in be.items() if f not in todo}}
        cur = {f: be[f] for f in todo if be.get(f)}
        if cur: item["be_current"] = cur
        out.append(item)
    return out


def quests_classic_update():
    """R721 (2026-10-22): the overnight scrape of every translated classic quest on wowhead's Forever pages
    (review/classic_quest_ids.txt) showed ~600 fields whose Forever English differs from the turtle-bel English we
    translated (Turtle's edited copy; Forever rewrote e.g. the Ashenvale Hunt completions) — the game cache agrees with
    Forever's text, never with ours. One item per quest with only those fields; `be_current` = our shipped Belarusian
    (reuse its wording where the meaning stayed). Import writes them into data/be tb_quests ONCE (re-pass target)."""
    wp = os.path.join(ROOT, "forever-data", "en", "quests.json")
    ip = os.path.join(ROOT, "review", "classic_quest_ids.txt")
    if not (os.path.exists(wp) and os.path.exists(ip)): return []
    wh = json.load(open(wp, encoding="utf-8"))
    ids = [l for l in open(ip, encoding="utf-8").read().split() if l.isdigit()]
    q_en = json.load(open(os.path.join(TB, "data", "classic", "quests_en.json"), encoding="utf-8"))
    corp = json.load(open(os.path.join(ROOT, "data", "be", "tb_quests.json"), encoding="utf-8"))
    names = {}                                            # R543: a player's name captured by wowhead -> $N
    pn = os.path.join(ROOT, "data", "player_names.tsv")
    for line in (open(pn, encoding="utf-8") if os.path.exists(pn) else []):
        if line.strip() and not line.startswith("#"):
            qid, f, nm = line.rstrip("\n").split("\t")[:3]; names[(qid, f)] = nm

    def norm(s):
        s = re.sub(r"\$[Gg]\s*([^:;$]*):([^;$]*);", r"\1/\2", s or "")        # $Ga:b; == wowhead's <a/b>
        s = re.sub(r"\$[Bb]", " ", re.sub(r"\$[Nn]", "$N", s))
        return re.sub(r"[^a-z0-9$/]+", " ", s.lower()).strip()       # spacing, punctuation, <…> markup: no change

    out = []
    for qid in ids:
        r = wh.get(qid) or {}
        if r.get("status") != "ok" or r.get("placeholder"): continue
        todo, cur = {}, {}
        for f in ("t", "o", "d", "p", "c"):
            new, old, key = r.get(f), (q_en.get(qid) or {}).get(f), "%s.%s" % (qid, f)
            if not new or not old or key not in corp: continue
            if (qid, f) in names:
                new = re.sub(r"(?<![\w'’])%s(?![\w'’])" % re.escape(names[(qid, f)]), "$N", new)
            new = re.sub(r"<([^<>/]*)/([^<>/]*)>", r"$G\1:\2;", new)          # wowhead gender pairs back to $G
            if norm(new) == norm(old): continue
            todo[f], cur[f] = new, corp[key]["be"]
        if todo:
            out.append({"id": "tb:" + qid, "en": todo, "be_current": cur,
                        "target": {"domain": "tb_quests", "keys": {f: "%s.%s" % (qid, f) for f in todo}},
                        "fix": ["WoW Forever's English for these fields differs from the text be_current was translated "
                                "from: translate the NEW English. Keep be_current's wording, names and tone where the "
                                "meaning is unchanged; change what the English changed (numbers, places, whole new lines)"]})
    return out


def spellnames_redo2():
    """R145: every other shipped spell name (NPC abilities, auras, item effects — ~8k, same bulk Sonnet source as R132).
    Same shape and import as spellnames_redo ({EN: BE}); internal/test names left out."""
    corp = json.load(open(os.path.join(ROOT, "data", "be", "spell_names.json"), encoding="utf-8"))
    first = {d["en"] for d in spellnames_redo()}
    ru = {r[0]: r[4] for r in tsv(os.path.join(ROOT, "out", "db2", "SpellName.tsv"))}
    desc = {}
    for r in tsv(os.path.join(ROOT, "out", "db2", "Spell.tsv")):
        if r[1] == "Description_lang": desc.setdefault(r[0], r[3])
    by_en = {}
    for sid, e in sorted(corp.items(), key=lambda kv: int(kv[0])):
        en = e["en"]
        if en in first or junk(en) or SPELL_JUNK.search(en): continue
        d = by_en.setdefault(en, {"id": md5(en, 10), "en": en, "ru": ru_ok(en, ru.get(sid, "")), "forms": Counter(), "spells": []})
        d["forms"][e["be"]] += 1
        if len(d["spells"]) < 3: d["spells"].append(int(sid))
        if "desc" not in d and desc.get(sid): d["desc"] = desc[sid][:220]
    out = []
    for d in sorted(by_en.values(), key=lambda d: d["en"]):
        d["be_current"] = d.pop("forms").most_common(1)[0][0]
        d["fix"] = ["be_current is a weak machine draft: give the spell a natural Belarusian name (glossary + decisions win; "
                    "sentence case; the same English word = the same Belarusian word across spells); keep it only where "
                    "it is already right"]
        out.append(d)
    return out


def spelldesc_redo():
    """R145: shipped spell descriptions (turtle-bel, bulk Sonnet): meaning right, wording drifts (урон/шкода/пашкоджанні,
    Thorns «Калючкі» vs the spell «Шыпы», Rank = «узровень»). Key = the md5 keyspace; import -> auto_spelldesc.json
    (wins over turtle-bel; data/be hand edits and spelldesc_fix.tsv still win)."""
    corp = json.load(open(os.path.join(ROOT, "data", "be", "spell_desc.json"), encoding="utf-8"))
    en = {r[0]: r[1] for r in tsv(os.path.join(TB, "spelldesc", "todo.tsv"))}
    fixp = os.path.join(ROOT, "data", "spelldesc_fix.tsv")
    fixed = {r[0] for r in tsv(fixp)} if os.path.exists(fixp) else set()
    names = json.load(open(os.path.join(ROOT, "data", "be", "spell_names.json"), encoding="utf-8"))
    sname = {r[0]: r[3] for r in tsv(os.path.join(ROOT, "out", "db2", "SpellName.tsv"))}
    ru, spell_of = {}, {}
    for r in tsv(os.path.join(ROOT, "out", "db2", "Spell.tsv")):
        if r[1] in ("Description_lang", "AuraDescription_lang"):
            k = md5(r[3]); ru.setdefault(k, ru_ok(r[3], r[4])); spell_of.setdefault(k, r[0])
    out = []
    for k, e in sorted(corp.items()):
        if k not in en or k in fixed: continue
        d = {"id": k, "en": en[k], "ru": ru.get(k, ""), "be_current": e["be"]}
        d["fix"] = ["be_current is an old draft whose wording drifts: rewrite it to data/STYLE_RULES + decisions + glossary "
                    "(damage = урон, Rank N = ранг N, spell names in «» exactly as the spell is called — terms.py / glossary; "
                    "resistance = супраціўленне агню / марозу / прыродзе / цемры / аркане / святлу); same meaning, all $tokens kept"]
        sid = spell_of.get(k)
        if sid and sname.get(sid):
            d["name"] = sname[sid] + (" = " + names[sid]["be"] if sid in names else "")
        out.append(d)
    return out


def speaker_repass():
    """R42 speaker-gender QA (tools/speaker_gender.py -> out/speaker_gender.json): the NPC speaking a quest text is
    female (or male) per the RU text, but the BE first-person forms say the other. The agent switches only the
    speaker's own first-person forms; import writes the field straight into data/be/ like quests_address."""
    p = os.path.join(ROOT, "out", "speaker_gender.json")
    if not os.path.exists(p): return []
    groups = {}
    for r in json.load(open(p, encoding="utf-8")):
        g = groups.setdefault((r["domain"], r["qid"]), {"en": {}, "be": {}, "keys": {}, "fix": set(), "ru": {}})
        g["be"][r["field"]] = r["be"]; g["keys"][r["field"]] = r["key"]; g["ru"][r["field"]] = r["ru"]
        g["fix"].add(("field " + r["field"] + ": the NPC speaking it is %s (" + r.get("source", "RU") + "): every first-person form of the speaker "
                      "(я …) must be %s; verbs of other people (ты, he, a third party) stay as they are")
                     % (("FEMALE", "feminine") if r["speaker"] == "f" else ("MALE", "masculine")))
    q_en = json.load(open(os.path.join(TB, "data", "classic", "quests_en.json"), encoding="utf-8"))
    f_en = json.load(open(os.path.join(ROOT, "data", "strings_en.json"), encoding="utf-8"))
    out = []
    for (dom, qid), g in sorted(groups.items()):
        src = q_en.get(qid, {}) if dom == "tb_quests" else f_en.get("quest:" + qid, {})
        out.append({"id": ("tb:" if dom == "tb_quests" else "fv:") + qid, "en": {f: src.get(f, "") for f in g["be"]},
                    "ru": g["ru"], "be_current": g["be"], "fix": sorted(g["fix"]),
                    "target": {"domain": dom, "keys": g["keys"]}})
    return out


def unify_repass(name="name_unify_repass.json"):
    """R33 name check (tools/name_unify.py -> out/name_unify_repass.json): quest titles / objectives that word an item
    or NPC differently from its own (final) name. The agent rewrites each listed field with that name, declined to
    fit, and changes nothing else; import writes it straight into data/be/ like quests_address."""
    p = os.path.join(ROOT, "out", name)
    if not os.path.exists(p): return []
    def load(dom):
        f = os.path.join(ROOT, "data", "be", dom + ".json")
        return json.load(open(f, encoding="utf-8")) if os.path.exists(f) else {}
    corp = {"tb_quests": load("tb_quests"), "forever": load("forever")}
    q_en = json.load(open(os.path.join(TB, "data", "classic", "quests_en.json"), encoding="utf-8"))
    f_en = json.load(open(os.path.join(ROOT, "data", "strings_en.json"), encoding="utf-8"))
    out = []
    for g in json.load(open(p, encoding="utf-8")):
        dom, qid, keys = g["domain"], g["qid"], g["keys"]
        be = {f: corp[dom][k]["be"] for f, k in keys.items() if k in corp[dom]}
        if not be: continue
        src = q_en.get(qid, {}) if dom == "tb_quests" else f_en.get("quest:" + qid, {})
        out.append({"id": ("tb:" if dom == "tb_quests" else "fv:") + qid, "en": {f: src.get(f, "") for f in be},
                    "be_current": be, "fix": g["fix"], "target": {"domain": dom, "keys": keys}})
    return out


def address_repass():
    """FINAL quest texts (data/be/: WoWBY vanilla tb_quests + Forever) with a word about the player in the masculine
    only — owner 2026-09-28 («Рады, што ты сёння знайшоў…» for a female character). The agent adds $G forms;
    import writes the result straight back into data/be/ as hand edits."""
    def load(dom):
        p = os.path.join(ROOT, "data", "be", dom + ".json")
        return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}
    q_en = json.load(open(os.path.join(TB, "data", "classic", "quests_en.json"), encoding="utf-8"))
    f_en = json.load(open(os.path.join(ROOT, "data", "strings_en.json"), encoding="utf-8"))
    groups = {}                                              # item id -> (domain, qid, {field: key})
    for dom, prefix in (("tb_quests", ""), ("forever", "quest:")):
        for key in load(dom):
            if prefix and not key.startswith(prefix):
                continue
            qid, _, f = key[len(prefix):].partition(".")
            if f in ("t", "o", "d", "p", "c"):
                groups.setdefault(("tb:" if not prefix else "fv:") + qid, (dom, qid, {}))[2][f] = key
    out = []
    corp = {"tb_quests": load("tb_quests"), "forever": load("forever")}
    for iid, (dom, qid, keys) in sorted(groups.items()):
        be = {f: corp[dom][k]["be"] for f, k in keys.items()}
        hits = sorted({m.group(1) for v in be.values() for m in ADDR.finditer(v) if m.group(1) not in ADDR_NOT})
        if not hits:
            continue
        src = q_en.get(qid, {}) if dom == "tb_quests" else f_en.get("quest:" + qid, {})
        en = {f: src.get(f) for f in be if src.get(f)}
        out.append({"id": iid, "en": en or {f: "" for f in be}, "be_current": be,
                    "fix": ["player-gender forms missing for: " + ", ".join(hits)],
                    "target": {"domain": dom, "keys": keys}})
    return out


def natural_done(pkg):
    """R714 (owner 2026-10-21): the naturalness re-pass is part of the first translation now (AGENTS.md); quests_natural /
    gossip_natural keep only the items of chunks already finished, so lines translated later never queue a second pass."""
    ids = set()
    for qf in glob.glob(os.path.join(OUT, "queue", pkg, "*.json")):
        if os.path.exists(os.path.join(OUT, "done", pkg, os.path.basename(qf))):
            ids |= {it["id"] for it in json.load(open(qf, encoding="utf-8"))["items"]}
    return ids


def quests_natural():
    """R230: every FINAL quest description / progress / completion (classic WoWBY first, then Forever), one item per
    quest with all its prose fields; the agent rewrites only unnatural sentences. Import writes into data/be."""
    def load(dom):
        p = os.path.join(ROOT, "data", "be", dom + ".json")
        return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}
    q_en = json.load(open(os.path.join(TB, "data", "classic", "quests_en.json"), encoding="utf-8"))
    f_en = json.load(open(os.path.join(ROOT, "data", "strings_en.json"), encoding="utf-8"))
    groups = {}
    for dom, prefix in (("tb_quests", ""), ("forever", "quest:")):
        corp = load(dom)
        for key in corp:
            if prefix and not key.startswith(prefix): continue
            qid, _, f = key[len(prefix):].partition(".")
            if f in ("d", "p", "c"):
                groups.setdefault((0 if dom == "tb_quests" else 1, int(qid) if qid.isdigit() else 0, dom, qid), {})[f] = key
    out = []
    for (_, _, dom, qid), keys in sorted(groups.items()):
        corp = load_cache.setdefault(dom, load(dom))
        src = q_en.get(qid, {}) if dom == "tb_quests" else f_en.get("quest:" + qid, {})
        en = {f: src.get(f) for f in keys if src.get(f)}
        if not en: continue                                   # no English to compare with (Turtle-only quest)
        be = {f: corp[k]["be"] for f, k in keys.items() if f in en}
        out.append({"id": ("tb:" if dom == "tb_quests" else "fv:") + qid, "en": en, "be_current": be,
                    "fix": ["NATURALNESS PASS (owner 2026-10-08): read be_current as a Belarusian player would. Rewrite ONLY what sounds translated: calques, word-by-word order, Russianisms, stiff or bookish phrasing, idioms rendered literally (\"funny business\" ≠ «нешта падазронае»), lifeless dialogue — give the speaker a living voice. Keep the meaning, every token ($N $G…; $B $1oa), names and glossary terms. Never shorten, never add content. If it already reads naturally, return be_current UNCHANGED (most texts should come back unchanged)."], "target": {"domain": dom, "keys": {f: keys[f] for f in be}}})
    keep = natural_done("quests_natural")
    return [it for it in out if it["id"] in keep]


load_cache = {}


def gossip_natural():
    """R230: Forever gossip / NPC speech (data/be forever "gossip:") — same naturalness pass, one line per item."""
    corp = json.load(open(os.path.join(ROOT, "data", "be", "forever.json"), encoding="utf-8"))
    # the key holds only the first 80 chars (+ "#hash" on a collision, R312): the full EN comes from strings_en
    full = {k: e.get("v") for k, e in json.load(open(os.path.join(ROOT, "data", "strings_en.json"),
                                                      encoding="utf-8")).items() if k.startswith("gossip:")}
    # item ids = md5 of the OLD key (R325 moved the keys to the full text): finished done/ files keep matching
    km = os.path.join(ROOT, "data", "gossip_keymap.json")
    old_of = {new: old for old, new in (json.load(open(km, encoding="utf-8")) if os.path.exists(km) else {}).items()}
    out = []
    for key, e in sorted(corp.items()):
        if not key.startswith("gossip:") or not isinstance(e.get("be"), str): continue
        en = full.get(key) or key[len("gossip:"):].split("#")[0]
        out.append({"id": md5(old_of.get(key, key), 10), "en": en, "be_current": e["be"], "fix": ["NATURALNESS PASS (owner 2026-10-08): read be_current as a Belarusian player would. Rewrite ONLY what sounds translated: calques, word-by-word order, Russianisms, stiff or bookish phrasing, idioms rendered literally (\"funny business\" ≠ «нешта падазронае»), lifeless dialogue — give the speaker a living voice. Keep the meaning, every token ($N $G…; $B $1oa), names and glossary terms. Never shorten, never add content. If it already reads naturally, return be_current UNCHANGED (most texts should come back unchanged)."],
                    "target": {"domain": "forever", "keys": {"v": key}}})
    keep = natural_done("gossip_natural")
    return [it for it in out if it["id"] in keep]


def gender_repass():
    """Finished quests whose text needs player-gender forms: the source had wowhead "<male/female>" pairs (EN or
    RU — Russian marks gender far more often, and Belarusian needs it where Russian does). The agent rewrites
    them with $G…:…; — the old validator rejected any $G the English lacked."""
    out = []
    for qf in sorted(glob.glob(os.path.join(OUT, "queue", "quests", "*.json"))):
        df = os.path.join(OUT, "done", "quests", os.path.basename(qf))
        if not os.path.exists(df): continue
        done = json.load(open(df, encoding="utf-8"))["items"]
        for it in json.load(open(qf, encoding="utf-8"))["items"]:
            be = done.get(it["id"])
            if not be: continue
            texts = list(it["en"].values()) + list((it.get("ru") or {}).values()) + list(be.values())
            if any(GPAIR.search(t or "") for t in texts):
                out.append({"id": it["id"], "en": {f: gender_tokens(v) for f, v in it["en"].items()},
                            "ru": {f: gender_tokens(v) for f, v in (it.get("ru") or {}).items()},
                            "be_current": {f: gender_tokens(v) for f, v in be.items()}})
    return out


def tb_glossary_lines(path):
    """turtle-bel's glossary lines, repaired here (R769; turtle-bel itself is not edited from this project): rows that lost
    their line break are split ("…Бронзабарод" + "Stormreaver\t…", "user" + "Prospector\t…", a BE cell + "# --- comment"),
    and a QA-triage row whose BE cell is an escaped copy of other rows is dropped."""
    out = []
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.startswith("#"):
            if "\\t" in line: continue
            i = line.find("# ---")
            if i > 0: line, comment = line[:i], line[i:]
            else: comment = None
            parts = re.split(r"(?<=[а-яёіўa-z])(?=[A-Z][A-Za-z' -]*\t)", line) if line.count("\t") > 2 else [line]
            out += parts
            if comment: out.append(comment)
        else:
            out.append(line)
    return out


def reference_files(rules):
    """Name/term memory for tools/terms.py: glossary + already-translated names/zones/UI."""
    from build_addon import fix_terms                     # owner decisions (Штармавей, Даланаар…) apply to references
    with open(os.path.join(rules, "glossary.tsv"), "w", encoding="utf-8", newline="\n") as f:
        owner_rows = open(os.path.join(ROOT, "data", "glossary_forever.tsv"), encoding="utf-8").read().splitlines()[1:]
        owner_en = {r.split("\t")[0] for r in owner_rows if r.strip()}
        for line in tb_glossary_lines(os.path.join(TB, "pipeline", "glossary.tsv")):
            p = line.split("\t")
            if not line.startswith("#") and len(p) >= 2:
                if p[0] in owner_en: continue             # an owner row overrides it (R250: Thistlefur qa vs owner)
                p[1] = fix_terms(p[1])
            f.write("\t".join(p) + "\n")
        f.write("# --- WoW Forever owner terms (data/glossary_forever.tsv) — these win ---\n")
        for line in owner_rows:
            if line.strip(): f.write(line + "\n")
    # R749 (owner 2026-10-26): the Belarusian rules come from the parallel-localization SKILL on every run (single
    # source: a correction there reaches every project) — brief rules (the short list) + the full reference — plus
    # the WoW-only addendum (goblin / gnome surnames, $ tokens). Before: a turtle-bel copy that still said
    # "unstressed э → а in every name" (wrong, official §4.3–4.6).
    skill_ref = os.path.join(os.path.expanduser("~"), ".claude", "skills", "parallel-localization", "references")
    parts = [os.path.join(skill_ref, "belarusian-brief-rules.md"), os.path.join(skill_ref, "belarusian-orthography.md"),
             os.path.join(ROOT, "data", "BELARUSIAN_RULES_wow.md")]
    if all(os.path.exists(p) for p in parts):
        with open(os.path.join(rules, "BELARUSIAN_RULES.md"), "w", encoding="utf-8", newline="\n") as f:
            f.write("<!-- GENERATED by tools/prepare_translate.py from the parallel-localization skill + "
                    "data/BELARUSIAN_RULES_wow.md — do not edit here -->\n\n")
            f.write("\n\n---\n\n".join(open(p, encoding="utf-8").read().strip() for p in parts) + "\n")
    else:                                                  # skill missing on this machine: the old turtle-bel copy
        shutil.copy2(os.path.join(TB, "BELARUSIAN_RULES.md"), os.path.join(rules, "BELARUSIAN_RULES.md"))
    shutil.copy2(os.path.join(ROOT, "data", "STYLE_RULES.md"), os.path.join(rules, "STYLE_RULES.md"))
    # R250 (2026-10-08): memory = what SHIPS (data/be corpus: hand > forever > turtle-bel), so owner renames
    # (names_fix, word_fix, hand edits) reach the translator; raw turtle-bel had «Дзяружнасты мядзведзь».
    def corpus(dm):
        f = os.path.join(ROOT, "data", "be", dm + ".json")
        return json.load(open(f, encoding="utf-8")) if os.path.exists(f) else {}
    names, zones = {}, {}
    for en, e in corpus("tb_names").items(): names[en] = e["be"]
    for en, e in corpus("tb_zones").items(): zones[en] = e["be"]
    for dm in ("forever", "hand"):
        for k, e in corpus(dm).items():
            kind, _, en = k.partition(":")
            if kind == "name": names[en] = e["be"]
            elif kind == "zone": zones[en] = e["be"]
    mem = [(en, be, "npc") for en, be in names.items()] + [(en, be, "zone") for en, be in zones.items()]
    for en, e in corpus("ui").items():
        if isinstance(e.get("be"), str) and e["be"] and len(en) <= 60 and "%" not in en and "\n" not in en:
            mem.append((en, e["be"], "ui"))
    # 2026-10-22: shipped ITEM and SPELL names too (agents translating items wrote their own grep helpers over
    # translations/ to see how a «Band» / «Greaves» had been named). By EN; several BE for one EN → the most common.
    def by_en(pairs):
        c = {}
        for en, be in pairs:
            if en and isinstance(be, str) and be: c.setdefault(en, Counter())[be] += 1
        return {en: cnt.most_common(1)[0][0] for en, cnt in c.items()}
    it_en = {r[0]: r[1] for r in tsv(os.path.join(TB, "items", "todo.tsv")) if len(r) > 1}
    it_en.update({r[0]: r[3] for r in tsv(os.path.join(ROOT, "out", "db2", "ItemSparse.tsv")) if r[1] == "Display_lang"})
    sp_en = {r[0]: r[3] for r in tsv(os.path.join(ROOT, "out", "db2", "SpellName.tsv"))}
    items = by_en([(it_en.get(k), e.get("be")) for k, e in corpus("items").items()]
                  + [(k, e.get("be")) for k, e in corpus("item_names").items()])
    spells = by_en([(sp_en.get(k), e.get("be")) for k, e in corpus("spell_names").items()]
                   + [(k, e.get("be")) for k, e in corpus("spell_names_en").items()])
    for k, e in corpus("hand").items():                   # owner name fixes win
        kind, _, en = k.partition(":")
        if kind == "itemname": items[en] = e["be"]
        elif kind == "spellname": spells[en] = e["be"]
    mem += [(en, be, "item") for en, be in items.items()] + [(en, be, "spell") for en, be in spells.items()]
    with open(os.path.join(rules, "memory.tsv"), "w", encoding="utf-8", newline="\n") as f:
        f.write("en\tbe\tkind\n")
        for en, be, kind in mem:
            be = fix_terms(be)
            f.write("%s\t%s\t%s\n" % (en.replace("\t", " ").replace("\n", " "), be.replace("\t", " ").replace("\n", " "), kind))
    # style examples: 6 finished WoWBY quests (EN + BE) to match tone and token handling
    q_en = json.load(open(os.path.join(TB, "data", "classic", "quests_en.json"), encoding="utf-8"))
    q_be = json.load(open(os.path.join(TB, "data", "classic", "quests_be.json"), encoding="utf-8"))
    ex = []
    for qid in ("783", "7", "33", "921", "2159", "4161"):
        if qid in q_en and qid in q_be:
            ex.append({"id": qid, "en": {f: q_en[qid][f] for f in "todpc" if q_en[qid].get(f)},
                       "be": {f: q_be[qid][f] for f in "todpc" if q_be[qid].get(f)}})
    from build_addon import fix_terms                     # owner decisions (Штармавей, Жалезнакузня…) apply here too
    for e in ex:
        e["be"] = {f: fix_terms(v) for f, v in e["be"].items()}
    json.dump(ex, open(os.path.join(rules, "examples_quests.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return len(mem)


def payload(it):
    """Characters of one queue item as the agent reads it (the chunk-size measure)."""
    return len(json.dumps(it, ensure_ascii=False))


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    rules = os.path.join(OUT, "rules")
    for d in ("queue", "done", "rules", "tools"):
        os.makedirs(os.path.join(OUT, d), exist_ok=True)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    nmem = reference_files(rules)
    if "--refs" in sys.argv:                              # refresh rules/glossary + memory only (safe while Gemini runs)
        print("rules refreshed: memory %d rows" % nmem); return
    pk, skipped = collect()
    summary = []
    only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None
    for pkg in ORDER:
        if only and pkg not in only: continue           # add/refresh one package without touching the others
        items = pk[pkg]
        qd, dd = os.path.join(OUT, "queue", pkg), os.path.join(OUT, "done", pkg)
        os.makedirs(qd, exist_ok=True); os.makedirs(dd, exist_ok=True)
        done_ids = set()
        share = UI_PKGS if pkg in UI_PKGS else [pkg]
        for sp in share:
            sd = os.path.join(OUT, "done", sp)
            for fn in (os.listdir(sd) if os.path.isdir(sd) else []):
                try: done_ids |= set(json.load(open(os.path.join(sd, fn), encoding="utf-8")).get("items", {}))
                except Exception: pass
        for fn in os.listdir(qd):                         # rebuild pending chunks; keep chunks already done
            if not os.path.exists(os.path.join(dd, fn)): os.remove(os.path.join(qd, fn))
        existing = {int(fn.split("_")[-1][:4]) for fn in os.listdir(qd)}
        todo = [it for it in items if it["id"] not in done_ids]
        n, size = max(existing, default=0), MAX_ITEMS
        groups, cur, chars = [], [], 0
        for it in todo:                                   # ~MAX_CHARS of item JSON each (at most MAX_ITEMS items)
            c = payload(it)
            if cur and (len(cur) >= size or chars + c > MAX_CHARS):
                groups.append(cur); cur, chars = [], 0
            cur.append(it); chars += c
        if cur: groups.append(cur)
        # a small leftover goes into the previous chunk (up to 30% over the limits): every chunk costs a sub-agent run
        # that re-reads ~62 KB of rules, so a 2-item tail chunk (titles_0004, 2026-10-07) cost as much as a full one
        if len(groups) >= 2:
            tail, prev = groups[-1], groups[-2]
            tchars = sum(payload(it) for it in tail)
            pchars = sum(payload(it) for it in prev)
            if len(prev) + len(tail) <= size * 1.3 and pchars + tchars <= MAX_CHARS * 1.3:
                groups[-2] = prev + tail; groups.pop()
        for g in groups:
            n += 1
            name = "%s_%04d" % (pkg, n)
            head = {"package": pkg, "chunk": name}
            # budget (2026-09-30): a fix/note shared by every item is written once per chunk, not per item (~25% of
            # the queue was that repetition); import derives names_qa / quests_capfix targets itself
            g = [dict(it) for it in g]
            for k in ("fix", "note"):
                vals = {json.dumps(it.get(k), ensure_ascii=False) for it in g}
                if len(vals) == 1 and g[0].get(k):
                    head[k + "_all"] = g[0][k]
                    for it in g: it.pop(k, None)
            if pkg in ("names_qa", "quests_capfix"):
                for it in g: it.pop("target", None)
            json.dump(dict(head, items=g),
                      open(os.path.join(qd, name + ".json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        summary.append((pkg, len(items), len(todo), len(os.listdir(qd))))
    with open(os.path.join(OUT, "skipped.tsv"), "w", encoding="utf-8", newline="\n") as f:
        f.write("package\tid\ten\n")
        for p, i, en in skipped: f.write("%s\t%s\t%s\n" % (p, i, str(en).replace("\t", " ").replace("\n", " ")))
    print("memory entries: %d | skipped junk: %d" % (nmem, len(skipped)))
    for pkg, total, todo, chunks in summary:
        print("  %-11s %6d strings, %6d to translate, %4d chunk files" % (pkg, total, todo, chunks))


if __name__ == "__main__":
    main()
