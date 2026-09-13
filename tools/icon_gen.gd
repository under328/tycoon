## 应用图标生成: 1024 渲染 → 512/192/432 变体。
## 设计: 藏青夜空渐变 + 描金双环 + 三张扇形卡牌(黑桃/红心/牌背) + 朱印"富"。
## 用法: godot --path . --script tools/icon_gen.gd (非 headless, 需渲染)
extends SceneTree

const GOLD := Color("e0a83c")
const RED := Color("c93a3a")
const FACE := Color("f9f4e6")
const BACK := Color("20204a")
const INK := Color("2b2b3d")

var f := 0
const AppTheme = preload("res://src/client/theme/app_theme.gd")
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
		bg.fill(Color("14142b"))
		bg.save_png("res://icon_432_bg.png")
		print("[icon] saved 1024/512/192/432fg/432bg")
		quit(0)
	return false


class IconDraw extends Control:
	const GOLD := Color("e0a83c")
	const RED := Color("c93a3a")
	const FACE := Color("f9f4e6")
	const BACK := Color("20204a")
	const INK := Color("2b2b3d")

	func _draw() -> void:
		var s := size
		# 夜空渐变(条带)
		var bands := 64
		for i in bands:
			var t := float(i) / (bands - 1)
			draw_rect(Rect2(0, s.y * i / bands, s.x, s.y / bands + 1),
					Color("1c1c40").lerp(Color("0d0d1e"), t))
		# 描金双环
		draw_arc(s / 2.0, s.x * 0.40, 0, TAU, 180, Color(GOLD, 0.95), s.x * 0.013, true)
		draw_arc(s / 2.0, s.x * 0.36, 0, TAU, 160, Color(GOLD, 0.42), s.x * 0.006, true)
		# 环上金点
		for i in 8:
			var a := TAU * i / 8.0 + PI / 8.0
			draw_circle(s / 2.0 + Vector2.from_angle(a) * s.x * 0.40, s.x * 0.011, GOLD)
		# 三张扇形卡牌(旋转绘制)
		_draw_card(s / 2.0 + Vector2(0, s.y * 0.10), s.y * 0.005, -20.0,
				BACK, Color(GOLD, 0.9), false)
		_draw_card(s / 2.0 + Vector2(0, s.y * 0.07), s.y * 0.005, -4.0,
				Color("efe9da"), Color(GOLD, 0.95), false)
		_draw_card(s / 2.0 + Vector2(0, s.y * 0.08), s.y * 0.005, 12.0,
				FACE, Color(GOLD, 1.0), true)
		# 朱印"富"
		var seal := s.x * 0.21
		var sp := Vector2(s.x * 0.735, s.y * 0.68)
		draw_set_transform_matrix(Transform2D(0.10, sp))
		draw_rect(Rect2(Vector2(-seal, -seal) * 0.5, Vector2(seal, seal)), Color(RED, 0.95))
		draw_rect(Rect2(Vector2(-seal, -seal) * 0.5 + Vector2(6, 6), Vector2(seal, seal) - Vector2(12, 12)),
				Color(0, 0, 0, 0), false, 3.0)
		var fnt: Font = AppTheme.title_font()
		draw_string(fnt, Vector2(-seal * 0.36, seal * 0.36), "富",
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(seal * 0.82), Color("f8f4ec"))
		draw_set_transform_matrix(Transform2D())


	func _draw_card(pivot: Vector2, lift: float, deg: float, face: Color,
			border: Color, with_spade: bool) -> void:
		var s := size
		var card := s * Vector2(0.30, 0.42)
		draw_set_transform_matrix(Transform2D(deg_to_rad(deg), pivot + Vector2(0, -lift)))
		var sb := StyleBoxFlat.new()
		sb.bg_color = face
		sb.set_corner_radius_all(s.x * 0.030)
		sb.set_border_width_all(s.x * 0.012)
		sb.border_color = border
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = s.x * 0.02
		draw_style_box(sb, Rect2(-card / 2.0, card))
		if with_spade:
			var c := Vector2(0, -card.y * 0.12)
			var r := card.x * 0.22
			# 黑桃: 倒心 + 颈座
			var pts := PackedVector2Array()
			for i in 26:
				var t := TAU * i / 26.0
				var x := 16.0 * pow(sin(t), 3)
				var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
				pts.append(c + Vector2(x, -y) * r / 16.0 + Vector2(0, -r * 0.1))
			draw_colored_polygon(pts, RED)
			draw_rect(Rect2(c + Vector2(-r * 0.14, r * 0.28), Vector2(r * 0.28, r * 0.62)), INK)
		else:
			var c := Vector2(0, -card.y * 0.10)
			var col := RED if face == FACE else Color(GOLD, 0.5)
			var r := card.x * 0.20
			var pts := PackedVector2Array()
			for i in 26:
				var t := TAU * i / 26.0
				var x := 16.0 * pow(sin(t), 3)
				var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
				pts.append(c + Vector2(x, -y) * r / 16.0)
			draw_colored_polygon(pts, col)
		draw_set_transform_matrix(Transform2D())
