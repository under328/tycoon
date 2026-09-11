## 主菜单程序化动态背景（和风 × 霓虹）。零外部素材，每帧直绘。
## 构成：夜空渐变 → 红日(光晕) → 远山剪影 → 青海波金云带 → 漂浮牌背 → 金尘粒子 → 描金边框。
extends Control

const Wafu = preload("res://src/client/ui/wafu_paint.gd")

const COLOR_GOLD := Color("e0a83c")
const COLOR_INDIGO := Color("3a3a6e")

var _t := 0.0
var _grad := GradientTexture2D.new()
var _vignette := GradientTexture2D.new()
var _back_sb := StyleBoxFlat.new()
var _petals: Array = []
var _cards: Array = []
var _stars: Array = []
var _birds: Array = []


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
	var vg := Gradient.new()
	vg.offsets = PackedFloat32Array([0.55, 1.0])
	vg.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.5)])
	_vignette.gradient = vg
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.5)
	_vignette.fill_to = Vector2(1.0, 1.0)

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
	for i in 70:
		_stars.append({
			"x": rng.randf(), "y": rng.randf() * 0.55,
			"r": rng.randf_range(0.8, 2.2),
			"tw": rng.randf_range(0, TAU),
			"tw_spd": rng.randf_range(1.0, 3.0),
		})
	for i in 5:
		_birds.append({
			"x": rng.randf(), "y": rng.randf_range(0.12, 0.38),
			"spd": rng.randf_range(0.008, 0.016),
			"ph": rng.randf_range(0, TAU),
			"s": rng.randf_range(0.7, 1.3),
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
	for b in _birds:
		b["x"] -= b["spd"] * delta
		if float(b["x"]) < -0.05:
			b["x"] = 1.05
			b["y"] = randf_range(0.10, 0.40)
	queue_redraw()


func _draw() -> void:
	var sz := size
	if sz.x < 10 or sz.y < 10:
		return
	draw_texture_rect(_grad, Rect2(Vector2.ZERO, sz), false)

	for st in _stars:
		var tw_a := 0.25 + 0.45 * (0.5 + 0.5 * sin(_t * float(st["tw_spd"]) + float(st["tw"])))
		draw_circle(Vector2(float(st["x"]) * sz.x, float(st["y"]) * sz.y),
				float(st["r"]), Color(Wafu.GOLD, tw_a * 0.5))
	var sun := Vector2(sz.x * 0.76, sz.y * 0.30)
	var breath := 1.0 + 0.05 * sin(_t * 1.4)
	draw_circle(sun, 150.0 * breath, Color(Wafu.RED, 0.08))
	draw_circle(sun, 132.0 * breath, Color(Wafu.RED, 0.10))
	Wafu.sun(self, sun, 110.0)

	Wafu.mountains(self, sz, sz.y * 0.66 - 30.0, sz.y * 0.30, Color("101028"))
	Wafu.mountains(self, sz, sz.y * 0.66 + 10.0, sz.y * 0.22, Color("181834"))

	var torii_c := Vector2(sz.x * 0.30, sz.y * 0.52)
	var tw2 := 46.0
	var torii := PackedVector2Array([
		torii_c + Vector2(-tw2 * 0.75, 0), torii_c + Vector2(-tw2 * 0.55, -tw2 * 0.95),
		torii_c + Vector2(tw2 * 0.55, -tw2 * 0.95), torii_c + Vector2(tw2 * 0.75, 0),
	])
	draw_colored_polygon(torii, Color(0.05, 0.04, 0.10, 0.85))
	draw_rect(Rect2(torii_c + Vector2(-tw2 * 1.05, -tw2 * 1.18), Vector2(tw2 * 2.1, tw2 * 0.14)),
			Color(0.05, 0.04, 0.10, 0.85))
	draw_rect(Rect2(torii_c + Vector2(-tw2 * 0.85, -tw2 * 0.86), Vector2(tw2 * 1.7, tw2 * 0.11)),
			Color(0.05, 0.04, 0.10, 0.85))
	Wafu.seigaiha(self, sz, sz.y * 0.78, 4, 44.0, _t * 6.0,
			COLOR_INDIGO.lerp(Color.BLACK, 0.25), Color(COLOR_GOLD, 0.35))
	for b in _birds:
		var bp := Vector2(float(b["x"]) * sz.x, float(b["y"]) * sz.y)
		var s: float = float(b["s"])
		var flap := sin(_t * 6.0 + float(b["ph"])) * 4.0 * s
		draw_line(bp + Vector2(-7 * s, flap), bp, Color(0.06, 0.05, 0.12, 0.85), 1.6 * s, true)
		draw_line(bp, bp + Vector2(7 * s, flap), Color(0.06, 0.05, 0.12, 0.85), 1.6 * s, true)

	for c in _cards:
		var pos := Vector2(float(c["x"]) * sz.x, float(c["y"]) * sz.y) \
				+ Vector2(0, sin(_t * float(c["bob_spd"]) + float(c["bob"])) * 14.0)
		var s: float = c["s"]
		draw_set_transform_matrix(Transform2D(float(c["rot"]), pos))
		_back_sb.draw(get_canvas_item(), Rect2(Vector2(-26 * s, -36 * s), Vector2(52 * s, 72 * s)))
		Wafu.corner_ticks(self, Rect2(Vector2(-26 * s, -36 * s), Vector2(52 * s, 72 * s)),
				8.0 * s, Color(Wafu.GOLD, 0.55))
		draw_arc(Vector2(0, 0), 16.0 * s, 0, TAU, 24, Color(Wafu.GOLD, 0.5), 1.2, true)
		draw_circle(Vector2(0, 0), 4.0 * s, Color(Wafu.GOLD, 0.8))
		draw_set_transform_matrix(Transform2D())

	for p in _petals:
		draw_circle(Vector2(float(p["x"]) * sz.x, float(p["y"]) * sz.y),
				float(p["r"]), Color(Wafu.GOLD, float(p["a"])))

	# P5 视觉: 半调网点(左上) + 标题后锯齿星芒 + 右上斜纹
	Wafu.halftone(self, Rect2(36, 36, 300, 170), 16.0, 2.6, Color(Wafu.GOLD, 0.15))
	Wafu.burst(self, Vector2(sz.x * 0.68, sz.y * 0.20), 180.0, 100.0, 14,
			Color(Wafu.RED, 0.10))
	Wafu.burst(self, Vector2(sz.x * 0.68, sz.y * 0.20), 125.0, 72.0, 10,
			Color(Wafu.GOLD, 0.08))
	Wafu.stripes(self, Rect2(sz.x * 0.62, 0, sz.x * 0.38, sz.y * 0.16), 26.0,
			Color(Wafu.GOLD, 0.05))

	var branch := PackedVector2Array([
		Vector2(0, 26), Vector2(90, 40), Vector2(180, 34), Vector2(260, 62),
		Vector2(330, 58), Vector2(392, 96),
	])
	draw_polyline(branch, Color(0.07, 0.05, 0.10, 0.9), 9.0, true)
	draw_polyline(PackedVector2Array([
		Vector2(180, 34), Vector2(238, 20), Vector2(300, 8),
	]), Color(0.07, 0.05, 0.10, 0.9), 6.0, true)
	var blossoms := [Vector2(96, 30), Vector2(196, 22), Vector2(268, 54),
			Vector2(340, 50), Vector2(300, 6), Vector2(392, 92), Vector2(60, 34)]
	for bl in blossoms:
		for pi in 5:
			var ang := TAU * pi / 5.0
			draw_circle(bl + Vector2.from_angle(ang) * 7.5, 5.5,
					Color(Color("f2b8c6"), 0.85))
		draw_circle(bl, 3.0, Color(Wafu.GOLD, 0.9))
	draw_texture_rect(_vignette, Rect2(Vector2.ZERO, sz), false)
	Wafu.frame(self, sz, Color(Wafu.GOLD, 0.28))
