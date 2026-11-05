"""CurseForge release zip (owner 2026-10-22): release/WoWBY-<version>.zip with one top folder WoWBY/ (what the CurseForge
app unpacks into Interface/AddOns). Only the shipped addon: no WoWBY_Explore (beta helper), no backups / temp files.
Checks first: core Lua compiles + loads (check_core), every TOC file exists, the TOC version is today's build.
    python tools/build_addon.py && python tools/package_release.py      (package_release.bat does both)"""
import os, re, subprocess, sys, zipfile
sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.path.join(ROOT, "addon", "WoWBY")
OUT = os.path.join(ROOT, "release")
SKIP = re.compile(r"(\.bak|\.orig|\.tmp|~|\.pyc)$|(^|[\\/])\.")


def main():
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "check_core.py")], capture_output=True, text=True,
                       encoding="utf-8")
    if r.returncode != 0:
        print(r.stdout + r.stderr); sys.exit("check_core failed: not packaging")
    toc = open(os.path.join(SRC, "WoWBY.toc"), encoding="utf-8").read()
    version = re.search(r"^## Version: (.+)$", toc, re.M).group(1).strip()
    listed = [l.split(" [")[0].strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")]
    missing = [f for f in listed if not os.path.exists(os.path.join(SRC, f.replace("\\", os.sep)))]
    if missing: sys.exit("TOC lists missing files: %s" % missing)
    os.makedirs(OUT, exist_ok=True)
    zp = os.path.join(OUT, "WoWBY-%s.zip" % version)
    n = 0
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for d, _, files in os.walk(SRC):
            for f in sorted(files):
                p = os.path.join(d, f)
                rel = os.path.relpath(p, os.path.dirname(SRC)).replace(os.sep, "/")       # WoWBY/...
                if SKIP.search(rel): continue
                z.write(p, rel); n += 1
    print("%s: %d files, %.1f MB (unpacked %.1f MB), version %s" % (
        zp, n, os.path.getsize(zp) / 1e6, sum(i.file_size for i in zipfile.ZipFile(zp).infolist()) / 1e6, version))


if __name__ == "__main__":
    main()
