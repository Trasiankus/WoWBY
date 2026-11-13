"""R229: reviewable JSON of the final Belarusian text, Trasiankus repo format:
    translations/<domain>.json  =  { key: {"en": …, "ru": …, "bel": …} }   (2-space indent, UTF-8, sorted keys)
Built from data/be/<domain>.json (the shipped text) + EN / RU from our sources (client DB2 dump, wowhead / harvest diff,
turtle-bel EN, GlobalStrings). Read-only view: hand fixes still go into data/be (fix_corpus / build keep them).
    python tools/export_review.py"""
import csv, glob, json, os, sys
sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TB = r"C:\Projects\WoW\turtle-bel"
OUT = os.path.join(ROOT, "translations")
csv.field_size_limit(10 ** 9)


def tsv(p):
    if not os.path.exists(p): return []
    return list(csv.reader(open(p, encoding="utf-8"), delimiter="\t", quoting=csv.QUOTE_NONE))[1:]


def db2(table, field):
    en, ru = {}, {}
    for r in tsv(os.path.join(ROOT, "out", "db2", table + ".tsv")):
        if len(r) > 4 and r[1] == field and r[2] == "0":
            en[r[0]] = r[3]; ru[r[0]] = r[4]
    return en, ru


ID_DOMAINS = {"tb_quests", "quests", "items", "spell_names"}         # keyed by game ids -> {id: {...}} JSON; the rest are keyed by
                                                          # their own English text -> one {"en","ru","bel"} per line (.jsonl)


def book_titles():
    """R257: page text key -> "<book title> #<page>" (title = the item / object that opens the first page; pages follow
    page_text.next). Same title for different books -> the first page id is added. Pages no book reaches: "page <id>"."""
    from import_broadcast import rows, SQL
    from build_addon import book_key
    text, nxt = {}, {}
    for v in rows(os.path.join(SQL, "tw_world_page_text.sql"), "page_text"):
        pid = int(v[0]); text[pid] = book_key(v[1] or ""); nxt[pid] = int(v[2] or 0)
    starts = []
    for v in rows(os.path.join(SQL, "tw_world_item_template.sql"), "item_template"):
        if len(v) > 108 and int(v[108] or 0): starts.append((v[3], int(v[108])))
    for v in rows(os.path.join(SQL, "tw_world_gameobject_template.sql"), "gameobject_template"):
        t = int(v[1] or 0)
        pid = int(v[7] or 0) if t == 9 else (int(v[14] or 0) if t == 10 and len(v) > 14 else 0)
        if pid: starts.append((v[3], pid))
    seen_title, out = {}, {}
    for title, first in sorted(starts, key=lambda s: s[1]):
        if first in seen_title.values() or first not in text: continue
        name = title if title not in seen_title else "%s (%d)" % (title, first)
        seen_title[name] = first
        pid, n, guard = first, 1, set()
        while pid and pid in text and pid not in guard:
            guard.add(pid)
            out.setdefault(text[pid], "%s #%d" % (name, n))
            pid, n = nxt.get(pid, 0), n + 1
    for pid, t in text.items(): out.setdefault(t, "page %d" % pid)
    ru = {int(v[0]): (v[9] or "").replace("\r", "") for v in rows(os.path.join(SQL, "tw_world_locales_page_text.sql"),
                                                                  "locales_page_text")}
    ru = {text[pid]: r for pid, r in ru.items() if pid in text and r}
    return out, ru


