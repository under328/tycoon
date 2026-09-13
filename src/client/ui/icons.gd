## 程序化图标库(和风×霓虹统一语言): 货币图标 + 菜单线性图标 + 金额行控件。
## 金币 = 铜钱(圆金方孔), 钻石 = 多刻面宝石; 菜单图标为线条风格, 全工程共用。
class_name GameIcons
extends RefCounted

const COIN_BODY := Color("f0c04a")
const COIN_RIM := Color(0.62, 0.44, 0.10, 1.0)
const COIN_HOLE := Color(0.16, 0.12, 0.04, 0.95)
const GEM_BODY := Color("4fc3f7")
const GEM_LIGHT := Color("9be0ff")
const GEM_DARK := Color("2e8fc7")


## 铜钱金币(圆金方孔 + 暗金环 + 左上高光)
static func coin(cv: CanvasItem, c: Vector2, r: float) -> void:
	cv.draw_circle(c, r, COIN_BODY)
	cv.draw_arc(c, r * 0.78, 0, TAU, 40, COIN_RIM, r * 0.14, true)
	var q := r * 0.52
	cv.draw_rect(Rect2(c - Vector2(q, q) * 0.5, Vector2(q, q)), COIN_HOLE)
	cv.draw_arc(c, r * 0.88, -2.5, -1.1, 12, Color(1, 1, 0.85, 0.55), r * 0.10, true)


## 多刻面宝石(顶台亮面 + 冠部 + 尖底 + 描边)
static func gem(cv: CanvasItem, c: Vector2, r: float) -> void:
	var tl := c + Vector2(-r * 0.55, -r * 0.55)
	var tr := c + Vector2(r * 0.55, -r * 0.55)
	var gl := c + Vector2(-r, -r * 0.08)
	var gr := c + Vector2(r, -r * 0.08)
	var tip := c + Vector2(0, r)
	var body := PackedVector2Array([tl, tr, gr, tip, gl])
	cv.draw_colored_polygon(body, GEM_BODY)
	cv.draw_colored_polygon(PackedVector2Array([tl, tr, c + Vector2(0, -r * 0.02)]),
			GEM_LIGHT)
	var line := body.duplicate()
	line.append(body[0])
	cv.draw_polyline(line, GEM_DARK, maxf(1.0, r * 0.09), true)
	cv.draw_line(c + Vector2(0, -r * 0.02), tip, GEM_DARK, maxf(1.0, r * 0.09), true)
	cv.draw_line(tl, gr, Color(1, 1, 1, 0.35), maxf(1.0, r * 0.05), true)
	cv.draw_line(tr, gl, GEM_DARK, maxf(1.0, r * 0.05), true)


