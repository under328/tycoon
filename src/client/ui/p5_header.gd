## P5 风页头横幅: 斜切色带 + 标题 + 半调网点点缀。
extends Control

const AppTheme = preload("res://src/client/theme/app_theme.gd")

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
	# 斜切色带
	var pts := PackedVector2Array([
		Vector2(24, 4), Vector2(s.x, 4),
		Vector2(s.x - 24, s.y - 4), Vector2(0, s.y - 4),
	])
	draw_colored_polygon(pts, band)
	# 左侧红色斜块
	var red := PackedVector2Array([
		Vector2(0, 4), Vector2(14, 4), Vector2(6, s.y - 4), Vector2(-8, s.y - 4),
	])
	draw_colored_polygon(red, Color(0.88, 0.31, 0.24, 0.95))
	# 右端半调网点
	for yy in range(0, 3):
		for xx in range(0, 8):
			draw_circle(Vector2(s.x - 80 + xx * 10, 12 + yy * 12), 2.0,
					Color(AppTheme.GOLD, 0.3))
	draw_string(AppTheme.body_font(), Vector2(30, s.y / 2.0 + 8), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, AppTheme.WHITE)
