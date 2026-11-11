"""R879: apply a reviewed fix list to data/be as hand edits — the job reviewer agents and one-off review/done scripts kept
re-writing (review/new_pass/scratch/apply_fixes.py, r864 / r874 / r876 on 2026-11-10).

    python tools/apply_tsv.py <fixes.tsv> [--apply]       dry run by default

TSV with a header; columns used: key, old, new (+ optional domain, kind; rows whose kind is in --kinds only, default all).
  * key = the data/be entry key (any domain unless `domain` is given; a key found in several domains is applied to each)
  * old must occur EXACTLY ONCE in that entry's "be", else the row is reported and skipped
  * refused: control characters, a changed count of $tokens / |c colour codes, an `old` == `new` row
Prints every change; writes nothing without --apply."""
import csv, glob, json, os, re, sys
sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from corpus import _write  # noqa: E402

args = [a for a in sys.argv[1:] if not a.startswith("--")]
if not args:
    print(__doc__); sys.exit(0)
apply = "--apply" in sys.argv
kinds = None
for a in sys.argv:
    if a.startswith("--kinds="):
        kinds = set(a.split("=", 1)[1].split(","))
rows = list(csv.DictReader(open(args[0], encoding="utf-8"), delimiter="\t"))
doms = {os.path.basename(p)[:-5]: p for p in glob.glob(os.path.join(ROOT, "data", "be", "*.json"))}
data, dirty = {}, set()
def dom(name):
    if name not in data:
        data[name] = json.load(open(doms[name], encoding="utf-8"))
    return data[name]
TOK = re.compile(r"\$[A-Za-z0-9]+|\|c[0-9A-Fa-f]{8}|\|r")
ok = bad = 0
for r in rows:
    if kinds and r.get("kind") not in kinds:
        continue
    key, old, new = r.get("key", ""), r.get("old", ""), r.get("new", "")
    why = None
    if not key or not old:
        why = "no key / old"
    elif old == new:
        why = "old == new"
    elif re.search(r"[\x00-\x08\x0b-\x1f]", new):
        why = "control character in new"
    elif sorted(TOK.findall(old)) != sorted(TOK.findall(new)):
        why = "tokens / colour codes differ"
    targets = [r["domain"]] if r.get("domain") else list(doms)
    hit = False
    if not why:
        for dn in targets:
            if dn not in doms:
                continue
            e = dom(dn).get(key)
            if not isinstance(e, dict) or not isinstance(e.get("be"), str):
                continue
            n = e["be"].count(old)
            if n != 1:
                print("SKIP %-14s %-40s old found %d× : %s" % (dn, key[:40], n, old[:60]))
                continue
            print("%-14s %-40s %s → %s" % (dn, key[:40], old[:60], new[:60]))
            e["be"] = e["be"].replace(old, new)
            dirty.add(dn)
            hit = True
    if why or not hit:
        bad += 1
        if why:
            print("REFUSED %s: %s" % (key[:40], why))
    else:
        ok += 1
if apply:
    for dn in dirty:
        _write(doms[dn], data[dn])
print("applied" if apply else "dry run:", ok, "rows ok,", bad, "skipped / refused")
