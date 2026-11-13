"""R965 (owner 2026-11-13): harvests other players send from the in-game button «Адправіць сабранае» (options window) —
one line "WoWBY1 {v=1,loc=…,ver=…,at=…,h={…}}" pasted into a GitHub issue / message. Save each paste as a text file in
data/harvest_inbox/ (any name; several "WoWBY1 …" lines per file are fine), then:
    python tools/import_paste.py [files…]      (default: every data/harvest_inbox/*.txt not imported yet)
→ merged into data/harvest.json like tools/import_harvest.py does; imported files move to data/harvest_inbox/done/.
Then the usual: update_queue.bat (extract_forever keeps names only when the WDB cache saw them as NPCs / objects)."""
import glob, os, re, shutil, sys
import lupa
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_harvest import ROOT, merge, to_py  # noqa: E402

INBOX = os.path.join(ROOT, "data", "harvest_inbox")
KINDS = {"quests", "names", "objects", "zones", "gossip", "objectives", "books", "items"}


def parse(text):
    """Every "WoWBY1 {…}" in the text → [{loc, ver, at, h}]; read by a sandboxed Lua (a table literal only)."""
    out = []
    for m in re.finditer(r"WoWBY1\s+\{", text):
        start = m.end() - 1                                  # the table literal: matching braces, strings skipped
        depth, i, q = 0, start, None
        while i < len(text):
            ch = text[i]
            if q:
                if ch == "\\":
                    i += 1
                elif ch == q:
                    q = None
            elif ch in "\"'":
                q = ch
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body = text[start:i + 1]
        L = lupa.LuaRuntime(unpack_returned_tuples=True, register_eval=False)
        env = L.eval("{}")
        f = L.eval("function(s, env) local f = load('return ' .. s, 'paste', 't', env); if not f then return nil end; "
                   "local ok, v = pcall(f); if ok then return v end end")
        v = f(body, env)
        if v is None:
            print("  skipped: not a valid export"); continue
        out.append(to_py(v))
    return out


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    files = sys.argv[1:] or sorted(glob.glob(os.path.join(INBOX, "*.txt")))
    if not files:
        print("Nothing to import: save pasted exports as %s\\*.txt" % INBOX); return
    merged, n = {}, 0
    for p in files:
        exports = parse(open(p, encoding="utf-8", errors="replace").read())
        print("%s: %d export(s)" % (os.path.basename(p), len(exports)))
        for e in exports:
            loc, h = e.get("loc") or "enUS", e.get("h") or {}
            if not isinstance(h, dict):
                continue
            n += 1
            m = merged.setdefault(str(loc), {})
            for kind, items in h.items():
                if kind not in KINDS or not isinstance(items, dict):
                    continue
                d = m.setdefault(kind, {})
                for k, v in items.items():
                    if kind == "quests" and isinstance(v, dict):
                        d.setdefault(str(k), {}).update({str(f): x for f, x in v.items() if isinstance(x, str)})
                    else:
                        d[str(k)] = v if isinstance(v, (str, int, float, bool, dict)) else True
            print("   %s, WoWBY %s, %s: " % (loc, e.get("ver"), e.get("at"))
                  + ", ".join("%s %d" % (k, len(v)) for k, v in sorted(h.items()) if isinstance(v, dict)))
    if not n:
        return
    merge(merged)
    if not sys.argv[1:]:
        os.makedirs(os.path.join(INBOX, "done"), exist_ok=True)
        for p in files:
            shutil.move(p, os.path.join(INBOX, "done", os.path.basename(p)))


if __name__ == "__main__":
    main()
