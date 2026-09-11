## 皮肤与卡面数据表 + 程序化头像绘制（计划 §12.3）。
## 全部程序化绘制, 零外部素材; 新增皮肤在此追加条目与绘制分支。
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
	{"id": "card_washi", "name": "和纸", "price": 0, "face": Color("f9f4e6"),
		"border": Color("caa24e"), "red": Color("c93a3a"), "black": Color("2b2b3d"),
		"shadow": Color(0.2, 0.16, 0.1, 0.35), "back": Color("20204a"),
		"speckle": Color(0.35, 0.28, 0.12, 0.10)},
	{"id": "card_mo", "name": "墨玉", "price": 40, "face": Color("1c1c30"),
		"border": Color("e0a83c"), "red": Color("ff6b6b"), "black": Color("d8d8ea"),
		"shadow": Color(0, 0, 0, 0.4), "back": Color("101024"),
		"speckle": Color(0.88, 0.66, 0.24, 0.12)},
	{"id": "card_hi", "name": "绯红", "price": 40, "face": Color("3a1420"),
		"border": Color("e0a83c"), "red": Color("ffb4a0"), "black": Color("f0e0e0"),
		"shadow": Color(0, 0, 0, 0.45), "back": Color("241018"),
		"speckle": Color(1.0, 0.7, 0.6, 0.10)},
	{"id": "card_umi", "name": "苍海", "price": 60, "face": Color("12233f"),
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


## 程序化头像: 在 center 以半径 r 绘制徽章(底盘+人物形象)。
static func draw_avatar(ci: CanvasItem, skin_id: String, center: Vector2, r: float) -> void:
	# 底盘 + 描金环
	ci.draw_circle(center, r, Color(0.10, 0.10, 0.22))
	ci.draw_arc(center, r, 0, TAU, 32, Color(GOLD, 0.8), r * 0.07, true)
	var head := r * 0.52
	var head_c := center + Vector2(0, r * 0.08)
	match skin_id:
		"skin_aka":
			_oni(ci, head_c, head, Color("c9452e"))
		"skin_ao":
			_oni(ci, head_c, head, Color("2e5ec9"))
		"skin_kitsu":
			_kitsu(ci, head_c, head)
		"skin_oiran":
			_oiran(ci, head_c, head)
		"skin_tengu":
			_tengu(ci, head_c, head)
		_:
			_monomo(ci, head_c, head)


## 墨客(默认): 斗笠行人
static func _monomo(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r, Color("d8cfc0"))
	ci.draw_circle(c + Vector2(-r * 0.35, -r * 0.1), r * 0.09, Color("2b2b3d"))
	ci.draw_circle(c + Vector2(r * 0.35, -r * 0.1), r * 0.09, Color("2b2b3d"))
	var hat := PackedVector2Array([
		c + Vector2(-r * 1.25, -r * 0.35), c + Vector2(r * 1.25, -r * 0.35),
		c + Vector2(0, -r * 1.05),
	])
	ci.draw_colored_polygon(hat, Color("8a7448"))


## 鬼(赤/青): 角 + 凶眼
static func _oni(ci: CanvasItem, c: Vector2, r: float, skin: Color) -> void:
	ci.draw_circle(c, r, skin)
	for side in [-1.0, 1.0]:
		var horn := PackedVector2Array([
			c + Vector2(side * r * 0.35, -r * 0.7),
			c + Vector2(side * r * 0.6, -r * 1.35),
			c + Vector2(side * r * 0.75, -r * 0.45),
		])
		ci.draw_colored_polygon(horn, Color("f2e6c8"))
	ci.draw_circle(c + Vector2(-r * 0.32, -r * 0.05), r * 0.11, Color("f2e6c8"))
	ci.draw_circle(c + Vector2(r * 0.32, -r * 0.05), r * 0.11, Color("f2e6c8"))
	ci.draw_rect(Rect2(c + Vector2(-r * 0.28, r * 0.28), Vector2(r * 0.56, r * 0.10)),
			Color("f2e6c8"))


## 狐妖: 白狐面 + 赤纹
static func _kitsu(ci: CanvasItem, c: Vector2, r: float) -> void:
	for side in [-1.0, 1.0]:
		var ear := PackedVector2Array([
			c + Vector2(side * r * 0.15, -r * 0.75),
			c + Vector2(side * r * 0.85, -r * 1.25),
			c + Vector2(side * r * 0.75, -r * 0.3),
		])
		ci.draw_colored_polygon(ear, Color("f2efe6"))
	ci.draw_circle(c, r * 0.92, Color("f2efe6"))
	ci.draw_circle(c + Vector2(-r * 0.3, -r * 0.05), r * 0.09, Color("2b2b3d"))
	ci.draw_circle(c + Vector2(r * 0.3, -r * 0.05), r * 0.09, Color("2b2b3d"))
	var nose := PackedVector2Array([
		c + Vector2(0, r * 0.12), c + Vector2(-r * 0.12, r * 0.3),
		c + Vector2(r * 0.12, r * 0.3),
	])
	ci.draw_colored_polygon(nose, Color("c93a3a"))
	ci.draw_line(c + Vector2(-r * 0.35, r * 0.42), c + Vector2(-r * 0.1, r * 0.34),
			Color("c93a3a"), r * 0.08, true)
	ci.draw_line(c + Vector2(r * 0.35, r * 0.42), c + Vector2(r * 0.1, r * 0.34),
			Color("c93a3a"), r * 0.08, true)


## 花魁: 黑发 + 髪饰
static func _oiran(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c + Vector2(0, -r * 0.15), r * 1.0, Color("2b2b3d"))
	ci.draw_circle(c + Vector2(0, r * 0.1), r * 0.75, Color("f2e6c8"))
	ci.draw_circle(c + Vector2(-r * 0.3, -r * 0.05), r * 0.09, Color("2b2b3d"))
	ci.draw_circle(c + Vector2(r * 0.3, -r * 0.05), r * 0.09, Color("2b2b3d"))
	ci.draw_circle(c + Vector2(0, r * 0.32), r * 0.10, Color("c93a3a"))
	for side in [-1.0, 1.0]:
		ci.draw_circle(c + Vector2(side * r * 0.55, -r * 0.55), r * 0.18,
				Color("e0a83c"))


## 天狗: 红面长鼻
static func _tengu(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r * 0.9, Color("c93a3a"))
	var nose := PackedVector2Array([
		c + Vector2(-r * 0.12, r * 0.05), c + Vector2(r * 0.12, r * 0.05),
		c + Vector2(r * 0.05, r * 1.15), c + Vector2(-r * 0.05, r * 1.15),
	])
	ci.draw_colored_polygon(nose, Color("f2e6c8"))
	ci.draw_circle(c + Vector2(-r * 0.32, -r * 0.2), r * 0.12, Color("f2efe6"))
	ci.draw_circle(c + Vector2(r * 0.32, -r * 0.2), r * 0.12, Color("f2efe6"))
	for side in [-1.0, 1.0]:
		ci.draw_line(c + Vector2(side * r * 0.45, -r * 0.85),
				c + Vector2(side * r * 0.7, -r * 1.25), Color("2b2b3d"), r * 0.12, true)
