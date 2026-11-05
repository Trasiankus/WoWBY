"""WoW Forever text extraction + diff against the WoWBY vanilla corpus. Client data (DB2s) from the NEWEST Forever build
installed, server caches (WDB, hotfixes) merged from every install (tools/forever_client.py, R687).

Full dumps (reference, everything the client has):
  out/db2/<Table>.tsv      id field idx en ru ann_en status   (every localized DB2 string column;
                           status vs Anniversary 2.5.6 enUS: same / changed / new)
  out/cache/{quests,creatures,gameobjects}.tsv   server text seen in the beta WDB cache (enUS)

Translation diff (parallel-localization shape) vs WoWBY vanilla (turtle-bel data/classic + names):
  data/strings_en.json     {"quest:<id>": {t,o,d, ru:{t,o,d}, why}, "name:<EN>": {v, ru, why}, "zone:<EN>": {v, ru, why}}
  todo.txt                 ordered ids
  out/quests_no_text.tsv   Forever quest IDs (QuestV2) not in WoWBY and with no EN text available yet
  out/report.md            counts

Re-run any time: the WDB cache grows as you play the beta, so the diff picks up new quests/NPCs."""
import os, re, json, struct, collections, sys
from wow_casc import Casc, build_key_for, load_listfile
from db2 import DB2, load_dbd
import forever_client

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "out")
TB = r"C:\Projects\WoW\turtle-bel\data"
QUESTIE = r"C:\Projects\WoW\Questie\Localization\lookups\Classic"


