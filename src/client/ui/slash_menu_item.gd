## P5 风斜切菜单项: 平行四边形面板 + 悬停滑移 + 左侧线性图标。
extends Control

signal pressed

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const Wafu = preload("res://src/client/ui/wafu_paint.gd")
const Icons = preload("res://src/client/ui/icons.gd")

var text := "":
	set(v):
		text = v
		queue_redraw()
var badge := "":
	set(v):
		badge = v
		queue_redraw()
## 左侧线性图标种类(card/net/bag/gear/scroll/exit), 空 = 不画
var icon := "":
	set(v):
		icon = v
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()


func _draw() -> void:
	var skew := 30.0
	var pts := PackedVector2Array([
		Vector2(skew, 2), Vector2(size.x, 2),
		Vector2(size.x - skew, size.y - 2), Vector2(0, size.y - 2),
	])
	var fill := Color(0.07, 0.07, 0.16, 0.88).lerp(Color(0.14, 0.13, 0.32, 0.97), _hover_t)
	draw_colored_polygon(PackedVector2Array(pts), fill)

	# 图标位: 与左斜边平行的斜切底(完全内缩不压边框) + 线性图标(悬停点亮)
	var top_y := 9.0
	var bot_y := size.y - 9.0
	var slope := skew / (size.y - 4.0)             # 菜单左斜边斜率
	var edge_top := skew - slope * (top_y - 2.0)   # 左斜边在各高度处的 x
	var edge_bot := skew - slope * (bot_y - 2.0)
	var gap := 5.0
	var pw := 42.0
	var pl := PackedVector2Array([
		Vector2(edge_top + gap, top_y), Vector2(edge_top + gap + pw, top_y),
		Vector2(edge_bot + gap + pw, bot_y), Vector2(edge_bot + gap, bot_y),
	])
	draw_colored_polygon(pl, Color(Wafu.GOLD, 0.10 + 0.16 * _hover_t))
	var pl_line := pl.duplicate()
	pl_line.append(pl[0])
	draw_polyline(pl_line, Color(Wafu.GOLD, 0.30 + 0.40 * _hover_t), 1.2, true)
	if icon != "":
		var col := Color.WHITE.lerp(Color(Wafu.GOLD, 1.0), _hover_t)
		var icon_cx := (edge_top + edge_bot) * 0.5 + gap + pw * 0.5 + _hover_t * 3.0
		Icons.menu_icon(self, icon, Vector2(icon_cx, size.y / 2.0), 12.0, col)

	# 描金边
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Color(Wafu.GOLD, 0.35 + 0.45 * _hover_t), 1.5, true)

	# 文字
	var f := AppTheme.display_font()
	draw_string(f, Vector2(edge_bot + gap + pw + 16.0, size.y / 2.0 + 10), tr(text),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 25, AppTheme.WHITE)
	if badge != "":
		var bf := AppTheme.accent_font()
		draw_string(bf, Vector2(size.x - skew - 52, size.y / 2.0 + 8), badge,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ff6b6b"))
	if _hover_t > 0.5:
		draw_string(f, Vector2(size.x - skew - 34, size.y / 2.0 + 9), "▶",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(Wafu.GOLD, 0.9))
