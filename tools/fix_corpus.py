"""Apply the owner wording rules (tools/terms_rules.py) to the final text in data/be/ — or just check it.

    python tools/fix_corpus.py            rewrite data/be/*.json where a rule changes an entry (prints each change)
    python tools/fix_corpus.py --check    only list entries a rule WOULD change (an old form came back); exit 1 if any
    python tools/fix_corpus.py --domain tb_quests --limit 20

Workflow for a new owner decision: add the rule to tools/terms_rules.py (or a row to data/word_fix.tsv), run this,
look at the printed diff, then `python tools/build_addon.py`. Hand edits: edit "be" in data/be/<domain>.json directly
(the build keeps them; see tools/corpus.py). Entries edited by hand keep their hand mark when a rule touches them.
"""
import argparse, glob, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus import DIR, h, rules  # noqa: E402


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--domain")
    ap.add_argument("--limit", type=int, default=8, help="changes shown per domain")
    a = ap.parse_args()
    total = 0
    for path in sorted(glob.glob(os.path.join(DIR, "*.json"))):
        dom = os.path.basename(path)[:-5]
        if a.domain and dom != a.domain:
            continue
        d = json.load(open(path, encoding="utf-8"))
        changed = []
        for k, e in d.items():
            new = rules(e["be"], e.get("en"), dom)
            if new != e["be"]:
                changed.append((k, e["be"], new))
                if not a.check:
                    hand = h(e["be"]) != e.get("auto")
                    e["be"] = new
                    if not hand:
                        e["auto"] = h(new)          # a rule change, not a hand edit
        if not changed:
            continue
        total += len(changed)
        print("%s: %d %s" % (dom, len(changed), "would change" if a.check else "changed"))
        for k, old, new in changed[:a.limit]:
            print("   %s\n     - %s\n     + %s" % (k, old[:160].replace("\n", " "), new[:160].replace("\n", " ")))
        if not a.check:
            # temp file + rename: a reader running at the same time (update_queue) never sees a half-written file (R435)
            with open(path + ".tmp", "w", encoding="utf-8", newline="\n") as f:
                json.dump(d, f, ensure_ascii=False, indent=0, sort_keys=True)
                f.write("\n")
            os.replace(path + ".tmp", path)
    print("total:", total, "(check only)" if a.check else "")
    # R888 (owner 2026-11-11): the same rules over the hand tables that win at build (ui_be, names_fix, itemnames_fix,
    # skills_be…) + a report of shipped Lua strings — a term change must reach EVERY place, not only data/be
    import subprocess
    r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fix_hand_tables.py")]
                       + (["--check"] if a.check else []), capture_output=True, text=True, encoding="utf-8")
    print((r.stdout or "").strip().splitlines()[-1] if r.stdout.strip() else r.stderr.strip()[-300:])
    if a.check and (total or r.returncode):
        sys.exit(1)


if __name__ == "__main__":
    main()
