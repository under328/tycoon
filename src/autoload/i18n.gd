## 多语言(16 种): 基于 Godot auto-translate —— 控件文本(Label/Button 等)
## 以简体中文源文为 message, 在 TranslationServer 查表; 切换语言后存量
## 控件经 NOTIFICATION_TRANSLATION_CHANGED 自动重翻译, 新界面即时生效。
## 词典: strings_db.gd(未覆盖的语言缺词按 fallback 英语回退)。
extends Node

const FALLBACK := "en"
const StringsDb = preload("res://src/autoload/strings_db.gd")

## 16 种常用语言(选项名以各自母语显示)
const LANGUAGES := [
	{"code": "zh_CN", "name": "简体中文"},
	{"code": "zh_TW", "name": "繁體中文"},
	{"code": "en", "name": "English"},
	{"code": "ja", "name": "日本語"},
	{"code": "ko", "name": "한국어"},
	{"code": "es", "name": "Español"},
	{"code": "fr", "name": "Français"},
	{"code": "de", "name": "Deutsch"},
	{"code": "pt", "name": "Português"},
	{"code": "it", "name": "Italiano"},
	{"code": "ru", "name": "Русский"},
	{"code": "ar", "name": "العربية"},
	{"code": "th", "name": "ไทย"},
	{"code": "vi", "name": "Tiếng Việt"},
	{"code": "id", "name": "Bahasa Indonesia"},
	{"code": "tr", "name": "Türkçe"},
]


var _registered := false


func _ready() -> void:
	# Main::start 完成时会重置 TranslationServer → 自动加载期注册的翻译
	# 会被清空; 必须延迟到首帧之后注册
	call_deferred("_register_translations")


func _register_translations() -> void:
	if _registered:
		return
	_registered = true
	# 逐语言构建 Translation 并注册(zh_CN 为源语言: 恒等映射防英文回退)
	var all_keys := StringsDb.DB.get("en", {}) as Dictionary
	var zh := {}
	for k in all_keys:
		zh[str(k)] = str(k)
	var db: Dictionary = StringsDb.DB.duplicate(true)
	db["zh_CN"] = zh
	for code in db:
		var t := Translation.new()
		t.locale = str(code)
		var msgs: Dictionary = db[code]
		for k in msgs:
			t.add_message(str(k), str(msgs[k]))
		TranslationServer.add_translation(t)
	# 占位 locale → 保存值: 制造一次变更, 触发全界面 NOTIFICATION_
	# TRANSLATION_CHANGED, 让首帧前已构建的存量控件重翻译
	TranslationServer.set_locale("zz")
	apply_saved()


## GameSettings 兄弟节点查找(绝对路径 get_node 在部分环境会报错中断)
func _gs() -> Node:
	var p := get_parent()
	if p == null:
		return null
	for c in p.get_children():
		if c.name == "GameSettings":
			return c
	return null


func language() -> String:
	var gs := _gs()
	if gs != null:
		return str(gs.language)
	return "zh_CN"


func set_language(code: String) -> void:
	var gs := _gs()
	if gs != null:
		gs.language = code
		gs.save_settings()
	TranslationServer.set_locale(code)


func apply_saved() -> void:
	TranslationServer.set_locale(language())


## 代码内动态拼接字符串的翻译入口(静态字符串由 auto-translate 自动处理)
func t(src: String) -> String:
	return tr(src)
