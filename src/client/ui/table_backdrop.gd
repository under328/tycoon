## 牌桌弱化和风夜景背景(与主菜单同一绘制库, 强度调低保证牌面可读性)。
extends Control

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const Wafu = preload("res://src/client/ui/wafu_paint.gd")

var _t := 0.0
var _stars: Array = []
var _petals: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260912
	for i in 34:
		_stars.append({"x": rng.randf(), "y": rng.randf() * 0.45,
				"r": rng.randf_range(0.7, 1.8), "tw": rng.randf_range(0, TAU),
				"tw_spd": rng.randf_range(0.8, 2.4)})
	for i in 10:
		_petals.append({"x": rng.randf(), "y": rng.randf(),
				"spd": rng.randf_range(0.015, 0.04), "sway": rng.randf_range(6.0, 18.0),
				"r": rng.randf_range(1.2, 2.6), "a": rng.randf_range(0.10, 0.22)})


func _process(delta: float) -> void:
	_t += delta
	for pt in _petals:
		pt["y"] += pt["spd"] * delta
		pt["x"] += sin(_t * 1.2 + pt["y"] * 7.0) * pt["sway"] * delta / 1280.0
		if float(pt["y"]) > 1.05:
			pt["y"] = -0.05
			pt["x"] = randf()
	queue_redraw()


func _draw() -> void:
	var sz := size
	if sz.x < 10 or sz.y < 10:
		return
	WafuPaint.sky(self, sz, Color("191934"), Color("0d0d1c"))
	for st in _stars:
		var tw_a := 0.15 + 0.25 * (0.5 + 0.5 * sin(_t * float(st["tw_spd"]) + float(st["tw"])))
		draw_circle(Vector2(float(st["x"]) * sz.x, float(st["y"]) * sz.y),
				float(st["r"]), Color(AppTheme.GOLD, tw_a))
	WafuPaint.sun(self, Vector2(sz.x * 0.86, sz.y * 0.14), 52.0, 0.45)
	WafuPaint.mountains(self, sz, sz.y * 0.50, sz.y * 0.16, Color("141428"))
	WafuPaint.mountains(self, sz, sz.y * 0.58, sz.y * 0.20, Color("101026"))
	for pt in _petals:
		draw_circle(Vector2(float(pt["x"]) * sz.x, float(pt["y"]) * sz.y),
				float(pt["r"]), Color(AppTheme.GOLD, float(pt["a"])))
	# 青海波(底部, 缓慢流动)
	WafuPaint.seigaiha(self, sz, sz.y * 0.74, 4, 42.0, _t * 3.0,
			Color(Wafu.INDIGO, 0.40), Color(Wafu.GOLD, 0.10))
	# 描金边框
	WafuPaint.frame(self, sz, Color(AppTheme.GOLD, 0.18))