def wtsv(path, header, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    clean = lambda v: "" if v is None else str(v).replace("\\", "\\\\").replace("\t", "\\t").replace("\r", "\\r").replace("\n", "\\n")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\t".join(header) + "\n")
        for r in rows: f.write("\t".join(clean(v) for v in r) + "\n")


def norm(s):
    """Compare text modulo whitespace and $-token case ($N==$n, $B==$b)."""
    s = re.sub(r"\$([A-Za-z])", lambda m: "$" + m.group(1).lower(), s or "")
    return re.sub(r"\s+", " ", s.replace("$b", " ")).strip()


# ---------------------------------------------------------------- DB2 dump
_HOTFIX = None
# string columns of a hotfix record, in record order (empty strings are not in the cache strings list) — R219
HOTFIX_FIELDS = {"SpellName": ["Name_lang"], "Spell": ["Description_lang", "AuraDescription_lang"],
                 "ItemSparse": ["Description_lang", "Display_lang"],
                 # R686: subtitles / NPC speech the server pushes (intro narration of the other races arrives this way)
                 "BroadcastText": ["Text_lang", "Text1_lang"]}


def hotfix_overlay(table, table_hash, en_rows):
    """Server hotfixes (Cache/ADB/enUS/DBCache.bin, tools/dbcache.py) override / add rows of a few text tables, so new
    talents ("Gore Drinker") and changed texts (Unbridled Wrath lost a sentence) reach the queue and the build (R219)."""
    global _HOTFIX
    if table not in HOTFIX_FIELDS:
        return en_rows
    if _HOTFIX is None:
        _HOTFIX = {}
        try:
            import dbcache
            for th, rid, st, strs in dbcache.entries():
                if st == 1:
                    _HOTFIX.setdefault(th, {})[rid] = [s for s in strs if "�" not in s]
        except Exception as e:
            print("hotfix cache not read:", e)
    hot = _HOTFIX.get(table_hash) or {}
    if not hot:
        return en_rows
    fields = HOTFIX_FIELDS[table]
    cur = {(i, f, a): s for i, f, a, s in en_rows}
    for rid, strs in hot.items():
        if not strs: continue
        if table == "Spell" and re.match(r"^(Rank \d+|Passive|Racial|Shapeshift)$", strs[0]): strs = strs[1:]
        if table == "ItemSparse":                      # [Description?, Display]: the LAST string is the item name
            vals = {"Display_lang": strs[-1]}
            if len(strs) > 1: vals["Description_lang"] = strs[0]
        else:
            vals = dict(zip(fields, strs))
        for f, s in vals.items():
            cur[(rid, f, 0)] = s
    return [(i, f, a, s) for (i, f, a), s in cur.items()]


RU_FALLBACK = []          # other Forever installs to read the ruRU files from (main() fills it)


def dump_db2(beta, ann):
    lf = {v.split("/")[-1][:-4]: k for k, v in load_listfile(r"^dbfilesclient/.*\.db2$").items()}
    tables, stats, errors = {}, collections.Counter(), []
    for t, fd in sorted(lf.items()):
        en_ck, ru_ck = beta.ckey_for(fd, "enUS"), beta.ckey_for(fd, "ruRU")
        if not en_ck or not ru_ck or en_ck == ru_ck: continue
        dbd, real = load_dbd(t)
        if dbd is None: errors.append((t, "no .dbd")); continue
        try:
            en = DB2(beta.read_ckey(en_ck), real)
            if en.record_count == 0: continue
            en_rows = en.strings(dbd)
        except Exception as e:
            errors.append((real, "%s: %s" % (type(e).__name__, e))); continue
        # 2026-10-28: the launch client (wowf 70658) is installed in English only — its ruRU files are not local. The
        # Russian column (translator reference, data/ru.lua) then comes from another Forever install that has it.
        ru_rows = []
        rb = beta.read_ckey(ru_ck)
        for src in ([beta] if rb else []) + RU_FALLBACK:
            try:
                ru_rows = DB2(rb if src is beta else src.read_fdid(fd, "ruRU"), real).strings(dbd); break
            except Exception:
                continue
        ann_rows = []
        ad = ann.read_fdid(fd, "enUS")
        if ad:
            try: ann_rows = DB2(ad, real).strings(dbd)
            except Exception: ann_rows = None  # older layout not in dbd / different schema
        ru = {(i, f, a): s for i, f, a, s in ru_rows}
        an = {(i, f, a): s for i, f, a, s in ann_rows} if ann_rows is not None else None
        en_rows = hotfix_overlay(real, en.table_hash, en_rows)
        rows = []
        for i, f, a, s in sorted(en_rows, key=lambda r: (r[0], r[1], r[2])):
            if not f.endswith("_lang"): continue  # non-localized string columns (internal tags, paths)
            k = (i, f, a)
            st = "?" if an is None else ("new" if k not in an else ("same" if an[k] == s else "changed"))
            rows.append((i, f, a, s, ru.get(k, ""), (an or {}).get(k, ""), st))
            stats[st] += 1
        if rows:
            wtsv(os.path.join(OUT, "db2", real + ".tsv"), ["id", "field", "idx", "en", "ru", "ann_en", "status"], rows)
            tables[real] = rows
    return tables, stats, errors


# ---------------------------------------------------------------- WDB cache
def wdb_records(name, loc="enUS"):
    """records of one WDB cache file, merged over every Forever install (R687: beta + stress test; oldest build first,
    so the newest build's record wins for an id both saw)"""
    merged = {}
    for d0 in forever_client.install_dirs():
        p = os.path.join(d0, "Cache", "WDB", loc, name + ".wdb")
        if not os.path.exists(p): continue
        d, pos = open(p, "rb").read(), 24
        while pos + 8 <= len(d):
            rid, sz = struct.unpack_from("<II", d, pos)
            if sz == 0: break
            merged[rid] = d[pos + 8:pos + 8 + sz]; pos += 8 + sz
    return sorted(merged.items())


def book_cache():
    """pagetextcache.wdb -> [(page id, EN text)]. The record layout isn't pinned down yet (the cache was empty when this
    was written, 2026-10-06), so take the record's readable UTF-8 runs: the longest run of >= 20 chars is the page."""
    out = []
    for rid, b in wdb_records("pagetextcache"):
        runs = [r.decode("utf-8", "ignore") for r in re.findall(rb"[\x09\x0a\x0d\x20-\x7e\x80-\xff]{20,}", b)]
        runs = [r.strip() for r in runs if r.strip()]
        if runs:
            out.append((rid, max(runs, key=len)))
    return out


QW = [9, 12, 12, 9, 10, 8, 10, 8, 11]
QF = ["t", "o", "d", "area", "pg_text", "pg_name", "pt_text", "pt_name", "complog"]


def parse_quest(b):
    """Strings are the record tail; their lengths sit in a 12-byte MSB-first bit header that
    immediately precedes them (widths QW). Find the offset o where o + 12 + sum(lengths) == len."""
    best = None
    for o in range(0, len(b) - 12):
        v = int.from_bytes(b[o:o + 12], "big"); used, L = 0, []
        for w in QW:
            used += w; L.append((v >> (96 - used)) & ((1 << w) - 1))
        s = len(b) - sum(L)
        if not L[0] or s != o + 12: continue
        try:
            parts, q = {}, s
            for f, l in zip(QF, L):
                parts[f] = b[q:q + l].decode("utf-8"); q += l
        except UnicodeDecodeError:
            continue
        if parts["t"].isprintable(): best = parts
    return best


def cstr(b, off):
    e = b.index(0, off)
    return b[off:e].decode("utf-8", "replace")


def read_cache():
    quests = {}
    for rid, b in wdb_records("questcache"):
        q = parse_quest(b)
        if q: quests[rid] = q
    creatures = {rid: cstr(b, 15) for rid, b in wdb_records("creaturecache") if len(b) > 16}
    objects = {rid: cstr(b, 8) for rid, b in wdb_records("gameobjectcache") if len(b) > 9}
    # R600: cumulative — a new client build empties the WDB cache (build 70374: 31 creatures left), so what earlier
    # runs saw is kept from the previous out/cache dump (the live cache wins for an id seen again)
    def old(name, cols):
        p = os.path.join(OUT, "cache", name)
        if not os.path.exists(p): return {}
        un = lambda v: re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t", "r": "\r"}.get(m.group(1), m.group(1)), v)
        rows = [[un(v) for v in l.rstrip("\n").split("\t")] for l in open(p, encoding="utf-8")][1:]
        return {int(r[0]): (r[1] if cols == 1 else dict(zip(QF, r[1:]))) for r in rows if r and r[0].isdigit()}
    creatures = {**old("creatures.tsv", 1), **creatures}
    objects = {**old("gameobjects.tsv", 1), **objects}
    quests = {**old("quests.tsv", len(QF)), **quests}
    wtsv(os.path.join(OUT, "cache", "quests.tsv"), ["id"] + QF, [[i] + [q[f] for f in QF] for i, q in sorted(quests.items())])
    wtsv(os.path.join(OUT, "cache", "creatures.tsv"), ["id", "name"], sorted(creatures.items()))
    wtsv(os.path.join(OUT, "cache", "gameobjects.tsv"), ["id", "name"], sorted(objects.items()))
    return quests, creatures, objects


# ---------------------------------------------------------------- Questie ruRU lookups
def questie_ru(kind):
    """kind: lookupQuests / lookupNpcs / lookupObjects -> {id: value} via lupa."""
    import lupa
    p = os.path.join(QUESTIE, kind, "ruRU.lua")
    src = open(p, encoding="utf-8").read()
    m = re.search(r"loadstring\(\[\[(.*)\]\]\)", src, re.S)
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    t = lua.execute(m.group(1))
    def py(v):
        if lupa.lua_type(v) == "table": return [py(x) for x in v.values()]
        return v
    return {int(k): py(v) for k, v in t.items()}


def questie_objects():
    """Questie Classic objectDB -> {id: EN name} for objects with spawns (in the world)."""
    import lupa
    src = open(os.path.join(QUESTIE, "..", "..", "..", "Database", "Classic", "classicObjectDB.lua"), encoding="utf-8").read()
    m = re.search(r"objectData = \[\[(.*?)\]\]", src, re.S)
    t = lupa.LuaRuntime(unpack_returned_tuples=True).execute(m.group(1))
    return {int(k): v[1] for k, v in t.items() if v[1] and v[4]}


# ---------------------------------------------------------------- main
def main():
    sys.stdout.reconfigure(encoding="utf-8")
    beta = Casc(build_key_for(forever_client.product()))         # the newest Forever build installed (R687)
    ann = Casc(build_key_for("wow_anniversary"), idx=beta.idx)
    print(beta.build_name, "vs baseline", ann.build_name)
    for p in ("wow_classic_beta",):         # ruRU source when the newest install has English only (2026-10-28)
        if p != forever_client.product():
            try: RU_FALLBACK.append(Casc(build_key_for(p), idx=beta.idx))
            except Exception as e: print("no ruRU fallback from", p, e)
    import db2 as _db2                       # layout fallback by build number (db2.by_layout, 2026-10-28)
    m = re.search(r"WOW-(\d+)patch([\d.]+)", beta.build_name)
    if m: _db2.BUILD = "%s.%s" % (m.group(2), m.group(1))

    tables, stats, errors = dump_db2(beta, ann)
    print("db2: %d tables, strings %s, errors %d" % (len(tables), dict(stats), len(errors)))
    quests_c, creatures_c, objects_c = read_cache()
    print("cache: %d quests, %d creatures, %d objects" % (len(quests_c), len(creatures_c), len(objects_c)))

    lf = {v.split("/")[-1][:-4]: k for k, v in load_listfile(r"^dbfilesclient/questv2\.db2$").items()}
    qv2 = DB2(beta.read_fdid(lf["questv2"], "enUS"), "QuestV2").ids()
    ann_qv2 = DB2(ann.read_fdid(lf["questv2"], "enUS"), "QuestV2").ids()

    q_en = json.load(open(os.path.join(TB, "classic", "quests_en.json"), encoding="utf-8"))
    q_be = json.load(open(os.path.join(TB, "classic", "quests_be.json"), encoding="utf-8"))
    names_be = json.load(open(os.path.join(TB, "names_be.json"), encoding="utf-8"))
    zones_be = json.load(open(os.path.join(TB, "classic", "zones.json"), encoding="utf-8"))
    ru_q, ru_n, ru_o = questie_ru("lookupQuests"), questie_ru("lookupNpcs"), questie_ru("lookupObjects")

    strings, why = {}, collections.Counter()

    # -- quests: cache text for quests WoWBY lacks, or whose EN changed
    for qid, q in sorted(quests_c.items()):
        k = str(qid)
        cur = {f: q[f] for f in ("t", "o", "d") if q[f]}
        if k in q_be and k in q_en:
            old = q_en[k]
            changed = [f for f in cur if norm(cur[f]) != norm(old.get(f))]
            if not changed: continue
            reason = "changed:" + ",".join(changed)
            be_old = {f: q_be[k].get(f) for f in changed}
        else:
            reason, be_old = ("new-in-forever" if qid not in ann_qv2 else "untranslated"), None
        r = ru_q.get(qid)
        o = r[1] if r and len(r) > 1 else None
        ru = {"t": r[0], "o": " ".join(o) if isinstance(o, list) else o} if r else {}
        e = dict(cur, ru={f: v for f, v in ru.items() if v}, why=reason)
        if be_old: e["be_old"] = be_old; e["en_old"] = {f: q_en[k].get(f) for f in be_old}
        strings["quest:%d" % qid] = e; why["quest " + reason.split(":")[0]] += 1

    # -- quests scraped from wowhead (tools/scrape_wowhead.py): fill new quests, add p/c to cached ones
    def wh(lang):
        p = os.path.join(ROOT, "forever-data", lang, "quests.json")
        rows = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}
        return {int(k): r for k, r in rows.items() if r.get("status") == "ok" and not r.get("placeholder")}
    wh_en, wh_ru = wh("en"), wh("ru")
    # R543: progress / completion texts wowhead captured from a player's client carry that player's name where the
    # game says $N ("Excellent work, Cola.") — data/player_names.tsv (review/player_names.py) puts $N back
    pn = os.path.join(ROOT, "data", "player_names.tsv")
    for line in (open(pn, encoding="utf-8") if os.path.exists(pn) else []):
        if line.startswith("#") or not line.strip(): continue
        qid, f, name = line.rstrip("\n").split("\t")[:3]
        r = wh_en.get(int(qid))
        if r and r.get(f):
            r[f] = re.sub(r"(?<![\w'’])%s(?![\w'’])" % re.escape(name), "$N", r[f])
    cp = os.path.join(ROOT, "forever-data", "en", "quest_changes.json")   # wowhead envChange "updated" (scraper)
    changed = {k for k, v in (json.load(open(cp, encoding="utf-8")) if os.path.exists(cp) else {}).items()
               if v.get("status") == "updated"}
    # wowhead's Forever list also carries quests the Forever client does NOT have (SoD "A Waylaid Shipment"…, removed
    # ones; 180 on 2026-10-01, none ever seen in game): keep a scraped quest only if QuestV2 has it or the game showed
    # it (WDB cache / harvest). The id list also tells forever_scraper which quests to stop re-checking.
    json.dump(sorted(qv2), open(os.path.join(OUT, "questv2_ids.json"), "w"))
    hq = os.path.join(ROOT, "data", "harvest.json")
    seen_q = {int(k) for k in (json.load(open(hq, encoding="utf-8")).get("enUS", {}).get("quests", {})
                               if os.path.exists(hq) else {})} | {int(k) for k in quests_c}
    not_client = [q for q in wh_en if q not in qv2 and q not in seen_q]
    for q in not_client:
        wh_en.pop(q, None)
    why["wowhead quest not in the Forever client (skipped)"] += len(not_client)
    for qid, r in sorted(wh_en.items()):
        k = "quest:%d" % qid
        if str(qid) in q_be and k not in strings:            # vanilla quest already translated…
            src = q_en.get(str(qid), {})
            gfold = lambda t: norm(re.sub(r"\$[Gg]\s*([^:;$]*):([^;$]*);", r"<\1/\2>", t or ""))   # $Ga:b; == <a/b>
            if str(qid) not in changed or all(gfold(r.get(f, "")) == gfold(src.get(f, "")) for f in ("t", "o", "d")
                                              if r.get(f)):
                continue                                      # …and wowhead's Forever text is the same
            why["quest changed in Forever"] += 1
        e = strings.get(k) or {"ru": {}, "why": "wowhead"}
        for f in ("t", "o", "d", "p", "c"):
            if r.get(f) and not e.get(f): e[f] = r[f]
        for f in ("t", "o", "d", "p", "c"):
            if wh_ru.get(qid, {}).get(f) and not e["ru"].get(f): e["ru"][f] = wh_ru[qid][f]
        if k not in strings: why["quest wowhead"] += 1
        strings[k] = e

    # -- in-game harvest (tools/import_harvest.py -> data/harvest.json): what WoWBY saw untranslated
    hp = os.path.join(ROOT, "data", "harvest.json")
    harv = json.load(open(hp, encoding="utf-8")) if os.path.exists(hp) else {}
    h_en, h_ru = harv.get("enUS", {}), harv.get("ruRU", {})
    # R665: a ruRU session's misses → their EN keys: NPC names by the NPC id WoWBY stored (WDB cache / wowhead EN list),
    # other texts through the RU/EN pairs of tools/build_ru.py; mapped names count as seen NPCs (the cache is enUS)
    ru_names = set()
    if any(h_ru.get(k) for k in ("names", "objects", "zones", "gossip", "books")):
        from build_ru import ru_to_en_index
        idx = ru_to_en_index()
        wh_np = os.path.join(ROOT, "forever-data", "en", "npcs.json")
        wh_n = {int(k): v.get("name") for k, v in json.load(open(wh_np, encoding="utf-8")).items()} if os.path.exists(wh_np) else {}
        h_en = {k: dict(v) for k, v in h_en.items()}
        n_map = 0
        for kind, dom in (("names", "names"), ("objects", "names"), ("zones", "zones"), ("gossip", "gossip"),
                          ("books", "books")):
            for ru, v in h_ru.get(kind, {}).items():
                en = None
                if kind == "names" and isinstance(v, (int, float)) and not isinstance(v, bool):
                    en = creatures_c.get(int(v)) or wh_n.get(int(v))
                en = en or idx.get(dom, {}).get(ru)
                if en and en not in h_en.setdefault(kind, {}):
                    h_en[kind][en] = v if kind in ("gossip", "books") else True
                    n_map += 1
                    if kind == "names": ru_names.add(en)
        why["ruRU harvest mapped to EN"] += n_map
    # R510: live texts that differ from the English a translation was made from ("c#<hash>" beside the normal fields, core
    # W.quest_variant): the game shows them in English. Kept for review in out/quest_variants.json, not queued yet.
    variants = {}
    for qid, q in h_en.get("quests", {}).items():
        v = {f: t for f, t in q.items() if "#" in f}
        if v: variants[qid] = v
    json.dump(variants, open(os.path.join(OUT, "quest_variants.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
    why["quest text variants kept (out/quest_variants.json, not queued)"] = sum(len(v) for v in variants.values())
    for qid, q in sorted(h_en.get("quests", {}).items(), key=lambda kv: int(kv[0])):
        if not any("#" not in f for f in q):                    # only variants: no normal field to queue
            continue
        k = "quest:" + qid
        same_title = not q.get("t") or norm(q["t"]) == norm(q_en.get(qid, {}).get("t", ""))
        if qid in q_be and k not in strings and same_title:
            continue                                            # vanilla, translated, unchanged title
        e = strings.get(k) or {"ru": {}, "why": "harvest"}
        for f in ("t", "o", "d", "p", "c"):
            if q.get(f) and not e.get(f): e[f] = q[f]
        for f, v in h_ru.get("quests", {}).get(qid, {}).items():
            e["ru"].setdefault(f, v)
        if k not in strings: why["quest harvest"] += 1
        strings[k] = e
    # harvested names are kept only if the WDB cache saw them as an NPC or object: older WoWBY versions also
    # collected other players' names and pets (459 of 473 on 2026-09-29) — players never enter creaturecache
    seen_names = set(creatures_c.values()) | set(objects_c.values()) | ru_names
    for kind, pre in (("names", "name:"), ("zones", "zone:")):
        known = names_be if kind == "names" else zones_be
        for en in sorted(h_en.get(kind, {})):
            if kind == "names" and (en not in seen_names or re.search("[Ѐ-ӿ]", en)):
                continue
            if en not in known and pre + en not in strings:
                strings[pre + en] = {"v": en, "ru": "", "why": "harvest"}; why["%s harvest" % kind[:-1]] += 1
    # R600: world objects hovered in game (Object tooltip data: never a player) need no WDB check — a new client build
    # empties the cache, and then even real NPC / object names were dropped
    for en in sorted(h_en.get("objects", {})):
        if en and en not in names_be and "name:" + en not in strings and not re.search("[Ѐ-ӿ]", en):
            strings["name:" + en] = {"v": en, "ru": "", "why": "object harvest"}; why["name object harvest"] += 1
    # client-side world objects (GameObjects.db2: inn / shop signs "Calmbreeze Inn", R565): never in the WDB cache or
    # wowhead lists → queued from the dump (test / DNT objects skipped)
    go_p = os.path.join(ROOT, "out", "db2", "GameObjects.tsv")
    if os.path.exists(go_p):
        with open(go_p, encoding="utf-8") as f:
            for line in f.read().split("\n")[1:]:
                c = line.split("\t")
                if len(c) < 5 or c[1] != "Name_lang": continue
                en = c[3].strip()
                if not en or re.search(r"\(DNT\)|\btest\b|[Ѐ-ӿ]", en, re.I): continue
                if en not in names_be and "name:" + en not in strings:
                    strings["name:" + en] = {"v": en, "ru": c[4].strip(), "why": "client object"}
                    why["name client object"] += 1
    # guard-direction minimap points ("Razor Hill Inn", R572; tools/import_broadcast.py → data/poi_en.json)
    pp = os.path.join(ROOT, "data", "poi_en.json")
    for en, ru in (sorted(json.load(open(pp, encoding="utf-8")).items()) if os.path.exists(pp) else []):
        if en not in names_be and "name:" + en not in strings:
            strings["name:" + en] = {"v": en, "ru": ru, "why": "guard poi"}
            why["name guard poi"] += 1
    # wowhead NPC / object lists (forever_scraper --names, 2026-10-01): names + NPC titles ("tag") are server-side;
    # every one WoWBY lacks is queued, RU from the ru list (same id)
    tb_titles = json.load(open(os.path.join(TB, "titles_be.json"), encoding="utf-8")) if os.path.exists(
        os.path.join(TB, "titles_be.json")) else {}
    for kind in ("npcs", "objects"):
        en_rows = json.load(open(os.path.join(ROOT, "forever-data", "en", kind + ".json"), encoding="utf-8")) \
            if os.path.exists(os.path.join(ROOT, "forever-data", "en", kind + ".json")) else {}
        ru_p = os.path.join(ROOT, "forever-data", "ru", kind + ".json")
        ru_rows = json.load(open(ru_p, encoding="utf-8")) if os.path.exists(ru_p) else {}
        for i, r in sorted(en_rows.items(), key=lambda kv: int(kv[0])):
            en, ru = (r.get("name") or "").strip(), (ru_rows.get(i) or {})
            if en and en not in names_be and "name:" + en not in strings and not re.search("[Ѐ-ӿ]", en):
                strings["name:" + en] = {"v": en, "ru": ru.get("name", ""), "why": "wowhead " + kind[:-1]}
                why["name wowhead"] += 1
            tag = (r.get("tag") or "").strip()
            if kind == "npcs" and tag and tag not in tb_titles and "title:" + tag not in strings:
                strings["title:" + tag] = {"v": tag, "ru": ru.get("tag", ""), "why": "wowhead npc title"}
                why["title wowhead"] += 1
    # gossip keys = "gossip:" + the FULL text (R325, owner 2026-10-09). Until then the first 80 chars: two texts sharing
    # them (trainer greetings "Welcome, my brother.  If you are here to train…", R312) lost the second one.
    # review/gossip_fullkeys.py moved the corpus keys; queue ids stay the old prefix ones (done/ files match them).
    def gkey(text):
        return "gossip:" + text
    for text, npc in sorted(h_en.get("gossip", {}).items()):
        strings.setdefault(gkey(text), {"v": text, "ru": "", "npc": npc if isinstance(npc, str) else "", "why": "harvest"})
    # NPC speech from wowhead NPC pages ("Quotes", forever_scraper --npc-quotes, R509): lines the player has not met yet.
    # Server double spaces collapsed (the addon's lookup collapses them too); a variant that is a $N line with a real
    # player's name in its place ("Good work, Gizmy!") is dropped
    # wowhead anonymised its recording character's name by plain substring replacement, so a short name ("Zeph", "Win",
    # "Sky", "No") became <name> inside words too: "$Nras Isle" (Zephras), "the $Ndshapers", "$Nw that" (2026-10-17, 27
    # lines) → a $N glued to letters marks the whole line as damaged ("$B$N" is a token pair, not damage)
    QUOTE_BROKEN = re.compile(r"\$[NRC][a-z]|(?<!\$)[A-Za-z]\$[NRC]")
    qp = os.path.join(ROOT, "forever-data", "en", "npc_quotes.json")
    if os.path.exists(qp):
        for npc_id, e in sorted(json.load(open(qp, encoding="utf-8")).items()):
            qs = [re.sub(r"\s{2,}", " ", q["text"]).strip()
                  for q in (e.get("quotes") or []) + (e.get("quotes_classic") or [])]     # /forever/ + /classic/ pages
            qs = list(dict.fromkeys(qs))
            withn = [re.compile("^" + re.escape(q).replace(re.escape("$N"), r"\S+?") + "$") for q in qs if "$N" in q]
            for q in qs:
                if "$N" not in q and any(rx.match(q) for rx in withn):
                    continue
                if QUOTE_BROKEN.search(q):
                    why["gossip wowhead quote with a mangled $N (skipped)"] += 1
                    continue
                if gkey(q) not in strings:
                    strings[gkey(q)] = {"v": q, "ru": "", "npc": e.get("name", ""), "why": "wowhead quote"}
                    why["gossip wowhead quote"] += 1
    # classic NPC speech / gossip greetings / gossip options from the local vanilla world DB (tools/import_broadcast.py,
    # R55): everything WoWBY does not translate yet, RU from the same DB as reference
    bp = os.path.join(ROOT, "data", "broadcast_en.json")
    if os.path.exists(bp):
        g_have = set()
        gl = os.path.join(TB, "..", "addon", "WoWBY", "data", "gossip.lua")
        if os.path.exists(gl):
            g_have = set(re.findall(r'^\["((?:[^"\\]|\\.)*)"\]=', open(gl, encoding="utf-8").read(), re.M))
        for text, e in sorted(json.load(open(bp, encoding="utf-8")).items()):
            k = gkey(text)
            if text in g_have or k in strings:
                continue
            strings[k] = {"v": text, "ru": e.get("ru", ""), "npc": "", "why": "classic " + e.get("kind", "broadcast")}
            why["gossip classic " + e.get("kind", "broadcast")] += 1
    # R686: the client's own BroadcastText DB2 (+ hotfix rows pushed at login) = cinematic / NPC speech subtitles — the
    # Skyborne race intro ("For thousands of years, …") was never queued; the subtitle hook looks lines up as gossip
    for r in tables.get("BroadcastText", []):
        if r[1] not in ("Text_lang", "Text1_lang") or not r[3].strip():
            continue
        k = gkey(r[3])
        if k not in strings:
            strings[k] = {"v": r[3], "ru": r[4], "npc": "", "why": "client broadcast text"}
            why["gossip client broadcast text"] += 1
    # R711 (owner 2026-10-21): race intro narration from web transcripts (data/intros_en.tsv, one sentence per line), queued
    # before the game has sent them. A subtitle line the game sends later (BroadcastText / harvest) that is the same sentence
    # with other capitals / punctuation / a typo: while the web line is untranslated the game line replaces it; once it is
    # translated, the game line becomes an alias (no second translation; build_addon ships the web line's BE under it)
    ip = os.path.join(ROOT, "data", "intros_en.tsv")
    if os.path.exists(ip):
        import difflib
        loose = lambda t: re.sub(r"[^a-z0-9]+", " ", t.lower()).strip()
        fb = os.path.join(ROOT, "data", "be", "forever.json")
        done_g = {k for k in json.load(open(fb, encoding="utf-8")) if k.startswith("gossip:")} if os.path.exists(fb) else set()
        web_lines = [l.partition("\t")[2].strip() for l in open(ip, encoding="utf-8").read().splitlines()[1:]]
        # R715: the harvest put the player's race / class back as $R / $C ("$Rregan" for a gnome, "arch $C" for a druid);
        # narration is the same for everyone → restore the word the web transcript has there
        WORDS = ["Human", "Dwarf", "Gnome", "Night Elf", "Orc", "Troll", "Tauren", "Undead", "Warrior", "Paladin", "Hunter",
                 "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid"]
        for gk in [k for k, v in strings.items() if k.startswith("gossip:") and v.get("why") == "harvest"
                   and re.search(r"\$[RC]", v.get("v", ""))]:
            t = strings[gk]["v"]
            best = (0.0, None)
            for w1 in WORDS:
                for w in (w1, w1.lower()):
                    cand = re.sub(r"\$[RC]", w, t)
                    for wl in web_lines:
                        r = difflib.SequenceMatcher(None, loose(cand), loose(wl)).ratio()
                        if r > best[0]: best = (r, cand)
            if best[0] >= 0.95 and gkey(best[1]) not in strings:
                strings[gkey(best[1])] = dict(strings.pop(gk), v=best[1])
                why["gossip race intro: race / class token restored"] += 1
        game = {k: loose(v["v"]) for k, v in strings.items()
                if k.startswith("gossip:") and v.get("why") in ("harvest", "client broadcast text")}
        for l in open(ip, encoding="utf-8").read().splitlines()[1:]:
            race, _, text = l.partition("\t")
            text, k = text.strip(), gkey(text.strip())
            if not text: continue
            lw = loose(text)
            same = [gk for gk, lg in game.items() if gk != k and abs(len(lg) - len(lw)) < 12
                    and difflib.SequenceMatcher(None, lw, lg).ratio() >= 0.92]
            if same and k not in done_g:
                why["gossip race intro (game line already there)"] += 1
                continue
            for gk in same:
                strings[gk]["alias"] = k; why["gossip race intro alias"] += 1
            if k not in strings:
                strings[k] = {"v": text, "ru": "", "npc": race + " intro narration", "why": "race intro (web text)"}
                why["gossip race intro (web text)"] += 1
    # objective lines ("0/1 Darnassus Bank", "Face Lunaclaw and earn…"): the counter and " slain" are cut, NPC and
    # item names are skipped (translated as names / items); the rest is queued (translate package "objectives")
    item_en = {r[3] for r in tables.get("ItemSparse", []) if r[1] == "Display_lang"}
    fo = os.path.join(ROOT, "data", "objectives_fix.tsv")
    obj_fix = {l.split("	")[0] for l in open(fo, encoding="utf-8").read().splitlines()[1:]} if os.path.exists(fo) else set()
    for text, qid in sorted(h_en.get("objectives", {}).items()):
        body = re.sub(r"^\d+/\d+(\s+|$)", "", text.strip())
        body = re.sub(r":\s*\d+/\d+$", "", body)
        body = re.sub(r"(^|\s+)slain$", "", body).strip()
        # hand lines (data/objectives_fix.tsv) and "Raise your X skill to N" (core pattern) are covered already
        if (not body or body in names_be or body in item_en or body in obj_fix or re.search("[Ѐ-ӿ]", body)
                or re.match(r"Raise your .+ skill to \d+", body)):
            continue
        k = "objective:" + body
        if k not in strings:
            strings[k] = {"v": body, "ru": "", "quest": str(qid), "why": "harvest"}; why["objective harvest"] += 1
    # free-text objective rows of the saved wowhead pages (R304: "Escort Lynessa Duskblossom out of Ban'ethil"; the
    # tracker shows them, quest text parsing had dropped the table). Local pages only; RU = the same row of the RU page.
    # lxml-parsing every saved page took ~5 min, so results are cached per page (size + mtime), and the whole cache is
    # dropped when objective_lines' source changes
    import hashlib, inspect, wowhead_parse
    from wowhead_parse import objective_lines
    ol_p = os.path.join(OUT, "objective_lines_cache.json")
    ol_ver = hashlib.md5(inspect.getsource(wowhead_parse.objective_lines).encode("utf-8")).hexdigest()
    ol_old = json.load(open(ol_p, encoding="utf-8")) if os.path.exists(ol_p) else {}
    ol_old = ol_old.get("pages", {}) if ol_old.get("ver") == ol_ver else {}
    ol_new = {}
    def page_lines(path):
        st = os.stat(path)
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        hit = ol_old.get(rel)
        if hit and hit[0] == st.st_size and hit[1] == st.st_mtime_ns:
            ol_new[rel] = hit
            return hit[2]
        lines = objective_lines(open(path, encoding="utf-8").read(), keep_rows=True)
        ol_new[rel] = [st.st_size, st.st_mtime_ns, lines]
        return lines
    for qid in sorted(wh_en):
        pe = os.path.join(ROOT, "forever-data", "en", "pages", "%d.html" % qid)
        if not os.path.exists(pe):
            continue
        en_l = page_lines(pe)
        if not any(en_l):
            continue
        pr = os.path.join(ROOT, "forever-data", "ru", "pages", "%d.html" % qid)
        ru_l = page_lines(pr) if os.path.exists(pr) else []
        for i, body in enumerate(en_l):
            if not body or body in names_be or body in item_en or body in obj_fix:
                continue
            k = "objective:" + body
            if k not in strings:
                ru = ru_l[i] if len(ru_l) == len(en_l) and ru_l[i] else ""
                strings[k] = {"v": body, "ru": ru, "quest": str(qid), "why": "wowhead objective"}
                why["objective wowhead"] += 1
    json.dump({"ver": ol_ver, "pages": ol_new}, open(ol_p, "w", encoding="utf-8"), ensure_ascii=False)
    # classic ObjectiveText1-4 (R305, tools/import_objtext.py ← the local vmangos world DB): "Release Oben Rageclaw's
    # spirit" — only quests the Forever client has (QuestV2), so Turtle-only quests stay out
    po = os.path.join(ROOT, "data", "objtext_en.json")
    for body, e in sorted((json.load(open(po, encoding="utf-8")) if os.path.exists(po) else {}).items()):
        if e.get("quest") not in qv2 or body in names_be or body in item_en or body in obj_fix:
            continue
        k = "objective:" + body
        if k not in strings:
            strings[k] = {"v": body, "ru": e.get("ru", ""), "quest": str(e["quest"]), "why": "classic objective"}
            why["objective classic"] += 1
    wtsv(os.path.join(OUT, "harvest_objectives.tsv"), ["text", "quest"],
         sorted((t, q) for t, q in h_en.get("objectives", {}).items()))

    # -- book pages (R138): what WoWBY harvested from the reading window + the game's own page cache.
    # prepare_translate books() adds the pages the vanilla world DB lacks to the "books" package.
    books = {}
    for text, meta in h_en.get("books", {}).items():
        meta = meta if isinstance(meta, dict) else {}
        books[text] = {"en": text, "title": meta.get("title", ""), "page": meta.get("page", 0), "why": "harvest"}
    for pid, text in book_cache():
        books.setdefault(text, {"en": text, "title": "", "page": 0, "why": "cache", "page_id": pid})
    json.dump(books, open(os.path.join(OUT, "books_forever.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    why["book pages (harvest + cache)"] = len(books)

    # -- quests with no text anywhere yet
    no_text = sorted(q for q in qv2 - set(map(int, q_en)) - set(quests_c) - set(wh_en)
                     - {int(x) for x in h_en.get("quests", {})})
    wtsv(os.path.join(OUT, "quests_no_text.tsv"), ["id", "in_anniversary", "questie_ru_name"],
         [(q, int(q in ann_qv2), (ru_q.get(q) or [""])[0]) for q in no_text])

    # -- names: NPCs / objects seen in cache + Creature.db2 (companions), not in names_be
    creature_db = {i: (s, ru) for i, f, a, s, ru, _a, _st in tables.get("Creature", []) if f == "Name_lang"}
    for src, items, rulk in (("npc", creatures_c, ru_n), ("object", objects_c, ru_o)):
        for i, n in sorted(items.items()):
            if not n or n in names_be or "name:" + n in strings: continue
            r = rulk.get(i); r = r[0] if isinstance(r, list) else r
            strings["name:" + n] = {"v": n, "ru": r or "", "why": src + ":%d" % i}; why["name " + src] += 1
    for i, (n, r) in sorted(creature_db.items()):
        if n in names_be or "name:" + n in strings: continue
        strings["name:" + n] = {"v": n, "ru": r, "why": "creature.db2:%d" % i}; why["name creature.db2"] += 1
    # world objects ("Moonkin Stone": hover tooltip = object name) are server-side and only a few are in the WDB
    # cache -> every Questie Classic object that has spawns (placed in the world), RU from Questie ruRU
    for i, n in sorted(questie_objects().items()):
        if n in names_be or "name:" + n in strings or re.search(r"\b(TEST|DND|UNUSED)\b|^zz", n, re.I): continue
        r = ru_o.get(i); r = r[0] if isinstance(r, list) else r
        strings["name:" + n] = {"v": n, "ru": r or "", "why": "questie object:%d" % i}; why["name questie object"] += 1

    # -- zones: AreaTable + Map names not in WoWBY classic zones nor the TM (id-keyed AreaTable)
    tm_area = set()
    for line in open(os.path.join(TB, "tm", "dbc", "AreaTable.tsv"), encoding="utf-8").read().splitlines()[1:]:
        p = line.split("\t")
        if len(p) >= 3 and p[2]: tm_area.add(p[1])
    junk = re.compile(r"UNUSED|Test|Prototype|\bDEV\b|Development|zzOld|\[.*\]|^\*", re.I)
    for tbl, fld in (("AreaTable", "AreaName_lang"), ("Map", "MapName_lang")):
        for i, f, a, s, ru, _a, st in tables.get(tbl, []):
            if f != fld or s in zones_be or s in tm_area or junk.search(s) or "zone:" + s in strings: continue
            strings["zone:" + s] = {"v": s, "ru": ru if ru != s else "", "why": "%s:%d:%s" % (tbl, i, st)}
            why["zone " + st] += 1
    # R738: indoor / sub-area banners (WMOAreaTable). The table carries every retail place; Forever's own rows are the
    # id >= 140000 block ("The Sky Enclave", "The Violet Citadel", re-added classic halls) → queue those still missing
    tm_wmo = {p[1] for p in (l.split("\t") for l in open(os.path.join(TB, "tm", "dbc", "WMOAreaTable.tsv"),
                                                         encoding="utf-8").read().splitlines()[1:]) if len(p) >= 3 and p[2]}
    for i, f, a, s, ru, _a, st in tables.get("WMOAreaTable", []):
        s = (s or "").strip()
        if f != "AreaName_lang" or int(i) < 140000 or not s or s in zones_be or s in tm_area or s in tm_wmo \
                or junk.search(s) or "zone:" + s in strings: continue
        strings["zone:" + s] = {"v": s, "ru": ru if ru != s else "", "why": "WMOAreaTable:%s:%s" % (i, st)}
        why["zone wmo " + st] += 1

    os.makedirs(os.path.join(ROOT, "data"), exist_ok=True)
    json.dump(strings, open(os.path.join(ROOT, "data", "strings_en.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    open(os.path.join(ROOT, "todo.txt"), "w", encoding="utf-8", newline="\n").write("\n".join(strings) + "\n")

    # -- UI (GlobalStrings) diff vs the turtle-bel TM, reference only
    tm = {}
    for line in open(os.path.join(TB, "tm", "ui_globalstrings.tsv"), encoding="utf-8").read().splitlines()[1:]:
        p = line.split("\t")
        if len(p) >= 3: tm[p[0]] = p[1]
    gs = collections.defaultdict(dict)
    for i, f, a, s, ru, _a, st in tables.get("GlobalStrings", []): gs[i]["en"], gs[i]["ru"] = s, ru
    base = {}
    gd = beta.read_fdid({v.split("/")[-1][:-4]: k for k, v in load_listfile(r"globalstrings\.db2$").items()}["globalstrings"], "enUS")
    for i, f, a, s in DB2(gd, "GlobalStrings").strings(load_dbd("GlobalStrings")[0]):
        if f == "BaseTag": base[i] = s
    # key-addressed copy (GlobalString KEY -> EN/RU) for key-based UI translation (format strings etc.)
    wtsv(os.path.join(OUT, "globalstrings_keys.tsv"), ["key", "en", "ru"],
         [(base.get(i, ""), v["en"], v.get("ru", "")) for i, v in sorted(gs.items()) if base.get(i)])
    ui = [(base.get(i, ""), v["en"], v.get("ru", ""), "changed" if base.get(i) in tm else "missing")
          for i, v in sorted(gs.items()) if base.get(i) not in tm or norm(tm[base.get(i)]) != norm(v["en"])]
    wtsv(os.path.join(OUT, "diff_ui_globalstrings.tsv"), ["key", "en", "ru", "status"], ui)

    rep = ["# WoW Forever text extraction — %s" % beta.build_name, "",
           "Baseline for 'new': %s (enUS). Translation baseline: WoWBY vanilla (turtle-bel data/classic, names_be)." % ann.build_name, "",
           "## Translation diff (`data/strings_en.json`, `todo.txt`): %d entries" % len(strings)]
    rep += ["- %s: %d" % kv for kv in sorted(why.items())]
    rep += ["", "## Quests", "- QuestV2 IDs in beta: %d; not in WoWBY classic: %d" % (len(qv2), len(qv2 - set(map(int, q_en)))),
            "- ... with no EN text available yet (need in-game cache/harvest): %d → `out/quests_no_text.tsv`" % len(no_text),
            "- in WDB cache: %d" % len(quests_c), "",
            "## DB2 full dump (`out/db2/`): %d tables; strings vs Anniversary: %s" % (len(tables), dict(stats)),
            "## UI GlobalStrings not in TM or changed: %d → `out/diff_ui_globalstrings.tsv`" % len(ui),
            "", "Encrypted sections skipped (unknown TACT keys): %d chunks" % sum(beta.missing_keys.values())]
    if errors: rep += ["", "## DB2 parse errors"] + ["- %s: %s" % e for e in errors]
    open(os.path.join(OUT, "report.md"), "w", encoding="utf-8").write("\n".join(rep) + "\n")
    print("\n".join(rep))


if __name__ == "__main__":
    main()
