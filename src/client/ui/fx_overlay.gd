## 像素风全屏特效覆盖层: 革命 / 反革命 / 8切 / 一落千丈 / 交换。
## 用法: fx_layer.add_child(FxOverlayScript.create("revolution"))；
## 播放完毕自动 queue_free，不拦截鼠标。
extends Control

const Wafu = preload("res://src/client/ui/wafu_paint.gd")
const AppTheme = preload("res://src/client/theme/app_theme.gd")

const DUR := 1.6

var _t := 0.0
var _fx_type := ""

var _slashes: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 8:
		_slashes.append({"y": rng.randf_range(0.1, 0.9),
			"delay": rng.randf_range(0.0, 0.4), "w": rng.randf_range(30, 100)})


static func create(type: String, seat: String = "") -> Control:
	var fx = load("res://src/client/ui/fx_overlay.gd").new()
	fx._fx_type = type
	return fx


func _process(delta: float) -> void:
	_t += delta
	if _t > DUR:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var sz := size
	if sz.x < 2.0 or sz.y < 2.0:
		return  # 布局未完成, 跳过本帧
	match _fx_type:
		"revolution":
			_draw_revolution(sz, false)
		"anti_revolution":
			_draw_revolution(sz, true)
		"eight_cut":
			_draw_eight_cut(sz)
		"fall":
			_draw_fall(sz)
		"exchange":
			_draw_exchange(sz)
		"eight_gift":
			_big_text(sz, "八喜临门 · 摸 1 张", 0.42, 54, Color("ffd166"), 0.95)


## 大字横贯居中(带错位阴影), 返回基线 y
func _big_text(sz: Vector2, txt: String, y_ratio: float, fs: int,
		col: Color, alpha: float, tilt := -0.06) -> void:
	var f := AppTheme.title_font()
	var off := Vector2(0, sz.y * y_ratio)
	draw_set_transform_matrix(Transform2D(tilt, off))
	draw_string(f, Vector2(6, 6), txt, HORIZONTAL_ALIGNMENT_CENTER, sz.x, fs,
			Color(0, 0, 0, alpha * 0.5))
	draw_string(f, Vector2.ZERO, txt, HORIZONTAL_ALIGNMENT_CENTER, sz.x, fs,
			Color(col, alpha))
	draw_set_transform_matrix(Transform2D())


## 像素方块线段(粗粝感): 沿折线每步画方块
func _pixel_polyline(pts: PackedVector2Array, col: Color, w: float) -> void:
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var steps := int(ceilf(a.distance_to(b) / maxf(w, 4.0)))
		for s_i in steps + 1:
			var p := a.lerp(b, float(s_i) / maxf(steps, 1))
			draw_rect(Rect2(p - Vector2(w, w) * 0.5, Vector2(w, w)), col)


## 革命/反革命: 全屏闪 + 旋转像素太阳 + 大字
func _draw_revolution(sz: Vector2, anti: bool) -> void:
	var base: Color = Color("3c5a9c") if anti else Wafu.RED  # 反革命: 靛蓝
	var flash_a := 0.0
	if _t < 0.3:
		flash_a = _t / 0.3 * 0.45
	elif _t < 1.0:
		flash_a = 0.45
	else:
		flash_a = 0.45 * maxf(0.0, 1.0 - (_t - 1.0) / 0.6)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(base.r, base.g, base.b, flash_a))
	# 锯齿星芒(旋转)
	var burst_c := Vector2(sz.x * 0.5, sz.y * 0.40)
	var rot := _t * 2.2
	var r_out := 200.0 + _t * 60.0
	var pts := PackedVector2Array()
	for i in 28:
		var ang := TAU * i / 28.0 + rot
		var rr := r_out if i % 2 == 0 else r_out * 0.62
		pts.append(burst_c + Vector2.from_angle(ang) * rr)
	draw_colored_polygon(pts, Color(Wafu.GOLD, 0.16))
	# 像素太阳: 粗放射线(方块点阵) + 方块环
	var sun_r := 110.0 + _t * 55.0
	for i in 16:
		var ang := TAU * i / 16.0 - rot * (0.6 if not anti else -0.6)
		var dir_v := Vector2.from_angle(ang)
		_pixel_polyline(PackedVector2Array([
			burst_c + dir_v * sun_r * 0.55, burst_c + dir_v * (sun_r + 46.0),
		]), Color(base, 0.8), 9.0)
	# 方块拼的实心日轮(逐环叠方块近似圆)
	var ring := int(sun_r * 0.72)
	while ring > 0:
		draw_rect(Rect2(burst_c + Vector2(-ring, -ring), Vector2(ring * 2, ring * 2)),
				Color(base, 0.16))
		ring -= maxi(int(sun_r * 0.16), 6)
	draw_circle(burst_c, sun_r * 0.62, Color(base, 0.9))
	# 大字
	var alpha := clampf(_t * 3.0, 0.0, 1.0) if _t < 1.0 else maxf(0.0, 1.0 - (_t - 1.0) * 2.0)
	_big_text(sz, "反革命" if anti else "革 命", 0.56, 150, Wafu.GOLD, alpha)


