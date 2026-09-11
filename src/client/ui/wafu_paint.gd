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


## 和纸颗粒(确定性噪点, 覆在牌面/面板上)
static func speckle(ci: CanvasItem, rect: Rect2, count: int, seed_v: int, color: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in count:
		ci.draw_circle(
			rect.position + Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y),
			rng.randf_range(0.5, 1.5), color)


## 和风角饰(四角短金线)
static func corner_ticks(ci: CanvasItem, rect: Rect2, ln: float, color: Color) -> void:
	var p := rect.position
	var e := rect.end
	for corner in [
		[p, Vector2(1, 1)], [Vector2(e.x, p.y), Vector2(-1, 1)],
		[p + Vector2(0, rect.size.y), Vector2(1, -1)],
		[e, Vector2(-1, -1)],
	]:
		var o: Vector2 = corner[0]
		var d: Vector2 = corner[1]
		ci.draw_line(o + Vector2(3 * d.x, 0), o + Vector2(3 * d.x + ln * d.x, 0), color, 2.0)
		ci.draw_line(o + Vector2(0, 3 * d.y), o + Vector2(0, 3 * d.y + ln * d.y), color, 2.0)


## 全屏描金边框
static func frame(ci: CanvasItem, size: Vector2, color: Color) -> void:
	ci.draw_rect(Rect2(2, 2, size.x - 4, size.y - 4), color, false, 2.0)


## 四周暗角
static func vignette(ci: CanvasItem, size: Vector2, alpha := 0.05) -> void:
	for i in 3:
		var k := float(i) * 12.0
		ci.draw_rect(Rect2(k, k, size.x - k * 2, size.y - k * 2), Color(0, 0, 0, alpha))
