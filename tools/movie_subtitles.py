"""Movie (pre-rendered cinematic) subtitles: interface/cinematics/*.srt files in the beta CASC (R480). The subtitles are
shown by SubtitlesFrame as "[Speaker] line" — WoWBY's hook_subtitles translates them via WoWBY_Gossip, so the lines go
to the translator as gossip.   python tools/movie_subtitles.py [--scan]  → out/movie_subtitles.json
--scan also tries every root file id near the known .srt ids (new movies are often missing from the community listfile)."""
import json, os, re, sys
sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wow_casc import Casc, build_key_for  # noqa: E402
import forever_client                    # newest Forever build installed (R687)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LF = os.path.join(ROOT, "ext", "community-listfile.csv")


def parse_srt(text):
    lines = []
    for block in re.split(r"\r?\n\r?\n", text.strip()):
        rows = [r for r in block.splitlines() if r.strip()]
        if len(rows) >= 3 and "-->" in rows[1]:
            lines.append(" ".join(rows[2:]).strip())
    return lines


def main():
    casc = Casc(build_key_for(forever_client.product()))
    known = {}
    for row in open(LF, encoding="utf-8", errors="replace"):
        fid, _, name = row.strip().partition(";")
        if name.endswith(".srt"): known[int(fid)] = name
    ids = dict(known)
    if "--scan" in sys.argv:
        for fid in list(known):
            for d in range(-300, 301):
                ids.setdefault(fid + d, None)
    out = {}
    for fid, name in sorted(ids.items()):
        for loc in ("enUS", "ruRU"):
            try:
                data = casc.read_fdid(fid, loc)
            except Exception:  # noqa: BLE001
                data = None
            if not data: continue
            text = data.decode("utf-8-sig", errors="replace")
            if "-->" not in text[:400]: continue
            out.setdefault(str(fid), {"name": name})[loc] = parse_srt(text)
    json.dump(out, open(os.path.join(ROOT, "out", "movie_subtitles.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    for fid, e in out.items():
        en = e.get("enUS") or []
        print(fid, e.get("name"), len(en), "lines |", (en[:2] if en else ""))


if __name__ == "__main__":
    main()
