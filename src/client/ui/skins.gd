## 皮肤与卡面数据表 + 程序化头像绘制 v2。
## v2: 每款头像=皮肤色底+内环珠纹+肩部衣领+头部细节+描金外环; 新增皮肤在此追加。
class_name SkinsLib
extends RefCounted

const GOLD := Color("e0a83c")
const RED := Color("e0503c")

## 皮肤(座位人物形象徽章)
const SKINS := [
	{"id": "skin_default", "name": "墨客", "price": 0},
	{"id": "skin_aka", "name": "赤鬼", "price": 40},
	{"id": "skin_ao", "name": "青鬼", "price": 40},
	{"id": "skin_kitsu", "name": "狐妖", "price": 60},
	{"id": "skin_oiran", "name": "花魁", "price": 60},
	{"id": "skin_tengu", "name": "天狗", "price": 80},
]

## 卡面皮肤(整套牌面+牌背配色主题)
const CARDS := [
	{"id": "card_washi", "motif": "washi", "name": "和纸", "price": 0, "face": Color("f9f4e6"),
		"border": Color("caa24e"), "red": Color("c93a3a"), "black": Color("2b2b3d"),
		"shadow": Color(0.2, 0.16, 0.1, 0.35), "back": Color("20204a"),
		"speckle": Color(0.35, 0.28, 0.12, 0.10)},
	{"id": "card_mo", "motif": "sumi", "name": "墨玉", "price": 40, "face": Color("1c1c30"),
		"border": Color("e0a83c"), "red": Color("ff6b6b"), "black": Color("d8d8ea"),
		"shadow": Color(0, 0, 0, 0.4), "back": Color("101024"),
		"speckle": Color(0.88, 0.66, 0.24, 0.12)},
	{"id": "card_hi", "motif": "hi", "name": "绯红", "price": 40, "face": Color("3a1420"),
		"border": Color("e0a83c"), "red": Color("ffb4a0"), "black": Color("f0e0e0"),
		"shadow": Color(0, 0, 0, 0.45), "back": Color("241018"),
		"speckle": Color(1.0, 0.7, 0.6, 0.10)},
	{"id": "card_umi", "motif": "umi", "name": "苍海", "price": 60, "face": Color("12233f"),
		"border": Color("7fb0d8"), "red": Color("ff8899"), "black": Color("d0e2f2"),
		"shadow": Color(0, 0, 0, 0.4), "back": Color("0e1a30"),
		"speckle": Color(0.5, 0.7, 1.0, 0.10)},
]


static func default_card_palette() -> Dictionary:
	return CARDS[0]


static func palette(card_id: String) -> Dictionary:
	for c in CARDS:
		if str(c["id"]) == card_id:
			return c
	return CARDS[0]


static func skin_name(skin_id: String) -> String:
	for s in SKINS:
		if str(s["id"]) == skin_id:
			return str(s["name"])
	return "墨客"


## 程序化头像 v2: 皮肤色底盘 + 内环珠纹 + 肩部衣领 + 头部细节 + 描金外环。
static func draw_avatar(ci: CanvasItem, skin_id: String, center: Vector2, r: float) -> void:
	var theme := _skin_theme(skin_id)
	ci.draw_circle(center, r, theme["bg"])
	for i in 12:
		var ang := TAU * i / 12.0
		ci.draw_circle(center + Vector2.from_angle(ang) * r * 0.86,
				r * 0.045, Color(GOLD, 0.5))
	var shoulder := PackedVector2Array([
		center + Vector2(-r * 0.78, r), center + Vector2(-r * 0.5, r * 0.52),
		center + Vector2(r * 0.5, r * 0.52), center + Vector2(r * 0.78, r),
	])
	ci.draw_colored_polygon(shoulder, theme["cloth"])
	var collar := PackedVector2Array([
		center + Vector2(-r * 0.3, r * 0.56), center + Vector2(0, r * 0.86),
		center + Vector2(r * 0.3, r * 0.56), center + Vector2(0, r * 0.62),
	])
	ci.draw_colored_polygon(collar, theme["collar"])
	var head_c := center + Vector2(0, -r * 0.12)
	var head_r := r * 0.52
	match skin_id:
		"skin_aka":
			_head_oni(ci, head_c, head_r, theme["skin"])
		"skin_ao":
			_head_oni(ci, head_c, head_r, Color("a8c0e0"))
		"skin_kitsu":
			_head_kitsu(ci, head_c, head_r)
		"skin_oiran":
			_head_oiran(ci, head_c, head_r)
		"skin_tengu":
			_head_tengu(ci, head_c, head_r)
		_:
			_head_monomo(ci, head_c, head_r, theme["skin"], theme["hair"])
	ci.draw_arc(center, r * 0.97, 0, TAU, 40, Color(GOLD, 0.75), r * 0.06, true)


