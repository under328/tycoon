## 和风 × 霓虹 共享绘制库。主菜单背景与牌桌背景共用同一套笔触，保证风格统一。
## 全部为静态函数, 传入 CanvasItem 直接绘制; 无外部纹理依赖。
class_name WafuPaint
extends RefCounted

const GOLD := Color("e0a83c")
const RED := Color("e0503c")
const INDIGO := Color("3a3a6e")


## 垂直渐变夜空(分条带直绘, 免纹理)
static func sky(ci: CanvasItem, size: Vector2, top: Color, bottom: Color, strips := 28) -> void:
	var sh := size.y / strips
	for i in strips:
		ci.draw_rect(Rect2(0, i * sh, size.x, sh + 1.0), top.lerp(bottom, float(i) / (strips - 1)))


## 红日与多层光晕
static func sun(ci: CanvasItem, center: Vector2, r: float, alpha := 1.0) -> void:
	for i in 6:
		ci.draw_circle(center, r + i * r * 0.22, Color(RED.r, RED.g, RED.b, 0.035 * alpha))
	ci.draw_circle(center, r, Color(RED.r, RED.g, RED.b, 0.85 * alpha))


## 远山剪影(锯齿山脊)
static func mountains(ci: CanvasItem, size: Vector2, base_y: float, h: float, ink: Color) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(-20, base_y + h))
	var peaks := [0.12, 0.30, 0.52, 0.74, 0.92]
	var heights := [0.5, 0.9, 0.65, 1.0, 0.55]
	for i in peaks.size():
		pts.append(Vector2(size.x * float(peaks[i]), base_y - h * float(heights[i])))
		pts.append(Vector2(size.x * (float(peaks[i]) + 0.09), base_y - h * 0.25))
	pts.append(Vector2(size.x + 20, base_y + h))
	ci.draw_colored_polygon(pts, ink)


## 青海波(重叠半圆波纹带), scroll 驱动缓慢流动
static func seigaiha(ci: CanvasItem, size: Vector2, top_y: float, rows: int, step: float,
		scroll: float, ink: Color, accent := Color(0, 0, 0, 0)) -> void:
	for row in rows:
		var yy := top_y + row * step * 0.55
		var off := (row % 2) * step * 0.5
		var x := -step + fmod(scroll, step) - off
		var k := 0
		while x < size.x + step:
			ci.draw_arc(Vector2(x, yy), step * 0.5, PI, TAU, 20, ink, 2.0, true)
			if accent.a > 0.0 and k % 6 == 0:
				ci.draw_arc(Vector2(x, yy), step * 0.5, PI, TAU, 20, accent, 1.3, true)
			x += step
			k += 1


## 和纸颗粒(确定性噪点, 覆在牌面/面板上)。
## 性能: 颗粒烘焙进纹理缓存(按尺寸+种子), 绘制仅 1 次 draw_texture_rect。
static var _speckle_tex := {}

static func speckle(ci: CanvasItem, rect: Rect2, count: int, seed_v: int, color: Color) -> void:
	var key := [int(rect.size.x), int(rect.size.y), seed_v, count]
	if not _speckle_tex.has(key):
		var img := Image.create(maxi(int(rect.size.x), 1), maxi(int(rect.size.y), 1),
				false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		for i in count:
			var cx := clampi(int(rng.randf() * img.get_width()), 0, img.get_width() - 1)
			var cy := clampi(int(rng.randf() * img.get_height()), 0, img.get_height() - 1)
			var rad := rng.randf_range(0.5, 1.5)
			img.set_pixel(cx, cy, Color(1, 1, 1, 1.0 if rad > 1.0 else 0.6))
			if rad > 1.2 and cx + 1 < img.get_width():
				img.set_pixel(cx + 1, cy, Color(1, 1, 1, 0.5))
		_speckle_tex[key] = ImageTexture.create_from_image(img)
	ci.draw_texture_rect(_speckle_tex[key], rect, false, color)


## 和风角饰(四角短金线): draw_multiline 单次提交
static func corner_ticks(ci: CanvasItem, rect: Rect2, ln: float, color: Color) -> void:
	var p := rect.position
	var e := rect.end
	var pts := PackedVector2Array()
	for corner: Array in [
		[p, Vector2(1, 1)], [Vector2(e.x, p.y), Vector2(-1, 1)],
		[p + Vector2(0, rect.size.y), Vector2(1, -1)],
		[e, Vector2(-1, -1)],
	]:
		var o: Vector2 = corner[0]
		var d: Vector2 = corner[1]
		pts.append(o + Vector2(3 * d.x, 0))
		pts.append(o + Vector2((3 + ln) * d.x, 0))
		pts.append(o + Vector2(0, 3 * d.y))
		pts.append(o + Vector2(0, (3 + ln) * d.y))
	ci.draw_multiline(pts, color, 2.0)


## 全屏描金边框
static func frame(ci: CanvasItem, size: Vector2, color: Color) -> void:
	ci.draw_rect(Rect2(2, 2, size.x - 4, size.y - 4), color, false, 2.0)


## 四周暗角
# ================================================================ P5×和风 视觉语言

## 斜切平行四边形面板(P5 标志性)
## 半调网点块(复古印刷质感)
static func halftone(ci: CanvasItem, rect: Rect2, gap: float, dot_r: float, color: Color) -> void:
	var y := rect.position.y
	var row := 0
	while y < rect.end.y:
		var x := rect.position.x + (gap * 0.5 if row % 2 == 1 else 0.0)
		while x < rect.end.x:
			ci.draw_circle(Vector2(x, y), dot_r, color)
			x += gap
		y += gap
		row += 1


## 锯齿星芒(P5 爆发形)
static func burst(ci: CanvasItem, center: Vector2, r_out: float, r_in: float,
		spikes: int, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in spikes * 2:
		var ang := TAU * i / (spikes * 2) - PI / 2
		var rr := r_out if i % 2 == 0 else r_in
		pts.append(center + Vector2.from_angle(ang) * rr)
	ci.draw_colored_polygon(pts, color)


## 斜纹饰带
static func stripes(ci: CanvasItem, rect: Rect2, step: float, color: Color) -> void:
	var x := rect.position.x - rect.size.y
	while x < rect.end.x:
		var quad := PackedVector2Array([
			Vector2(x, rect.end.y), Vector2(x + step, rect.position.y),
			Vector2(x + step * 1.4, rect.position.y), Vector2(x + step * 0.4, rect.end.y),
		])
		ci.draw_colored_polygon(quad, color)
		x += step * 2.0


## 粗斜杠(标题下的红色斩切线)
