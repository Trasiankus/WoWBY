"""WoW Forever installs (R687, 2026-10-21). Two Forever clients share the CASC Data\\ folder:
  _classic_beta_   product wow_classic_beta   (the beta, 1.60.1.70450 on 2026-10-17)
  _forever_        product wowf               (the stress-test client, 1.60.1.70532 on 2026-10-21)
Tools read client data (DB2s) from the NEWEST build and merge the server caches (WDB, DBCache.bin, SavedVariables) of
EVERY install — the owner plays either one. FOREVER_PRODUCT=<product> picks a build instead of the newest.
    from forever_client import product, newest, install_dirs
    python tools/forever_client.py      → the installs found, newest first"""
import os

WOW = r"C:\Games\World of Warcraft"
INSTALLS = {"wowf": "_forever_", "wow_classic_beta": "_classic_beta_"}


def _vt(v):
    try: return tuple(int(x) for x in v.split("."))
    except ValueError: return (0,)


def builds():
    """[{product, version, key, dir}] of the Forever installs present, newest build first."""
    hdr, out = None, []
    for line in open(os.path.join(WOW, ".build.info"), encoding="utf-8"):
        cols = line.rstrip("\n").split("|")
        if hdr is None:
            hdr = [c.split("!")[0] for c in cols]; continue
        r = dict(zip(hdr, cols))
        p = r.get("Product")
        d = os.path.join(WOW, INSTALLS.get(p, ""))
        if p in INSTALLS and os.path.isdir(d):
            out.append({"product": p, "version": r.get("Version", "?"), "key": r.get("Build Key"), "dir": d})
    return sorted(out, key=lambda b: _vt(b["version"]), reverse=True)


def newest():
    bs = builds()
    want = os.environ.get("FOREVER_PRODUCT")
    for b in bs:
        if b["product"] == want: return b
    if not bs: raise SystemExit("no WoW Forever install found in %s" % WOW)
    return bs[0]


def product():
    return newest()["product"]


def install_dirs():
    """every install folder, OLDEST build first — merge caches in this order so the newest build's data wins"""
    return [b["dir"] for b in reversed(builds())]


if __name__ == "__main__":
    for b in builds():
        print("%-18s %-14s %s" % (b["product"], b["version"], b["dir"]))
    print("newest:", product())
