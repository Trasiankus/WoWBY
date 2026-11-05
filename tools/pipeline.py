"""One-command pipeline steps for the .bat files in the project root.

  pipeline.py queue  — game files + scraped wowhead data -> new chunks for the translator:
                       reports a new beta client build, runs import_harvest + extract_forever (client DB2 + WDB cache
                       + forever-data),
                       npc_race, prepare_translate, then shows what the queue gained.
  pipeline.py addon  — translator output -> the game addon: import_translations, fix_corpus --check, build_addon.
  pipeline.py scrape [args] — wowhead: no args = forever_scraper --all (summary on screen, full log out/scrape_log.txt),
                       then a one-line-per-step queue update; args go to the scraper as is.
  pipeline.py status — translator progress + the newest finished chunks.
The .bat files in the project root are one-line launchers for these.

Each step runs with this venv's python; the first failing step stops the run (non-zero exit)."""
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PY = sys.executable
BUILD_INFO = r"C:\Games\World of Warcraft\.build.info"
LAST = os.path.join(ROOT, "out", "last_build.txt")


def run(title, args, capture=False, ok_codes=(0,)):
    if not capture:                                   # captured steps print their own summary
        print("\n==== %s ====" % title, flush=True)
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    p = subprocess.run([PY] + args, cwd=ROOT, env=env, text=True, encoding="utf-8",
                       stdout=subprocess.PIPE if capture else None, stderr=subprocess.STDOUT if capture else None)
    if p.returncode not in ok_codes:
        if capture: print(p.stdout)
        sys.exit("FAILED: %s (exit %d)" % (title, p.returncode))
    return p.stdout or ""


def client_version():
    """the newest Forever build installed (beta or the stress-test client, tools/forever_client.py, R687)"""
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import forever_client
    try:
        b = forever_client.newest()
        return "%s (%s)" % (b["version"], b["product"])
    except SystemExit:
        return "?"


def progress():
    out = run("translator progress", ["translate/tools/progress.py"], capture=True)
    m = re.search(r"(\d+)/(\d+) chunks, (\d+)/(\d+) strings", out)
    return tuple(map(int, m.groups())) if m else None


def queue(quiet=False):
    ver = client_version()
    old = open(LAST).read().strip() if os.path.exists(LAST) else None
    if old and old != ver:
        print("NEW CLIENT BUILD: %s (last extracted: %s)" % (ver, old))
    else:
        print("Client build %s%s" % (ver, "" if old else " (first recorded run)"))
    before = progress()
    if quiet:                                          # scrape_wowhead.bat: one summary line per step
        print("\nUpdating the translator queue…", flush=True)
        h = run("collected in game", ["tools/import_harvest.py"], capture=True)
        m = re.search(r"enUS: (.+)", h)
        print("  in-game harvest: %s" % (m.group(1) if m else "-"))
        x = run("extract", ["tools/extract_forever.py"], capture=True)
        m = re.search(r"Translation diff[^:]*: (\d+) entries", x)
        print("  text that differs from vanilla WoWBY: %s entries" % (m.group(1) if m else "?"))
        open(LAST, "w").write(ver)
        run("npc races", ["tools/npc_race.py"], capture=True)
        pr = run("chunks", ["tools/prepare_translate.py"], capture=True)
        new = [(m.group(1), int(m.group(2))) for m in re.finditer(r"^\s+(\w+)\s+\d+ strings,\s+(\d+) to translate", pr, re.M)]
        new = [(k, n) for k, n in new if n]
        print("  packages with work left: " + (", ".join("%s +%d" % kv for kv in new) if new else "none"))
    else:
        run("what WoWBY collected in game (untranslated quests, names, gossip, book pages)", ["tools/import_harvest.py"])
        run("extract text from the client + game cache + wowhead data", ["tools/extract_forever.py"])
        open(LAST, "w").write(ver)
        run("NPC races (surnames)", ["tools/npc_race.py"])
        run("build translator chunks", ["tools/prepare_translate.py"])
    after = progress()
    if before and after:
        print("\nQueue: %d -> %d chunks, %d -> %d strings (+%d new to translate). Done: %d chunks (%.1f%%)." % (
            before[1], after[1], before[3], after[3], after[3] - before[3], after[0], 100.0 * after[2] / after[3]))
    if old and old != ver:
        print("Client build changed %s -> %s: tell Claude to update CLAUDE.md's build note." % (old, ver))


def new_done_chunks():
    """Translator chunks finished (or rewritten) since the last addon build: {path: item count}, plus the state to save."""
    import glob, json
    state_p = os.path.join(ROOT, "out", "last_import.json")
    old = json.load(open(state_p, encoding="utf-8")) if os.path.exists(state_p) else {}
    now, fresh = {}, {}
    for p in glob.glob(os.path.join(ROOT, "translate", "done", "*", "*.json")):
        rel = os.path.relpath(p, ROOT).replace("\\", "/")
        now[rel] = os.path.getmtime(p)
        if old.get(rel) != now[rel]:
            try: fresh[rel] = len(json.load(open(p, encoding="utf-8")).get("items", {}))
            except Exception: fresh[rel] = 0
    return fresh, now, state_p, bool(old)


