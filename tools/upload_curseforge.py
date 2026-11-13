"""Upload a release zip to CurseForge (owner 2026-11-13). Runs ONLY when the owner says so; without --upload it is a
dry run that shows exactly what would be sent.

    python tools/upload_curseforge.py                 # dry run: newest release/WoWBY-*.zip + its CHANGELOG
    python tools/upload_curseforge.py --versions      # list CurseForge game versions (pick names for the config)
    python tools/upload_curseforge.py --upload        # really upload (owner's go-ahead)
    python tools/upload_curseforge.py --zip release/WoWBY-2026.11.13.zip --upload

The API token is read from curseforge_api_key.txt in the project root (gitignored by *api_key*; never printed, never
copied into the public repo — make_public_repo only copies addon / translations / tools). Settings (no secrets) live
in release/curseforge.json: {"project_id": 123456, "game_versions": ["1.15.7"], "release_type": "release"}.
API: CurseForge's author upload API (wow.curseforge.com/api: GET game/versions, POST projects/<id>/upload-file,
header X-Api-Token, multipart "metadata" JSON + "file")."""
import glob, json, os, re, sys, urllib.error, urllib.request, uuid

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
API = "https://wow.curseforge.com/api"
CONF = os.path.join(ROOT, "release", "curseforge.json")
UA = "WoWBY-release-tool"


def token():
    p = os.path.join(ROOT, "curseforge_api_key.txt")
    if not os.path.exists(p):
        sys.exit("curseforge_api_key.txt not found in the project root")
    t = open(p, encoding="utf-8").read().strip()
    if not t:
        sys.exit("curseforge_api_key.txt is empty")
    return t


def req(method, path, body=None, ctype=None):
    r = urllib.request.Request(API + path, data=body, method=method,
                               headers={"X-Api-Token": token(), "User-Agent": UA, **({"Content-Type": ctype} if ctype else {})})
    hide = lambda s: s.replace(token(), "<token hidden>")    # the API echoes a bad token back in its error text
    try:
        with urllib.request.urlopen(r, timeout=120) as resp:
            return resp.status, hide(resp.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        return e.code, hide(e.read().decode("utf-8", "replace"))


def game_versions():
    st, txt = req("GET", "/game/versions")
    if st != 200:
        sys.exit("game/versions failed: HTTP %s %s" % (st, txt[:300]))
    return json.loads(txt)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    a = sys.argv[1:]
    if "--versions" in a:
        for v in sorted(game_versions(), key=lambda v: (v.get("gameVersionTypeID", 0), v.get("name", ""))):
            print("%6s  type %-5s %s" % (v.get("id"), v.get("gameVersionTypeID"), v.get("name")))
        return
    conf = json.load(open(CONF, encoding="utf-8")) if os.path.exists(CONF) else {}
    zp = a[a.index("--zip") + 1] if "--zip" in a else max(glob.glob(os.path.join(ROOT, "release", "WoWBY-*.zip")),
                                                           key=os.path.getmtime)
    ver = re.search(r"WoWBY-(.+)\.zip$", os.path.basename(zp)).group(1)
    clp = os.path.join(ROOT, "release", "CHANGELOG-%s.md" % ver)
    changelog = open(clp, encoding="utf-8").read() if os.path.exists(clp) else "WoWBY %s" % ver
    meta = {"changelog": changelog, "changelogType": "markdown", "displayName": "WoWBY %s" % ver,
            "releaseType": conf.get("release_type", "release")}
    print("zip:        %s (%.1f MB)" % (os.path.relpath(zp, ROOT), os.path.getsize(zp) / 1048576))
    print("changelog:  %s" % (os.path.relpath(clp, ROOT) if os.path.exists(clp) else "(none, a one-line default)"))
    print("project:    %s" % conf.get("project_id", "MISSING — set project_id in release/curseforge.json"))
    print("versions:   %s" % ", ".join(conf.get("game_versions", [])) or "MISSING")
    print("release:    %s, name «%s»" % (meta["releaseType"], meta["displayName"]))
    if "--upload" not in a:
        print("\nDry run. Add --upload to send it.")
        return
    if not conf.get("project_id") or not conf.get("game_versions"):
        sys.exit("set project_id and game_versions in release/curseforge.json first (see --versions)")
    names = set(conf["game_versions"])
    ids = [v["id"] for v in game_versions() if v.get("name") in names]
    if not ids:
        sys.exit("none of %s is a CurseForge game version name (see --versions)" % sorted(names))
    meta["gameVersions"] = ids
    b = uuid.uuid4().hex
    body = ("--%s\r\nContent-Disposition: form-data; name=\"metadata\"\r\n\r\n%s\r\n" % (b, json.dumps(meta))).encode("utf-8")
    body += ("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\nContent-Type: application/zip\r\n\r\n"
             % (b, os.path.basename(zp))).encode("utf-8")
    body += open(zp, "rb").read() + ("\r\n--%s--\r\n" % b).encode("utf-8")
    st, txt = req("POST", "/projects/%s/upload-file" % conf["project_id"], body, "multipart/form-data; boundary=" + b)
    print("upload: HTTP %s %s" % (st, txt[:300]))
    if st != 200:
        sys.exit(1)


if __name__ == "__main__":
    main()
