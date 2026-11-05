"""R240 (2026-10-08): Belarusian word-form index from Verbum grammardb (every form of every word, ~350 MB XML in the local
slouniki clone, read with git cat-file) -> ext/slouniki/forms.tsv  `form <TAB> lemma[,lemma…]` (lower case, stress marks
dropped, current spelling only: variants whose pravapis lists A2008). translate/tools/lookup.py uses it to say whether a
Belarusian word form exists (мяшочак ✓, мяшэчак ✗).
    python tools/build_forms.py"""
import os, re, subprocess, sys
sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLONE = r"C:\Projects\Rogue trader\work\slouniki2"
OUT = os.path.join(ROOT, "ext", "slouniki", "forms.tsv")
files = subprocess.run(["git", "-C", CLONE, "ls-tree", "--name-only", "HEAD", "grammardb/"], capture_output=True,
                       text=True, encoding="utf-8").stdout.split()
PDG = re.compile(r'<Paradigm [^>]*lemma="([^"]*)"')
VAR = re.compile(r'<Variant [^>]*?(?:pravapis="([^"]*)")?[^>]*>')
FORM = re.compile(r"<Form[^>]*>([^<]*)</Form>")
idx = {}
for fn in files:
    if not fn.endswith(".xml"): continue
    p = subprocess.Popen(["git", "-C", CLONE, "cat-file", "-p", "HEAD:" + fn], stdout=subprocess.PIPE)
    lemma, ok, n = None, True, 0
    for raw in p.stdout:
        line = raw.decode("utf-8", "replace")
        m = PDG.search(line)
        if m: lemma = m.group(1).replace("+", "").lower(); continue
        if "<Variant" in line:
            pv = re.search(r'pravapis="([^"]*)"', line)
            ok = not pv or "A2008" in pv.group(1)
            continue
        if ok and lemma:
            for f in FORM.findall(line):
                f = f.replace("+", "").lower()
                if f:
                    s = idx.setdefault(f, set())
                    if len(s) < 4: s.add(lemma)
                    n += 1
    p.wait()
    print(fn, n, "forms; index", len(idx))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    for form in sorted(idx): f.write("%s\t%s\n" % (form, ",".join(sorted(idx[form]))))
print("->", OUT, len(idx), "forms", os.path.getsize(OUT) // 1048576, "MB")