def collect(parked=False):
    """{domain: {corpus key: {"en", "ru", "bel"}}} for every data/be domain (also the QA chunker, qa/tools);
    parked=True: data/be_parked (text Forever cannot show, R718)."""
    os.makedirs(OUT, exist_ok=True)
    s_en = json.load(open(os.path.join(ROOT, "data", "strings_en.json"), encoding="utf-8"))
    q_en = {}                                             # R260: classic + tbc + turtle (9.4k fields had no EN)
    for b in ("turtle", "tbc", "classic"):
        p = os.path.join(TB, "data", b, "quests_en.json")
        if os.path.exists(p): q_en.update(json.load(open(p, encoding="utf-8")))
    # R964 (owner 2026-11-13: "use the fresh source, stop using Turtle"): the live Forever English from wowhead
    # (forever-data/en/quests.json) wins field by field; turtle-bel's EN had Turtle's own rewrites (6503.c)
    fp = os.path.join(ROOT, "forever-data", "en", "quests.json")
    if os.path.exists(fp):
        for qid, v in json.load(open(fp, encoding="utf-8")).items():
            if isinstance(v, dict) and v.get("status") == "ok" and not v.get("placeholder"):
                d = q_en.setdefault(str(qid), {})
                for f in ("t", "o", "d", "p", "c"):
                    if v.get(f): d[f] = v[f]
    # R260: RU for text-keyed domains: every client DB2 string (EN -> RU, items / spells / zones / factions…) +
    # Questie's ruRU NPC names
    ALL = {}
    for p in glob.glob(os.path.join(ROOT, "out", "db2", "*.tsv")):
        for r in tsv(p):
            if len(r) > 4 and r[3] and r[4] and r[3] not in ALL: ALL[r[3]] = r[4]
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        from questie_names import load as questie
        for v in questie().values():
            if v["en"] and v["ru"]: ALL.setdefault(v["en"], v["ru"])
    except Exception as e:
        print("questie names skipped:", e)
    gs_ru = {}
    for r in tsv(os.path.join(ROOT, "out", "globalstrings_keys.tsv")):
        if len(r) > 2: gs_ru.setdefault(r[1].replace("\\n", "\n"), r[2].replace("\\n", "\n"))
    # classic quests: RU from the local world DB (locales_quest loc8; same source as tools/speaker_gender.py)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from import_broadcast import rows, SQL
    q_ru = {}
    for v in rows(os.path.join(SQL, "tw_world_locales_quest.sql"), "locales_quest"):
        q_ru[v[0]] = {f: (v[i] or "") for f, i in (("t", 9), ("d", 18), ("o", 27), ("c", 36), ("p", 45)) if i < len(v)}
    # Forever quests no longer in the diff (strings_en) still have their EN / RU in the translation queue
    for p in glob.glob(os.path.join(ROOT, "translate", "queue", "quests*", "*.json")):
        for it in json.load(open(p, encoding="utf-8")).get("items", []):
            if isinstance(it.get("en"), dict) and str(it.get("id", "")).isdigit():
                q_en.setdefault(it["id"], it["en"])
                if isinstance(it.get("ru"), dict): q_ru.setdefault(it["id"], it["ru"])
    item_en, item_ru = db2("ItemSparse", "Display_lang")
    sn_en, sn_ru = db2("SpellName", "Name_lang")
    res = {}
    for p in sorted(glob.glob(os.path.join(ROOT, "data", "be_parked" if parked else "be", "*.json"))):
        dom = os.path.basename(p)[:-5]
        out = res[dom] = {}
        for k, e in json.load(open(p, encoding="utf-8")).items():
            if not isinstance(e, dict) or not isinstance(e.get("be"), str): continue
            en, ru = e.get("en") or "", ""
            if dom == "tb_quests":
                qid, _, f = k.partition(".")
                en = (q_en.get(qid) or {}).get(f, "")
                ru = (q_ru.get(qid) or {}).get(f, "").replace("\r", "")
            elif dom == "forever":
                head, _, f = k.partition(".") if k.startswith("quest:") else (k, "", "")
                src = s_en.get(head) or {}
                if f:
                    qid = head.split(":", 1)[1]
                    en = ((src.get(f) or "") if isinstance(src, dict) else "") or (q_en.get(qid) or {}).get(f, "")
                    ru = (((src.get("ru") or {}).get(f, "")) if isinstance(src, dict) else "") \
                        or (q_ru.get(qid) or {}).get(f, "").replace("\r", "")
                else:
                    en = k.split(":", 1)[-1]
                    ru = (src.get("ru") or "") if isinstance(src, dict) and isinstance(src.get("ru"), str) else ""
            elif dom == "items":
                en, ru = item_en.get(k, en), item_ru.get(k, "")
            elif dom == "spell_names":
                en, ru = sn_en.get(k, en), sn_ru.get(k, "")
            elif dom == "hand":
                en = k.split(":", 1)[-1]                   # "name:X", "itemname:X", "gossip:X" …
            elif not en:
                en = k                                    # keyed by the English text (item_names, ui, names, zones…)
            if dom in ("ui", "ui_fmt") and not ru:
                ru = gs_ru.get(en, "")
            if not ru and en:
                ru = ALL.get(en, "")
            out[k] = {"en": en, "ru": ru, "bel": e["be"]}
    return res


