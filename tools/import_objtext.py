"""Classic quest objective lines (quest_template ObjectiveText1-4: the tracker / log lines the server sends for
script-completed objectives, "Release Oben Rageclaw's spirit") from the local vmangos world DB dump (R305, owner
2026-10-09: "this is in classic files"), RU from locales_quest loc8.

    python tools/import_objtext.py            -> data/objtext_en.json {en: {"ru", "quest"}} + counts

extract_forever.py queues the lines of quests the Forever client has (QuestV2) as "objective:" entries (package
`objectives`) when WoWBY does not translate them yet."""
import json, os, sys
sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_broadcast import rows, SQL  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OBJ = (34, 35, 36, 37)                   # quest_template ObjectiveText1-4 (value positions, checked on quest 2561)
RU = (54, 63, 72, 81)                    # locales_quest ObjectiveText1-4 _loc8 (9 locales per field, loc0 first)


def main():
    ru = {}
    for v in rows(os.path.join(SQL, "tw_world_locales_quest.sql"), "locales_quest"):
        ru[int(v[0])] = [v[i] if i < len(v) else None for i in RU]
    out = {}
    for v in rows(os.path.join(SQL, "tw_world_quest_template.sql"), "quest_template"):
        qid = int(v[0])
        for n, i in enumerate(OBJ):
            en = (v[i] or "").strip() if i < len(v) else ""
            if not en or en in out:
                continue
            r = (ru.get(qid) or [None] * 4)[n]
            out[en] = {"ru": (r or "").strip(), "quest": qid}
    json.dump(out, open(os.path.join(ROOT, "data", "objtext_en.json"), "w", encoding="utf-8"), ensure_ascii=False,
              indent=0, sort_keys=True)
    print("objective lines:", len(out), "| with RU:", sum(1 for e in out.values() if e["ru"]))


if __name__ == "__main__":
    main()