## 菜单线性图标: kind = card/net/bag/gear/scroll/exit, s≈图标半径(12 左右)
static func menu_icon(cv: CanvasItem, kind: String, center: Vector2, s: float,
		col: Color) -> void:
	var ws := maxf(1.6, s * 0.16)
	match kind:
		"card":  # 单张扑克 + 中央菱形花色
			var pts := PackedVector2Array([
				center + Vector2(-0.5, -0.78) * s, center + Vector2(0.62, -0.78) * s,
				center + Vector2(0.62, 0.78) * s, center + Vector2(-0.5, 0.78) * s,
			])
			pts.append(pts[0])
			cv.draw_polyline(pts, col, ws, true)
			var m := center + Vector2(0.06, 0.02) * s
			cv.draw_colored_polygon(PackedVector2Array([
				m + Vector2(0, -0.34) * s, m + Vector2(0.24, 0) * s,
				m + Vector2(0, 0.34) * s, m + Vector2(-0.24, 0) * s,
			]), col)
		"net":  # 信号弧 + 圆点
			var base := center + Vector2(0, 0.58) * s
			for i in 3:
				cv.draw_arc(base, 0.4 * s * (i + 1), PI + 0.55, TAU - 0.55,
						14, col, ws, true)
			cv.draw_circle(base, ws * 1.05, col)
		"bag":  # 钱袋: 底弧 + 收口交叉束带
			cv.draw_arc(center + Vector2(0, 0.14) * s, 0.55 * s,
					0.2 * PI, 0.8 * PI, 16, col, ws, true)
			cv.draw_line(center + Vector2(-0.53, 0.28) * s,
					center + Vector2(-0.2, -0.3) * s, col, ws, true)
			cv.draw_line(center + Vector2(0.53, 0.28) * s,
					center + Vector2(0.2, -0.3) * s, col, ws, true)
			cv.draw_line(center + Vector2(-0.3, -0.46) * s,
					center + Vector2(0.3, -0.16) * s, col, ws * 1.3, true)
			cv.draw_line(center + Vector2(0.3, -0.46) * s,
					center + Vector2(-0.3, -0.16) * s, col, ws * 1.3, true)
		"gear":  # 齿轮(16 点齿廓) + 中孔
			var pts := PackedVector2Array()
			for i in 16:
				var rad := 0.74 * s if i % 2 == 0 else 0.5 * s
				pts.append(center + Vector2.from_angle(TAU * i / 16.0 + 0.2) * rad)
			pts.append(pts[0])
			cv.draw_polyline(pts, col, ws, true)
			cv.draw_arc(center, 0.22 * s, 0, TAU, 16, col, ws, true)
		"scroll":  # 卷轴: 双卷筒 + 幅面横线
			for dx in [-0.62, 0.62]:
				var cx := center + Vector2(dx * s, 0)
				cv.draw_line(cx + Vector2(0, -0.34) * s, cx + Vector2(0, 0.34) * s,
						col, ws * 1.9, true)
				cv.draw_arc(cx, 0.13 * s, 0, TAU, 10, col, ws * 0.8, true)
			cv.draw_line(center + Vector2(-0.62, -0.2) * s,
					center + Vector2(0.62, -0.2) * s, col, ws, true)
			cv.draw_line(center + Vector2(-0.62, 0.2) * s,
					center + Vector2(0.62, 0.2) * s, col, ws, true)
		"exit":  # 门框(右开口) + 出门箭头
			cv.draw_line(center + Vector2(-0.5, -0.72) * s,
					center + Vector2(0.32, -0.72) * s, col, ws, true)
			cv.draw_line(center + Vector2(-0.5, -0.72) * s,
					center + Vector2(-0.5, 0.72) * s, col, ws, true)
			cv.draw_line(center + Vector2(-0.5, 0.72) * s,
					center + Vector2(0.32, 0.72) * s, col, ws, true)
			cv.draw_line(center + Vector2(0.02, 0) * s,
					center + Vector2(0.82, 0) * s, col, ws * 1.3, true)
			cv.draw_line(center + Vector2(0.5, -0.3) * s,
					center + Vector2(0.82, 0) * s, col, ws * 1.3, true)
			cv.draw_line(center + Vector2(0.5, 0.3) * s,
					center + Vector2(0.82, 0) * s, col, ws * 1.3, true)


## 货币图标控件(kind: "coin"/"gem", 尺寸跟随控件)
class CurrencyIcon extends Control:
	var kind := "coin":
		set(v):
			kind = v
			queue_redraw()

	func _init(p_kind := "coin") -> void:
		kind = p_kind
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r: float = size.y * 0.5
		if r <= 1.0:
			return
		if kind == "gem":
			GameIcons.gem(self, size / 2.0, r)
		else:
			GameIcons.coin(self, size / 2.0, r)


## 富文本金额行: text() 追加文案, amount() 追加 图标+数字 — 替代 emoji 拼接
class CurrencyText extends HBoxContainer:
	var _fs := 19

	func _init(p_font := 19) -> void:
		_fs = p_font
		alignment = BoxContainer.ALIGNMENT_CENTER
		add_theme_constant_override("separation", 6)

	func text(t: String, col: Color) -> void:
		var lb := Label.new()
		lb.text = t
		lb.add_theme_font_size_override("font_size", _fs)
		lb.add_theme_color_override("font_color", col)
		add_child(lb)

	func amount(kind: String, t: String, col: Color) -> void:
		var ic := CurrencyIcon.new(kind)
		ic.custom_minimum_size = Vector2(_fs * 1.2, _fs * 1.2)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(ic)
		var lb := Label.new()
		lb.text = t
		lb.add_theme_font_size_override("font_size", _fs)
		lb.add_theme_color_override("font_color", col)
		add_child(lb)

	## 清空重建(余额刷新用)
	func set_amounts(gold: int, diamonds: int, col: Color) -> void:
		for c in get_children():
			remove_child(c)
			c.free()
		amount("coin", str(gold), col)
		amount("gem", str(diamonds), col)
