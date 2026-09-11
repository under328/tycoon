## P5 风斜切菜单项: 平行四边形面板 + 悬停滑移 + 红色侧块。
extends Control

signal pressed

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const Wafu = preload("res://src/client/ui/wafu_paint.gd")

var text := "":
	set(v):
		text = v
		queue_redraw()
var badge := "":
	set(v):
		badge = v
		queue_redraw()
var hovered := false:
	set(v):
		hovered = v
		queue_redraw()

var _hover_t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(430, 62)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void: hovered = false)


func _process(delta: float) -> void:
	var target := 1.0 if hovered else 0.0
	if _hover_t != target:
		_hover_t = move_toward(_hover_t, target, delta * 7.0)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		Audio.play("click")
		pressed.emit()
		accept_event()


func _draw() -> void:
	var skew := 30.0
	var pts := PackedVector2Array([
		Vector2(skew, 2), Vector2(size.x, 2),
		Vector2(size.x - skew, size.y - 2), Vector2(0, size.y - 2),
	])
	var fill := Color(0.07, 0.07, 0.16, 0.88).lerp(Color(0.14, 0.13, 0.32, 0.97), _hover_t)
	draw_colored_polygon(PackedVector2Array(pts), fill)

	# 左侧红色斜块(悬停加宽)
	var rw := 12.0 + _hover_t * 12.0
	var red := PackedVector2Array([
		Vector2(0, 2), Vector2(rw, 2), Vector2(rw - 9.0, size.y - 2), Vector2(-9.0, size.y - 2),
	])
	draw_colored_polygon(red, Color(0.88, 0.31, 0.24, 0.92))

	# 描金边
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Color(Wafu.GOLD, 0.35 + 0.45 * _hover_t), 1.5, true)

	# 文字
	var f := AppTheme.display_font()
	draw_string(f, Vector2(skew + rw + 4, size.y / 2.0 + 10), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 25, AppTheme.WHITE)
	if badge != "":
		var bf := AppTheme.accent_font()
		draw_string(bf, Vector2(size.x - skew - 52, size.y / 2.0 + 8), badge,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ff6b6b"))
	if _hover_t > 0.5:
		draw_string(f, Vector2(size.x - skew - 34, size.y / 2.0 + 9), "▶",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(Wafu.GOLD, 0.9))
