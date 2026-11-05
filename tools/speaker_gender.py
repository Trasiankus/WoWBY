"""Speaker-gender QA for quest texts (R42, owner 2026-09-29: «прасіў» from a female NPC → «прасіла»; "source RU for
all quests to support gender QA").

    python tools/speaker_gender.py          -> out/speaker_gender.json + counts

The quest giver / turn-in NPC speaks the description, progress and completion texts in the first person. Russian
past-tense verbs and short adjectives show the speaker's gender («я просила», «я рада»), so the RU text of the same
quest (forever-data/ru/quests.json — wowhead, scraped by the owner: `forever_scraper.py --todo wowby --lang ru`
covers every quest WoWBY translated) tells whether the BE text got it right. A field is flagged when RU is clearly
one gender and the BE first-person forms are the other. Flagged fields go to the translate re-pass "quests_speaker"
(prepare_translate): the agent switches the speaker's first-person forms only."""
import json, os, re, sys, collections

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
FIELDS = ("d", "p", "c")

# first person = «я» then up to 5 words in the same clause, then the gendered form
RU_F = re.compile(r"(?i)\bя\b(?:[^.!?;:\n]{0,40}?)\b(\w+ла|рада|должна|готова|благодарна|уверена|сама|одна)\b")
RU_M = re.compile(r"(?i)\bя\b(?:[^.!?;:\n]{0,40}?)\b(\w+[^aеиоуыэюяё\W]л|рад|должен|готов|благодарен|уверен|сам|один)\b")
BE_F = re.compile(r"(?i)\bя\b(?:[^.!?;:\n$]{0,40}?)\b([а-яёіў]+ла|рада|павінна|гатовая|удзячная|упэўненая|сама|адна)\b")
BE_M = re.compile(r"(?i)\bя\b(?:[^.!?;:\n$]{0,40}?)\b([а-яёіў]+ў|рады|павінен|гатовы|удзячны|упэўнены|сам|адзін)\b")
RU_NOT = {"была", "мала", "сила", "стала"}          # frequent words ending -ла that are not a speaker's verb
BE_NOT = {"сіла", "мала", "была", "стала", "зямля", "хвала"}


def gender(text, fem, masc, notset):
    f = sum(1 for m in fem.finditer(text) if m.group(1).lower() not in notset)
    m = sum(1 for m in masc.finditer(text))
    return "f" if f and not m else "m" if m and not f else None


SQL = r"C:\Projects\custom-wow\penqle-tortoise\sql\base"
DB_FIELDS = {"d": 18, "c": 36, "p": 45}     # locales_quest loc8 columns: Details / OfferRewardText / RequestItemsText


def local_db():
    """R61: the local classic world DB (vmangos-based Turtle dump, read-only). Returns
    ru {qid: {d, p, c}} from locales_quest loc8 and sex {(qid, field): "f"/"m"} of the NPC who speaks the field: the quest
    giver for the description, the turn-in NPC for progress/completion; sex from every display id of the creature
    (creature_display_info_addon.gender 0 = male, 1 = female) — only when all its NPCs/models agree."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from import_broadcast import rows
    tab = lambda t: rows(os.path.join(SQL, "tw_world_%s.sql" % t), t)
    ru = {}
    for v in tab("locales_quest"):
        q = {f: (v[i] or "") for f, i in DB_FIELDS.items() if i < len(v) and v[i]}
        if q: ru[v[0]] = q
    model = {v[0]: v[3] for v in tab("creature_display_info_addon")}
    npc = {}
    for v in tab("creature_template"):
        gs = {model.get(d) for d in v[1:5] if d and d != "0"} - {None}
        npc[v[0]] = {"0": "m", "1": "f"}.get(gs.pop()) if len(gs) == 1 else None
    sex = {}
    for t, fields in (("creature_questrelation", ("d",)), ("creature_involvedrelation", ("p", "c"))):
        for v in tab(t):
            for f in fields:
                sex.setdefault((v[1], f), set()).add(npc.get(v[0]))
    return ru, {k: s.pop() for k, s in sex.items() if len(s) == 1 and None not in s}


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ru = json.load(open(os.path.join(ROOT, "forever-data", "ru", "quests.json"), encoding="utf-8"))
    ru_db, npc_sex = local_db()
    for qid, q in ru_db.items():                  # the scrape wins where it has the field
        cur = ru.setdefault(qid, {})
        if isinstance(cur, dict):
            for f, t in q.items(): cur.setdefault(f, t)
    be = {}
    for dom, pre in (("tb_quests", ""), ("forever", "quest:")):
        for k, e in json.load(open(os.path.join(ROOT, "data", "be", dom + ".json"), encoding="utf-8")).items():
            if pre and not k.startswith(pre):
                continue
            qid, _, f = k[len(pre):].partition(".")
            if f in FIELDS:
                be[(qid, f)] = (dom, k, e["be"])
    out, c = [], collections.Counter()
    for (qid, f), b in sorted(be.items()):
        q = ru.get(qid)
        rt = q.get(f, "") if isinstance(q, dict) else ""
        rg = gender(rt, RU_F, RU_M, RU_NOT) if rt else None
        ng = npc_sex.get((qid, f))
        bg = gender(b[2].replace("$B", " "), BE_F, BE_M, BE_NOT)
        if not bg:
            continue
        c["checked"] += 1
        if rg and ng and rg != ng:
            c["npc/RU disagree (skipped)"] += 1        # letters, a third party speaking… — leave to a human
            continue
        sp = ng or rg
        if sp and sp != bg:
            c["mismatch_" + sp] += 1
            c["by " + ("npc+ru" if ng and rg else "npc" if ng else "ru")] += 1
            out.append({"domain": b[0], "qid": qid, "key": b[1], "field": f, "speaker": sp,
                        "source": "npc model + RU" if ng and rg else "npc model" if ng else "RU", "ru": rt[:600], "be": b[2]})
    json.dump(out, open(os.path.join(ROOT, "out", "speaker_gender.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("RU quests: %d (local DB %d); NPC sex known for %d fields; BE fields with first-person forms: %d"
          % (len(ru), len(ru_db), len(npc_sex), c["checked"]))
    print("speaker female but BE masculine: %d; male but BE feminine: %d -> out/speaker_gender.json" % (c["mismatch_f"], c["mismatch_m"]))
    print({k: v for k, v in c.items() if k.startswith("by ") or "skipped" in k})


if __name__ == "__main__":
    main()
