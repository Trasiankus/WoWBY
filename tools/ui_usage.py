"""Which GlobalStrings keys can WoW Forever's own UI reach?

Forever (game type `camelot`, mainline family) ships the whole mainline GlobalStrings table, Legion+ features
included. This loads the beta's FrameXML (ext/beta-ui) the way the client does for camelot — addon-level and
per-file AllowLoadGameType / ExcludeLoadGameType, [Family] = mainline, [Game] = camelot, XML Include/Script —
and collects the identifiers the loaded code references.

    python tools/ui_usage.py          prints counts
    from ui_usage import classifier;  why = classifier()(key) -> "code" | "prefix" | "engine" | None

"engine": families the client sends as text without Lua referencing the key (errors, spell failures, stats…).
None = never referenced: queued last (translate package `ui_unused`)."""
import glob, os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
AD = os.path.join(ROOT, "ext", "beta-ui", "interface", "addons")
GAME = {"camelot", "mainline"}
ENGINE = re.compile(r"^(ERR_|SPELL_FAILED_|LOOT_|CHAT_MSG_|COMBATLOG_|INSTANCE_|LFG_|PETITION_|GUILD_|RAID_|PARTY_|"
                    r"TRADE_|MAIL_|AUCTION_|ITEM_|SPELL_|STAT_|DURABILITY|QUEST_|OBJECTIVE|UNIT_|PET_|TALENT|"
                    r"INVTYPE_|FACTION_|SKILL|EMOTE|MOUNT|BIND|KEY_|OPTION_|VIDEO_|AUDIO_|SOUND_)")


def _allowed(cond):
    m = re.search(r"AllowLoadGameType\s*:?\s*([^\]\n]*)", cond)
    if m and not (GAME & {x.strip().lower() for x in m.group(1).split(",")}): return False
    m = re.search(r"ExcludeLoadGameType\s*:?\s*([^\]\n]*)", cond)
    return not (m and (GAME & {x.strip().lower() for x in m.group(1).split(",")}))


def _resolve(base, rel):
    rel = rel.replace("[Family]", "mainline").replace("[Game]", "camelot").replace("\\", "/").strip()
    p = os.path.normpath(os.path.join(base, rel.lower()))
    return p if os.path.exists(p) else None


def loaded_files():
    loaded = set()
    for toc in glob.glob(os.path.join(AD, "*", "*.toc")):
        base = os.path.dirname(toc)
        lines = open(toc, encoding="utf-8", errors="replace").read().splitlines()
        head = "\n".join(l for l in lines if re.match(r"## (Allow|Exclude)LoadGameType", l))
        if head and not _allowed(head): continue
        for l in lines:
            if not l.strip() or l.startswith("#"): continue
            m = re.match(r"^(.*?)(\s*\[(?:Allow|Exclude)LoadGameType[^\]]*\])?\s*$", l)
            if m.group(2) and not _allowed(m.group(2)): continue
            p = _resolve(base, m.group(1))
            if p: loaded.add(p)
    todo = [p for p in loaded if p.endswith(".xml")]
    while todo:
        x = todo.pop()
        for m in re.finditer(r'<(?:Include|Script)\s+file="([^"]+)"', open(x, encoding="utf-8", errors="replace").read()):
            p = _resolve(os.path.dirname(x), m.group(1))
            if p and p not in loaded:
                loaded.add(p)
                if p.endswith(".xml"): todo.append(p)
    return loaded


def classifier():
    code = "\n".join(open(p, encoding="utf-8", errors="replace").read() for p in loaded_files())
    idents = set(re.findall(r"\b[A-Z][A-Z0-9_]{2,}\b", code))
    prefixes = [p for p in set(re.findall(r'"([A-Z][A-Z0-9_]*)"\s*\.\.', code)) if len(p) >= 5]

    def why(key):
        if key in idents: return "code"
        if any(key.startswith(p) for p in prefixes): return "prefix"
        if ENGINE.match(key): return "engine"
        return None
    return why


if __name__ == "__main__":
    import csv, collections
    csv.field_size_limit(10 ** 9)
    why = classifier()
    rows = list(csv.reader(open(os.path.join(ROOT, "out", "globalstrings_keys.tsv"), encoding="utf-8"), delimiter="\t"))[1:]
    print("files loaded for camelot: %d" % len(loaded_files()))
    print(dict(collections.Counter(why(r[0]) or "unused" for r in rows)))
