"""Standing QA on new Belarusian text (owner 2026-11-20: "include them into the pipeline, not on demand").

Library used by translate/tools/validate.py (per chunk, LAYER 1: warnings the translating agent must fix or explain)
and tools/qa_new.py (after import, LAYER 2: the full grammar scan on the strings new since the last import).

  QA(texts)                      texts = every Belarusian text that will be checked (loads only the tags they need)
  QA.check(be, en="", layer=1)   -> [warning text, ...]

Checks (all from the parallel-localization skill + project data; nothing here is a new rule):
  unknown   a word grammardb (ext/slouniki/forms.tsv) does not know AND the shipped corpus (data/be) never uses —
            a typo, a Russian word or a new invented one (names: capitalised mid-sentence words are skipped)
  calque    such a word whose Russian spelling is in the rus-bel / rbs dictionaries with OTHER Belarusian words
            (skill calque_scan.py): «наградны» ← наградной: «узнагародны»
  rare      a real but rare dictionary word that is usually a calque (skill rare_lookalike.py): трудна → цяжка
  grammar   skill grammar.py line detectors. Layer 1: the mechanical / precise ones (у/ў, homoglyphs, lone Latin
            letter, spacing, quotes, doubled word, «яна павінен», «шмат людзі»). Layer 2: every detector (case after a
            preposition, agreement, verb gender, naturalness …) — high recall, a reviewer decides each.
"""
import glob, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKILL = os.path.join(os.path.expanduser("~"), ".claude", "skills", "parallel-localization", "scripts")
DICT = os.path.join(ROOT, "ext", "slouniki")
VOCAB = os.path.join(ROOT, "out", "qa_vocab.json")
RULES_MECH = {"u-short", "mixed-script", "latin-letter", "spacing", "quotes", "double-word"}
LAYER1 = {"u-short", "mixed-script", "latin-letter", "spacing", "quotes", "double-word", "pron-pred", "quant-case"}
# game tokens / codes → neutral filler (same length, no letters) so the detectors see words only
TOKEN = re.compile(r"\$[GgSs][^:;$]{0,40}:[^;$]{0,40};|\$[A-Za-z][A-Za-z0-9]*:[^;]*;|\$\d*[A-Za-z]+\d*|\|c[0-9a-fA-F]{8}|\|r|\|H[^|]*\|h|\|T[^|]*\|t|"
                   r"%\d*\$?[sdif]|<[^<>]{1,40}>|\\n")
L = "А-Яа-яЁёІіЎў'’A-Za-z-"
WLOW = re.compile(r"(?<![" + L + r"])([а-яёіў][а-яёіў'’]+)(?![" + L + r"])")
START = re.compile(r"(?:^|[.!?:—]\s+|§\s*|\n\s*|[«(\"]\s*)([А-ЯЁІЎ][а-яёіў'’]+)(?![" + L + r"])")


def _norm(w):
    w = w.lower().replace("’", "'").replace("́", "")
    return "у" + w[1:] if w[:1] == "ў" else w


def form_known(word):
    return form_lemmas(word) is not None


def form_lemmas(word, fname="forms.tsv"):
    """binary search in forms.tsv (sorted by form) → the lemma column ("" when listed without one), None = unknown.
    fname="stress.tsv": the stressed vowel numbers ("2" or "2,3")"""
    p = os.path.join(DICT, fname)
    key = _norm(word).encode("utf-8")
    with open(p, "rb") as f:
        lo, hi = 0, os.path.getsize(p)
        while lo < hi:
            mid = (lo + hi) // 2
            f.seek(mid); f.readline()
            line = f.readline()
            if not line or line.split(b"\t", 1)[0] >= key: hi = mid
            else: lo = mid + 1
        f.seek(lo)
        if lo: f.readline()
        for _ in range(3):
            k, _, v = f.readline().rstrip(b"\r\n").partition(b"\t")
            if k == key: return v.decode("utf-8")
            if k > key: break
    return None


