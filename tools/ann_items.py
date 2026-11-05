"""Item id -> English name from the Anniversary client (2.5.x: every vanilla + TBC item, unencrypted) → out/ann_items.json.
R726: vanilla items whose Forever row is encrypted are shipped by name only when the Anniversary client has that id with
the same English name as turtle-bel (Turtle re-used low ids for its own items: 2 = "Ebon Gryphon").
    python tools/ann_items.py"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wow_casc import Casc
from db2 import DB2
from extract_forever import build_key_for, load_listfile, load_dbd

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ann = Casc(build_key_for("wow_anniversary"))
    lf = {v.split("/")[-1][:-4]: k for k, v in load_listfile(r"^dbfilesclient/itemsparse\.db2$").items()}
    dbd, real = load_dbd("itemsparse")
    d = DB2(ann.read_fdid(lf["itemsparse"], "enUS"), real)
    out = {}
    for rid, field, idx, s in d.strings(dbd):
        if field == "Display_lang" and s: out[str(rid)] = s
    json.dump(out, open(os.path.join(ROOT, "out", "ann_items.json"), "w", encoding="utf-8"), ensure_ascii=False)
    print("Anniversary items:", len(out))


if __name__ == "__main__":
    main()
