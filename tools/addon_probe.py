"""Load the built addon (data + core modules, TOC order) in a stub WoW environment and evaluate Lua expressions
against its namespace W — to test translation functions without the game.

    python tools/addon_probe.py 'W.ui_be("Druid")' 'W.substitute("юны $C")'
    python tools/addon_probe.py --female 'W.ui_val("Druid")'
    python tools/addon_probe.py --ru 'W.ui_be("Отмена")'      # ruRU client (R665): locale ruRU + data/ru.lua, Russian stubs

Stubs: UnitClass("player") = "Druid", UnitRace = "Night Elf", UnitSex = 2 (3 with --female), locale enUS, lang BE.
"""
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_core import STUB, CORE, DATA, core_files  # noqa: E402


def load(female=False, ru=False):
    import lupa
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute(STUB)
    L.execute('ENV.UnitClass = function() return "Druid", "DRUID" end; ENV.UnitRace = function() return "Night Elf" end;'
              'ENV.UnitSex = function() return %d end; ENV.WoWBY_DB = { lang = "be" }' % (3 if female else 2))
    if ru:
        L.execute('ENV.GetLocale = function() return "ruRU" end;'
                  'ENV.UnitClass = function() return "Друид", "DRUID" end;'
                  'ENV.UnitRace = function() return "Ночной эльф", "NightElf" end;'
                  'ENV.ITEM_SPELL_TRIGGER_ONUSE = "Использование:"; ENV.ITEM_SPELL_TRIGGER_ONEQUIP = "Если на персонаже:";'
                  'ENV.ITEM_SPELL_TRIGGER_ONPROC = "Возможный эффект при попадании:"; ENV.LEVEL = "Уровень";'
                  'ENV.SELL_PRICE = "Цена продажи"')
    run = L.globals().RUN
    # data files open with `X = X or {}`: the stub would hand them a stub object instead of a table (R564)
    L.execute("for _, k in ipairs({'WoWBY_Objectives', 'WoWBY_NamesF', 'WoWBY_TitlesF', 'WoWBY_QTitleFV', 'WoWBY_QuestOA'}) do ENV[k] = {} end")
    core_list, data_list = core_files()
    for f in data_list:
        run(open(os.path.join(DATA, f), encoding="utf-8").read(), "data/" + f)
    ns = L.table()
    for m in core_list:
        run(open(os.path.join(CORE, m), encoding="utf-8").read(), "core/" + m, "WoWBY", ns)
    L.globals().W = ns
    L.execute("ENV.W = W")
    # optional data tables a build may not ship: the stub would answer every lookup with a stub object (R472)
    L.execute("for _, k in ipairs({'WoWBY_Objectives', 'WoWBY_NamesF', 'WoWBY_TitlesF'}) do"
              " if type(rawget(ENV, k)) ~= 'table' or getmetatable(rawget(ENV, k)) then ENV[k] = {} end end")
    return L


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    args = [a for a in sys.argv[1:] if a not in ("--female", "--ru")]
    L = load("--female" in sys.argv, "--ru" in sys.argv)
    ev = L.globals().RUN
    for expr in args:
        try:
            print("%s  =>  %r" % (expr, ev("return " + expr, "probe")))
        except Exception as e:  # noqa: BLE001
            print("%s  =>  ERROR %s" % (expr, str(e)[:300]))


if __name__ == "__main__":
    main()