## 8切: 闪电劈落 + 大 8 + 白闪
func _draw_eight_cut(sz: Vector2) -> void:
	var bolt_a := clampf(_t * 5.0, 0.0, 1.0) if _t < 0.25 else maxf(0.0, 1.0 - (_t - 0.25) * 1.6)
	var bx := sz.x * 0.5
	var bolt_pts := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8 + int(_t * 18.0)  # 逐帧抖动
	var cy := -20.0
	while cy < sz.y * 0.46:
		bolt_pts.append(Vector2(bx + rng.randf_range(-46, 46), cy))
		cy += rng.randf_range(26, 42)
	_pixel_polyline(bolt_pts, Color(Wafu.GOLD, bolt_a), 8.0)
	# 闪电末端大 8
	var f := AppTheme.display_font()
	draw_string(f, Vector2(0, sz.y * 0.46 + 60), "8",
			HORIZONTAL_ALIGNMENT_CENTER, sz.x, 160, Color(Wafu.GOLD, bolt_a))
	# 全屏白闪(前段)
	var flash := clampf(1.0 - _t * 2.4, 0.0, 1.0) if _t > 0.08 else clampf(_t * 10.0, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 0.85, flash * 0.42))
	# 细碎斜切线(清桌感)
	if bolt_a > 0.05:
		for s_info in _slashes:
			var y: float = sz.y * float(s_info["y"])
			var w: float = float(s_info["w"])
			var a2: float = clampf((_t - float(s_info["delay"])) * 3.0, 0.0, 1.0) * bolt_a
			draw_line(Vector2(sz.x * 0.62, y), Vector2(sz.x * 0.62 + w, y - 14),
					Color(1, 1, 1, a2 * 0.35), 3.0)


## 一落千丈: 大字坠落 + 下坠箭头 + 落地尘土
func _draw_fall(sz: Vector2) -> void:
	var progress := clampf(_t / 1.2, 0.0, 1.0)
	var ease_p := progress * progress
	var y := sz.y * (0.12 + ease_p * 0.46)
	var f := AppTheme.title_font()
	var alpha := clampf(_t * 3.0, 0.0, 1.0)
	# 坠落拖影
	if ease_p > 0.05:
		for g in range(1, 4):
			var gy := y - g * 46.0
			draw_string(f, Vector2(0, gy), "一落千丈",
					HORIZONTAL_ALIGNMENT_CENTER, sz.x, 110,
					Color(AppTheme.RED, alpha * 0.10 * (4 - g)))
	# 大字本体
	draw_string(f, Vector2(0, y), "一落千丈",
			HORIZONTAL_ALIGNMENT_CENTER, sz.x, 110, Color(AppTheme.RED, alpha))
	# 下坠箭头
	var cx := sz.x / 2.0
	var arrow_y := y + 24.0
	var tri := PackedVector2Array([
		Vector2(cx - 46, arrow_y), Vector2(cx + 46, arrow_y), Vector2(cx, arrow_y + 62),
	])
	draw_colored_polygon(tri, Color(Wafu.RED, alpha * 0.85))
	draw_rect(Rect2(cx - 12, arrow_y - 74, 24, 74), Color(Wafu.RED, alpha * 0.85))
	# 落地尘土
	if progress > 0.55:
		var dust_a := clampf((progress - 0.55) * 3.0, 0.0, 1.0) * 0.5
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		for i in 26:
			var dx := rng.randf_range(-1.0, 1.0)
			var dy := rng.randf_range(-0.35, 0.0)
			var ds := rng.randf_range(6.0, 16.0)
			var dpos := Vector2(cx + dx * 260.0 * progress, sz.y * 0.62 + dy * 80.0)
			draw_rect(Rect2(dpos, Vector2(ds, ds)), Color(Wafu.GOLD, dust_a))


## 交换: 两张像素卡交叉飞过 + 大字
func _draw_exchange(sz: Vector2) -> void:
	var mid := Vector2(sz.x / 2, sz.y / 2 - 40)
	var p := clampf(_t / 1.0, 0.0, 1.0)
	for dir in [-1.0, 1.0]:
		var off_x: float = dir * (p - 0.5) * sz.x * 0.55
		var card := Rect2(mid + Vector2(off_x - 52, -70), Vector2(104, 140))
		# 卡底 + 内框(像素双框)
		draw_rect(card.grow(8), Color(Wafu.GOLD, 0.55))
		draw_rect(card, Color(0.12, 0.10, 0.08, 0.92))
		draw_rect(card.grow(-10), Color(Wafu.GOLD, 0.25), false, 4.0)
	# 中央大 "交" 字压在交叉点
	var f := AppTheme.title_font()
	var alpha := clampf(_t * 2.5, 0.0, 1.0) if _t < 0.9 else clampf(1.0 - (_t - 0.9) * 2.2, 0.0, 1.0)
	draw_string(f, Vector2(0, mid.y + 40), "交", HORIZONTAL_ALIGNMENT_CENTER,
			sz.x, 130, Color(AppTheme.GOLD, alpha))
	_big_text(sz, "换 牌", 0.74, 76, AppTheme.GOLD, alpha * 0.9)
