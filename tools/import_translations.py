"""Import finished translations from translate/done/ into the addon build inputs.

    python tools/import_translations.py      (then: python tools/build_addon.py)

Only chunks that pass translate/tools/validate.py are imported. Writes:
  data/strings_be.json        quests {"quest:<id>": {t,o,d,p,c}}, names/zones {"name:<EN>": {"v": BE}}, gossip
                              (quests_gender re-pass wins over quests; "<male/female>" pairs -> $Gmale:female;)
  data/auto_spelldesc.json    {md5(en)[:8]: BE}   spelldesc + auras + stylefix (same keyspace as turtle-bel)
  data/auto_names.json        {"spells": {EN: BE}, "items": {EN: BE}}   (queue grouped them by English name)
  data/auto_ui.tsv            en<TAB>be   UI strings (plain + format), SLASH_/DEBUG keys never shipped
Re-runnable; overwrites these four files from the current done/ state."""
import glob, hashlib, json, os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TR = os.path.join(ROOT, "translate")
sys.path.insert(0, os.path.join(TR, "tools"))
from validate import validate  # noqa: E402
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from terms_rules import fix_terms  # noqa: E402

NO_SHIP = re.compile(r"^SLASH_|DEBUG")
# R325: old "gossip:<first 80 chars>[#hash]" corpus key → "gossip:<full EN>" (review/gossip_fullkeys.py)
_GK = os.path.join(ROOT, "data", "gossip_keymap.json")
GOSSIP_KEYMAP = json.load(open(_GK, encoding="utf-8")) if os.path.exists(_GK) else {}
GPAIR = re.compile(r"<([^<>/\n]{1,40})/([^<>/\n]{1,40})>")   # wowhead's rendering of $G — the addon needs the token


GFORM = re.compile(r"\$G([^:;$]+):([^;$]+);")


def carry_g(prev, new):
    """Two packages rewrote the same field from the same old text (quests_address added the PLAYER's gender forms,
    quests_speaker the NPC's own): the later text keeps the earlier one's $Gm:f; — each masculine form m that the
    later text still has as a plain whole word (not inside a $G already) becomes $Gm:f; (2026-10-01: 18 fields had
    lost their player-gender forms)."""
    for m, f in GFORM.findall(prev):
        if "$G%s:%s;" % (m, f) in new:
            continue
        pat = re.compile(r"(?<![\w$:])%s(?![\w;])" % re.escape(m))
        hit = pat.search(new)
        if hit and not new[max(0, hit.start() - 2):hit.start()].endswith("$G"):
            new = new[:hit.start()] + "$G%s:%s;" % (m, f) + new[hit.end():]
    return new


