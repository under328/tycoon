## 首页标题下的「刀斩」朱红切线: 锥形笔触(中段最厚两端收锋) + 垂直渐变
## + 平行金发丝线 + 左端起笔火花。入场时自左向右描绘(draw_t 0→1)。
extends Control

const AppTheme = preload("res://src/client/theme/app_theme.gd")

## 描绘进度 0..1(入场动画驱动; =1 时整线完整)
var draw_t := 1.0:
	set(v):
		draw_t = clampf(v, 0.0, 1.0)
		queue_redraw()

## 斜率: 线身整体向右上挑(替代旧 ColorRect.rotation, 尺寸计算不受旋转影响)
var slope := -0.055
## 中段最大厚度
var thick := 13.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 20.0 or h < 6.0:
		return
	var max_x := w * draw_t
	# 中线: 左低右高(slope<0), 厚度包络: 两端收锋 + 中段饱满(笔触)
	var prof_l := 0.30   # 左峰位置(起笔后立刻变厚)
	var prof_r := 0.78   # 右峰位置(收锋前保持)
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	var steps := 22
	for i in steps + 1:
		var u := float(i) / float(steps)
		var x := u * max_x
		var env := 1.0
		if u < prof_l:
			env = u / prof_l
		elif u > prof_r:
			env = (1.0 - u) / (1.0 - prof_r)
		env = clampf(env, 0.06, 1.0)
		env = pow(env, 0.7)             # 收锋更锐
		var t := thick * env
		var y := h * 0.52 + slope * x
		top.append(Vector2(x, y - t * 0.5))
		bot.append(Vector2(x, y + t * 0.5))
	var pts := PackedVector2Array(top)
	for i in range(bot.size() - 1, -1, -1):
		pts.append(bot[i])
	# 顶亮底暗的垂直渐变(逐顶点色), 上缘再叠一线高光
	var c_top := Color("ff6a52")
	var c_mid := Color("e0503c")
	var c_bot := Color("8e2418")
	var cols := PackedColorArray()
	for p in pts:
		var rel := clampf(inverse_lerp(top[0].y, bot[0].y, p.y), 0.0, 1.0)
		cols.append(c_top.lerp(c_bot, rel) if rel < 0.5
				else c_mid.lerp(c_bot, (rel - 0.5) * 2.0))
	draw_polygon(pts, cols)
	# 左端起笔火花: 小三角亮斑(出刀瞬间)
	if draw_t > 0.02:
		var tip_y := h * 0.52 + slope * max_x if draw_t < 1.0 else h * 0.52
		var spark := PackedVector2Array([
			Vector2(1.0, tip_y), Vector2(11.0, tip_y - 4.5), Vector2(9.0, tip_y + 3.5),
		])
		draw_colored_polygon(spark, Color("ffd9a0", 0.85))
	# 平行金发丝线(右下方, 随描绘同步延展)
	if max_x > 24.0:
		var line := PackedVector2Array()
		for i in 2:
			var x := (6.0 if i == 0 else max_x - 4.0)
			line.append(Vector2(x, h * 0.52 + slope * x + thick * 0.5 + 4.0))
		draw_polyline(line, Color(AppTheme.GOLD, 0.55), 1.4, true)
	# 右端收锋小残影(完整时才有: 出刀余韵)
	if draw_t >= 1.0:
		var ey := h * 0.52 + slope * w
		var echo := PackedVector2Array([
			Vector2(w - 3.0, ey), Vector2(w + 14.0, ey + slope * 17.0 - 1.5),
		])
		draw_polyline(echo, Color("ff6a52", 0.35), 2.0, true)
