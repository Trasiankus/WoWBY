"""Stress index from Verbum grammardb (local copy C:\\Projects\\Qwen\\bench\\ext\\grammardb_xml; the slouniki2 clone lost its
.git) -> ext/slouniki/stress.tsv  `form <TAB> stressed vowel numbers` (1 = first vowel; several = "2,3" when forms
differ). Used by review/compound_o.py (§5: о / а in the first part of compound words depends on the stress of the
second part). Current spelling only (variants whose pravapis lists A2008, or none).
    python tools/build_stress.py"""
import glob, os, re, sys
sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = r"C:\Projects\Qwen\bench\ext\grammardb_xml"
OUT = os.path.join(ROOT, "ext", "slouniki", "stress.tsv")
FORM = re.compile(r"<Form[^>]*>([^<]*)</Form>")
VOW = set("аеёіоуыэюяАЕЁІОУЫЭЮЯ")
idx = {}
for fn in sorted(glob.glob(os.path.join(SRC, "*.xml"))):
    ok = True
    for line in open(fn, encoding="utf-8"):
        if "<Variant" in line:
            pv = re.search(r'pravapis="([^"]*)"', line)
            ok = not pv or "A2008" in pv.group(1)
            continue
        if not ok or "<Form" not in line:
            continue
        for f in FORM.findall(line):
            if "+" not in f:
                continue
            n, st = 0, set()
            for ch in f:
                if ch in VOW:
                    n += 1
                elif ch == "+":
                    st.add(n)
            w = f.replace("+", "").lower()
            idx.setdefault(w, set()).update(st)
    print(os.path.basename(fn), len(idx))
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    for w in sorted(idx):
        f.write("%s\t%s\n" % (w, ",".join(map(str, sorted(idx[w])))))
print("->", OUT, len(idx))