static func _skin_theme(skin_id: String) -> Dictionary:
	match skin_id:
		"skin_aka":
			return {"bg": Color("38141c"), "cloth": Color("8a2a20"),
				"collar": Color("3a1420"), "skin": Color("e0a08a"),
				"hair": Color("1c1c2a")}
		"skin_ao":
			return {"bg": Color("142038"), "cloth": Color("24508a"),
				"collar": Color("12203a"), "skin": Color("a8c0e0"),
				"hair": Color("1c1c2a")}
		"skin_kitsu":
			return {"bg": Color("2a2038"), "cloth": Color("c9c9d8"),
				"collar": Color("8a8aa0"), "skin": Color("f2efe6"),
				"hair": Color("f2efe6")}
		"skin_oiran":
			return {"bg": Color("301428"), "cloth": Color("5a1848"),
				"collar": Color("2b0a20"), "skin": Color("f2e6d8"),
				"hair": Color("241a28")}
		"skin_tengu":
			return {"bg": Color("30141c"), "cloth": Color("5a2020"),
				"collar": Color("2a0a0a"), "skin": Color("e0a08a"),
				"hair": Color("1c1c2a")}
	return {"bg": Color("182038"), "cloth": Color("3a4a6a"),
		"collar": Color("1a2438"), "skin": Color("e8dcc8"),
		"hair": Color("3a3428")}


static func _eyes(ci: CanvasItem, c: Vector2, r: float, ink: Color) -> void:
	ci.draw_circle(c + Vector2(-r * 0.34, -r * 0.1), r * 0.11, ink)
	ci.draw_circle(c + Vector2(r * 0.34, -r * 0.1), r * 0.11, ink)


static func _head_monomo(ci: CanvasItem, c: Vector2, r: float, skin: Color, hair: Color) -> void:
	ci.draw_circle(c, r, skin)
	var hat := PackedVector2Array([
		c + Vector2(-r * 1.35, -r * 0.3), c + Vector2(r * 1.35, -r * 0.3),
		c + Vector2(r * 0.2, -r * 1.15), c + Vector2(-r * 0.2, -r * 1.15),
	])
	ci.draw_colored_polygon(hat, Color("8a7448"))
	ci.draw_line(c + Vector2(-r * 1.1, -r * 0.34), c + Vector2(r * 1.1, -r * 0.34),
			Color("6a5836"), r * 0.07, true)
	_eyes(ci, c, r, Color("2b2b3d"))
	ci.draw_circle(c + Vector2(0, r * 0.38), r * 0.07, Color("c93a3a"))
	ci.draw_line(c + Vector2(-r * 0.12, r * 0.5), c + Vector2(-r * 0.2, r * 0.85),
			Color("d8cfc0"), r * 0.06, true)
	ci.draw_line(c + Vector2(r * 0.12, r * 0.5), c + Vector2(r * 0.2, r * 0.85),
			Color("d8cfc0"), r * 0.06, true)


static func _head_oni(ci: CanvasItem, c: Vector2, r: float, skin: Color, hair := Color("1c1c2a")) -> void:
	for side in [-1.0, 1.0]:
		var horn := PackedVector2Array([
			c + Vector2(side * r * 0.3, -r * 0.72),
			c + Vector2(side * r * 0.62, -r * 1.4),
			c + Vector2(side * r * 0.78, -r * 0.42),
		])
		ci.draw_colored_polygon(horn, Color("f2e6c8"))
	ci.draw_circle(c, r, skin)
	ci.draw_arc(c + Vector2(0, -r * 0.15), r * 0.92, PI + 0.3, TAU - 0.3, 24,
			hair, r * 0.16, true)
	for side in [-1.0, 1.0]:
		ci.draw_circle(c + Vector2(side * r * 0.34, -r * 0.08), r * 0.13, Color("f2e6c8"))
		ci.draw_circle(c + Vector2(side * r * 0.34, -r * 0.08), r * 0.06, Color("1c1c2a"))
	for side in [-1.0, 1.0]:
		var fang := PackedVector2Array([
			c + Vector2(side * r * 0.2, r * 0.42),
			c + Vector2(side * r * 0.32, r * 0.42),
			c + Vector2(side * r * 0.26, r * 0.62),
		])
		ci.draw_colored_polygon(fang, Color("f2e6c8"))
	ci.draw_line(c + Vector2(-r * 0.2, -r * 0.4), c + Vector2(r * 0.2, -r * 0.4),
			Color(0, 0, 0, 0.4), r * 0.06, true)


