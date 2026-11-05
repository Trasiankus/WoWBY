"""Which DB2 sections the Forever client keeps encrypted, under which TACT key, and whether we have that key (R726).
Encrypted sections hold rows of not-yet-released content; their key arrives later (a game patch, or a TactKey hotfix the
server pushes) — or from the community key list (ext/TACTKeys.txt, refresh it) once someone publishes it.
    python tools/encrypted_sections.py [table ...]      (default: ItemSparse SpellName Spell QuestV2 Creature)"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wow_casc import Casc
from db2 import DB2
from extract_forever import build_key_for, load_listfile, load_dbd
import forever_client

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def known_keys():
    ks = set()
    for l in open(os.path.join(ROOT, "ext", "TACTKeys.txt"), encoding="utf-8", errors="ignore"):
        p = l.split()
        if len(p) >= 2 and len(p[1]) == 32: ks.add(p[0].upper())
    return ks


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    tables = [t.lower() for t in sys.argv[1:]] or ["itemsparse", "spellname", "spell", "questv2", "creature"]
    beta = Casc(build_key_for(forever_client.product()))
    lf = {v.split("/")[-1][:-4]: k for k, v in load_listfile(r"^dbfilesclient/.*\.db2$").items()}
    keys = known_keys()
    for t in tables:
        dbd, real = load_dbd(t)
        d = DB2(beta.read_fdid(lf[t], "enUS"), real)
        enc = [s for s in d.sections if s.get("key")]
        print("%s: %d sections, %d encrypted" % (real, len(d.sections), len(enc)))
        for s in enc:
            k = "%016X" % s["key"] if isinstance(s["key"], int) else str(s["key"]).upper()
            print("   key %s  records %5d  %s" % (k, s["record_count"], "HAVE KEY" if k in keys else "no key"))


if __name__ == "__main__":
    main()
