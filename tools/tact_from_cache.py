"""R172: encryption keys the SERVER pushed to the beta client (hotfixes in Cache/ADB/enUS/DBCache.bin): TactKey rows
(16-byte key) + TactKeyLookup rows (8-byte key name), joined by record id → "NAME KEY" lines like ext/TACTKeys.txt.
No download: the client already has them.
    python tools/tact_from_cache.py            → shows tables shaped like the key tables + new keys
    python tools/tact_from_cache.py --write    → appends keys missing from ext/TACTKeys.txt"""
import collections, os, struct, sys
sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
CACHE = r"C:\Games\World of Warcraft\_classic_beta_\Cache\ADB\enUS\DBCache.bin"


def raw_entries(path=CACHE):
    b = open(path, "rb").read()
    pos = 4 + 4 + 4 + 32
    while pos + 32 <= len(b):
        if b[pos:pos + 4] != b"XFTH":
            nxt = b.find(b"XFTH", pos + 1)
            if nxt < 0: break
            pos = nxt; continue
        _, push, uniq, th, rid, size, status = struct.unpack_from("<iiIIIiB", b, pos + 4)
        yield th, rid, status, b[pos + 32: pos + 32 + max(size, 0)]
        pos += 32 + max(size, 0)


by = collections.defaultdict(dict)
for th, rid, st, data in raw_entries():
    if st == 1 and data: by[th][rid] = data                 # status 1 = valid row
sizes = {th: collections.Counter(len(d) for d in rows.values()) for th, rows in by.items()}
keys16 = [th for th, c in sizes.items() if set(c) == {16}]
look8 = [th for th, c in sizes.items() if set(c) == {8}]
print("tables with only 16-byte rows:", ["%08X(%d)" % (t, len(by[t])) for t in keys16])
print("tables with only 8-byte rows: ", ["%08X(%d)" % (t, len(by[t])) for t in look8])
have = set()
kp = os.path.join(ROOT, "ext", "TACTKeys.txt")
for l in open(kp, encoding="utf-8", errors="ignore"):
    p = l.split()
    if p: have.add(p[0].upper())
found = {}
for tk in keys16:
    for tl in look8:
        common = set(by[tk]) & set(by[tl])
        if not common: continue
        for rid in common:
            name = by[tl][rid][::-1].hex().upper()           # lookup stored little-endian → key name as written in lists
            name2 = by[tl][rid].hex().upper()
            key = by[tk][rid].hex().upper()
            found[rid] = (name, name2, key)
new = [(r, n, n2, k) for r, (n, n2, k) in found.items() if n not in have and n2 not in have]
print("key pairs in the cache:", len(found), "| not in ext/TACTKeys.txt:", len(new))
for r, n, n2, k in sorted(new)[:10]: print("  ", r, n, "/", n2, k)
if "--write" in sys.argv and new:
    # name orientation: the one already used in the file for an existing pair decides
    orient_le = any(f[0] in have for f in found.values())
    with open(kp, "a", encoding="utf-8", newline="\n") as f:
        for r, n, n2, k in sorted(new):
            f.write("%s %s\n" % (n if orient_le else n2, k))
    print("appended", len(new), "keys (", "LE" if orient_le else "BE", "names )")