def prefix_count(prefix, cap=5):
    """how many forms.tsv words start with prefix (stops at cap)"""
    p = os.path.join(DICT, "forms.tsv")
    key = _norm(prefix).encode("utf-8")
    n = 0
    with open(p, "rb") as f:
        lo, hi = 0, os.path.getsize(p)
        while lo < hi:
            mid = (lo + hi) // 2
            f.seek(mid); f.readline()
            line = f.readline()
            if not line or line.split(b"\t", 1)[0] >= key: hi = mid
            else: lo = mid + 1
        f.seek(lo)
        if lo: f.readline()
        while n < cap:
            k = f.readline().split(b"\t", 1)[0]
            if not k.startswith(key): break
            n += 1
    return n


VOWELS = "аеёіоуыэюя"


def yak_fix(word):
    """я written where the 2008 rules keep е (R1028, owner 2026-11-20: «зямлеступ» → «земляступ»): я replaces е only
    in the syllable right before the stress, so the first part of a compound keeps е (землятрус, земляроб, землякоп).
    Signal: no dictionary word starts with the я-spelling up to the next vowel, but several start with the е-spelling.
    Returns the corrected word or None."""
    w = _norm(word)
    if "'" in w: return None                                # Мяо'зан: a foreign name
    for i, ch in enumerate(w[:8]):
        if ch != "я" or i == 0 or w[i - 1] in VOWELS + "ьў'": continue
        alt = w[:i] + "е" + w[i + 1:]
        m = sum(1 for c in w[:i + 1] if c in VOWELS)        # the я is vowel number m
        if form_known(alt) and prefix_count(w[:-1], 1) == 0:   # «сняжка» = gen. of сняжо́к (сняжкі is listed)
            # суцяшыць → суцешыць: the е-spelling is a real word stressed ON that vowel or 2+ syllables later (а я
            # right before the stress would be right). Stress before it = another word (грэбня ≠ грэ́бне, ценява́й ≠ це́невы)
            st = [int(s) for s in (form_lemmas(alt, "stress.tsv") or "").split(",") if s.isdigit()]
            if st and all(s >= m and s != m + 1 for s in st): return alt
            continue
        j = next((k for k in range(i + 1, len(w)) if w[k] in VOWELS), None)
        if j is None or j == len(w) - 1: continue           # the я must start a compound's first part, not end the word
        if not (prefix_count(w[:j + 1], 1) == 0 and prefix_count(alt[:j + 1], 3) >= 3): continue
        # a linking я right before the stressed syllable is correct (нясвя́ты, ценяпа́шчы, землявы́лепнік): find the
        # second part in stress.tsv and where its stress falls; unknown second part → still flagged
        before_stress = False
        for k in range(i + 1, len(w) - 2):
            # the second part as written, else its longest known start (ценяпашчых → пашча, землявылепнік → вылепі)
            st = next((s for s in (form_lemmas(w[k:e], "stress.tsv") for e in range(len(w), k + 3, -1)) if s), None)
            if not st: continue
            between = sum(1 for c in w[i + 1:k] if c in VOWELS)
            if any(m + between + int(s) == m + 1 for s in st.split(",") if s.isdigit()): before_stress = True
            break                                           # the longest known second part decides
        if not before_stress: return alt
    return None


def _stress_of_start(s, minlen=3):
    """stressed vowel numbers of s, or of its longest dictionary start (≥ minlen letters); [] = unknown"""
    for e in range(len(s), minlen - 1, -1):
        st = form_lemmas(s[:e], "stress.tsv")
        if st: return [int(x) for x in st.split(",") if x.isdigit()], e
    return [], 0