def chunks(pkg):
    for dpath in sorted(glob.glob(os.path.join(TR, "done", pkg, "*.json"))):
        errs, _ = validate(dpath)
        qpath = os.path.join(TR, "queue", pkg, os.path.basename(dpath))
        if errs or not os.path.exists(qpath):
            print("  skip %s (%d validation errors)" % (os.path.relpath(dpath, TR), len(errs))); continue
        done = json.load(open(dpath, encoding="utf-8"))["items"]
        for it in json.load(open(qpath, encoding="utf-8"))["items"]:
            if it["id"] in done:
                yield it, done[it["id"]]


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sbe, n = {}, {}
    for pkg in ("quests", "quests_gender", "quests_namefix"):
        for it, be in chunks(pkg):
            sbe["quest:" + it["id"]] = {f: GPAIR.sub(r"$G\1:\2;", v) for f, v in be.items() if v}
    for pkg, pre in (("names", "name:"), ("zones", "zone:"), ("gossip", "gossip:"), ("objectives", "objective:")):
        for it, be in chunks(pkg):
            # gossip (R325): keyed by the FULL English (queue ids are the old 80-char prefix)
            k = pre + (it["en"] if pkg == "gossip" and isinstance(it.get("en"), str) else it["id"])
            sbe[k] = {"v": be}
    for it, be in chunks("quests_update"):                       # re-scraped fields: MERGE into the quest
        q = sbe.setdefault("quest:" + it["id"], {})
        q.update({f: GPAIR.sub(r"$G\1:\2;", v) for f, v in be.items() if v})
    json.dump(sbe, open(os.path.join(ROOT, "data", "strings_be.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    n["quests/names/zones"] = len(sbe)

    desc = {}
    for pkg in ("spelldesc", "auras", "stylefix", "spelldesc_redo"):
        for it, be in chunks(pkg):
            desc[it["id"]] = be
    json.dump(desc, open(os.path.join(ROOT, "data", "auto_spelldesc.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    n["spell/aura texts"] = len(desc)

    names = {"spells": {}, "items": {}}
    for pkg, key in (("spellnames", "spells"), ("items", "items")):
        for it, be in chunks(pkg):
            names[key][it["en"]] = be
    json.dump(names, open(os.path.join(ROOT, "data", "auto_names.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    redo = {it["id"]: be for pkg in ("items_redo", "items_hidden") for it, be in chunks(pkg)}   # R65 + R726 (hidden vanilla items), by item id
    json.dump(redo, open(os.path.join(ROOT, "data", "auto_items_redo.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    n["item names redone"] = len(redo)
    sredo = {it["en"]: be for pkg in ("spellnames_redo", "spellnames_redo2") for it, be in chunks(pkg)}  # R132: re-translated learnable spell names, by EN
    json.dump(sredo, open(os.path.join(ROOT, "data", "auto_spellnames_redo.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    n["spell names redone"] = len(sredo)
    tit = {it["en"]: be for it, be in chunks("titles")}            # NPC titles (wowhead lists) -> WoWBY_Titles
    json.dump(tit, open(os.path.join(ROOT, "data", "auto_titles.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    n["npc titles"] = len(tit)
    n["spell names"], n["item names"] = len(names["spells"]), len(names["items"])

    # quests_address: player-gender forms added to FINAL texts -> written straight into data/be/ as hand edits
    # (the corpus keeps them; tools/corpus.py reports a conflict if that quest's upstream text changes later)
    from corpus import DIR as BE_DIR
    be_files, n_addr, written = {}, 0, {}
    # R325b: every re-pass result is applied ONCE. Re-applying the finished chunks on every import overwrote later
    # corpus fixes made by data scripts (2026-10-09: the WC3-sync «выклікальнік», «жнец» went back to the chunk wording).
    # data/repass_applied.json = md5 of (package, item, field, chunk text) already written; --record-only marks the
    # current chunks as applied without writing (bootstrap).
    rp_path = os.path.join(ROOT, "data", "repass_applied.json")
    rp_done = set(json.load(open(rp_path, encoding="utf-8"))) if os.path.exists(rp_path) else set()
    record_only = "--record-only" in sys.argv
    n_skip = 0
    stale_rows, orig = [], {}
    for pkg_, it, be in [(pkg, *x) for pkg in ("quests_address", "quests_unify", "quests_itemfix", "quests_speaker", "quests_capfix", "names_qa", "zones_qa", "quests_natural", "gossip_natural", "quests_classic_update") for x in chunks(pkg)]:
        tgt = it.get("target") or {}
        if not tgt and isinstance(it.get("en"), str) and isinstance(be, str):          # names_qa (target not in the queue)
            # names_qa / zones_qa: the queue item has no target; zones_qa items carry a zones note in "fix"
            zq = "zone / place names" in " ".join(it.get("fix") or []) or "Bladefist Bay" in " ".join(it.get("fix") or [])
            tgt = {"domain": "tb_zones" if zq else "tb_names", "keys": {"v": it["en"]}}
        elif not tgt and str(it.get("id", "")).startswith("tb:") and isinstance(be, dict) and list(be) == ["o"]:
            tgt = {"domain": "tb_quests", "keys": {"o": it["id"][3:] + ".o"}}          # quests_capfix
        dom, keys = tgt.get("domain"), tgt.get("keys") or {}
        if not dom:
            continue
        # gossip_natural chunks written before R325 target the old "gossip:<80 chars>" corpus keys
        keys = {f: GOSSIP_KEYMAP.get(k, k) for f, k in keys.items()}
        if dom not in be_files:
            be_files[dom] = json.load(open(os.path.join(BE_DIR, dom + ".json"), encoding="utf-8"))
        if isinstance(be, str):                                  # names_qa: one string per name
            be = {"v": be}
        for f, v in be.items():
            k = keys.get(f)
            if not (k in be_files[dom] and v):
                continue
            h = hashlib.md5(("%s|%s|%s|%s" % (pkg_, it.get("id"), f, v)).encode("utf-8")).hexdigest()[:16]
            if h in rp_done or record_only:
                rp_done.add(h); n_skip += 1
                continue
            rp_done.add(h)
            # the text the agent rewrote must still be the shipped one (2026-10-13): a chunk queued days ago carries
            # an old be_current; a hand / script fix made since then would be overwritten by a rewrite of the old
            # text → such fields are skipped and listed in out/repass_stale.tsv (re-queue them if the rewrite matters)
            bc = it.get("be_current")
            bc = bc.get(f) if isinstance(bc, dict) else (bc if isinstance(bc, str) and f == "v" else None)
            cur = orig.setdefault((dom, k), be_files[dom][k]["be"])     # before this import's own writes
            if isinstance(bc, str) and cur not in (bc, fix_terms(bc), fix_terms(GPAIR.sub(r"$G\1:\2;", bc))):
                stale_rows.append((pkg_, str(it.get("id")), dom, k, bc, cur, v))
                continue
            # owner rules on the way in (2026-10-01): these chunks were written before later rules (Таўраха, дзік,
            # скрутак…); writing them raw re-imported the old wording on EVERY import (132 texts reverted)
            v = fix_terms(GPAIR.sub(r"$G\1:\2;", v))
            prev = written.get((dom, k))
            if prev:                                   # an earlier package wrote this field in this import
                v = carry_g(prev, v)
            written[(dom, k)] = v
            if be_files[dom][k]["be"] != v:
                be_files[dom][k]["be"] = v; n_addr += 1
    if stale_rows:
        with open(os.path.join(ROOT, "out", "repass_stale.tsv"), "a", encoding="utf-8", newline="\n") as f:
            esc = lambda s: (s or "").replace("\t", " ").replace("\r", "").replace("\n", "\\n")
            for r in stale_rows: f.write("\t".join(esc(x) for x in r) + "\n")
    n["re-pass fields skipped: shipped text changed since queued (out/repass_stale.tsv)"] = len(stale_rows)
    for dom, d in be_files.items():
        with open(os.path.join(BE_DIR, dom + ".json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(d, f, ensure_ascii=False, indent=0, sort_keys=True)
            f.write("\n")
    with open(rp_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(sorted(rp_done), f, indent=0)
    n["re-pass fields already applied (skipped)"] = n_skip
    n["gender forms added (data/be)"] = n_addr

    rows = []
    for pkg in ("ui", "ui_later", "ui_unused", "ui_termfix", "emotes", "ui_prof", "itemsets", "enchants", "achievements",
                "chartitles", "factions", "focus", "tips", "flavor", "item_text", "db2_misc", "barber"):
        for it, be in chunks(pkg):
            if pkg == "flavor":                                   # the tooltip shows it in quotes
                rows.append(('"%s"' % it["en"], '"%s"' % be))
            if it.get("keys") and all(NO_SHIP.search(k) for k in it["keys"]):
                continue
            rows.append((it["en"], be))
    with open(os.path.join(ROOT, "data", "auto_ui.tsv"), "w", encoding="utf-8", newline="\n") as f:
        f.write("en\tbe\n")
        esc = lambda s: s.replace("\\", "\\\\").replace("\t", "\\t").replace("\r", "").replace("\n", "\\n")
        for en, be in rows:
            f.write("%s\t%s\n" % (esc(en), esc(be)))
    n["ui strings"] = len(rows)
    labels = {pkg: {it["en"]: be for it, be in chunks(pkg)} for pkg in ("suffixes", "books")}   # runtime tables (R141/R138)
    json.dump(labels, open(os.path.join(ROOT, "data", "auto_labels.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    n["suffixes/book pages"] = sum(len(v) for v in labels.values())
    print("imported: " + ", ".join("%s %d" % kv for kv in n.items()))
    print("Next: python tools/build_addon.py")


if __name__ == "__main__":
    main()
