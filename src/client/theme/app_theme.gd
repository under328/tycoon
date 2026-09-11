## 统一主题与色板（计划 M4"Theme 全套皮肤"的落地点）。
## 换肤只改本文件: 颜色常量 / 字体 / 按钮样式全局生效。
## 各场景通过 AppTheme.build_theme()、颜色常量与 make_* 助手引用。
extends RefCounted

const BG := Color("14142b")              # 深靛底
const PANEL := Color(0.10, 0.10, 0.22, 0.92)
const PANEL_SOLID := Color("22224a")     # 面板靛
const GOLD := Color("e0a83c")            # 霓虹金
const RED := Color("e0503c")             # 朱红
const WHITE := Color("f0f0f0")
const DIM := Color("8a8ab0")             # 灰蓝次要文字
const GREEN := Color("7dd87d")           # 若竹绿(成功/轮到你)
const OVERLAY_BG := Color(0.08, 0.08, 0.17, 0.97)  # 教程等全屏覆盖层

static var _font: SystemFont
static var _theme: Theme


static func font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray([
			"Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC", "SimHei", "Arial",
		])
	return _font


## 共享 Theme: 默认中文字体 + 全局金色按钮样式(普通/悬停/按下)。
static func build_theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	_theme.default_font = font()
	_theme.default_font_size = 18
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
