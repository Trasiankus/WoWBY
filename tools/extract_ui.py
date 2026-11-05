"""Extract the beta client's interface code (interface/addons/**.lua|xml|toc) from the local CASC into ext/beta-ui, by the
community listfile. Re-run after a new beta build; prints files added / changed / removed.   python tools/extract_ui.py
(Same content as github.com/Gethe/wow-ui-source branch "forever", which keeps one commit per build.)"""
import hashlib, os, sys
sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wow_casc import Casc, build_key_for  # noqa: E402
import forever_client                    # newest Forever build installed (R687)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "ext", "beta-ui")
LF = os.path.join(ROOT, "ext", "community-listfile.csv")


def main():
    casc = Casc(build_key_for(forever_client.product()))
    old = {}
    for dp, _, fs in os.walk(OUT):
        for f in fs:
            p = os.path.join(dp, f)
            old[os.path.relpath(p, OUT).replace("\\", "/")] = hashlib.md5(open(p, "rb").read()).hexdigest()
    seen, added, changed = set(), [], []
    for row in open(LF, encoding="utf-8", errors="replace"):
        fid, _, name = row.strip().partition(";")
        name = name.lower()
        if not (name.startswith("interface/addons/") and name.endswith((".lua", ".xml", ".toc"))): continue
        try:
            data = casc.read_fdid(int(fid), "enUS")
        except Exception:  # noqa: BLE001  (not in this build)
            continue
        if not data: continue
        seen.add(name)
        h = hashlib.md5(data).hexdigest()
        if old.get(name) == h: continue
        (changed if name in old else added).append(name)
        p = os.path.join(OUT, *name.split("/"))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "wb").write(data)
    removed = sorted(n for n in old if n.startswith("interface/addons/") and n not in seen)
    print("files: %d in build | %d added, %d changed, %d no longer in the build (kept)" % (
        len(seen), len(added), len(changed), len(removed)))
    for n in sorted(changed)[:60]: print("  changed", n)
    for n in sorted(added)[:30]: print("  added  ", n)


if __name__ == "__main__":
    main()
