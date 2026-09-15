# 生成 src/autoload/strings_db.gd(源数据: tools/i18n_data_*.py)
# 用法: python tools/i18n_build.py
import io, sys, importlib, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
en = importlib.import_module("i18n_data_en").T
tw = importlib.import_module("i18n_data_tw").T
ja = importlib.import_module("i18n_data_ja").T
ko = importlib.import_module("i18n_data_ko").T
tpl = importlib.import_module("i18n_data_tpl").T_TPL
part = importlib.import_module("i18n_data_part").T_PART

DB = {"en": en, "zh_TW": tw, "ja": ja, "ko": ko}
for k, langs in tpl.items():
    for lang, v in langs.items():
        DB.setdefault(lang, {})[k] = v
for code, t in part.items():
    DB.setdefault(code, {}).update(t)

BS = chr(92)

def esc(x):
    return (x.replace(BS, BS + BS)
             .replace('"', BS + '"')
             .replace(chr(10), BS + "n"))

ORDER = ["en", "zh_TW", "ja", "ko", "es", "fr", "de", "pt", "it", "ru",
         "ar", "th", "vi", "id", "tr"]
lines = [
    "## 16 语言词典(自动生成: tools/i18n_data_*.py -> 本文件)。",
    "## key = 简体中文源文(必须与代码字面量逐字一致); 缺词回退英语(fallback)。",
    "## zh_CN 为源语言, 由 I18n 注册恒等映射, 不在本表。",
    "class_name StringsDb",
    "extends RefCounted",
    "",
    "const DB := {",
]
for code in ORDER:
    if code not in DB:
        continue
    lines.append('\t"%s": {' % code)
    for k, v in DB[code].items():
        lines.append('\t\t"%s": "%s",' % (esc(k), esc(v)))
    lines.append("\t},")
lines.append("}")
out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "src", "autoload", "strings_db.gd")
io.open(out, "w", encoding="utf-8", newline=chr(10)).write(
        chr(10).join(lines) + chr(10))
print("sizes:", {k: len(v) for k, v in sorted(DB.items())})
