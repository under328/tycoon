## 应用图标生成: 1024 渲染 → 512/192/432 变体。
## 设计(动漫风): 暮色渐变 + 描金双环 + Q版动漫少女(大眼高光/腮红/双马尾/
## 金色发饰) 手持三张扇形卡牌(♠A 主牌) + 朱印"富"。
## 用法: godot --path . --script tools/icon_gen.gd (非 headless, 需渲染)
extends SceneTree

var f := 0
var vp: SubViewport = null


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		vp = SubViewport.new()
		vp.size = Vector2i(1024, 1024)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var c: Control = IconDraw.new()
		c.position = Vector2.ZERO
		c.size = Vector2(1024, 1024)
		vp.add_child(c)
	if f == 15:
		var img: Image = vp.get_texture().get_image()
		img.save_png("res://icon.png")
		var i512 := img.duplicate()
		i512.resize(512, 512, Image.INTERPOLATE_LANCZOS)
		i512.save_png("res://icon_512.png")
		var i192 := img.duplicate()
		i192.resize(192, 192, Image.INTERPOLATE_LANCZOS)
		i192.save_png("res://icon_192.png")
		var fg := img.duplicate()
		fg.resize(432, 432, Image.INTERPOLATE_LANCZOS)
		fg.save_png("res://icon_432_fg.png")
		var bg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
		bg.fill(Color("241640"))
		bg.save_png("res://icon_432_bg.png")
		print("[icon] saved 1024/512/192/432fg/432bg")
		quit(0)
	return false


