"""List localized DB2s (enUS != ruRU content) in the beta build + record counts."""
import struct
from wow_casc import Casc, build_key_for, load_listfile
import forever_client                    # newest Forever build installed (R687)

c = Casc(build_key_for(forever_client.product()))
lf = load_listfile(r"\.db2$")
rows = []
for fd, name in lf.items():
    en, ru = c.ckey_for(fd, "enUS"), c.ckey_for(fd, "ruRU")
    if en and ru and en != ru:
        d = c.read_ckey(en)
        if not d: rows.append((name, "NOT-INSTALLED", 0)); continue
        magic = d[:4].decode("latin1")
        off = 4 + (4 + 128 if magic == "WDC5" else 0)
        rc = struct.unpack_from("<I", d, off)[0]
        rows.append((name.split("/")[-1][:-4], magic, rc))
for r in sorted(rows): print(*r)
print(len(rows), "localized db2; missing TACT keys:", c.missing_keys)
