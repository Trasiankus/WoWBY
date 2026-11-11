"""R888 (owner 2026-11-11, «Целабудова 23» still in the stat tooltip after Stamina = Вынослівасць: "if we change a term, we
need to check all cases and fix there too!!!"): the owner rules (terms_rules.fix_terms) also run over every HAND table
that wins over the corpus at build time, and over the shipped Lua strings in addon/WoWBY/core. Before, fix_corpus only
rewrote data/be — a term changed there stayed old in ui.lua stat names, ui_be.tsv formats, names_fix.tsv surnames…
    python tools/fix_hand_tables.py          rewrite + print the changes
    python tools/fix_hand_tables.py --check  only report (exit 1 when something would change); fix_corpus --check calls it
Core Lua is report-only (fix the real hits by hand). Tables: data/*.tsv whose 2nd (or 3rd for name_unify) column is Belarusian; core Lua: only "…" string literals with Cyrillic.
Skipped on purpose: word_fix / soft_td_fix (rule tables: their OLD column must keep the old form) and owner rows the owner
kept against a rule (KEEP)."""
import glob, os, re, sys
sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import terms_rules  # noqa: E402

SKIP = {"word_fix.tsv", "soft_td_fix.tsv", "yakanne_fix.tsv", "spell_fix.tsv", "surname_fixes.tsv",   # rule tables
        "auto_ui.tsv", "name_caps.tsv"}   # upstream input (corpus intake applies the rules) / a word list
KEEP = {("glossary_forever.tsv", "Linen"), ("glossary_forever.tsv", "Spiced Wolf Meat")}
CYR = re.compile("[А-Яа-яЁёІіЎў]")
check = "--check" in sys.argv
changed = []

for p in sorted(glob.glob(os.path.join(ROOT, "data", "*.tsv"))):
    fn = os.path.basename(p)
    if fn in SKIP:
        continue
    lines = open(p, encoding="utf-8").read().split("\n")
    dirty = False
    for i, line in enumerate(lines):
        q = line.split("\t")
        if len(q) < 2 or q[0].startswith("#") or (fn, q[0]) in KEEP:
            continue
        for c in (1, 2) if fn == "name_unify.tsv" else (1,):
            if c < len(q) and CYR.search(q[c]):
                nb = terms_rules.fix_terms(q[c])
                if nb != q[c]:
                    changed.append("%s:%d  %s | %s -> %s" % (fn, i + 1, q[0][:40], q[c][:60], nb[:60]))
                    q[c] = nb
                    dirty = True
        lines[i] = "\t".join(q)
    if dirty and not check:
        open(p, "w", encoding="utf-8", newline="\n").write("\n".join(lines))

LIT = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
# core Lua: REPORT ONLY. Match patterns there must keep old forms (base.lua race-form lists, spells.lua unit keys), and
# deliberate spacing must stay; a run on 2026-11-11 that rewrote them had to be reverted by hand.
# Lua strings that are deliberately "old" (patterns / keys) and must not be reported:
# (+ Russian chat-tab names WoWBY matches to translate them, R912)
LUA_OK = re.compile(r"^(?:[а-яёіў' ]+\|)+[а-яёіў' ]+$|^(?:ярд|ярда|ярдов)$|  >  |^(?:Журнал боя|Общий|Общее|Голос)$")
lua_hits = []
for p in sorted(glob.glob(os.path.join(ROOT, "addon", "WoWBY", "core", "*.lua"))):
    src = open(p, encoding="utf-8").read()
    def sub(m):
        s = m.group(1)
        if not CYR.search(s):
            return m.group(0)
        nb = terms_rules.fix_terms(s)
        if nb != s and not LUA_OK.search(s):
            lua_hits.append("%s  %s -> %s" % (os.path.basename(p), s[:60], nb[:60]))
        return m.group(0)
    LIT.sub(sub, src)                                          # never writes

for c in changed:
    print(c)
for c in lua_hits:
    print("LUA (fix by hand if it is shipped text): " + c)
print("hand tables %s: %d | core Lua strings to check by hand: %d" % ("that would change" if check else "changed",
                                                                    len(changed), len(lua_hits)))
if check and (changed or lua_hits):
    sys.exit(1)
