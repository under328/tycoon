# i18n 词典漂移审计: 对比 UI 代码中的中文静态字符串与 strings_db 词典键。
#   [未覆盖] 代码里有、词典没有 → 显示保持中文(候选迁移项)
#   [失配]   词典有、代码里已找不到 → 代码改了文案, 词典键过期
# 用法: python tools/i18n_audit.py
import io
import re
import sys
import collections

NL = chr(10)
BS = chr(92)
DQ = chr(34)

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

cjk = re.compile("[" + chr(0x4E00) + "-" + chr(0x9FFF) + "]")


def extract_strings(text):
    """状态机提取字符串字面量: 跳过 # 注释, 处理转义。"""
    out = []
    cur = []
    in_str = False
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if in_str:
            if ch == BS and i + 1 < n:
                nxt = text[i + 1]
                cur.append(NL if nxt == "n" else nxt)
                i += 2
                continue
            if ch == DQ:
                out.append("".join(cur))
                in_str = False
            else:
                cur.append(ch)
        else:
            if ch == DQ:
                in_str = True
                cur = []
            elif ch == "#":
                while i < n and text[i] != NL:
                    i += 1
        i += 1
    return out


code_strings = collections.Counter()
for f in FILES:
    try:
        s = io.open(f, encoding="utf-8").read()
    except OSError:
        continue
    for t in extract_strings(s):
        if cjk.search(t):
            code_strings[t] += 1   # 含 % 的模板串也纳入(词典按整串匹配)

db_src = io.open(DB_PATH, encoding="utf-8").read()
db_keys = set()
for m in re.finditer(r'^\t\t"((?:[^' + BS + DQ + BS + BS + '])*)":', db_src, re.M):
    key = m.group(1).replace(BS + BS, BS).replace(BS + "n", NL).replace(BS + DQ, DQ)
    db_keys.add(key)

missing = sorted(s for s in code_strings if s not in db_keys)
stale = sorted(k for k in db_keys if k not in code_strings)

print("i18n 审计 —— 代码中文静态串 %d 个, 词典键 %d 个" %
      (len(code_strings), len(db_keys)))
print("")
print("[未覆盖] %d 个(界面将保持中文):" % len(missing))
for s in missing:
    print("  -", s.replace(NL, " / "))
print("")
print("[失配] %d 个(词典键在代码中已不存在, 可清理):" % len(stale))
for k in stale:
    print("  -", k.replace(NL, " / "))
print("")
print("覆盖率: %d/%d = %d%%" % (len(code_strings) - len(missing),
      len(code_strings),
      100 * (len(code_strings) - len(missing)) // max(len(code_strings), 1)))
sys.exit(0)
