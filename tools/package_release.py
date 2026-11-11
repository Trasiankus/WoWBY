"""CurseForge release zip (owner 2026-10-22): release/WoWBY-<version>.zip with one top folder WoWBY/ (what the CurseForge
app unpacks into Interface/AddOns). Only the shipped addon: no WoWBY_Explore (beta helper), no backups / temp files.
Checks first: core Lua compiles + loads (check_core), every TOC file exists.
Version (owner 2026-11-11, R925): every release run gets a NEW number — the build date, then .2, .3 … for further
releases the same day (the next free number after every WoWBY-<date>*.zip already in release/; the plain date counts
as 1). The number is written into the zip's TOC and into addon/WoWBY/WoWBY.toc, so the game shows the same version.
    python tools/build_addon.py && python tools/package_release.py      (release_zip.bat does both)"""
import glob, os, re, subprocess, sys, zipfile
sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.path.join(ROOT, "addon", "WoWBY")
OUT = os.path.join(ROOT, "release")
SKIP = re.compile(r"(\.bak|\.orig|\.tmp|~|\.pyc)$|(^|[\\/])\.")
VER = re.compile(r"^## Version: (.+)$", re.M)


def next_version(base):
    """base = "2026.11.11" → the plain date if no zip of that day exists, else base.<highest + 1>."""
    nums = []
    for p in glob.glob(os.path.join(OUT, "WoWBY-%s*.zip" % base)):
        m = re.match(r"^WoWBY-%s(?:\.(\d+))?\.zip$" % re.escape(base), os.path.basename(p))
        if m:
            nums.append(int(m.group(1) or 1))
    return base if not nums else "%s.%d" % (base, max(nums) + 1)


def main():
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "check_core.py")], capture_output=True, text=True,
                       encoding="utf-8")
    if r.returncode != 0:
        print(r.stdout + r.stderr); sys.exit("check_core failed: not packaging")
    toc_path = os.path.join(SRC, "WoWBY.toc")
    toc = open(toc_path, encoding="utf-8").read()
    base = re.match(r"\d{4}\.\d{2}\.\d{2}", VER.search(toc).group(1).strip()).group(0)
    os.makedirs(OUT, exist_ok=True)
    version = next_version(base)
    toc = VER.sub("## Version: " + version, toc, count=1)
    open(toc_path, "w", encoding="utf-8", newline="\n").write(toc)
    listed = [l.split(" [")[0].strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")]
    missing = [f for f in listed if not os.path.exists(os.path.join(SRC, f.replace("\\", os.sep)))]
    if missing: sys.exit("TOC lists missing files: %s" % missing)
    zp = os.path.join(OUT, "WoWBY-%s.zip" % version)
    n = 0
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for d, _, files in os.walk(SRC):
            for f in sorted(files):
                p = os.path.join(d, f)
                rel = os.path.relpath(p, os.path.dirname(SRC)).replace(os.sep, "/")       # WoWBY/...
                if SKIP.search(rel): continue
                if rel == "WoWBY/data/forever.lua":
                    # R836: the owner's own harvest list (other players' names possible) stays out of the release
                    body = open(p, encoding="utf-8").read().split("\n-- R836: harvested text already imported")[0]
                    z.writestr(rel, body); n += 1; continue
                z.write(p, rel); n += 1
    print("%s: %d files, %.1f MB (unpacked %.1f MB), version %s" % (
        zp, n, os.path.getsize(zp) / 1e6, sum(i.file_size for i in zipfile.ZipFile(zp).infolist()) / 1e6, version))


if __name__ == "__main__":
    main()
