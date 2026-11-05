"""Re-bake corpus domains from their upstream sources with the CURRENT rules, keeping hand edits.

    python tools/rebake.py ui ui_fmt spell_desc spell_names

Use after fixing a rule that had damaged text (a rule bug cannot be undone by fix_corpus, which only applies rules
forward). Hand-edited entries (be != what intake produced) are saved, the domain files deleted, the build re-run
(intake re-applies the rules to the upstream text), then the hand edits are put back and the build re-run.
"""
import json, os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus import DIR, h  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def build():
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "build_addon.py")], env=env, capture_output=True,
                       text=True, encoding="utf-8")
    if r.returncode:
        raise SystemExit(r.stdout + r.stderr)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    hand = {}
    for dom in sys.argv[1:]:
        p = os.path.join(DIR, dom + ".json")
        d = json.load(open(p, encoding="utf-8"))
        hand[dom] = {k: e["be"] for k, e in d.items() if h(e["be"]) != e.get("auto")}
        os.remove(p)
        print("%s: %d entries, %d hand-edited kept aside" % (dom, len(d), len(hand[dom])))
    build()
    for dom, edits in hand.items():
        p = os.path.join(DIR, dom + ".json")
        d = json.load(open(p, encoding="utf-8"))
        for k, be in edits.items():
            if k in d:
                d[k]["be"] = be
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            json.dump(d, f, ensure_ascii=False, indent=0, sort_keys=True)
            f.write("\n")
    build()
    print("re-baked:", " ".join(hand))


if __name__ == "__main__":
    main()
