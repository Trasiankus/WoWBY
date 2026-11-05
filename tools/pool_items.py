"""Item names turtle-bel got from the opencode free-model pool (R65, 2026-09-29) — weaker than the Opus/Sonnet ones.

    python tools/pool_items.py          -> data/pool_items.json  [item ids]

turtle-bel/items/pool_run*.log + pool_err.log list every window the pool finished ("wNNNN  done"); items/windows/
wNNNN.ids.json give the item ids of each window. prepare_translate queues the shipped ones as "items_redo" and keeps
all of them out of the translator's "similar" examples; import -> data/auto_items_redo.json; the build ships that text
for those ids instead of the pool one."""
import glob, json, os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TB = r"C:\Projects\WoW\turtle-bel\items"


def main():
    wins = set()
    for f in glob.glob(os.path.join(TB, "pool_run*.log")) + glob.glob(os.path.join(TB, "pool_err.log")):
        wins |= set(re.findall(r"(w\d{4}) +done", open(f, encoding="utf-8", errors="replace").read()))
    ids = set()
    for w in wins:
        ids |= set(json.load(open(os.path.join(TB, "windows", w + ".ids.json"), encoding="utf-8")))
    json.dump(sorted(ids, key=int), open(os.path.join(ROOT, "data", "pool_items.json"), "w", encoding="utf-8"))
    print("pool windows %d -> %d item ids -> data/pool_items.json" % (len(wins), len(ids)))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
