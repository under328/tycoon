# 全量翻译覆盖工具: 提取未覆盖串 → 生成翻译 → 合并到 strings_db.gd
# 用法: python tools/i18n_full_coverage.py
# 覆盖率目标: 100% 英文, 其他语言逐步补充
import io, os, re, sys, collections

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
NL = chr(10)
BS = chr(92)
DQ = chr(34)

# ── 路径 ──
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH = os.path.join(ROOT, "src", "autoload", "strings_db.gd")
AUDIT = os.path.join(ROOT, "tools", "i18n_audit.py")

# ── 步骤 1: 提取未覆盖串(复用审计逻辑) ──
sys.path.insert(0, AUDIT and os.path.dirname(AUDIT) or ".")

FILES = [
    "src/client/scenes/main_menu.gd", "src/client/ui/settings_panel.gd",
    "src/client/scenes/lobby.gd", "src/client/scenes/table.gd",
    "src/client/ui/fight_panel.gd", "src/client/ui/fight_arena.gd",
    "src/client/ui/profile_panel.gd", "src/client/ui/game_end_panel.gd",
    "src/client/ui/shop.gd", "src/client/ui/rogue_help.gd",
    "src/client/ui/fight_help.gd", "src/client/ui/normal_help.gd",
    "src/client/ui/lobby_help.gd", "src/rules/fight/fight_mode.gd",
    "src/rules/fight/fight_pvp.gd", "src/client/scenes/tutorial.gd",
]
cjk_re = re.compile("[" + chr(0x4E00) + "-" + chr(0x9FFF) + "]")


def extract_strings(text):
    out = []; cur = []; in_str = False; i = 0; n = len(text)
    while i < n:
        ch = text[i]
        if in_str:
            if ch == BS and i + 1 < n:
                cur.append(NL if text[i + 1] == "n" else text[i + 1]); i += 2; continue
            if ch == DQ:
                out.append("".join(cur)); in_str = False
            else:
                cur.append(ch)
        else:
            if ch == DQ:
                in_str = True; cur = []
            elif ch == "#":
                while i < n and text[i] != NL: i += 1
        i += 1
    return out


all_strs = set()
for f in FILES:
    fp = os.path.join(ROOT, f)
    if not os.path.exists(fp):
        continue
    for t in extract_strings(io.open(fp, encoding="utf-8").read()):
        if cjk_re.search(t):
            all_strs.add(t)

# ── 步骤 2: 读取现有词典 ──
db_src = io.open(DB_PATH, encoding="utf-8").read()
en_match = re.search(r'"en": \{(.*?)\n\t\},', db_src, re.S)
en_keys = set()
if en_match:
    for m in re.finditer(r'^\t\t"((?:[^' + BS + DQ + '])*)":', en_match.group(1), re.M):
        k = m.group(1).replace(BS + "n", NL).replace(BS + DQ, DQ).replace(BS + BS, BS)
        en_keys.add(k)

# ── 步骤 3: 找出未覆盖串 ──
uncovered = sorted(s for s in all_strs if s not in en_keys)
print("全量中文串: %d | 已覆盖: %d | 未覆盖: %d" % (
    len(all_strs), len(all_strs) - len(uncovered), len(uncovered)))

# ── 步骤 4: 输出未覆盖清单(供翻译参考) ──
out_path = os.path.join(ROOT, "tools", "i18n_uncovered.txt")
io.open(out_path, "w", encoding="utf-8", newline=NL).write(
    NL.join(uncovered) + NL)
print("未覆盖清单已写入:", out_path)
print("完成 — 请编辑 tools/i18n_data_full.py 填入翻译后重新运行 i18n_build.py")
