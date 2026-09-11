## 主菜单程序化动态背景（和风 × 霓虹）。零外部素材，每帧直绘。
## 构成：夜空渐变 → 红日(光晕) → 远山剪影 → 青海波金云带 → 漂浮牌背 → 金尘粒子 → 描金边框。
extends Control

const COLOR_GOLD := Color("e0a83c")
const COLOR_RED := Color("e0503c")
const COLOR_INDIGO := Color("3a3a6e")
const COLOR_DIM := Color("8a8ab0")

var _t := 0.0
var _grad := GradientTexture2D.new()
var _back_sb := StyleBoxFlat.new()
var _petals: Array = []
var _cards: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([
		Color("232348"), Color("16162e"), Color("0d0d1e"),
	])
	_grad.gradient = g
	_grad.fill_from = Vector2(0, 0)
	_grad.fill_to = Vector2(0, 1)

	_back_sb.bg_color = Color("20204a")
	_back_sb.set_corner_radius_all(6)
	_back_sb.set_border_width_all(2)
	_back_sb.border_color = Color(0.79, 0.66, 0.24, 0.75)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260911
	for i in 46:
		_petals.append({
			"x": rng.randf(), "y": rng.randf(),
			"spd": rng.randf_range(0.02, 0.06),
			"sway": rng.randf_range(8.0, 26.0),
			"sway_spd": rng.randf_range(0.6, 1.6),
			"r": rng.randf_range(1.4, 3.4),
			"a": rng.randf_range(0.25, 0.7),
		})
	for i in 6:
		_cards.append({
			"x": rng.randf_range(0.06, 0.94),
			"y": rng.randf_range(0.10, 0.55),
			"rot": rng.randf_range(-0.3, 0.3),
			"bob": rng.randf_range(0.0, TAU),
			"bob_spd": rng.randf_range(0.5, 1.1),
			"drift": rng.randf_range(-0.004, 0.004),
			"s": rng.randf_range(0.55, 0.95),
		})


func _process(delta: float) -> void:
	_t += delta
	for p in _petals:
		p["y"] += p["spd"] * delta
		p["x"] += sin(_t * p["sway_spd"] + p["y"] * 6.0) * p["sway"] * delta / maxf(size.x, 1.0)
		if float(p["y"]) > 1.05:
			p["y"] = -0.05
			p["x"] = randf()
	for c in _cards:
		c["x"] += c["drift"] * delta
		if float(c["x"]) > 1.02:
			c["x"] = -0.02
		elif float(c["x"]) < -0.02:
			c["x"] = 1.02
	queue_redraw()


func _draw() -> void:
	var sz := size
	if sz.x < 10 or sz.y < 10:
		return
	draw_texture_rect(_grad, Rect2(Vector2.ZERO, sz), false)

	# --- 红日 + 光晕 ---
	var sun := Vector2(sz.x * 0.76, sz.y * 0.30)
	for i in 6:
		draw_circle(sun, 110.0 + i * 30.0, Color(0.88, 0.31, 0.24, 0.035))
	draw_circle(sun, 110.0, Color(0.88, 0.31, 0.24, 0.85))
	draw_circle(sun, 110.0, Color(1, 0.6, 0.4, 0.0) if false else Color(0, 0, 0, 0))

	# --- 远山剪影（两层） ---
	var base_y := sz.y * 0.66
	_draw_mountains(base_y - 30.0, sz.y * 0.30, Color("101028"))
	_draw_mountains(base_y + 10.0, sz.y * 0.22, Color("181834"))

	# --- 青海波金云带（底部三行半圆） ---
	var row_y := sz.y * 0.78
	var step := 44.0
	for row in 4:
		var yy := row_y + row * step * 0.55
		var off := (row % 2) * step * 0.5
		var x := -step + fmod(_t * 6.0, step) - off
		while x < sz.x + step:
			draw_arc(Vector2(x, yy), step * 0.5, PI, TAU, 20,
					COLOR_INDIGO.lerp(Color.BLACK, 0.25), 2.0, true)
			if row == 1 and int((x + off) / step) % 6 == 0:
				draw_arc(Vector2(x, yy), step * 0.5, PI, TAU, 20,
						Color(COLOR_GOLD, 0.35), 1.4, true)
			x += step

	# --- 漂浮牌背 ---
	for c in _cards:
		var pos := Vector2(float(c["x"]) * sz.x, float(c["y"]) * sz.y) \
				+ Vector2(0, sin(_t * float(c["bob_spd"]) + float(c["bob"])) * 14.0)
		var s: float = c["s"]
		draw_set_transform_matrix(Transform2D(float(c["rot"]), pos))
		_back_sb.draw(get_canvas_item(), Rect2(Vector2(-26 * s, -36 * s), Vector2(52 * s, 72 * s)))
		draw_arc(Vector2(0, 0), 16.0 * s, 0, TAU, 24, Color(COLOR_GOLD, 0.5), 1.2, true)
		draw_circle(Vector2(0, 0), 4.0 * s, Color(COLOR_GOLD, 0.8))
		draw_set_transform_matrix(Transform2D())

	# --- 金尘粒子 ---
	for p in _petals:
		draw_circle(Vector2(float(p["x"]) * sz.x, float(p["y"]) * sz.y),
				float(p["r"]), Color(COLOR_GOLD, float(p["a"])))

	# --- 描金边框 + 暗角 ---
	var border := 2
	draw_rect(Rect2(border, border, sz.x - border * 2, sz.y - border * 2),
			Color(COLOR_GOLD, 0.28), false, border)
	for i in 3:
		var k := i * 10.0
		draw_rect(Rect2(k, k, sz.x - k * 2, sz.y - k * 2), Color(0, 0, 0, 0.05))


func _draw_mountains(base_y: float, h: float, ink: Color) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(-20, base_y + h))
	var peaks := [0.12, 0.3, 0.52, 0.74, 0.92]
	var heights := [0.5, 0.9, 0.65, 1.0, 0.55]
	for i in peaks.size():
		pts.append(Vector2(size.x * peaks[i], base_y - h * heights[i]))
		pts.append(Vector2(size.x * (peaks[i] + 0.09), base_y - h * 0.25))
	pts.append(Vector2(size.x + 20, base_y + h))
	draw_colored_polygon(pts, ink)
