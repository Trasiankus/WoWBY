# -*- coding: utf-8 -*-
"""Russian extraction and queue update pipeline for WoW Forever.

Usage:
    C:\\Projects\\venv\\Scripts\\python.exe tools\\sync_ru.py --report
    C:\\Projects\\venv\\Scripts\\python.exe tools\\sync_ru.py --status
    C:\\Projects\\venv\\Scripts\\python.exe tools\\sync_ru.py --extract
    C:\\Projects\\venv\\Scripts\\python.exe tools\\sync_ru.py --scrape
    C:\\Projects\\venv\\Scripts\\python.exe tools\\sync_ru.py --all
"""
import argparse
import glob
import json
import os
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
PYTHON = sys.executable


def get_queue_coverage():
    queue_dir = os.path.join(ROOT, "translate", "queue")
    stats = {}
    if not os.path.isdir(queue_dir):
        return stats
    for pkg in sorted(os.listdir(queue_dir)):
        pkg_path = os.path.join(queue_dir, pkg)
        if not os.path.isdir(pkg_path):
            continue
        files = glob.glob(os.path.join(pkg_path, "*.json"))
        total = 0
        with_ru = 0
        for f in files:
            try:
                data = json.load(open(f, encoding="utf-8"))
                for it in data.get("items", []):
                    total += 1
                    ru = it.get("ru")
                    if isinstance(ru, dict):
                        if any(ru.values()):
                            with_ru += 1
                    elif ru:
                        with_ru += 1
            except Exception:
                pass
        stats[pkg] = (total, with_ru)
    return stats


def print_report():
    stats = get_queue_coverage()
    print("=== Russian Reference Coverage in translate/queue ===")
    if not stats:
        print("  No queue found.")
        return
    for pkg, (total, with_ru) in stats.items():
        pct = (with_ru / total * 100.0) if total else 0.0
        print(f"  {pkg:12s}: {total:6d} items, {with_ru:6d} with RU ({pct:5.1f}%)")


def run_cmd(cmd_list, desc):
    print(f"\n--- Running: {desc} ---", flush=True)
    env = dict(os.environ)
    env["PYTHONIOENCODING"] = "utf-8"
    env["PYTHONUNBUFFERED"] = "1"
    res = subprocess.run(cmd_list, cwd=ROOT, env=env)
    if res.returncode != 0:
        print(f"ERROR: {desc} exited with code {res.returncode}", file=sys.stderr)
        return False
    return True


def cmd_scrape():
    scraper = os.path.join(ROOT, "tools", "forever_scraper.py")
    return run_cmd([PYTHON, scraper, "--todo", "listed", "--lang", "ru"], "Scraping Russian quests from Wowhead")


def cmd_status():
    scraper = os.path.join(ROOT, "tools", "forever_scraper.py")
    return run_cmd([PYTHON, scraper, "--status", "--lang", "ru"], "Scraper status")


def cmd_extract():
    import_h = os.path.join(ROOT, "tools", "import_harvest.py")
    extract = os.path.join(ROOT, "tools", "extract_forever.py")
    prepare = os.path.join(ROOT, "tools", "prepare_translate.py")
    run_cmd([PYTHON, import_h], "Import in-game harvest (from SavedVariables)")
    if not run_cmd([PYTHON, extract], "Extract Forever (merge DB2 + Cache + Wowhead into data/strings_en.json)"):
        return False
    if not run_cmd([PYTHON, prepare], "Prepare Translate (update translate/queue with Russian reference)"):
        return False
    print_report()
    return True


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="WoW Forever Russian Pipeline")
    parser.add_argument("--report", action="store_true", help="Print Russian reference coverage report")
    parser.add_argument("--status", action="store_true", help="Check scraper progress")
    parser.add_argument("--scrape", action="store_true", help="Run wowhead Russian quest scraper")
    parser.add_argument("--extract", action="store_true", help="Run extract_forever + prepare_translate")
    parser.add_argument("--all", action="store_true", help="Run scraper, then extract and prepare")
    args = parser.parse_args()

    if args.status:
        cmd_status()
    elif args.report:
        print_report()
    elif args.scrape:
        cmd_scrape()
    elif args.extract:
        cmd_extract()
    elif args.all:
        if cmd_scrape():
            cmd_extract()
    else:
        # Default action: show report and scraper status
        cmd_status()
        print()
        print_report()


if __name__ == "__main__":
    main()
