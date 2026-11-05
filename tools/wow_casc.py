"""Minimal read-only CASC reader for a local WoW install (shared Data/ storage).

    casc = Casc(build_key_hex)          # build config key from .build.info
    data = casc.read_fdid(fdid, 'enUS') # bytes or None (not installed / missing)

Layers: build config -> encoding (CKey->EKey, paged, looked up lazily)
-> root (MFST, FileDataID + locale/content flags -> CKey) -> local .idx -> data.NNN -> BLTE.
Encrypted BLTE chunks are decrypted with ext/TACTKeys.txt when the key is known,
otherwise zero-filled (like CascLib) and counted in casc.missing_keys."""
import os, struct, zlib, glob, bisect

WOW = r"C:\Games\World of Warcraft"
DATA = os.path.join(WOW, "Data")
HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(HERE, "..", "ext")

LOCALES = {"enUS": 0x2, "koKR": 0x4, "frFR": 0x10, "deDE": 0x20, "zhCN": 0x40, "esES": 0x80,
           "zhTW": 0x100, "enGB": 0x200, "esMX": 0x1000, "ruRU": 0x2000, "ptBR": 0x4000, "itIT": 0x8000}
LOW_VIOLENCE = 0x80


def be32(b, o=0): return struct.unpack_from(">I", b, o)[0]


def read_config(key_hex):
    p = os.path.join(DATA, "config", key_hex[:2], key_hex[2:4], key_hex)
    cfg = {}
    for line in open(p, encoding="utf-8"):
        if " = " in line:
            k, v = line.rstrip("\n").split(" = ", 1)
            cfg[k] = v.split()
    return cfg


# ---------------------------------------------------------------- salsa20 (TACT)
def _rotl(v, c): return ((v << c) & 0xffffffff) | (v >> (32 - c))


def _salsa_block(inp):
    x = list(inp)
    def qr(a, b, c, d):
        x[b] ^= _rotl((x[a] + x[d]) & 0xffffffff, 7)
        x[c] ^= _rotl((x[b] + x[a]) & 0xffffffff, 9)
        x[d] ^= _rotl((x[c] + x[b]) & 0xffffffff, 13)
        x[a] ^= _rotl((x[d] + x[c]) & 0xffffffff, 18)
    for _ in range(10):
        qr(0, 4, 8, 12); qr(5, 9, 13, 1); qr(10, 14, 2, 6); qr(15, 3, 7, 11)
        qr(0, 1, 2, 3); qr(5, 6, 7, 4); qr(10, 11, 8, 9); qr(15, 12, 13, 14)
    return struct.pack("<16I", *[(x[i] + inp[i]) & 0xffffffff for i in range(16)])


def salsa20(key16, nonce8, data):
    k = struct.unpack("<4I", key16); n = struct.unpack("<2I", nonce8)
    c = struct.unpack("<4I", b"expand 16-byte k")
    out = bytearray(len(data))
    for blk in range(0, len(data), 64):
        ctr = blk // 64
        st = [c[0], k[0], k[1], k[2], k[3], c[1], n[0], n[1], ctr & 0xffffffff, ctr >> 32,
              c[2], k[0], k[1], k[2], k[3], c[3]]
        ks = _salsa_block(st)
        seg = data[blk:blk + 64]
        out[blk:blk + len(seg)] = bytes(a ^ b for a, b in zip(seg, ks))
    return bytes(out)


def load_keys():
    keys = {}
    p = os.path.join(EXT, "TACTKeys.txt")
    if os.path.exists(p):
        for line in open(p, encoding="utf-8", errors="replace"):
            f = line.split()
            if len(f) >= 2 and len(f[0]) == 16 and len(f[1]) == 32:
                try: keys[int(f[0], 16)] = bytes.fromhex(f[1])
                except ValueError: pass
    return keys


