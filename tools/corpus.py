"""Project-owned final Belarusian text: data/be/<domain>.json (owner 2026-09-28).

Every piece of Belarusian the addon ships goes through here. Upstream sources (turtle-bel files, Gemini's
translate/done via data/strings_be.json + auto_*.json, our hand .tsv files) stay untouched; data/be/ holds the FINAL
text per entry, with the owner wording rules (tools/terms_rules.py) already applied — plain JSON you can read and edit.

Entry: {"be": final text, "src": hash of the upstream text (+EN context), "auto": hash of what intake produced,
        "en": EN context, only where a rule needs it (spell_word)}.

Corpus(domain).get(key, upstream, en=None):
  * upstream unchanged since the last build -> the stored "be" (hand edits survive);
  * new key, or upstream changed -> rules applied once to the new upstream, stored, returned;
  * upstream changed but the stored text was hand-edited (be != auto) -> the hand text is kept and the key is
    reported as a conflict until you resolve it (edit "be", or delete the entry to take the new upstream).
Entries whose upstream disappeared are dropped on save (reported).
Corpus.park(key) (R718): the build skips a key Forever cannot show (tools/forever_scope.py); its entry moves to
data/be_parked/<domain>.json — out of every scan / QA / rule run — and returns as it was (hand edits too) once a later
build ships the key again.
"""
import hashlib, json, os

from terms_rules import DOMAIN_RULES, fix_terms, spell_word

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
DIR = os.path.join(ROOT, "data", "be")
PARKED = os.path.join(ROOT, "data", "be_parked")


def h(s):
    return hashlib.md5(s.encode("utf-8")).hexdigest()[:10]


def rules(text, en=None, domain=None):
    """The full owner rule chain for one text (spell_word only where the EN context allows it; + the domain's own
    rules, e.g. sentence case for spell names)."""
    out = fix_terms(text)
    if en:
        out = spell_word(out, en)
    extra = DOMAIN_RULES.get(domain)
    return extra(out) if extra else out


class Corpus:
    def __init__(self, domain):
        self.domain = domain
        self.path = os.path.join(DIR, domain + ".json")
        self.d = json.load(open(self.path, encoding="utf-8")) if os.path.exists(self.path) else {}
        self.ppath = os.path.join(PARKED, domain + ".json")
        self.pk = json.load(open(self.ppath, encoding="utf-8")) if os.path.exists(self.ppath) else {}
        self.seen, self.new, self.changed, self.conflicts = set(), 0, 0, []
        self.parked, self.restored = set(), 0

    def park(self, key):
        self.parked.add(str(key))

    def get(self, key, upstream, en=None, fix=rules):
        key = str(key)
        self.seen.add(key)
        if key not in self.d and key in self.pk:        # back in scope: the parked entry as it was
            self.d[key] = self.pk.pop(key)
            self.restored += 1
        src = h(upstream + "\x1f" + (en or ""))
        e = self.d.get(key)
        if e and e.get("src") == src:
            return e["be"]
        be = fix(upstream, en, self.domain) if fix is rules else fix(upstream)
        if e and h(e["be"]) != e.get("auto"):          # hand-edited, and upstream moved on: keep the hand text
            if be != e["be"]:                           # (upstream now says the same as the hand text: adopt it quietly)
                self.conflicts.append(key)
                return e["be"]
        ent = {"be": be, "src": src, "auto": h(be)}
        if en:
            ent["en"] = en
        if e:
            self.changed += 1
        else:
            self.new += 1
        self.d[key] = ent
        return be

    def save(self):
        moved = [k for k in self.d if k in self.parked and k not in self.seen]
        for k in moved:
            self.pk[k] = self.d.pop(k)
        stale = [k for k in self.d if k not in self.seen]
        for k in stale:
            del self.d[k]
        pk_stale = [k for k in self.pk if k not in self.parked] if self.parked or self.seen else []
        for k in pk_stale:                              # gone upstream altogether
            del self.pk[k]
        if self.new or self.changed or stale or moved or self.restored or not os.path.exists(self.path):
            _write(self.path, self.d)                   # untouched corpus: no rewrite
        if moved or pk_stale or self.restored:
            _write(self.ppath, self.pk)
        parts = []
        if moved: parts.append("%d parked (not in Forever)" % len(moved))
        if self.restored: parts.append("%d restored from parked" % self.restored)
        if self.new: parts.append("%d new" % self.new)
        if self.changed: parts.append("%d updated from upstream" % self.changed)
        if stale: parts.append("%d dropped (gone upstream)" % len(stale))
        if self.conflicts:
            parts.append("%d CONFLICTS (hand-edited, upstream changed): %s" % (
                len(self.conflicts), ", ".join(self.conflicts[:5]) + (" …" if len(self.conflicts) > 5 else "")))
        return "%s: %d entries%s" % (self.domain, len(self.d), (" — " + "; ".join(parts)) if parts else "")


def _write(path, d):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w", encoding="utf-8", newline="\n") as f:      # atomic (R435)
        json.dump(d, f, ensure_ascii=False, indent=0, sort_keys=True)
        f.write("\n")
    os.replace(path + ".tmp", path)