# R719: corpus domain (+ key prefix) -> the file it is shown in; hand fixes go into the file of what they fix
FILES = {"tb_quests": "quests", "tb_names": "names", "tb_zones": "zones", "tb_gossip": "gossip",
         ("forever", "quest"): "quests", ("forever", "name"): "names", ("forever", "zone"): "zones",
         ("forever", "gossip"): "gossip", ("forever", "objective"): "objectives",
         ("hand", "name"): "names", ("hand", "gossip"): "gossip", ("hand", "objective"): "objectives",
         ("hand", "itemname"): "item_names", ("hand", "spellname"): "spell_names_en", ("hand", "skill"): "ui"}


def file_key(dom, key):
    """(file, key in that file): "quest:123.d" -> ("quests", "123.d"); "name:X" -> ("names", "X")"""
    kind, _, rest = key.partition(":")
    f = FILES.get((dom, kind)) or FILES.get(dom) or dom
    if dom in ("forever", "hand") and (dom, kind) in FILES: key = rest
    return f, key


def main():
    from expansion import classify
    res = {}                                             # R719: translations/<vanilla|forever|ui|tbc|wotlk|turtle>/<file>
    for parked in (False, True):
        for dom, out in sorted(collect(parked).items(), key=lambda d: d[0] == "hand"):     # hand last: it wins
            for k, v in out.items():
                f, fk = file_key(dom, k)
                res.setdefault((classify(dom, k, parked), f), {})[fk] = v
    titles, book_ru = book_titles()
    total = 0
    for f in glob.glob(os.path.join(OUT, "*.json*")) + glob.glob(os.path.join(OUT, "*", "*.json*")):
        os.remove(f)                                     # format of a domain may change (json <-> jsonl)
    counts = {}
    for (exp, dom), out in sorted(res.items()):
        os.makedirs(os.path.join(OUT, exp), exist_ok=True)
        n = write_domain(os.path.join(OUT, exp), dom, out, titles, book_ru)
        counts.setdefault(exp, []).append("%s %d" % (dom, n))
        total += n
    for exp, c in counts.items(): print("%-8s %s" % (exp, ", ".join(c)))
    print("total", total, "->", OUT)


def write_domain(out_dir, dom, out, titles, book_ru):
    """one domain's entries -> <out_dir>/<domain>.json (by id / book title) and / or .jsonl (by English text)"""
    ids = {k: v for k, v in out.items() if dom in ID_DOMAINS}
    if dom == "books":                                   # keyed by book title + page (R257)
        ids = {}
        for k, v in out.items():
            t = titles.get(k, "page ?")
            if not v["ru"]: v["ru"] = book_ru.get(k, "")
            ids[t if t not in ids else "%s [%s]" % (t, k[:20])] = v
        out = {}
    lines = [v for k, v in sorted(out.items()) if k not in ids]
    if ids:                                             # keys sorted (quest / item ids by number); inside: en, ru, bel
        num = lambda k: (int(k.split(".")[0]), k) if k.split(".")[0].isdigit() else (1 << 40, k)
        ids = {k: ids[k] for k in sorted(ids, key=num)}
        with open(os.path.join(out_dir, dom + ".json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(ids, f, ensure_ascii=False, indent=2)
            f.write("\n")
    if lines:
        with open(os.path.join(out_dir, dom + ".jsonl"), "w", encoding="utf-8", newline="\n") as f:
            for v in lines: f.write(json.dumps(v, ensure_ascii=False) + "\n")
    return len(ids) + len(lines)


if __name__ == "__main__":
    main()
