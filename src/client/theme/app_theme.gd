## 统一主题与色板（计划 M4"Theme 全套皮肤"的落地点）。
## 换肤只改本文件: 颜色常量 / 字体 / 按钮样式全局生效。
## 各场景通过 AppTheme.build_theme()、颜色常量与 make_* 助手引用。
extends RefCounted

const BG := Color("14142b")              # 深靛底
const PANEL := Color(0.10, 0.10, 0.22, 0.92)
const GOLD := Color("e0a83c")            # 霓虹金
const RED := Color("e0503c")             # 朱红
const WHITE := Color("f0f0f0")
const DIM := Color("8a8ab0")             # 灰蓝次要文字
const GREEN := Color("7dd87d")           # 若竹绿(成功/轮到你)
const OVERLAY_BG := Color(0.08, 0.08, 0.17, 0.97)  # 教程等全屏覆盖层

const FONT_TITLE_PATH := "res://assets/fonts/WenKaiMedium.ttf"    # 霞鹜文楷 Medium: 主标题/勝利敗北(和风楷体)
const FONT_DISPLAY_PATH := "res://assets/fonts/WenKaiMedium.ttf"  # 霞鹜文楷 Medium: 按钮/HUD/卡面点数
const FONT_ACCENT_PATH := "res://assets/fonts/ZCOOLKuaiLe.ttf"     # 站酷快乐体: 点缀标签(保留)
const FONT_BODY_PATH := "res://assets/fonts/WenKaiRegular.ttf"    # 霞鹜文楷 Regular: 正文/聊天

static var _title_font: FontFile
static var _display_font: FontFile
static var _accent_font: FontFile
static var _body_font: FontFile
static var _theme: Theme


## 志莽行书（主标题/勝利敗北/朱印）
static func title_font() -> FontFile:
	if _title_font == null:
		_title_font = load(FONT_TITLE_PATH)
	return _title_font


## 站酷快乐体（点缀标签）
static func accent_font() -> FontFile:
	if _accent_font == null:
		_accent_font = load(FONT_ACCENT_PATH)
	return _accent_font


## 站酷黄油体（按钮/HUD/卡面点数）
static func display_font() -> FontFile:
	if _display_font == null:
		_display_font = load(FONT_DISPLAY_PATH)
	return _display_font


## 思源黑体（正文/聊天）
static func body_font() -> FontFile:
	if _body_font == null:
		_body_font = load(FONT_BODY_PATH)
	return _body_font


## 共享 Theme 2.0: 三态按钮(普通/悬停加亮/按下内凹红边) + 正文字体 + 焦点隐藏。
static func build_theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	_theme.default_font = body_font()
	_theme.default_font_size = 18
	_theme.set_font("font", "Button", display_font())
	_theme.set_font_size("font_size", "Button", 18)
	# 普通态: 深靛面板 + 弱金描边
	var bn := flat(PANEL, Color(GOLD, 0.45), 8, 1)
	bn.content_margin_left = 14
	bn.content_margin_right = 14
	bn.content_margin_top = 8
	bn.content_margin_bottom = 8
	# 悬停态: 亮面板 + 实金描边
	var bh := flat(Color(0.17, 0.16, 0.36, 0.97), GOLD, 8, 2)
	bh.content_margin_left = 14
	bh.content_margin_right = 14
	bh.content_margin_top = 8
	bh.content_margin_bottom = 8
	# 按下态: 内凹 + 朱红描边
	var bp := flat(Color(0.20, 0.11, 0.14, 0.97), Color(RED, 0.9), 8, 2)
	bp.content_margin_left = 15
	bp.content_margin_right = 13
	bp.content_margin_top = 9
	bp.content_margin_bottom = 7
	_theme.set_stylebox("normal", "Button", bn)
	_theme.set_stylebox("hover", "Button", bh)
	_theme.set_stylebox("pressed", "Button", bp)
	_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	_theme.set_color("font_hover_color", "Button", Color("ffd75e"))
	_theme.set_color("font_pressed_color", "Button", Color("ffd75e"))
	return _theme


static func flat(bg: Color, border: Color, radius := 8, border_width := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_width)
	sb.border_color = border
	return sb


## 分区标题: 斜切红块 + 金字(P5 语言)
static func section_label(text: String, size := 15) -> Label:
	var lb := make_label(size, GOLD)
	lb.text = "▎" + text
	lb.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	lb.add_theme_constant_override("shadow_offset_x", 1)
	lb.add_theme_constant_override("shadow_offset_y", 1)
	return lb


## 翻页式面板的导航按钮(教程/帮助共用)
static func nav_button(text: String, pos: Vector2, size := Vector2(180, 46)) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", 18)
	var sb := flat(Color(0.10, 0.10, 0.22, 0.9), Color(GOLD, 0.5), 8, 1)
	b.add_theme_stylebox_override("normal", sb)
	var hv := flat(Color(0.13, 0.12, 0.28, 0.95), GOLD, 8, 1)
	b.add_theme_stylebox_override("hover", hv)
	return b


static func make_label(size: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", color)
	return lb


static func make_button(text: String, min_size := Vector2(96, 44), font_size := 18) -> Button:
	var b := Button.new()
	b.text = text
	b.name = text
	b.custom_minimum_size = min_size
	b.size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	return b
