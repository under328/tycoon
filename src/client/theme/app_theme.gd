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

const FONT_TITLE_PATH := "res://assets/fonts/ZhiMangXing.ttf"      # 志莽行书: 主标题/勝利敗北
const FONT_DISPLAY_PATH := "res://assets/fonts/ZCOOL.ttf"          # 站酷黄油体: 按钮/HUD/卡面
const FONT_ACCENT_PATH := "res://assets/fonts/ZCOOLKuaiLe.ttf"     # 站酷快乐体: 点缀标签
const FONT_BODY_PATH := "res://assets/fonts/NotoSansSC.ttf"        # 思源黑体: 正文/聊天

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


## 共享 Theme: 正文黑体默认 + 全局黄油体按钮 + 金色样式(普通/悬停/按下)。
static func build_theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	_theme.default_font = body_font()
	_theme.default_font_size = 18
	_theme.set_font("font", "Button", display_font())
	_theme.set_font_size("font_size", "Button", 18)
	_theme.set_stylebox("normal", "Button", flat(PANEL, Color(GOLD, 0.55)))
	_theme.set_stylebox("hover", "Button", flat(Color(0.16, 0.15, 0.34, 0.95), GOLD))
	_theme.set_stylebox("pressed", "Button", flat(Color(0.22, 0.12, 0.16, 0.95), GOLD))
	_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	return _theme


static func flat(bg: Color, border: Color, radius := 8, border_width := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_width)
	sb.border_color = border
	return sb


static func make_label(size: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", color)
	return lb


static func make_button(text: String, min_size := Vector2(96, 44), font_size := 18) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	return b
