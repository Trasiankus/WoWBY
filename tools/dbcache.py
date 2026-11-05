"""Server hotfixes from the beta's Cache/ADB/enUS/DBCache.bin (R219): Blizzard pushes changed DB2 rows at login
(new talents "Gore Drinker", changed spell texts) — they are NOT in the CASC files extract_forever reads.
Format (v9): header 'XFTH', version, build, 32-byte hash; then entries:
'XFTH', unk i32 (70), pushID i32, uniqueID u32, tableHash u32, recordID u32, dataSize i32, status u8 + 3 pad, data.
Strings in a record's data are NUL-terminated inline; we keep the printable ones per (table, record).
    python tools/dbcache.py            → summary per table hash + samples
    import: entries() → [(tableHash, recordID, status, [strings])]"""
import os, re, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import forever_client                                        # noqa: E402
CACHE = r"C:\Games\World of Warcraft\_classic_beta_\Cache\ADB\enUS\DBCache.bin"


def entries(path=None):
    """every install's DBCache.bin (R687), oldest build first: a later entry for the same row wins in the overlay"""
    if path is None:
        out = []
        for d in forever_client.install_dirs():
            p = os.path.join(d, "Cache", "ADB", "enUS", "DBCache.bin")
            if os.path.exists(p): out += entries(p)
        return out
    b = open(path, "rb").read()
    assert b[:4] == b"XFTH", "not a DBCache"
    pos = 4 + 4 + 4 + 32
    out = []
    while pos + 32 <= len(b):
        if b[pos:pos + 4] != b"XFTH":
            nxt = b.find(b"XFTH", pos + 1)
            if nxt < 0: break
            pos = nxt; continue
        _, push, uniq, th, rid, size, status = struct.unpack_from("<iiIIIiB", b, pos + 4)
        data = b[pos + 32: pos + 32 + max(size, 0)]
        strs = []
        for s in re.findall(rb"[\x20-\x7e\xc0-\xff][\x09\x0a\x0d\x20-\x7e\x80-\xff]{2,}(?=\x00)", data):
            try: t = s.decode("utf-8")                     # binary fields decode badly → not a string
            except UnicodeDecodeError: continue
            # float / int bytes can look like text ('?"lx?'): a real string has a 3-letter run and no '?' at either end
            if (re.search(r"[A-Za-z]{3}", t) and t.strip()[:1] != "?" and t.strip()[-1:] != "?"
                    and not re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", t)):
                strs.append(t)
        out.append((th, rid, status, strs))
        pos += 32 + max(size, 0)
    return out


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    es = entries()
    by = {}
    for th, rid, st, s in es:
        by.setdefault(th, []).append((rid, st, s))
    print(len(es), "entries in", len(by), "tables")
    for th, rows in sorted(by.items(), key=lambda x: -len(x[1]))[:25]:
        sample = next((r for r in rows if r[2]), rows[0])
        print("%08X %5d  e.g. %d %s" % (th, len(rows), sample[0], [x[:60] for x in sample[2][:3]]))