def link_fix(word):
    """wrong linking vowel in a compound (R1029, owner 2026-11-20: «Каменалоб» → «Каменялоб»). After a first part the
    dictionary links with е/я (soft: каменя-, земле-) the link may not be а/о, and the reverse; е vs я by the stress:
    я right before the stressed syllable, е further away (землятрус, землеўладальнік). The second part must be a word
    (or start with one) the stress dictionary knows. Returns the corrected word or None."""
    w = _norm(word)
    if "'" in w or len(w) < 7 or form_known(w): return None
    for k in range(3, len(w) - 3):
        v = w[k]
        if v not in "аоея" or w[k - 1] in VOWELS + "ьў'" or w[k + 1] in VOWELS: continue
        first, second = w[:k], w[k + 1:]
        # the first part is a real word's stem (камен ← камень), the second a word or a long start of one (лоб, хват)
        if not any(form_known(first + e) for e in ("", "ь", "а", "я", "ы", "і")): continue
        st, n = _stress_of_start(second, 3)
        if not st or (n < len(second) and n < 5): continue
        soft = prefix_count(first + "е", 40) + prefix_count(first + "я", 40)
        hard = prefix_count(first + "а", 40) + prefix_count(first + "о", 40)
        # only the clear case: a hard link where the dictionary links this first part with е/я, or the reverse.
        # е vs я inside a soft link is NOT judged: the second part's own stress misleads (землятру́са ≠ труса́)
        if v in "ао" and soft >= 30 and hard <= 8:
            want = "я" if all(s == 1 for s in st) else "е"
            return first + want + second
        if v in "ея" and hard >= 30 and soft <= 8:
            return first + "а" + second
    return None


def corpus_vocab():
    """lower-case words of every shipped text (data/be), cached in out/qa_vocab.json until data/be changes"""
    files = glob.glob(os.path.join(ROOT, "data", "be", "*.json"))
    newest = max(os.path.getmtime(p) for p in files)
    if os.path.exists(VOCAB) and os.path.getmtime(VOCAB) >= newest:
        return set(json.load(open(VOCAB, encoding="utf-8")))
    words = set()
    for p in files:
        for e in json.load(open(p, encoding="utf-8")).values():
            t = e.get("be") if isinstance(e, dict) else None
            if isinstance(t, str):
                words.update(_norm(w) for w in re.findall(r"[А-Яа-яЁёІіЎў'’]+", t))
    os.makedirs(os.path.dirname(VOCAB), exist_ok=True)
    json.dump(sorted(words), open(VOCAB, "w", encoding="utf-8"), ensure_ascii=False)
    return words


def glossary_stems():
    """stems of every Belarusian word in the glossaries (translate/rules/glossary.tsv = turtle-bel + owner rows,
    data/glossary_forever.tsv): a word built on one («арканы» ← аркана) is a project term — never "unknown", and the
    case / agreement detectors skip it (grammardb may read it as another word: «арканы» = lassos)"""
    stems = set()
    for p in (os.path.join(ROOT, "translate", "rules", "glossary.tsv"), os.path.join(ROOT, "data", "glossary_forever.tsv")):
        if not os.path.exists(p): continue
        for line in open(p, encoding="utf-8"):
            if line.startswith("#") or "\t" not in line: continue
            for w in re.findall(r"[А-Яа-яЁёІіЎў'’]+", line.split("\t")[1]):
                s = re.sub(r"[аеёіоуыэюяйь]+$", "", _norm(w))
                if len(s) >= 4: stems.add((s, _norm(w)))
    # only terms that are not a dictionary headword themselves: unknown (Жалезнакузня) or only a form of ANOTHER word
    # (аркана = genitive of аркан, a lasso). A headword («горад», «вежа») keeps every check.
    out = set()
    for s, w in stems:
        lem = form_lemmas(w)
        if lem is None or w not in re.split(r"[,;| ]+", lem.lower()): out.add(s)
    return out


def _skill_import():
    """the skill's modules resolve their dictionary dir from the current directory → import them from ROOT"""
    if SKILL not in sys.path: sys.path.insert(0, SKILL)
    cwd = os.getcwd()
    os.chdir(ROOT)
    try:
        import grammar, rare_lookalike, calque_scan          # noqa: E401
    finally:
        os.chdir(cwd)
    return grammar, rare_lookalike, calque_scan


def mask(t):
    return TOKEN.sub(lambda m: "§" * len(m.group(0)), (t or "").replace("\r", ""))


