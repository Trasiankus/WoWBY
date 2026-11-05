"""R172: names (TACTID, 8 bytes) of TactKey records from the client's own TactKeyLookup.db2 (local CASC), for the keys the
server pushed into DBCache.bin (tools/tact_from_cache.py). Appends "NAME KEY" lines missing from ext/TACTKeys.txt.
    python tools/tact_lookup_names.py [--write]"""
import os, struct, sys
sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wow_casc import Casc, build_key_for, load_listfile  # noqa: E402
import forever_client                    # newest Forever build installed (R687)
from db2 import DB2  # noqa: E402
import tact_from_cache as tc  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
beta = Casc(build_key_for(forever_client.product()))
lf = {v.split("/")[-1][:-4]: k for k, v in load_listfile(r"^dbfilesclient/tactkeylookup\.db2$").items()}
raw = beta.read_fdid(lf["tactkeylookup"], "enUS")
db = DB2(raw, "TactKeyLookup")
rs = db.record_size
names = {}
for s in db.sections:
    n = s["record_count"]
    base = s["file_offset"]
    idl = base + n * rs + s["string_table_size"]
    ids = struct.unpack_from("<%dI" % (s["id_list_size"] // 4), db.d, idl) if s["id_list_size"] else ()
    for i in range(n):
        rec = db.d[base + i * rs: base + i * rs + 8]
        rid = ids[i] if i < len(ids) else None
        if rid is not None: names[rid] = rec
print("TactKeyLookup records:", len(names), "| record size", rs)
print("lookup names already in the list — little-endian:", sum(1 for nm in names.values() if nm[::-1].hex().upper() in
      {l.split()[0].upper() for l in open(os.path.join(ROOT, "ext", "TACTKeys.txt"), encoding="utf-8", errors="ignore") if l.split()}),
      "| as stored:", sum(1 for nm in names.values() if nm.hex().upper() in
      {l.split()[0].upper() for l in open(os.path.join(ROOT, "ext", "TACTKeys.txt"), encoding="utf-8", errors="ignore") if l.split()}))
kp = os.path.join(ROOT, "ext", "TACTKeys.txt")
have = {l.split()[0].upper() for l in open(kp, encoding="utf-8", errors="ignore") if l.split()}
new = []
for rid, key in sorted(tc.by[0xDF2F53CF].items()):
    nm = names.get(rid)
    if not nm:
        print("  key", rid, "has no lookup row"); continue
    le, be = nm[::-1].hex().upper(), nm.hex().upper()
    name = le if le in have or be not in have else be
    state = "known" if (le in have or be in have) else "NEW"
    print("  %d %s %s %s" % (rid, le, key.hex().upper(), state))
    if state == "NEW": new.append((le, key.hex().upper()))
if "--write" in sys.argv and new:
    with open(kp, "a", encoding="utf-8", newline="\n") as f:
        for nm, k in new: f.write("%s %s\n" % (nm, k))
    print("appended", len(new))
