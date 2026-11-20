"""LAYER 2 of the standing QA (owner 2026-11-20): every check of tools/qa_lines.py — incl. the high-recall grammar
detectors (case after a preposition, agreement, verb gender, naturalness …) — on the translator chunks that are new
since the last addon build. Run by `pipeline.py addon` (update_addon.bat) right after the import; the release step
warns while findings are open.

  python tools/qa_new.py                 chunks new since the last build (out/last_import.json), or --all-done
  python tools/qa_new.py <done chunk>…   only these (translate/done/<pkg>/<chunk>.json)
  python tools/qa_new.py --ack           after review: every finding now listed counts as checked (review/qa_ack.json)

Report: review/qa_new.md ("OPEN: N" on line 2). A finding is closed by fixing the text (data/be for imported text, or
the done file before import) or by --ack once Claude / the owner has judged it a false alarm. KEEP lines the
translating agent wrote (done file "keep") are respected."""
import glob, hashlib, json, os, re, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
REPORT = os.path.join(ROOT, "review", "qa_new.md")
ACK = os.path.join(ROOT, "review", "qa_ack.json")
STATE = os.path.join(ROOT, "out", "last_import.json")


def fresh_chunks():
    old = json.load(open(STATE, encoding="utf-8")) if os.path.exists(STATE) else {}
    out = []
    for p in glob.glob(os.path.join(ROOT, "translate", "done", "*", "*.json")):
        rel = os.path.relpath(p, ROOT).replace("\\", "/")
        if old.get(rel) != os.path.getmtime(p): out.append(p)
    return sorted(out)


def texts_of(done_p):
    """(where, id, en, be) for every NEW Belarusian text of a done chunk (re-pass text equal to the shipped one skipped)"""
    pkg = os.path.basename(os.path.dirname(done_p))
    qp = os.path.join(ROOT, "translate", "queue", pkg, os.path.basename(done_p))
    if not os.path.exists(qp): return [], {}
    d, q = json.load(open(done_p, encoding="utf-8")), json.load(open(qp, encoding="utf-8"))
    keep = {(k.get("id"), (k.get("word") or "").lower()) for k in d.get("keep") or [] if isinstance(k, dict)}
    out = []
    for it in q["items"]:
        be = d.get("items", {}).get(it["id"])
        cur = it.get("be_current")
        if isinstance(be, dict):
            curd = cur if isinstance(cur, dict) else {}
            for f, t in be.items():
                if isinstance(t, str) and t != curd.get(f):
                    out.append(("%s.%s" % (it["id"], f), it["id"], (it.get("en") or {}).get(f, "") or "", t))
        elif isinstance(be, str) and be != cur:
            out.append((it["id"], it["id"], it.get("en") or "", be))
    return out, keep


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--all-done" in sys.argv:
        chunks = sorted(glob.glob(os.path.join(ROOT, "translate", "done", "*", "*.json")))
    else:
        # a path, or the short "<pkg>/<chunk>" form (2026-11-20: the short form silently found 0 texts)
        chunks = [p if os.path.exists(p) else os.path.join(ROOT, "translate", "done", a.replace(".json", "") + ".json")
                  for a in args for p in [os.path.abspath(a)]] or fresh_chunks()
        missing = [c for c in chunks if not os.path.exists(c)]
        if missing: sys.exit("no such done chunk: " + ", ".join(missing))
    ack = set(json.load(open(ACK, encoding="utf-8"))) if os.path.exists(ACK) else set()
    jobs = []
    # check the text as it SHIPS: the owner rules (terms_rules.fix_terms: дварф → дворф, word_fix, yakanne_fix…) run at
    # import; checking the raw draft reported what the rules already fix (2026-11-20: «пад дварфа»)
    from terms_rules import fix_terms
    for c in chunks:
        t, keep = texts_of(c)
        jobs.append((c, [(w, i, en, fix_terms(be)) for w, i, en, be in t], keep))
    from qa_lines import QA
    qa = QA([x[3] for _, t, _ in jobs for x in t])
    # judge the text that SHIPS (2026-11-20: a re-imported old chunk raised 19 findings on draft text that later
    # data/be fixes had replaced): a draft text that ships verbatim → every finding; otherwise a finding stays only if
    # its flagged span still occurs somewhere in data/be
    shipped, blob = set(), []
    for p in glob.glob(os.path.join(ROOT, "data", "be", "*.json")):
        for e in json.load(open(p, encoding="utf-8")).values():
            b = e.get("be") if isinstance(e, dict) else None
            if isinstance(b, str):
                shipped.add(b.strip()); blob.append(b.lower())
    blob = "\n".join(blob)
    found, stale = [], 0
    for c, t, keep in jobs:
        rel = os.path.relpath(c, os.path.join(ROOT, "translate", "done")).replace("\\", "/")
        for where, iid, en, be in t:
            ships = be.strip() in shipped
            for w in qa.check(be, en, 2):
                m = re.search(r"«([^»]*)»", w)
                if m and (iid, m.group(1).lower()) in keep: continue
                if not ships and m and m.group(1).lower() not in blob:
                    stale += 1; continue
                h = hashlib.md5(("%s|%s|%s" % (rel, where, w)).encode("utf-8")).hexdigest()[:12]
                found.append((h, rel, where, w))
    open_ = [f for f in found if f[0] not in ack]
    if "--ack" in sys.argv:
        json.dump(sorted(ack | {f[0] for f in found}), open(ACK, "w", encoding="utf-8"), indent=0)
        print("acknowledged %d findings" % len(open_))
        open_ = []
    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    with open(REPORT, "w", encoding="utf-8", newline="\n") as o:
        o.write("# QA of new translations — %s (%d chunks, %d texts)\n" % (
            time.strftime("%Y-%m-%d %H:%M"), len(chunks), sum(len(t) for _, t, _ in jobs)))
        o.write("OPEN: %d\n\n" % len(open_))
        for h, rel, where, w in open_:
            o.write("- `%s` %s %s — %s\n" % (h, rel, where[:60], w))
    print("QA of new translations (%d findings on draft text that no longer ships skipped): %d chunks, %d texts, %d OPEN findings -> %s" % (stale, 
        len(chunks), sum(len(t) for _, t, _ in jobs), len(open_), os.path.relpath(REPORT, ROOT)))
    for h, rel, where, w in open_[:15]:
        print("  %s %s — %s" % (rel, where[:40], w[:150]))


def open_count():
    try:
        return int(open(REPORT, encoding="utf-8").read().split("\n")[1].split(":")[1])
    except Exception:
        return 0


if __name__ == "__main__":
    main()
