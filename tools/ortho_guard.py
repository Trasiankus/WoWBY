"""R748 (official 2008 rules, re-read 2026-10-26): letter patterns a WRITE may never add — counted per word against the
text it replaces (an existing hit stays allowed until it is fixed; a new one is refused). Same idea as the skill's
apply.py ortho_guard, plus §16.3 (й before a vowel). All-caps abbreviations (ШІ:7) and $ / % / | tokens are skipped.
    from ortho_guard import guard     →  guard(old, new) = None or "ortho-guard (<what> added)"
    python tools/ortho_guard.py "old" "new"   (try it)"""
import re, sys

TOK = re.compile(r"\$[A-Za-z0-9]+(?::[^;]*;)?|\|c[0-9a-fA-F]{8}|\|r|\|[HhTt][^|]*\||%[0-9$.]*[sdif]|<[^>]*>")
V = "аеёіоуыэюя"
RULES = [
    ("р ж ш ч дж + і я е ё ю (§3.1)", re.compile("[рРжЖшШчЧ][іяеёюІЯЕЁЮ]")),
    ("ў after a consonant / й / ь / apostrophe (§15.1)", re.compile("[бвгджзйклмнпрстфхцчшьў'’]ў", re.I)),
    ("ь after б в м п ф ж ш ч р д т (§18.7)", re.compile("[бвмпфжшчрдтБВМПФЖШЧРДТ]ь")),
    ("й before a vowel (§16.3)", re.compile("(?<!^на)(?<!^На)[йЙ][%s]" % V, re.I)),
    ("Palladius чж / цз (2026 Chinese norm)", re.compile("чж|цз", re.I)),
]
SKIP = re.compile("чжурчж|маньчжур", re.I)


def _count(rx, s):
    n = 0
    for w in re.findall("[А-ЯЁІЎа-яёіў'’-]+", TOK.sub(" ", s or "")):
        if (len(w) > 1 and w.isupper()) or SKIP.search(w): continue
        for part in w.split("-"):
            n += len(rx.findall(part))
    return n


def guard(old, new):
    for name, rx in RULES:
        if _count(rx, new) > _count(rx, old):
            return "ortho-guard (%s added)" % name
    return None


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    print(guard(sys.argv[1], sys.argv[2]) or "ok")