# ---------------------------------------------------------------- local index
class Idx:
    def __init__(self, datadir):
        self.map = {}
        buckets = {}
        for p in glob.glob(os.path.join(datadir, "*.idx")):
            n = os.path.basename(p)
            b, ver = int(n[0:2], 16), int(n[2:10], 16)
            if b not in buckets or buckets[b][0] < ver: buckets[b] = (ver, p)
        for _, p in buckets.values(): self._parse(p)

    def _parse(self, path):
        d = open(path, "rb").read()
        lenH = struct.unpack_from("<I", d, 0)[0]
        (_v, _b, _x, encSizeLen, stOffLen, ekeyLen, offBits) = struct.unpack_from("<HBBBBBB", d, 8)
        pos = (8 + lenH + 15) & ~15
        lenE = struct.unpack_from("<I", d, pos)[0]; pos += 8
        esz = ekeyLen + stOffLen + encSizeLen
        mask = (1 << offBits) - 1
        m = self.map
        for i in range(lenE // esz):
            e = d[pos + i * esz: pos + (i + 1) * esz]
            k = e[:ekeyLen]
            if k in m: continue
            raw = int.from_bytes(e[ekeyLen:ekeyLen + stOffLen], "big")
            m[k] = (raw >> offBits, raw & mask, int.from_bytes(e[ekeyLen + stOffLen:], "little"))
        self.ekeyLen = ekeyLen

    def find(self, ekey): return self.map.get(bytes(ekey)[:self.ekeyLen])


# ---------------------------------------------------------------- CASC
class Casc:
    def __init__(self, build_key, idx=None):
        self.cfg = read_config(build_key)
        self.build_name = self.cfg.get("build-name", ["?"])[0]
        self.datadir = os.path.join(DATA, "data")
        self.idx = idx or Idx(self.datadir)
        self.keys = load_keys()
        self.missing_keys = {}
        self._handles = {}
        self._init_encoding(self.read_ekey(bytes.fromhex(self.cfg["encoding"][1])))
        root_ek = self.ckey_to_ekey(bytes.fromhex(self.cfg["root"][0]))
        self._init_root(self.read_ekey(root_ek))

    # -- raw
    def read_ekey(self, ekey):
        loc = self.idx.find(ekey)
        if not loc: return None
        arc, off, size = loc
        f = self._handles.get(arc)
        if f is None:
            f = self._handles[arc] = open(os.path.join(self.datadir, "data.%03d" % arc), "rb")
        f.seek(off); raw = f.read(size)
        return self.blte(raw[30:])

    def blte(self, data):
        assert data[:4] == b"BLTE", data[:8]
        hsize = be32(data, 4)
        if hsize == 0: return self._chunk(data[8:], 0, None)
        cnt = int.from_bytes(data[9:12], "big")
        pos, dpos, out = 12, hsize, []
        for i in range(cnt):
            cs, ds = be32(data, pos), be32(data, pos + 4); pos += 24
            out.append(self._chunk(data[dpos:dpos + cs], i, ds)); dpos += cs
        return b"".join(out)

    def _chunk(self, c, idx, dsize):
        m = c[0:1]
        if m == b"N": return c[1:]
        if m == b"Z": return zlib.decompress(c[1:])
        if m == b"F": return self.blte(c[1:])
        if m == b"E":
            p = 1
            kn = c[p]; p += 1
            keyname = int.from_bytes(c[p:p + kn], "little"); p += kn
            ivs = c[p]; p += 1
            iv = bytearray(c[p:p + ivs]); p += ivs
            typ = c[p:p + 1]; p += 1
            key = self.keys.get(keyname)
            if key is None or typ != b"S":
                self.missing_keys[keyname] = self.missing_keys.get(keyname, 0) + 1
                return bytes(dsize or 0)
            for i in range(4): iv[i] ^= (idx >> (i * 8)) & 0xff
            return self._chunk(salsa20(key, bytes(iv).ljust(8, b"\0"), c[p:]), idx, dsize)
        raise ValueError("unknown BLTE mode %r" % m)

    # -- encoding (lazy page lookup)
    def _init_encoding(self, d):
        assert d[:2] == b"EN"
        self.enc = d
        ckp_kb = struct.unpack_from(">H", d, 5)[0]
        ckp_cnt = be32(d, 9)
        espec = be32(d, 18)
        pos = 22 + espec
        self.enc_first = [d[pos + i * 32: pos + i * 32 + 16] for i in range(ckp_cnt)]
        self.enc_pages = pos + ckp_cnt * 32
        self.enc_psize = ckp_kb * 1024

    def ckey_to_ekey(self, ckey):
        i = bisect.bisect_right(self.enc_first, ckey) - 1
        if i < 0: return None
        d, p = self.enc, self.enc_pages + i * self.enc_psize
        end = p + self.enc_psize
        while p + 22 <= end:
            kc = d[p]
            if kc == 0: break
            if d[p + 6:p + 22] == ckey: return d[p + 22:p + 38]
            p += 22 + kc * 16
        return None

    # -- root (MFST)
    def _init_root(self, d):
        self.root = {}  # fdid -> list of (locale_flags, content_flags, ckey)
        assert d[:4] == b"TSFM", d[:4]
        hs, ver = struct.unpack_from("<II", d, 4)
        if hs > 1000:  # old header: magic,total,named
            total, named = hs, ver; pos, ver = 12, 0
        else:
            total, named = struct.unpack_from("<II", d, 12); pos = hs
        allow_nonamed = named < total
        while pos < len(d):
            if ver >= 2:
                n, loc, f1, f2, f3 = struct.unpack_from("<IIIIB", d, pos); pos += 17
                cf = f1 | f2 | (f3 << 17)
            else:
                n, cf, loc = struct.unpack_from("<III", d, pos); pos += 12
            deltas = struct.unpack_from("<%di" % n, d, pos); pos += 4 * n
            ck = d[pos:pos + 16 * n]; pos += 16 * n
            if not (allow_nonamed and cf & 0x10000000): pos += 8 * n
            fd = -1
            for i in range(n):
                fd += deltas[i] + 1
                self.root.setdefault(fd, []).append((loc, cf, ck[i * 16:i * 16 + 16]))

    def ckey_for(self, fdid, locale="enUS"):
        lf = LOCALES[locale]
        best = None
        for loc, cf, ck in self.root.get(fdid, ()):
            if loc & lf and not cf & LOW_VIOLENCE: return ck
            if loc & lf: best = ck
        return best

    def read_ckey(self, ck):
        ek = self.ckey_to_ekey(ck)
        return self.read_ekey(ek) if ek else None

    def read_fdid(self, fdid, locale="enUS"):
        ck = self.ckey_for(fdid, locale)
        return self.read_ckey(ck) if ck else None


def build_key_for(product):
    hdr, rows = None, []
    for line in open(os.path.join(WOW, ".build.info"), encoding="utf-8"):
        cols = line.rstrip("\n").split("|")
        if hdr is None: hdr = [c.split("!")[0] for c in cols]; continue
        rows.append(dict(zip(hdr, cols)))
    for r in rows:
        if r.get("Product") == product: return r["Build Key"]
    # 2026-10-28: the launcher keeps only ACTIVE products in .build.info (wow_anniversary vanished while it was
    # downloading Anniversary 70577). Fall back to the build configs in Data/config: newest build of that product
    # whose data is actually local (a half-downloaded build fails to open and is skipped).
    tag = PRODUCT_TAGS.get(product)
    if tag:
        import glob, re
        cands = []
        for p in glob.glob(os.path.join(WOW, "Data", "config", "*", "*", "*")):
            try: head = open(p, encoding="utf-8", errors="replace").read(4000)
            except OSError: continue
            m = re.search(r"^build-name = WOW-(\d+)patch\S*%s\s*$" % re.escape(tag), head, re.M)
            if m: cands.append((int(m.group(1)), os.path.basename(p)))
        for _, key in sorted(cands, reverse=True):
            try:
                Casc(key)
                return key
            except Exception:
                continue
    raise KeyError(product)


PRODUCT_TAGS = {"wow_anniversary": "_Anniversary", "wow_classic_beta": "_Beta", "wow_classic_era": "_ClassicRetail"}


def load_listfile(pattern=None):
    """fdid -> path (lowercase) from ext/community-listfile.csv; optional regex filter."""
    import re
    rx = re.compile(pattern) if pattern else None
    out = {}
    for line in open(os.path.join(EXT, "community-listfile.csv"), encoding="utf-8", errors="replace"):
        fd, _, name = line.rstrip("\n").partition(";")
        if rx and not rx.search(name): continue
        try: out[int(fd)] = name
        except ValueError: pass
    return out
