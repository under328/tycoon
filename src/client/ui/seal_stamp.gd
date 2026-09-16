## 「富」字朱印(落款印章): 垂直渐变印泥红 + 白文内框 + 做旧斑点 + 微斜印面。
## 入场钤印动画: 放大→落下盖实(scale 1.7→1.0, TRANS_BACK), 配合标题登场。
extends Control

const AppTheme = preload("res://src/client/theme/app_theme.gd")

## 印文字(默认「富」; 亦可换任意单字)
var seal_char := "富":
	set(v):
		seal_char = v
		queue_redraw()

## 钤印进度 0..1(入场动画; 1=盖实)
var stamp_t := 1.0:
	set(v):
		stamp_t = clampf(v, 0.0, 1.0)
		queue_redraw()

## 手工雕刻的印面四角微偏移(固定种子, 每次绘制一致)
var _jitter := [Vector2(-1.5, 0.8), Vector2(1.8, -1.2), Vector2(1.2, 1.6), Vector2(-1.0, -1.8)]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size / 2.0


func _draw() -> void:
	var s := size
	if s.x < 16.0 or s.y < 16.0:
		return
	# 印面: 微斜四边形(逐顶点色 = 垂直渐变: 上鲜下沉)
	var poly := PackedVector2Array([
		_jitter[0], Vector2(s.x, 0) + _jitter[1],
		s + _jitter[2], Vector2(0, s.y) + _jitter[3],
	])
	var cols := PackedColorArray([
		Color("e8563e"), Color("dd4430"), Color("b52c1e"), Color("c23526"),
	])
	draw_polygon(poly, cols)
	# 边缘沉色(印泥积边)
	var closed := PackedVector2Array(poly)
	closed.append(poly[0])
	draw_polyline(closed, Color("8e2015", 0.9), 2.0, true)
	# 白文内框(细白线, 与印面同微斜)
	var m := 5.0
	var inner := PackedVector2Array([
		Vector2(m, m * 1.1), Vector2(s.x - m * 0.8, m),
		Vector2(s.x - m, s.y - m * 0.9), Vector2(m * 0.9, s.y - m),
	])
	var inner_c := PackedVector2Array(inner)
	inner_c.append(inner[0])
	draw_polyline(inner_c, Color(1, 0.96, 0.9, 0.85), 1.6, true)
	# 做旧: 印泥不匀的暗斑 + 一处白斑(磨损), 固定位置不闪烁
	draw_circle(Vector2(s.x * 0.18, s.y * 0.80), s.x * 0.05, Color("8e2015", 0.55))
	draw_circle(Vector2(s.x * 0.82, s.y * 0.16), s.x * 0.04, Color("8e2015", 0.45))
	draw_circle(Vector2(s.x * 0.72, s.y * 0.86), s.x * 0.035, Color("f4e7d2", 0.28))
	draw_circle(Vector2(s.x * 0.30, s.y * 0.12), s.x * 0.03, Color("f4e7d2", 0.20))
	# 印文: 白字 + 深红晕影(印泥洇出)
	var f := AppTheme.title_font()
	var fs := int(s.y * 0.58)
	var c := s / 2.0
	var base_y := c.y + f.get_ascent(fs) * 0.36
	draw_string(f, Vector2(1.5, base_y + 1.5), seal_char,
			HORIZONTAL_ALIGNMENT_CENTER, s.x, fs, Color("7a1b10", 0.6))
	draw_string(f, Vector2(0, base_y), seal_char,
			HORIZONTAL_ALIGNMENT_CENTER, s.x, fs, Color("fdf6ea"))
	# 钤印未实(入场中): 半透明红晕从印面向外扩散
	if stamp_t < 1.0:
		var a := (1.0 - stamp_t) * 0.5
		draw_arc(c, s.x * 0.75, 0, TAU, 28, Color("e0503c", a * 0.5), 3.0, true)
