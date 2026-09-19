## 应用图标生成: 1024 渲染 → 512/192/432 变体。
## 设计 v2「朱印·富」: 暮色靛紫渐变底 + 描金双环(品牌延续) + 三张扇形卡牌
## (♠A 主牌 / ♥ 红心 / 金纹牌背) + 中央朱印「富」为视觉主角 — 大字号高对比,
## 48px 小图标仍清晰可辨; 金色花瓣点缀呼应和风霓虹主视觉。
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
		# Android 自适应图标: 前景整体缩进安全区(外缘 18% 会被圆形蒙版裁掉),
		# 背景铺纯深靛
		var fg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
		fg.fill(Color("241640"))
		var inner := img.duplicate()
		inner.resize(360, 360, Image.INTERPOLATE_LANCZOS)
		fg.blend_rect(inner, Rect2i(0, 0, 360, 360), Vector2i(36, 36))
		fg.save_png("res://icon_432_fg.png")
		var bg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
		bg.fill(Color("241640"))
		bg.save_png("res://icon_432_bg.png")
		print("[icon] saved 1024/512/192/432fg/432bg")
		quit(0)
	return false


class IconDraw extends Control:
	const AppTheme = preload("res://src/client/theme/app_theme.gd")
	const GOLD := Color("e0a83c")
	const RED := Color("c9403a")
	const RED_D := Color("99302a")
	const CREAM := Color("f9f4e6")
	const BACK := Color("262048")
	const INK := Color("2a2a3c")

	func _draw() -> void:
		var s := size
		# ── 暮色夜空: 上深靛 → 下紫(条带渐变) + 中央暖光晕托出主体 ──
		var bands := 64
		for i in bands:
			var t := float(i) / (bands - 1)
			var col := Color("181234").lerp(Color("381e54"), t)
			draw_rect(Rect2(0, s.y * i / bands, s.x, s.y / bands + 1), col)
		for i in 26:
			draw_circle(s / 2.0 + Vector2(0, s.y * 0.03), s.x * (0.58 - i * 0.016),
					Color(1.0, 0.85, 0.6, 0.020))
		# ── 描金双环 + 金点(品牌延续) ──
		draw_arc(s / 2.0, s.x * 0.46, 0, TAU, 180, Color(GOLD, 0.92), s.x * 0.012, true)
		draw_arc(s / 2.0, s.x * 0.424, 0, TAU, 160, Color(GOLD, 0.38), s.x * 0.005, true)
		for i in 8:
			var a := TAU * i / 8.0 + PI / 8.0
			draw_circle(s / 2.0 + Vector2.from_angle(a) * s.x * 0.46, s.x * 0.009, GOLD)
		# ── 三张扇形卡牌(中上, 后方衬底): 金纹牌背 / ♥ / ♠A ──
		_draw_back_card(s / 2.0 + Vector2(-s.x * 0.165, -s.y * 0.095), -16.0)
		_draw_pip_card(s / 2.0 + Vector2(s.x * 0.160, -s.y * 0.105), 15.0, true)
		_draw_pip_card(s / 2.0 + Vector2(0.0, -s.y * 0.150), 0.0, false)
		# ── 朱印「富」(视觉主角, 压在卡扇前) ──
		_draw_seal(s / 2.0 + Vector2(0.0, s.y * 0.085), s.x * 0.35)
		# ── 金粉花瓣点缀(呼应和风) ──
		for pet: Array in [[0.175, 0.215, -0.5, 0.030], [0.815, 0.30, 0.9, 0.024],
				[0.735, 0.795, 0.25, 0.019], [0.235, 0.80, -1.1, 0.016]]:
			_petal(Vector2(s.x * float(pet[0]), s.y * float(pet[1])),
					float(pet[2]), s.x * float(pet[3]))

	## 牌背: 深靛 + 金框 + 内回纹线 + 中央金菱
	func _draw_back_card(c: Vector2, deg: float) -> void:
		var s := size
		var card := s * Vector2(0.235, 0.325)
		draw_set_transform_matrix(Transform2D(deg_to_rad(deg), c))
		_card_face(BACK, Color(GOLD, 0.85))
		# 空心内框: 四条细金线
		var iw := card.x * 0.5 - s.x * 0.014
		var ih := card.y * 0.5 - s.x * 0.014
		for seg: Array in [[Vector2(-iw, -ih), Vector2(iw, -ih)],
				[Vector2(-iw, ih), Vector2(iw, ih)],
				[Vector2(-iw, -ih), Vector2(-iw, ih)],
				[Vector2(iw, -ih), Vector2(iw, ih)]]:
			draw_line(seg[0], seg[1], Color(GOLD, 0.55), s.x * 0.004, true)
		draw_set_transform_matrix(Transform2D())

	## 牌面: with_heart=true 红心牌(♥), 否则黑桃 A(♠A 主牌)
	func _draw_pip_card(c: Vector2, deg: float, with_heart: bool) -> void:
		var s := size
		var card := s * Vector2(0.235, 0.325)
		draw_set_transform_matrix(Transform2D(deg_to_rad(deg), c))
		_card_face(CREAM, Color(GOLD, 0.9))
		var ink := Color("c93a3a") if with_heart else INK
		# 角标 A
		var fnt: Font = AppTheme.display_font()
		draw_string(fnt, Vector2(-card.x * 0.44, -card.y * 0.24), "A",
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(card.x * 0.30), ink)
		var pr := card.x * 0.14
		if with_heart:
			_heart(Vector2(-card.x * 0.30, -card.y * 0.12), pr, ink)
		else:
			_spade(Vector2(-card.x * 0.30, -card.y * 0.14), pr, ink)
		# 中央大花色
		var big := card.x * 0.30
		if with_heart:
			_heart(Vector2(0, card.y * 0.06), big, ink)
		else:
			_spade(Vector2(0, card.y * 0.04), big, ink)
		draw_set_transform_matrix(Transform2D())

	## 卡片底板(需先 draw_set_transform): 米面/深背 + 圆角 + 描金 + 落影
	func _card_face(face: Color, border: Color) -> void:
		var s := size
		var card := s * Vector2(0.235, 0.325)
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0, 0, 0, 0.30)
		sh.set_corner_radius_all(s.x * 0.028)
		draw_style_box(sh, Rect2(-card / 2.0 + Vector2(s.x * 0.008, s.y * 0.012), card))
		var sb := StyleBoxFlat.new()
		sb.bg_color = face
		sb.set_corner_radius_all(s.x * 0.028)
		sb.set_border_width_all(int(s.x * 0.010))
		sb.border_color = border
		draw_style_box(sb, Rect2(-card / 2.0, card))

	## 朱印「富」: 落影 + 深红描边印身 + 白字(大字号, 小图标仍可读)
	func _draw_seal(c: Vector2, sz: float) -> void:
		draw_set_transform_matrix(Transform2D(deg_to_rad(4.0), c))
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0, 0, 0, 0.40)
		sh.set_corner_radius_all(sz * 0.16)
		draw_style_box(sh, Rect2(Vector2(-sz * 0.49, -sz * 0.46),
				Vector2(sz, sz)))
		var sb := StyleBoxFlat.new()
		sb.bg_color = RED
		sb.set_corner_radius_all(sz * 0.16)
		sb.set_border_width_all(int(sz * 0.040))
		sb.border_color = RED_D
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = int(sz * 0.06)
		draw_style_box(sb, Rect2(Vector2(-sz / 2.0, -sz / 2.0), Vector2(sz, sz)))
		# 内衬细白线(印章篆框感)
		var iw := sz * 0.5 - sz * 0.085
		for seg: Array in [[Vector2(-iw, -iw), Vector2(iw, -iw)],
				[Vector2(-iw, iw), Vector2(iw, iw)],
				[Vector2(-iw, -iw), Vector2(-iw, iw)],
				[Vector2(iw, -iw), Vector2(iw, iw)]]:
			draw_line(seg[0], seg[1], Color("faf6ee", 0.28), sz * 0.012, true)
		var fnt: Font = AppTheme.title_font()
		draw_string(fnt, Vector2(-sz * 0.5, sz * 0.30), "富",
				HORIZONTAL_ALIGNMENT_CENTER, sz, int(sz * 0.72), Color("faf6ee"))
		draw_set_transform_matrix(Transform2D())

	## 黑桃(16 点参数式心形倒置 + 带柄)
	func _spade(c: Vector2, r: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 26:
			var t := TAU * i / 26.0
			var x := 16.0 * pow(sin(t), 3)
			var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) \
					- cos(4.0 * t)
			pts.append(c + Vector2(x, -y) * r / 16.0)
		draw_colored_polygon(pts, col)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-r * 0.10, r * 0.05), c + Vector2(r * 0.10, r * 0.05),
			c + Vector2(r * 0.42, r * 0.85), c + Vector2(-r * 0.42, r * 0.85),
		]), col)

	## 红心(双圆 + 尖底三角)
	func _heart(c: Vector2, r: float, col: Color) -> void:
		draw_circle(c + Vector2(-r * 0.42, -r * 0.28), r * 0.52, col)
		draw_circle(c + Vector2(r * 0.42, -r * 0.28), r * 0.52, col)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-r * 0.88, -r * 0.06), c + Vector2(r * 0.88, -r * 0.06),
			c + Vector2(0, r * 0.78),
		]), col)

	## 花瓣(旋转椭圆, 粉金)
	func _petal(c: Vector2, rot: float, r: float) -> void:
		draw_set_transform_matrix(Transform2D(rot, c))
		_ell(Vector2.ZERO, r, r * 0.60, Color("f0b8c0", 0.8))
		draw_set_transform_matrix(Transform2D())

	func _ell(c: Vector2, rx: float, ry: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 48:
			var a := TAU * i / 48.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts, col)
