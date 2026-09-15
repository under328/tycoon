# i18n 词典漂移审计: 对比 UI 代码中的中文静态字符串与 strings_db 词典键。
#   [未覆盖] 代码里有、词典没有 → 显示保持中文(候选迁移项)
#   [失配]   词典有、代码里已找不到 → 代码改了文案, 词典键过期
# 用法: python tools/i18n_audit.py
import io, re, sys, collections

FILES = [
    "src/client/scenes/main_menu.gd",
    "src/client/ui/settings_panel.gd",
    "src/client/scenes/lobby.gd",
    "src/client/scenes/table.gd",
    "src/client/ui/fight_panel.gd",
    "src/client/ui/fight_arena.gd",
    "src/client/ui/profile_panel.gd",
    "src/client/ui/game_end_panel.gd",
    "src/client/ui/shop.gd",
    "src/client/ui/rogue_help.gd",
    "src/client/ui/fight_help.gd",
    "src/client/ui/normal_help.gd",
    "src/client/ui/lobby_help.gd",
    "src/rules/fight/fight_mode.gd",
    "src/rules/fight/fight_pvp.gd",
]
DB_PATH = "src/autoload/strings_db.gd"

pat = re.compile(r'"([^"\n]*)"')
cjk = re.compile(r"[\u4e00-\u9fff]")

code_strings = collections.Counter()
for f in FILES:
    try:
        s = io.open(f, encoding="utf-8").read()
    except OSError:
        continue
    for m in pat.finditer(s):
        t = m.group(1)
        if cjk.search(t):
            code_strings[t] += 1   # 含 % 的模板串也纳入(词典按整串匹配)

db_src = io.open(DB_PATH, encoding="utf-8").read()
db_keys = set(m.group(1) for m in re.finditer(r'^\t\t"([^"]+)":', db_src, re.M))

missing = sorted(s for s in code_strings if s not in db_keys)
stale = sorted(k for k in db_keys if k not in code_strings)

print("i18n 审计 —— 代码静态中文字符串 %d 个, 词典键 %d 个" %
      (len(code_strings), len(db_keys)))
print("")
print("[未覆盖] %d 个(界面将保持中文):" % len(missing))
for s in missing:
    print("  -", s)
print("")
print("[失配] %d 个(词典键在代码中已不存在, 可清理):" % len(stale))
for k in stale:
    print("  -", k)
print("")
print("覆盖率: %d/%d = %d%%" % (len(code_strings) - len(missing),
      len(code_strings),
      100 * (len(code_strings) - len(missing)) // max(len(code_strings), 1)))
sys.exit(0)
