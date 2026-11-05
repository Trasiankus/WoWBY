# WoWBY: Belarusian translation for World of Warcraft (Forever)

The Belarusian text of WoW Forever: quests, NPC speech, names, items, spells, books and the game interface.

## Install

Copy `addon/WoWBY` into `World of Warcraft/_forever_/Interface/AddOns/`, or take the ready zip from CurseForge.
In the game: `/wowby` opens the options.

## What is here

| Path | What |
|---|---|
| `addon/WoWBY` | The ready mod, as built. Its lookup tables are keyed by the game's English and Russian text, because that is how it finds a translation |
| `translations/` | The Belarusian text only. `vanilla/` = Classic content, `forever/` = what Forever added or rewrote, `ui/` = the interface |
| `tools/` | The scripts |

In `translations/`, `quests.json`, `items.json` and `spell_names.json` map a quest field (`123.d`) or an id to the text.
The other files hold one text per key, where the key is the first 10 hex digits of the MD5 of the English original.
The game's own English and Russian text is not stored there.

## Pack the mod

Needs Python 3 and lupa:

    pip install lupa
    python tools/package_release.py

This checks the code and writes `release/WoWBY-<version>.zip`.

## Rebuild the mod

`tools/build_addon.py` regenerates `addon/WoWBY/data`. That needs inputs which are NOT in this repo: the text corpus
(keyed by the English originals), data dumps from your own game client (`tools/extract_forever.py`) and the earlier WoWBY
Classic translation. So from this repo alone you can change and pack the code in `addon/WoWBY/core`, but not regenerate the data.
`tools/` paths such as `C:\\Projects\\WoW\\turtle-bel` are the author's and need changing on another machine.

## License

GPL-3.0, see `LICENSE`. Credits are in `addon/WoWBY/README.txt`.
World of Warcraft is (c) Blizzard Entertainment. This is a fan project, not affiliated with Blizzard.
