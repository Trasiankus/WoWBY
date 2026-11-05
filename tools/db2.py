"""WDC3/4/5 DB2 reader focused on text: yields (id, field_name, index, string) for every
string/locstring column, using WoWDBDefs (.dbd) definitions matched by layout hash."""
import os, re, struct

DBD_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ext", "WoWDBDefs", "definitions")


# ---------------------------------------------------------------- DBD
class DBD:
    FIELD_RX = re.compile(r"^(?:\$([^$]*)\$)?([A-Za-z0-9_:]+)(?:<(u?)(\d+)>)?(?:\[(\d+)\])?")

    def __init__(self, path):
        self.types, self.versions = {}, []
        sect, cur = None, None
        for raw in open(path, encoding="utf-8"):
            line = raw.split("//")[0].rstrip()
            if not line.strip():
                cur = None; continue
            if line == "COLUMNS":
                sect = "c"; continue
            if sect == "c" and not line.startswith(("LAYOUT", "BUILD", "COMMENT")):
                t, name = line.split()[0], line.split()[1].rstrip("?")
                self.types[name] = t.split("<")[0]
                continue
            sect = "v"
            if cur is None:
                cur = {"layouts": set(), "builds": [], "fields": []}; self.versions.append(cur)
            if line.startswith("LAYOUT"):
                cur["layouts"].update(h.strip().upper() for h in line[6:].split(","))
            elif line.startswith("BUILD"):
                cur["builds"].append(line[5:].strip())
            elif line.startswith("COMMENT"):
                pass
            else:
                m = self.FIELD_RX.match(line.strip())
                ann = (m.group(1) or "").split(",")
                name = m.group(2)
                cur["fields"].append({
                    "name": name, "type": self.types.get(name, "int"),
                    "size": int(m.group(4)) if m.group(4) else None,
                    "arr": int(m.group(5)) if m.group(5) else 1,
                    "inline": "noninline" not in ann, "id": "id" in ann})

    def by_layout(self, h):
        h = "%08X" % h
        for v in self.versions:
            if h in v["layouts"]: return v
        # 2026-10-28: Forever 1.60.1.70658 files carry layout hashes WoWDBDefs has not recorded (every table), while
        # its .dbd files list that build under the old layout — fall back to the version naming the client's build
        if BUILD:
            for v in self.versions:
                if any(BUILD in b.split(", ") or BUILD in [x.strip() for x in b.split(",")] for b in v["builds"]):
                    return v
        return None


BUILD = None      # "1.60.1.70658" — set by the caller (extract_forever) from the client's build config


# ---------------------------------------------------------------- DB2
def _bits(rec, off, size):
    return (int.from_bytes(rec, "little") >> off) & ((1 << size) - 1) if size else 0