class IconDraw extends Control:
	const GOLD := Color("e0a83c")
	const RED := Color("d0453c")
	const HAIR := Color("323064")
	const HAIR_L := Color("4c4a8c")
	const SKIN := Color("ffe2c8")
	const SKIN_S := Color("f0c0a0")
	const INK := Color("2a2438")

	func _draw() -> void:
		var s := size
		# 暮色渐变(条带): 靛夜 → 紫霓 → 暖绯
		var bands := 64
		for i in bands:
			var t := float(i) / (bands - 1)
			var col: Color
			if t < 0.55:
				col = Color("1c1440").lerp(Color("582460"), t / 0.55)
			else:
				col = Color("582460").lerp(Color("b04858"), (t - 0.55) / 0.45)
			draw_rect(Rect2(0, s.y * i / bands, s.x, s.y / bands + 1), col)
		# 中央暖光晕(托出人物)
		for i in 24:
			draw_circle(s / 2.0 + Vector2(0, s.y * 0.06), s.x * (0.52 - i * 0.012),
					Color(1.0, 0.85, 0.6, 0.018))
		# 描金双环 + 金点(品牌延续)
		draw_arc(s / 2.0, s.x * 0.46, 0, TAU, 180, Color(GOLD, 0.9), s.x * 0.011, true)
		draw_arc(s / 2.0, s.x * 0.425, 0, TAU, 160, Color(GOLD, 0.38), s.x * 0.005, true)
		for i in 8:
			var a := TAU * i / 8.0 + PI / 8.0
			draw_circle(s / 2.0 + Vector2.from_angle(a) * s.x * 0.46, s.x * 0.009, GOLD)
		# 双马尾(先画, 压在头后)
		for side in [-1.0, 1.0]:
			var tail_x: float = s.x * 0.5 + side * s.x * 0.315
			_ell(Vector2(tail_x, s.y * 0.40), s.x * 0.082, s.y * 0.22, HAIR)
			_ell(Vector2(tail_x, s.y * 0.60), s.x * 0.065, s.y * 0.15, HAIR)
			# 发束高光
			_ell(Vector2(tail_x - side * s.x * 0.02, s.y * 0.36),
					s.x * 0.022, s.y * 0.08, HAIR_L)
			# 红发绳
			draw_circle(Vector2(tail_x, s.y * 0.255), s.x * 0.026, RED)
		# 后发(大头轮廓)
		_ell(s / 2.0 + Vector2(0, -s.y * 0.06), s.x * 0.30, s.y * 0.29, HAIR)
		# 脸
		_ell(s / 2.0 + Vector2(0, s.y * 0.015), s.x * 0.215, s.y * 0.205, SKIN)
		# 耳朵
		for side in [-1.0, 1.0]:
			_ell(s / 2.0 + Vector2(side * s.x * 0.205, s.y * 0.03),
					s.x * 0.035, s.y * 0.05, SKIN)
		# 刘海: 整片实心(上缘平, 下缘锯齿) + 侧发束 + 光泽带
		var bl := s.x * 0.235
		var br := s.x * 0.765
		var ytop := s.y * 0.145
		var yval := s.y * 0.325
		var ytip := s.y * 0.415
		var tips := 7
		var zw := (br - bl) / tips
		var zig := PackedVector2Array()
		zig.append(Vector2(bl, ytop))
		zig.append(Vector2(br, ytop))
		for i in tips:  # 右→左: 尖-谷交替, x 严格单调 → 简单多边形
			zig.append(Vector2(br - zw * (i + 0.5),
					ytip if i % 2 == 0 else ytip - s.y * 0.025))
			zig.append(Vector2(br - zw * (i + 1), yval))
		draw_colored_polygon(zig, HAIR)
		# 光泽带(刘海实体内的平滑弧形亮带)
		draw_arc(Vector2(s.x * 0.5, s.y * 0.285), s.x * 0.145,
				PI * 1.25, PI * 1.75, 24, HAIR_L, s.x * 0.016, true)
		# 大眼(动漫核心: 大虹膜+双层高光+粗上睫毛)
		for side in [-1.0, 1.0]:
			var ec := s / 2.0 + Vector2(side * s.x * 0.105, s.y * 0.035)
			# 眼白
			_ell(ec, s.x * 0.062, s.y * 0.075, Color("fdf8f4"))
			# 虹膜(上暗下亮渐层: 两半椭圆)
			_ell(ec + Vector2(0, s.y * 0.006), s.x * 0.046, s.y * 0.062, Color("c8801c"))
			_ell(ec + Vector2(0, s.y * 0.020), s.x * 0.041, s.y * 0.040, Color("f2b43c"))
			# 瞳
			_ell(ec + Vector2(0, s.y * 0.008), s.x * 0.017, s.y * 0.024, INK)
			# 大高光(左上) + 小高光(右下)
			draw_circle(ec + Vector2(-s.x * 0.018, -s.y * 0.024), s.x * 0.017, Color("ffffff"))
			draw_circle(ec + Vector2(s.x * 0.016, s.y * 0.022), s.x * 0.008, Color(1, 1, 1, 0.85))
			# 粗上睫毛(贴眼白上缘)
			draw_rect(Rect2(ec + Vector2(-s.x * 0.062, -s.y * 0.078),
					Vector2(s.x * 0.124, s.y * 0.014)), INK)
			# 细眉(留出额头呼吸)
			draw_rect(Rect2(ec + Vector2(-s.x * 0.045, -s.y * 0.105),
					Vector2(s.x * 0.09, s.y * 0.007)), HAIR)
		# 鼻影 + 微笑小嘴
		draw_circle(s / 2.0 + Vector2(0, s.y * 0.095), s.x * 0.006, SKIN_S)
		var mc := s / 2.0 + Vector2(0, s.y * 0.125)
		draw_colored_polygon(PackedVector2Array([
			mc + Vector2(-s.x * 0.032, 0), mc + Vector2(s.x * 0.032, 0),
			mc + Vector2(0, s.y * 0.030),
		]), Color("b04838"))
		# 腮红
		for side in [-1.0, 1.0]:
			_ell(s / 2.0 + Vector2(side * s.x * 0.15, s.y * 0.095),
					s.x * 0.038, s.y * 0.022, Color(1.0, 0.62, 0.62, 0.55))
		# 三张扇形卡牌(胸前, ♠A 主牌)
		_draw_card(s / 2.0 + Vector2(0, s.y * 0.40), -22.0,
				Color("2c2450"), Color(GOLD, 0.85), false)
		_draw_card(s / 2.0 + Vector2(0, s.y * 0.37), -5.0,
				Color("efe9da"), Color(GOLD, 0.9), false)
		_draw_card(s / 2.0 + Vector2(0, s.y * 0.38), 14.0,
				Color("f9f4e6"), GOLD, true)
		# 朱印"富"(右上, 品牌延续)
		var seal := s.x * 0.155
		var sp := Vector2(s.x * 0.83, s.y * 0.155)
		draw_set_transform_matrix(Transform2D(0.10, sp))
		draw_rect(Rect2(Vector2(-seal, -seal) * 0.5, Vector2(seal, seal)), Color(RED, 0.95))
		var fnt: Font = preload("res://src/client/theme/app_theme.gd").title_font()
		draw_string(fnt, Vector2(-seal * 0.36, seal * 0.36), "富",
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(seal * 0.82), Color("f8f4ec"))
		draw_set_transform_matrix(Transform2D())

	func _ell(c: Vector2, rx: float, ry: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 48:
			var a := TAU * i / 48.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts, col)

	func _draw_card(pivot: Vector2, deg: float, face: Color,
			border: Color, with_spade: bool) -> void:
		var s := size
		var card := s * Vector2(0.24, 0.33)
		draw_set_transform_matrix(Transform2D(deg_to_rad(deg), pivot))
		var sb := StyleBoxFlat.new()
		sb.bg_color = face
		sb.set_corner_radius_all(s.x * 0.028)
		sb.set_border_width_all(s.x * 0.010)
		sb.border_color = border
		sb.shadow_color = Color(0, 0, 0, 0.4)
		sb.shadow_size = s.x * 0.018
		draw_style_box(sb, Rect2(-card / 2.0, card))
		if with_spade:
			var c := Vector2(0, -card.y * 0.05)
			var r := card.x * 0.24
			var pts := PackedVector2Array()
			for i in 26:
				var t := TAU * i / 26.0
				var x := 16.0 * pow(sin(t), 3)
				var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
				pts.append(c + Vector2(x, -y) * r / 16.0)
			draw_colored_polygon(pts, Color("2a2a3c"))
			draw_rect(Rect2(c + Vector2(-r * 0.13, r * 0.30), Vector2(r * 0.26, r * 0.6)),
					Color("2a2a3c"))
		else:
			var c := Vector2(0, -card.y * 0.02)
			var col := Color("c93a3a") if face == Color("f9f4e6") else Color(GOLD, 0.5)
			var r := card.x * 0.20
			var pts := PackedVector2Array()
			for i in 26:
				var t := TAU * i / 26.0
				var x := 16.0 * pow(sin(t), 3)
				var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
				pts.append(c + Vector2(x, -y) * r / 16.0)
			draw_colored_polygon(pts, col)
		draw_set_transform_matrix(Transform2D())