class QA:
    def __init__(self, texts):
        self.grammar, self.rare, self.calq = _skill_import()
        masked = [mask(t) for t in texts]
        cwd = os.getcwd()
        os.chdir(ROOT)
        try:
            self.an = self.grammar.analyzer(self.grammar.load_tags(masked))
        finally:
            os.chdir(cwd)
        self.vocab = corpus_vocab()
        self.stems = glossary_stems()
        self._rd = None

    def term(self, w):
        """a form of a glossary word: its stem + an ending of at most 4 letters"""
        w = _norm(w)
        return any(w[:n] in self.stems for n in range(max(4, len(w) - 4), len(w) + 1))

    def russian(self):
        if self._rd is None:
            cwd = os.getcwd()
            os.chdir(ROOT)
            try:
                self._rd = self.calq.russian_dict()
            finally:
                os.chdir(cwd)
        return self._rd

    def calque_hint(self, w):
        rd = self.russian()
        for ru in sorted(self.calq.ru_spellings(w)):
            art = rd.get(ru)
            if not art: continue
            text = re.sub(r"\[[^\]]*\]|<[^>]*>", " ", art)
            be = set(re.findall(r"[а-яёіў'’]+", text.lower()))
            if any(x.startswith(w[:max(4, len(w) - 2)]) for x in be): return None
            return "%s: %s" % (ru, re.sub(r"\s+", " ", text).strip()[:90])
        return None

    def check(self, be, en="", layer=1):
        out = []
        t = mask(be)
        # unknown words (+ calque hint)
        names = {_norm(w) for w in re.findall(r"(?<=[а-яёіўa-z0-9,;)»] )([А-ЯЁІЎ][а-яёіў'’]+)", t)}
        words = [_norm(w) for w in WLOW.findall(t)]
        words += [w for w in (_norm(x) for x in START.findall(t)) if w not in names]
        seen = set()
        # я / е in a compound's first part (names too: «Зямлеход» is as wrong as «зямлеступ»); never KEEP-able
        for w in {_norm(x) for x in re.findall(r"[А-Яа-яЁёІіЎў'’]{6,}", t)}:
            if w in self.vocab and form_known(w): continue
            if not form_known(w):
                fix = yak_fix(w)
                if fix:
                    i = next(k for k in range(len(w)) if w[k] != fix[k])
                    out.append("spelling «%s»: first part «%s-» → «%s-» (я only right before the stress, so a compound's "
                               "first part keeps е: землятрус, земляроб, землеўладальнік)" % (w, w[:i + 1], fix[:i + 1]))
                    continue
                fix = link_fix(w)
                if fix: out.append("spelling «%s» → «%s»: linking vowel (after a soft first part е/я — я right before "
                                   "the stress, else е: каменяломня, землеўладальнік; after a hard one а)" % (w, fix))
        for w in words:
            if len(w) < 3 or w in seen or w in self.vocab or self.term(w) or form_known(w): continue
            seen.add(w)
            hint = self.calque_hint(w)
            out.append("unknown word «%s» (no dictionary, never used in the shipped text)%s — check it with lookup.py"
                       % (w, ("; Russian-like: " + hint) if hint else ""))
        # rare dictionary look-alikes
        for f in self.rare.flags(t):
            out.append(self.rare.warning(f))
        # grammar detectors
        try:
            cands = self.grammar.line_cands(t, en or "", self.an)
        except Exception as e:                                  # a detector bug must never block a chunk
            cands = []
            out.append("(grammar check skipped: %s)" % e)
        for kind, s, e, new, hint in cands:
            if layer == 1 and kind not in LAYER1: continue
            if "§" in t[max(0, s - 3):e + 3]: continue          # next to a game token ($N, $B, a colour code): unknowable
            old = be[s:e] if len(be) == len(t) else t[s:e]
            # a glossary term in the flagged span: grammardb judges it as some other word («ад арканы»: lassos)
            if kind not in RULES_MECH and any(self.term(x) for x in re.findall(r"[А-Яа-яЁёІіЎў'’]{4,}", old)): continue
            out.append("grammar %s: «%s»%s%s" % (kind, old, (" → «%s»" % new) if new else "", (" (%s)" % hint) if hint else ""))
        return out
