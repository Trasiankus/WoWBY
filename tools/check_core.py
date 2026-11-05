"""Static + load check of the addon runtime (addon/WoWBY/core/*.lua) — run after editing any core file.

    python tools/check_core.py            compile every module, list NEW global names, load all modules in order
    python tools/check_core.py --accept   store the current global names as the baseline (tools/core_globals.txt)

(1) compile: syntax errors per file.
(2) globals: names the modules read/write as GLOBALS (tools/lua_scope.py). A name that is not a WoW API / Lua builtin
    usually means a missing `W.` (a helper from another module used without the namespace) or a typo -> it would be
    nil in game. New names vs the baseline are printed.
(3) load: runs data/*.lua + all modules in TOC order in a stub WoW environment (every unknown global is a
    permissive stub); catches `W.x` used at load time before the module that defines it.
"""
import os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lua_scope  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
CORE = os.path.join(ROOT, "addon", "WoWBY", "core")
DATA = os.path.join(ROOT, "addon", "WoWBY", "data")
BASELINE = os.path.join(ROOT, "tools", "core_globals.txt")

STUB = r'''
local function mk(name)
  return setmetatable({}, {
    __index = function(t, k)
      if type(k) == "number" then return nil end          -- stub lists are empty (ipairs over a stub ends)
      local v = mk(name .. "." .. tostring(k)); rawset(t, k, v); return v end,
    __call = function() return mk(name .. "()") end,
    __concat = function(a, b) return tostring(a) .. tostring(b) end,
    __tostring = function() return name end,
    __eq = function() return false end, __lt = function() return false end, __le = function() return false end,
    __unm = function() return 0 end, __add = function() return 0 end, __sub = function() return 0 end,
    __mul = function() return 0 end, __div = function() return 0 end, __len = function() return 0 end,
  })
end
ENV = setmetatable({}, { __index = function(t, k)
  local g = _G[k]; if g ~= nil then return g end
  local v = mk(k); rawset(t, k, v); return v end })
ENV._G = ENV
ENV.string = setmetatable({}, { __index = string })
ENV.issecretvalue = function() return false end
ENV.hooksecurefunc = function() end
ENV.GetLocale = function() return "enUS" end
ENV.InCombatLockdown = function() return false end
ENV.NUM_CONTAINER_FRAMES = 13
ENV.GetTime = function() return 0 end
ENV.UnitName = function() return "Test" end
ENV.UnitSex = function() return 2 end
ENV.C_QuestLog = { GetNumQuestLogEntries = function() return 0 end }
function RUN(src, name, ...)
  local f, e = load(src, "=" .. name, "t", ENV)
  if not f then error(e) end
  return f(...)
end
'''


def core_files():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from build_addon import CORE_FILES, DATA_FILES
    data = DATA_FILES + ["quest_guard.lua", "forever.lua", "quest_sig.lua", "spells_items.lua", "ui.lua", "titles.lua", "questnpc.lua", "ru.lua"]
    return CORE_FILES, data


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    import lupa
    core_list, data_list = core_files()
    mods = [(m, open(os.path.join(CORE, m), encoding="utf-8").read()) for m in core_list]
    ok = True
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    for m, t in mods:
        err = L.execute("local f,e=load(...); return e", t)
        if err:
            print("(1) COMPILE ERROR", m, err); ok = False
    print("(1) compile:", "ok" if ok else "FAILED")
    names = {}
    for m, t in mods:
        refs, _ = lua_scope.resolve(t)
        for r in refs:
            if r.decl is None:
                names.setdefault(r.name, m)
    base = set(open(BASELINE, encoding="utf-8").read().split()) if os.path.exists(BASELINE) else set()
    new = sorted(n for n in names if n not in base)
    if "--accept" in sys.argv:
        open(BASELINE, "w", encoding="utf-8", newline="\n").write("\n".join(sorted(names)) + "\n")
        print("(2) baseline stored: %d global names" % len(names))
    else:
        print("(2) globals: %d; new since baseline: %s" % (len(names), ", ".join("%s (%s)" % (n, names[n]) for n in new)
                                                         or "none"))
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute(STUB)
    run = L.globals().RUN
    for f in data_list:
        run(open(os.path.join(DATA, f), encoding="utf-8").read(), "data/" + f)
    ns = L.table()
    for m, t in mods:
        try:
            run(t, "core/" + m, "WoWBY", ns)
        except Exception as e:  # noqa: BLE001
            print("(3) LOAD ERROR in %s: %s" % (m, str(e)[:400])); ok = False
            break
    else:
        print("(3) load: ok")
    # (4) a `-- comment` pasted in the middle of a list swallows the rest of that line — it silently cut
    # Druid/Mage/Warlock from CLASSES and CharacterFrame/FriendsFrame/MerchantFrame from PANELS (2026-09-28/29)
    swallowed = []
    for m, t in mods:
        for n, line in enumerate(t.splitlines(), 1):
            code, sep, comment = line.partition("--")
            # only inside a list: the code before `--` ends with "," or "{" and the comment holds quoted items
            if sep and code.rstrip().endswith((",", "{")) and re.search(r'"[^"\n]+"\s*[,}]', comment):
                swallowed.append("%s:%d" % (m, n))
    if swallowed:
        print("(4) COMMENT SWALLOWS CODE (quoted items after `--`): " + ", ".join(swallowed)); ok = False
    else:
        print("(4) mid-line comments: ok")
    # (5) `local a, b = x and s:match(...)` — an `and` expression yields ONE value, so b is always nil (R373: the
    # profession title crashed; mail expiry / recipe icon silently broke)
    multi = []
    for m, t in mods:
        for n, line in enumerate(t.splitlines(), 1):
            code = line.split("--", 1)[0]
            if re.search(r"^\s*(?:local\s+)?\w+\s*,\s*\w+[^=]*=\s*[^=]*\band\s+[\w.:\[\]\"]+:(?:match|find)\(", code):
                multi.append("%s:%d" % (m, n))
    if multi:
        print("(5) MULTI-VALUE AFTER `and` (only the 1st value survives): " + ", ".join(multi)); ok = False
    else:
        print("(5) multi-value `and`: ok")
    sys.exit(0 if ok and (not new or "--accept" in sys.argv) else 1)


if __name__ == "__main__":
    main()
