## P5 风页头横幅: 斜切色带 + 图标 + 标题 + 半调网点点缀。
extends Control

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const Icons = preload("res://src/client/ui/icons.gd")
const Wafu = preload("res://src/client/ui/wafu_paint.gd")

var text := "标题":
	set(v):
		text = v
		queue_redraw()
var band := Color(0.10, 0.10, 0.22, 0.92):
	set(v):
		band = v
		queue_redraw()
## 左侧线性图标种类(icons.gd menu_icon), 空 = 淡金斜块
var icon := "":
	set(v):
		icon = v
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(420, 58)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()


func _draw() -> void:
	var s := size
	# 斜切色带
	var pts := PackedVector2Array([
		Vector2(24, 4), Vector2(s.x, 4),
		Vector2(s.x - 24, s.y - 4), Vector2(0, s.y - 4),
	])
	draw_colored_polygon(pts, band)
	# 左侧图标区: 淡金斜块 + 线性图标(取代旧红色斜块)
	var pl := PackedVector2Array([
		Vector2(14, 6), Vector2(52, 6), Vector2(44, s.y - 6), Vector2(6, s.y - 6),
	])
	draw_colored_polygon(pl, Color(Wafu.GOLD, 0.14))
	var pl_line := pl.duplicate()
	pl_line.append(pl[0])
	draw_polyline(pl_line, Color(Wafu.GOLD, 0.45), 1.2, true)
	if icon != "":
		Icons.menu_icon(self, icon, Vector2(30, s.y / 2.0), 12.0, Color(Wafu.GOLD, 1.0))
	# 右端半调网点
	for yy in range(0, 3):
		for xx in range(0, 8):
			draw_circle(Vector2(s.x - 80 + xx * 10, 12 + yy * 12), 2.0,
					Color(AppTheme.GOLD, 0.3))
	draw_string(AppTheme.body_font(), Vector2(62, s.y / 2.0 + 8), tr(text),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, AppTheme.WHITE)