def addon():
    import collections, json
    fresh, now, state_p, had_state = new_done_chunks()
    if not had_state:
        print("First run: no record of earlier merges, so every finished chunk counts as merged now (%d)." % len(fresh))
    elif fresh:
        by = collections.Counter(k.split("/")[2] for k in fresh)
        print("NEW from the translator since the last merge: %d chunks, %d strings (%s)" % (
            len(fresh), sum(fresh.values()), ", ".join("%s %d" % kv for kv in sorted(by.items()))))
    else:
        print("Nothing new from the translator since the last merge (rebuilding anyway: rules / hand edits apply).")
    out = run("import translator output", ["tools/import_translations.py"], capture=True)
    print(out.strip().splitlines()[-2] if out.strip() else "")
    chk = run("check owner rules", ["tools/fix_corpus.py", "--check"], capture=True, ok_codes=(0, 1))   # 1 = found texts to fix (reported, not fatal)
    last = chk.strip().splitlines()[-1] if chk.strip() else ""
    print(last)
    if not last.startswith("total: 0"):
        print("  (some texts break a rule — tell Claude; the build still runs)")
    out = run("build the addon", ["tools/build_addon.py"], capture=True)
    # R623: new generic NPC names arrive in data/be at build time; a mixed / male-model mob translated in the feminine
    # («Міратворка» on a man) goes back to the masculine (the addon shows the feminine by UnitSex) → rebuild if any
    fm = run("generic NPC names masculine", ["review/fem_mobs.py", "--apply"], capture=True)
    if not fm.strip().endswith("changed 0"):
        print(fm.strip().splitlines()[-1])
        out = run("rebuild the addon", ["tools/build_addon.py"], capture=True)
    for l in out.splitlines():
        if l.startswith("built") or "CONFLICT" in l or "new;" in l:
            print(l)
    json.dump(now, open(state_p, "w", encoding="utf-8"), indent=0)          # only after a successful build
    run("review JSON (translations/)", ["tools/export_review.py"], capture=True)    # R229: en / ru / bel per entry, for git
    print("  translations/ updated (review JSON); commit with git when you like")
    p = progress()
    if p:
        print("\nMerged %d new chunks (%d strings). Translated: %d/%d chunks, %.1f%% of strings." % (
            len(fresh), sum(fresh.values()), p[0], p[1], 100.0 * p[2] / p[3]))
        print("Addon is live in the beta (junction) — /reload in game.")


def scrape(args):
    """No args: the whole wowhead scrape (--all), then the queue update. The window shows the scraper's FULL output
    (every quest line, owner 2026-10-09: the filtered view of 10-07 hid the progress he liked); a copy goes to
    out/scrape_log.txt. Args: passed to the scraper."""
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    if args:
        sys.exit(subprocess.run([PY, "tools/forever_scraper.py"] + args, cwd=ROOT, env=env).returncode)
    log_p = os.path.join(ROOT, "out", "scrape_log.txt")
    print("Scraping wowhead (full log: out/scrape_log.txt)…", flush=True)
    with open(log_p, "w", encoding="utf-8") as log:
        p = subprocess.Popen([PY, "tools/forever_scraper.py", "--all"], cwd=ROOT, env=env, text=True, encoding="utf-8",
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        for line in p.stdout:
            log.write(line); log.flush()
            # "still missing: p,c" is in the summary at the end → window shows only "no change" / "FILLED: …" (owner)
            # the scraper's "-- so far: N re-checked …" interim lines are skipped too: only the end summary counts
            if line.lstrip().startswith("-- so far:"): continue
            print(re.sub(r"\s+still missing: \S+", "", line.rstrip("\n")), flush=True)
        rc = p.wait()
    if rc:
        sys.exit("Scrape stopped early - rerun to resume. Translator queue NOT updated.")
    queue(quiet=True)


def status():
    """Translator progress per package + the newest finished chunks."""
    import glob
    print(run("translator progress", ["translate/tools/progress.py"], capture=True))
    print("Last finished chunks:")
    files = sorted(glob.glob(os.path.join(ROOT, "translate", "done", "*", "*.json")), key=os.path.getmtime, reverse=True)
    for p in files[:8]:
        print("  %s  %s" % (time.strftime("%Y-%m-%d %H:%M", time.localtime(os.path.getmtime(p))),
                            os.path.splitext(os.path.basename(p))[0]))


def release():
    """CurseForge zip: the usual addon step, then release/WoWBY-<version>.zip (tools/package_release.py)."""
    addon()
    print(run("CurseForge zip", ["tools/package_release.py"], capture=True))


if __name__ == "__main__":
    cmd, rest = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    try:
        {"queue": queue, "addon": addon, "status": status, "scrape": lambda: scrape(rest), "release": release}.get(
            cmd, lambda: sys.exit(__doc__))()
    except KeyboardInterrupt:                                # Ctrl+C: a pause, not an error (every step resumes)
        print("\nPaused. Run it again to continue where it stopped.")
    finally:
        if os.environ.get("PIPELINE_PAUSE"):                 # set by the .bat launchers: keep the window open
            input("\nPress Enter to close.")
