## P5 风页头横幅: 斜切色带 + 快乐体标题 + 半调网点点缀。
extends Control

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const Wafu = preload("res://src/client/ui/wafu_paint.gd")

var text := "标题":
	set(v):
		text = v
		queue_redraw()
var band := Color(0.10, 0.10, 0.22, 0.92):
	set(v):
		band = v
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(420, 58)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := size
	Wafu.slash_panel(self, Rect2(0, 4, s.x, s.y - 8), 24.0, band,
			Color(AppTheme.GOLD, 0.55), 1.5)
	# 左侧红色斜块
	var red := PackedVector2Array([
		Vector2(0, 4), Vector2(14, 4), Vector2(6, s.y - 4), Vector2(-8, s.y - 4),
	])
	draw_colored_polygon(red, Color(0.88, 0.31, 0.24, 0.95))
	# 半调网点(右端)
	Wafu.halftone(self, Rect2(s.x - 90, 10, 80, s.y - 20), 9.0, 2.2,
			Color(AppTheme.GOLD, 0.35))
	draw_string(AppTheme.body_font(), Vector2(30, s.y / 2.0 + 8), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, AppTheme.WHITE)