class DB2:
    def __init__(self, data, name):
        self.name, d = name, data
        self.magic = d[:4].decode("latin1")
        if self.magic not in ("WDC3", "WDC4", "WDC5"): raise ValueError("unsupported " + self.magic)
        p = 4 + (132 if self.magic == "WDC5" else 0)
        (self.record_count, self.field_count, self.record_size, self.string_table_size, self.table_hash,
         self.layout_hash, _mn, _mx, _loc) = struct.unpack_from("<9I", d, p); p += 36
        self.flags, self.id_index = struct.unpack_from("<HH", d, p); p += 4
        (self.total_field_count, _bpo, _lcc, fsi_size, common_size, pallet_size,
         nsect) = struct.unpack_from("<7I", d, p); p += 28
        self.sections = []
        for _ in range(nsect):
            k, *rest = struct.unpack_from("<Q8I", d, p); p += 40
            self.sections.append(dict(zip(
                ("key", "file_offset", "record_count", "string_table_size", "offset_records_end",
                 "id_list_size", "relationship_data_size", "offset_map_id_count", "copy_table_count"),
                [k] + rest)))
        p += 4 * self.total_field_count  # field_structure (unused; storage info is authoritative)
        self.storage = []
        for i in range(fsi_size // 24):
            self.storage.append(struct.unpack_from("<HHIIIII", d, p)); p += 24
        pallet_blob = d[p:p + pallet_size]; p += pallet_size
        common_blob = d[p:p + common_size]; p += common_size
        # per-field pallet / common slices
        self.pallet, self.common = {}, {}
        po = co = 0
        for i, (_o, _s, add, comp, v1, v2, v3) in enumerate(self.storage):
            if comp in (3, 4):
                self.pallet[i] = struct.unpack_from("<%dI" % (add // 4), pallet_blob, po); po += add
            elif comp == 2:
                vals = struct.unpack_from("<%dI" % (add // 4), common_blob, co); co += add
                self.common[i] = dict(zip(vals[0::2], vals[1::2]))
        self.d = d
        self.sparse = bool(self.flags & 1)

    def field_value(self, rec, i, rid=None):
        """Packed fields (bitpacked / pallet) live at the field's record bit offset `off`, `v2` bits wide
        (`v1` is the offset inside the bitpacked block — NOT the record position; fixed 2026-09-25)."""
        off, size, add, comp, v1, v2, v3 = self.storage[i]
        if comp == 0:
            return _bits(rec, off, size)
        if comp in (1, 5):
            v = _bits(rec, off, v2)
            if comp == 5 and v >> (v2 - 1): v -= 1 << v2
            return v
        if comp == 2:
            return self.common[i].get(rid, v1)
        if comp == 3:
            return self.pallet[i][_bits(rec, off, v2)]
        if comp == 4:
            return self.pallet[i][_bits(rec, off, v2) * v3]
        raise ValueError("compression %d" % comp)

    def ids(self):
        """All record IDs (non-sparse tables; sparse -> offset-map ids), incl. copy-table IDs."""
        d, rs, out = self.d, self.record_size, set()
        for s in self.sections:
            p = (s["offset_records_end"] if self.sparse
                 else s["file_offset"] + s["record_count"] * rs + s["string_table_size"])
            n = s["id_list_size"] // 4
            if n:
                out.update(struct.unpack_from("<%dI" % n, d, p))
            elif not self.sparse:
                for k in range(s["record_count"]):
                    rec = d[s["file_offset"] + k * rs: s["file_offset"] + (k + 1) * rs]
                    if s["key"] and not any(rec): continue
                    out.add(self.field_value(rec, self.id_index))
            p += s["id_list_size"]
            out.update(struct.unpack_from("<I", d, p + 8 * k)[0] for k in range(s["copy_table_count"]))
            if self.sparse:
                p += 8 * s["copy_table_count"] + 6 * s["offset_map_id_count"] + s["relationship_data_size"]
                out.update(struct.unpack_from("<%dI" % s["offset_map_id_count"], d, p))
        return out

    def strings(self, dbd):
        """Yield (id, field, idx, text) for string/locstring columns."""
        ver = dbd.by_layout(self.layout_hash)
        if ver is None: raise LookupError("no DBD layout %08X for %s" % (self.layout_hash, self.name))
        inline = [f for f in ver["fields"] if f["inline"]]
        if not self.sparse and len(inline) != self.field_count:
            raise ValueError("%s: dbd inline %d != header %d" % (self.name, len(inline), self.field_count))
        d, rs = self.d, self.record_size
        total_rec_bytes = self.record_count * rs
        # concatenated string tables (non-sparse)
        strtab, gidx = bytearray(), 0
        out = []
        by_id, seen = {}, 0          # rows of `out` per record id, for the copy tables (was a full scan per copy: 50 s)
        for s in self.sections:
            base = s["file_offset"]
            if self.sparse:
                p = s["offset_records_end"]
            else:
                p = base + s["record_count"] * rs
                strtab += d[p:p + s["string_table_size"]]; p += s["string_table_size"]
            ids = struct.unpack_from("<%dI" % (s["id_list_size"] // 4), d, p); p += s["id_list_size"]
            copies = [struct.unpack_from("<II", d, p + 8 * k) for k in range(s["copy_table_count"])]
            p += 8 * s["copy_table_count"]
            omap = [struct.unpack_from("<IH", d, p + 6 * k) for k in range(s["offset_map_id_count"])]
            p += 6 * s["offset_map_id_count"]
            p += s["relationship_data_size"]
            omap_ids = struct.unpack_from("<%dI" % s["offset_map_id_count"], d, p)
            s.update(ids=ids, copies=copies, omap=omap, omap_ids=omap_ids, gidx=gidx)
            gidx += s["record_count"]

        for s in self.sections:
            recs = []
            if self.sparse:
                ids = s["ids"] or s["omap_ids"]
                for k, (off, size) in enumerate(s["omap"]):
                    if size == 0: continue
                    recs.append((ids[k] if k < len(ids) else None, off, size))
                for rid, off, size in recs:
                    if rid is None: continue
                    try:
                        for fname, idx, txt in self._sparse_rec(d[off:off + size], inline):
                            out.append((rid, fname, idx, txt))
                    except (struct.error, IndexError, UnicodeDecodeError):
                        pass  # zero-filled encrypted record
            else:
                base = s["file_offset"]
                for k in range(s["record_count"]):
                    ro = base + k * rs
                    rec = d[ro:ro + rs]
                    if s["key"] and not any(rec): continue  # encrypted, key unknown
                    rid = s["ids"][k] if s["ids"] else self.field_value(rec, self.id_index)
                    g = (s["gidx"] + k) * rs
                    for fi, f in enumerate(inline):
                        if f["type"] not in ("string", "locstring"): continue
                        foff = self.storage[fi][0] // 8
                        for a in range(f["arr"]):
                            fo = foff + 4 * a
                            v = struct.unpack_from("<I", rec, fo)[0]
                            if v == 0: continue
                            sp = g + fo + v - total_rec_bytes
                            if not 0 <= sp < len(strtab): continue
                            e = strtab.index(0, sp)
                            txt = strtab[sp:e].decode("utf-8", "replace")
                            if txt: out.append((rid, f["name"], a, txt))
            if not s["copies"]: continue
            for r in out[seen:]: by_id.setdefault(r[0], []).append(r)
            for new, old in s["copies"]:
                add = [(new, fn, a, t) for (_r, fn, a, t) in by_id.get(old, ())]
                out += add
                by_id.setdefault(new, []).extend(add)
            seen = len(out)
        return out

    def ints(self, dbd, want):
        """{id: {field: value}} for the named integer columns (first element of array fields)."""
        ver = dbd.by_layout(self.layout_hash)
        if ver is None: raise LookupError("no DBD layout %08X for %s" % (self.layout_hash, self.name))
        inline = [f for f in ver["fields"] if f["inline"]]
        idx = {f["name"]: i for i, f in enumerate(inline) if f["name"] in want}
        out, d, rs = {}, self.d, self.record_size
        for s in self.sections:
            if self.sparse:
                p = s["offset_records_end"]
            else:
                p = s["file_offset"] + s["record_count"] * rs + s["string_table_size"]
            ids = struct.unpack_from("<%dI" % (s["id_list_size"] // 4), d, p); p += s["id_list_size"]
            copies = [struct.unpack_from("<II", d, p + 8 * k) for k in range(s["copy_table_count"])]
            p += 8 * s["copy_table_count"]
            if self.sparse:
                omap = [struct.unpack_from("<IH", d, p + 6 * k) for k in range(s["offset_map_id_count"])]
                p += 6 * s["offset_map_id_count"] + s["relationship_data_size"]
                omap_ids = struct.unpack_from("<%dI" % s["offset_map_id_count"], d, p)
                ids = ids or omap_ids
                for k, (off, size) in enumerate(omap):
                    if not size or k >= len(ids): continue
                    rec, q, row = d[off:off + size], 0, {}
                    try:
                        for f in inline:
                            for a in range(f["arr"]):
                                if f["type"] in ("string", "locstring"):
                                    q = rec.index(0, q) + 1; continue
                                n = 4 if f["type"] == "float" else (f["size"] or 32) // 8
                                if a == 0 and f["name"] in idx: row[f["name"]] = int.from_bytes(rec[q:q + n], "little")
                                q += n
                    except ValueError:
                        continue
                    out[ids[k]] = row
            else:
                for k in range(s["record_count"]):
                    rec = d[s["file_offset"] + k * rs: s["file_offset"] + (k + 1) * rs]
                    if s["key"] and not any(rec): continue
                    rid = ids[k] if ids else self.field_value(rec, self.id_index)
                    row = {}
                    for name, i in idx.items():
                        off, size, _a, comp, v1, v2, v3 = self.storage[i]
                        if comp == 0 and inline[i]["arr"] > 1:           # inline array: first element only
                            row[name] = _bits(rec, off, size // inline[i]["arr"])
                        else:
                            row[name] = self.field_value(rec, i, rid)
                    out[rid] = row
            for new, old in copies:
                if old in out: out[new] = dict(out[old])
        return out

    @staticmethod
    def _sparse_rec(rec, inline):
        p = 0
        for f in inline:
            for a in range(f["arr"]):
                t = f["type"]
                if t in ("string", "locstring"):
                    e = rec.index(0, p)
                    txt = rec[p:e].decode("utf-8"); p = e + 1
                    if txt: yield f["name"], a, txt
                elif t == "float":
                    p += 4
                else:
                    p += (f["size"] or 32) // 8


def load_dbd(table):
    """table name case-insensitive -> DBD or None."""
    want = table.lower() + ".dbd"
    for fn in os.listdir(DBD_DIR):
        if fn.lower() == want: return DBD(os.path.join(DBD_DIR, fn)), fn[:-4]
    return None, table