static func _head_kitsu(ci: CanvasItem, c: Vector2, r: float) -> void:
	var white := Color("f2efe6")
	for side in [-1.0, 1.0]:
		var ear := PackedVector2Array([
			c + Vector2(side * r * 0.15, -r * 0.7),
			c + Vector2(side * r * 0.85, -r * 1.3),
			c + Vector2(side * r * 0.78, -r * 0.28),
		])
		ci.draw_colored_polygon(ear, white)
		var inner := PackedVector2Array([
			c + Vector2(side * r * 0.32, -r * 0.72),
			c + Vector2(side * r * 0.7, -r * 1.08),
			c + Vector2(side * r * 0.66, -r * 0.45),
		])
		ci.draw_colored_polygon(inner, Color("e8b4b4"))
	ci.draw_circle(c, r * 0.92, white)
	ci.draw_circle(c + Vector2(-r * 0.45, r * 0.28), r * 0.14, Color("e8a0a0"))
	ci.draw_circle(c + Vector2(r * 0.45, r * 0.28), r * 0.14, Color("e8a0a0"))
	_eyes(ci, c, r, Color("2b2b3d"))
	var nose := PackedVector2Array([
		c + Vector2(0, r * 0.1), c + Vector2(-r * 0.12, r * 0.3),
		c + Vector2(r * 0.12, r * 0.3),
	])
	ci.draw_colored_polygon(nose, Color("c93a3a"))


static func _head_oiran(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c + Vector2(0, -r * 0.12), r * 1.0, Color("241a28"))
	ci.draw_circle(c + Vector2(-r * 0.7, -r * 0.75), r * 0.22, Color("241a28"))
	ci.draw_circle(c + Vector2(r * 0.7, -r * 0.75), r * 0.22, Color("241a28"))
	ci.draw_circle(c + Vector2(-r * 0.7, -r * 0.75), r * 0.09, Color("e0a83c"))
	ci.draw_circle(c + Vector2(r * 0.7, -r * 0.75), r * 0.09, Color("e0a83c"))
	ci.draw_circle(c + Vector2(0, r * 0.08), r * 0.72, Color("f2e6d8"))
	_eyes(ci, c + Vector2(0, r * 0.05), r, Color("2b2b3d"))
	ci.draw_circle(c + Vector2(0, r * 0.4), r * 0.09, Color("c93a3a"))
	ci.draw_circle(c + Vector2(0, -r * 0.02), r * 0.05, Color("c93a3a"))
	ci.draw_circle(c + Vector2(r * 0.55, -r * 0.85), r * 0.14, Color("e8a0b4"))
	ci.draw_circle(c + Vector2(r * 0.55, -r * 0.85), r * 0.06, Color("e0a83c"))


static func _head_tengu(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c + Vector2(0, -r * 0.3), r * 0.95, Color("1c1c2a"))
	ci.draw_circle(c, r * 0.9, Color("c93a3a"))
	for side in [-1.0, 1.0]:
		ci.draw_line(c + Vector2(side * r * 0.15, -r * 0.32),
				c + Vector2(side * r * 0.55, -r * 0.42), Color("f2e6c8"), r * 0.14, true)
	_eyes(ci, c + Vector2(0, -r * 0.05), r, Color("2b2b3d"))
	var nose := PackedVector2Array([
		c + Vector2(-r * 0.1, r * 0.05), c + Vector2(r * 0.1, r * 0.05),
		c + Vector2(r * 0.06, r * 1.1), c + Vector2(-r * 0.06, r * 1.1),
	])
	ci.draw_colored_polygon(nose, Color("f2e6d8"))
	ci.draw_circle(c + Vector2(r * 0.95, -r * 0.1), r * 0.28, Color("e0a83c"))
