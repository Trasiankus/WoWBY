"""R854: locative of every shipped zone name, learned from our own Belarusian texts ("у Брыле", "на Сонечнай паляне").
zone_loc(zones {en: be}) -> {en: (prep, loc)}; prep = "у" | "на" (the runtime writes «ў» after a vowel).
Only forms seen in data/be after у/ў/ва/на that are not the nominative / a feminine accusative are taken; the most
frequent wins. A zone never written after a preposition gets nothing (the caller falls back to «X (Брыл)»)."""
import collections, glob, json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L = "а-яёіўА-ЯЁІЎ'’"


def _corpus():
    out = []
    for f in glob.glob(os.path.join(ROOT, "data", "be", "*.json")):
        if os.path.basename(f).startswith(("tb_quests", "forever", "tb_gossip", "books", "hand")):
            for e in json.load(open(f, encoding="utf-8")).values():
                b = e.get("be") if isinstance(e, dict) else None
                if isinstance(b, str):
                    out.append(b)
    return "\n".join(out)


def _stem(w):
    return w[:-2] if len(w) > 5 else w[:-1] if len(w) > 3 else w


def zone_loc(zones):
    text = _corpus()
    res = {}
    for en, be in zones.items():
        words = be.split()
        if not words or len(words) > 4 or not all(re.fullmatch("[" + L + "-]+", w) for w in words):
            continue
        rx = r"(?<![" + L + r"])(у|ў|ва|на) (" + " ".join(re.escape(_stem(w)) + "[" + L + r"]{0,4}" for w in words) + r")(?![" + L + "])"
        cnt = collections.Counter()
        last_nom = words[-1].lower()
        for m in re.finditer(rx, text):
            form = m.group(2)
            ws = form.split()
            # the words after the preposition must keep the name's capitals (a capitalised word stays capitalised)
            if any(w[:1].isupper() != f[:1].isupper() for w, f in zip(words, ws)):
                continue
            last = ws[-1].lower()
            if last == last_nom:
                continue                                  # nominative = masculine accusative ("у Брыл")
            if last_nom[-1:] in "ая" and last[-1:] in "ую":
                continue                                  # feminine accusative ("у Жалезнакузню")
            if last_nom[-1:] in "ыі" and len(ws) == len(words) and last.endswith(("ыя", "ія")):
                continue
            prep = "на" if m.group(1) == "на" else "у"
            cnt[(prep, form)] += 1
        if cnt:
            res[en] = cnt.most_common(1)[0][0]
    return res


if __name__ == "__main__":
    import sys
    sys.stdout.reconfigure(encoding="utf-8")
    test = {"Brill": "Брыл", "Sunnyglade": "Сонечная паляна", "Stormwind City": "Штармавей", "Ironforge": "Жалезнакузня",
            "Deathknell": "Пахавальны Звон", "Goldshire": "Залатарэчча"}
    for k, v in zone_loc(test).items():
        print(k, v)
