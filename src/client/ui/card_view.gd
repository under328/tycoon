## 程序化绘制的扑克牌控件（风格 A：和风×霓虹）。
## 无纹理依赖（运行时 _draw 直绘），headless 环境安全（不渲染即不执行）。
## 花色用多边形绘制；点数/JQK/王 用系统字体。
extends Control

signal picked(card: int)

const CardsGd = preload("res://src/rules/cards.gd")
const Wafu = preload("res://src/client/ui/wafu_paint.gd")
const AppTheme = preload("res://src/client/theme/app_theme.gd")
const SkinsLib = preload("res://src/client/ui/skins.gd")

const COLOR_FACE := Color("f9f4e6")        # 和纸米白
const COLOR_BORDER := Color("caa24e")      # 描金
const COLOR_BACK_BG := Color("20204a")     # 牌背深靛
const COLOR_RED := Color("c93a3a")         # 朱红（♥♦）
const COLOR_BLACK := Color("2b2b3d")       # 墨（♠♣）
const COLOR_GOLD := Color("e0a83c")

var card := -1:
	set(v):
		card = v
		queue_redraw()
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var face_down := false:
	set(v):
		face_down = v
		queue_redraw()
## 显式指定卡面皮肤 id(商城预览用); 空 = 跟随已装备
var palette_id := "":
	set(v):
		palette_id = v
		_refresh_palette()
		queue_redraw()

var _pal: Dictionary = {}
var _face_sb := StyleBoxFlat.new()
var _inner_sb := StyleBoxFlat.new()
var _joker_sb := StyleBoxFlat.new()
var _back_sb := StyleBoxFlat.new()
var _sel_sb := StyleBoxFlat.new()
var _font_ascii: Font = AppTheme.display_font() if false else null
var _font_cjk: Font = null


func _init(p_card: int = -1) -> void:
	card = p_card
	custom_minimum_size = Vector2(72, 100)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_face_sb.bg_color = COLOR_FACE
	_face_sb.set_corner_radius_all(7)
	_face_sb.set_border_width_all(2)
	_face_sb.border_color = COLOR_BORDER

	_inner_sb.bg_color = Color(0, 0, 0, 0)
	_inner_sb.set_corner_radius_all(5)
	_inner_sb.set_border_width_all(1)
	_inner_sb.border_color = Color(COLOR_BORDER, 0.6)

	_joker_sb.bg_color = Color(0, 0, 0, 0)
	_joker_sb.set_corner_radius_all(7)
	_joker_sb.set_border_width_all(2)
	_joker_sb.border_color = COLOR_BORDER

	_back_sb.bg_color = COLOR_BACK_BG
	_back_sb.set_corner_radius_all(7)
	_back_sb.set_border_width_all(2)
	_back_sb.border_color = COLOR_BORDER

	_sel_sb.bg_color = Color(1, 1, 1, 0.06)
	_sel_sb.set_corner_radius_all(7)
	_sel_sb.set_border_width_all(3)
	_sel_sb.border_color = COLOR_GOLD

	_font_ascii = AppTheme.display_font()
	_font_cjk = AppTheme.title_font()
	_refresh_palette()


## 当前装备卡面皮肤的调色板(跟随商城更换)
func _refresh_palette() -> void:
	var w := get_node_or_null("/root/Wallet")
	var cid := "card_washi"
	if palette_id != "":
		cid = palette_id
	elif w != null:
		cid = str(w.equipped_card)
	_pal = SkinsLib.palette(cid)
	_face_sb.bg_color = _pal["face"]
	_face_sb.border_color = _pal["border"]
	_back_sb.bg_color = _pal["back"]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		picked.emit(card)
		accept_event()


func _draw() -> void:
	if face_down:
		_draw_back()
	else:
		_draw_face()
	if selected:
		draw_style_box(_sel_sb, Rect2(Vector2.ZERO, size))
		draw_style_box(_sel_sb, Rect2(Vector2(-2, -2), size + Vector2(4, 4)))


func _draw_face() -> void:
	_refresh_palette()
	draw_style_box(_face_sb, Rect2(Vector2.ZERO, size))
	if card < 0 or card > 53:
		return
	# 全部元素按牌面高度等比缩放(标准 100 高 → s=1.0)
	var s := size.y / 100.0
	# 内框细线(双框)
	draw_style_box(_inner_sb, Rect2(Vector2(4, 4) * s, size - Vector2(8, 8) * s))
	# 和纸颗粒与和风角饰
	Wafu.speckle(self, Rect2(Vector2(5, 5) * s, size - Vector2(10, 10) * s),
			int(20 * s), 100 + card, _pal["speckle"])
	Wafu.corner_ticks(self, Rect2(Vector2(2, 2) * s, size - Vector2(4, 4) * s),
			6.0 * s, Color(Wafu.GOLD, 0.5))
	var ink: Color = _pal["red"] if CardsGd.is_red(card) else _pal["black"]
	var rank: String = CardsGd.rank_label(card)
	if CardsGd.is_joker(card):
		_draw_joker()
		return
	# 主题中心纹样: J/QK 纹章水印, 数字牌纹环
	var motif := str(_pal.get("motif", "washi"))
	var c0 := size / 2.0
	if rank in ["J", "Q", "K"]:
		_draw_crest(motif, c0, 24.0 * s, Color(ink, 0.30))
	else:
		_draw_center_ring(motif, c0, 23.0 * s, Color(ink, 0.18))
	# 左上: 点数牌匾(底色=花色) + 白字
	var plaque := AppTheme.flat(ink, Color(0, 0, 0, 0), 3, 0)
	plaque.set_content_margin_all(2 * s)
	plaque.draw(get_canvas_item(), Rect2(Vector2(4, 3) * s, Vector2(19, 22) * s))
	draw_string(_font_ascii, Vector2(8, 20) * s, rank,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s), _pal["face"])
	_suit(card, Vector2(13, 38) * s, 5.5 * s, ink)
	# 中心: 大花色(投影 + 内芯环)
	var c := size / 2.0
	_suit(card, c + Vector2(2.5, 2.5) * s, 17 * s, Color(0.20, 0.16, 0.10, 0.35))
	_suit(card, c, 17 * s, ink)
	_suit(card, c, 17 * s * 0.42, _pal["face"])
	# 右下: 小点数
	var rank_w: float = _font_ascii.get_string_size(
			rank, HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * s)).x
	draw_string(_font_ascii, size - Vector2(rank_w + 7, 6) * s,
			rank, HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * s), ink)


## 在 pos（中心）以半径 r 绘制花色形状。
func _suit(card_id: int, pos: Vector2, r: float, ink: Color) -> void:
	var s := CardsGd.suit(card_id)  # 0♠ 1♥ 2♦ 3♣
	match s:
		0:
			_draw_spade(pos, r, ink)
		1:
			_draw_heart(pos, r, ink)
		2:
			_draw_diamond(pos, r, ink)
		3:
			_draw_club(pos, r, ink)


func _heart_points(scale: float, flip := false) -> PackedVector2Array:
	# 经典心形参数曲线
	var pts := PackedVector2Array()
	for i in 26:
		var t := TAU * i / 26.0
		var x := 16.0 * pow(sin(t), 3)
		var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
		if flip:
			y = -y
		pts.append(Vector2(x, -y) * scale / 17.0)
	return pts


func _draw_heart(pos: Vector2, r: float, ink: Color) -> void:
	var moved := PackedVector2Array()
	for p in _heart_points(r):
		moved.append(pos + p)  # 心形多边形围绕原点生成, 必须平移到目标位置
	draw_colored_polygon(moved, ink)


func _draw_spade(pos: Vector2, r: float, ink: Color) -> void:
	var pts := _heart_points(r, true)
	var moved := PackedVector2Array()
	for p in pts:
		moved.append(pos + p + Vector2(0, -r * 0.18))
	draw_colored_polygon(moved, ink)
	draw_rect(Rect2(pos + Vector2(-r * 0.12, r * 0.1), Vector2(r * 0.24, r * 0.62)), ink)


func _draw_diamond(pos: Vector2, r: float, ink: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(0, -r), pos + Vector2(r * 0.7, 0),
		pos + Vector2(0, r), pos + Vector2(-r * 0.7, 0),
	]), ink)


func _draw_club(pos: Vector2, r: float, ink: Color) -> void:
	var u := r * 0.42
	draw_circle(pos + Vector2(0, -u), u * 1.15, ink)
	draw_circle(pos + Vector2(-u, u * 0.45), u * 1.15, ink)
	draw_circle(pos + Vector2(u, u * 0.45), u * 1.15, ink)
	draw_rect(Rect2(pos + Vector2(-r * 0.1, r * 0.1), Vector2(r * 0.2, r * 0.62)), ink)


## JOKER 花牌: 各主题专属像素画(达摩/仙鹤/狐面/河童)。
## 大王(53)带描金放射光芒, 小王(52)素面 —— 便于玩家区分。
func _draw_joker() -> void:
	var big := card == 53
	var motif := str(_pal.get("motif", "washi"))
	# 主题夜空底: 牌背色系竖向渐变
	var base: Color = _pal["back"]
	var strips := 10
	var sh := size.y / strips
	for i in strips:
		draw_rect(Rect2(0, i * sh, size.x, sh + 1.0),
				base.lerp(Color(0, 0, 0), 0.4 * float(i) / (strips - 1)))
	Wafu.speckle(self, Rect2(Vector2(3, 3), size - Vector2(6, 6)), 16, 500 + card,
			Color(Wafu.GOLD, 0.12))
	draw_style_box(_joker_sb, Rect2(Vector2.ZERO, size))
	Wafu.corner_ticks(self, Rect2(Vector2(2, 2), size - Vector2(4, 4)), 6.0,
			Color(Wafu.GOLD, 0.6))
	var c := size / 2.0
	if big:
		for i in 12:
			var ang := TAU * i / 12.0
			draw_line(c + Vector2.from_angle(ang) * size.y * 0.10,
					c + Vector2.from_angle(ang) * size.y * 0.40,
					Color(Wafu.GOLD, 0.55), 1.5, true)
	match motif:
		"sumi":
			_pixel_art(PIX_CRANE, _pix_pal_crane(), c, size)
		"hi":
			_pixel_art(PIX_FOX, _pix_pal_fox(), c, size)
		"umi":
			_pixel_art(PIX_KAPPA, _pix_pal_kappa(), c, size)
		_:
			_pixel_art(PIX_DARUMA, _pix_pal_daruma(), c, size)
	# 角标: JOKER
	var js := size.y / 100.0
	draw_string(_font_ascii, Vector2(6, 15) * js, "JOKER",
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * js), Color(Wafu.GOLD, 0.85))
	var jw: float = _font_ascii.get_string_size(
			"JOKER", HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * js)).x
	draw_string(_font_ascii, size - Vector2(jw + 6, 6) * js, "JOKER",
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * js), Color(Wafu.GOLD, 0.85))


## 像素画: grid 每行一个字符串, 字符映射调色板, '.' 为透明。
func _pixel_art(grid: Array, pal: Dictionary, center: Vector2, card_size: Vector2) -> void:
	var cell := card_size.y * 0.052
	var rows := grid.size()
	var cols := (grid[0] as String).length()
	var origin := center - Vector2(cols, rows) * cell * 0.5
	for y in rows:
		var row: String = grid[y]
		for x in row.length():
			var ch := row[x]
			if ch == "." or not pal.has(ch):
				continue
			draw_rect(Rect2(origin + Vector2(x, y) * cell,
					Vector2(cell + 0.6, cell + 0.6)), pal[ch])


func _pix_pal_daruma() -> Dictionary:
	return {"R": _pal["red"], "W": COLOR_FACE, "B": COLOR_BLACK, "G": Wafu.GOLD}


func _pix_pal_crane() -> Dictionary:
	return {"W": COLOR_FACE, "B": COLOR_BLACK, "R": _pal["red"]}


func _pix_pal_fox() -> Dictionary:
	return {"W": COLOR_FACE, "R": Color("d84a3a"), "B": COLOR_BLACK}


func _pix_pal_kappa() -> Dictionary:
	return {"Y": Wafu.GOLD, "G": Color("58a878"), "B": COLOR_BLACK, "P": Color("e8a0b4")}


const PIX_DARUMA := [
	"....RRRR....",
	"...RRRRRR...",
	"..RRRRRRRR..",
	".RRWWRRWWRR.",
	".RRWBRRWBRR.",
	".RRRRRRRRRR.",
	"RRRRRRRRRRRR",
	"RRGGGGGGGGRR",
	"RRRGGGGGGRRR",
	".RRRRRRRRRR.",
	"..RRRRRRRR..",
	"....RRRR....",
]

const PIX_CRANE := [
	"....RR......",
	"....WWW.....",
	"BB..WWW.....",
	".B.WWWWW....",
	"...WWWWWWW..",
	"..BWWWWWWWW.",
	".BWWWWWWWWB.",
	".BWWWWWWWWB.",
	"..BWWWWWWB..",
	"...BWWWWB...",
	"....WWWW....",
	"....W..W....",
]

const PIX_FOX := [
	".WW......WW.",
	".WWW....WWW.",
	".WWWWWWWWWW.",
	"WWWWWWWWWWWW",
	"WWWRRWWRRWWW",
	"WWRRBWWBRRWW",
	"WWWWWWWWWWWW",
	".WWWWRRWWWW.",
	"..WWWWWWWW..",
	"...WWWWWW...",
	"....W..W....",
	"............",
]

const PIX_KAPPA := [
	"..YYYYYYYY..",
	".Y........Y.",
	"..GGGGGGGG..",
	".GGGGGGGGGG.",
	".GBBGGGGBBG.",
	".GGGGGGGGGG.",
	"..GGGPPGGG..",
	"..GGGGGGGG..",
	".GGGGGGGGGG.",
	".GGGGGGGGGG.",
	"..G.G..G.G..",
	"............",
]


## 数字牌中心主题纹环(低饱和, 不干扰识别)。
func _draw_center_ring(motif: String, c: Vector2, r: float, col: Color) -> void:
	match motif:
		"sumi":  # 圆相禅圈(留缺口)
			draw_arc(c, r, PI * 0.55, PI * 2.25, 40, col, 3.0, true)
		"hi":  # 焰环(锯齿芒)
			var pts := PackedVector2Array()
			for i in 16:
				var ang := TAU * i / 16.0 - PI * 0.5
				var rr := r if i % 2 == 0 else r * 0.72
				pts.append(c + Vector2.from_angle(ang) * rr)
			draw_colored_polygon(pts, Color(col, col.a * 0.55))
		"umi":  # 波环(六组浪头弧)
			for i in 6:
				var ang := TAU * i / 6.0
				var p := c + Vector2.from_angle(ang) * r * 0.78
				draw_arc(p, r * 0.5, ang + PI * 0.9, ang + PI * 2.1, 14,
						col, 2.2, true)
		_:  # washi 樱花五瓣
			for i in 5:
				var ang := TAU * i / 5.0 - PI * 0.5
				draw_circle(c + Vector2.from_angle(ang) * r * 0.62, r * 0.34, col)
			draw_circle(c, r * 0.22, col)


## J/QK 主题纹章(花牌水印): 仙鹤/墨龙/狐面/锦鲤。
func _draw_crest(motif: String, c: Vector2, s: float, col: Color) -> void:
	var light := Color(_pal["face"], 0.7)
	match motif:
		"sumi":
			var pts := PackedVector2Array()
			for i in 25:
				var t := float(i) / 24.0
				pts.append(c + Vector2(-s * 0.7 + t * s * 1.5,
						s * 0.55 * sin(t * PI * 1.6)))
			for i in range(1, pts.size()):
				draw_line(pts[i - 1], pts[i], col, s * 0.16, true)
			draw_circle(pts[0], s * 0.17, col)
			draw_line(pts[0] + Vector2(-s * 0.1, -s * 0.08),
					c + Vector2(-s * 1.0, -s * 0.62), col, s * 0.05, true)
		"hi":
			var mask := PackedVector2Array([
				c + Vector2(0, -s * 0.85), c + Vector2(s * 0.62, -s * 0.2),
				c + Vector2(s * 0.5, s * 0.55), c + Vector2(0, s * 0.95),
				c + Vector2(-s * 0.5, s * 0.55), c + Vector2(-s * 0.62, -s * 0.2),
			])
			draw_colored_polygon(mask, col)
			for side in [-1.0, 1.0]:
				var ear := PackedVector2Array([
					c + Vector2(side * s * 0.55, -s * 0.5),
					c + Vector2(side * s * 0.95, -s * 1.05),
					c + Vector2(side * s * 0.72, -s * 0.05),
				])
				draw_colored_polygon(ear, col)
			draw_line(c + Vector2(-s * 0.34, -s * 0.12),
					c + Vector2(-s * 0.1, -s * 0.02), light, s * 0.07, true)
			draw_line(c + Vector2(s * 0.34, -s * 0.12),
					c + Vector2(s * 0.1, -s * 0.02), light, s * 0.07, true)
			draw_circle(c + Vector2(0, s * 0.34), s * 0.08, light)
		"umi":
			var body := PackedVector2Array([
				c + Vector2(-s * 0.9, 0), c + Vector2(-s * 0.5, -s * 0.42),
				c + Vector2(s * 0.35, -s * 0.38), c + Vector2(s * 0.85, 0),
				c + Vector2(s * 0.35, s * 0.38), c + Vector2(-s * 0.5, s * 0.42),
			])
			draw_colored_polygon(body, col)
			var tail := PackedVector2Array([
				c + Vector2(s * 0.8, 0), c + Vector2(s * 1.3, -s * 0.5),
				c + Vector2(s * 1.15, 0), c + Vector2(s * 1.3, s * 0.5),
			])
			draw_colored_polygon(tail, col)
			draw_circle(c + Vector2(-s * 0.62, -s * 0.12), s * 0.1, light)
			draw_arc(c + Vector2(s * 0.1, 0), s * 0.3, -PI * 0.4, PI * 0.4, 12,
					light, s * 0.05, true)
		_:
			var body := PackedVector2Array([
				c + Vector2(-s * 0.7, s * 0.1), c + Vector2(-s * 0.2, -s * 0.35),
				c + Vector2(s * 0.5, -s * 0.25), c + Vector2(s * 0.75, s * 0.15),
				c + Vector2(s * 0.2, s * 0.5), c + Vector2(-s * 0.4, s * 0.5),
			])
			draw_colored_polygon(body, col)
			var wing := PackedVector2Array([
				c + Vector2(-s * 0.15, -s * 0.2), c + Vector2(s * 0.1, -s * 0.9),
				c + Vector2(s * 0.45, -s * 0.1),
			])
			draw_colored_polygon(wing, col)
			draw_line(c + Vector2(-s * 0.55, s * 0.05),
					c + Vector2(-s * 0.8, -s * 0.45), col, s * 0.12, true)
			draw_circle(c + Vector2(-s * 0.86, -s * 0.55), s * 0.13, col)
			draw_line(c + Vector2(-s * 0.95, -s * 0.58),
					c + Vector2(-s * 1.3, -s * 0.5), col, s * 0.05, true)
			var tail := PackedVector2Array([
				c + Vector2(s * 0.6, s * 0.05), c + Vector2(s * 1.15, -s * 0.25),
				c + Vector2(s * 1.05, s * 0.35),
			])
			draw_colored_polygon(tail, col)
			draw_line(c + Vector2(-s * 0.2, s * 0.5),
					c + Vector2(-s * 0.25, s * 0.95), col, s * 0.05, true)
			draw_line(c + Vector2(s * 0.15, s * 0.5),
					c + Vector2(s * 0.1, s * 0.95), col, s * 0.05, true)


## 主题牌背: 和纸=青海波+樱花 / 墨玉=远山月夜 / 绯红=市松纹+焰芯 / 苍海=层浪落日。
func _draw_back() -> void:
	_refresh_palette()
	draw_style_box(_back_sb, Rect2(Vector2.ZERO, size))
	var motif := str(_pal.get("motif", "washi"))
	var border_c: Color = _pal["border"]
	match motif:
		"sumi":
			draw_circle(Vector2(size.x * 0.72, size.y * 0.26), size.y * 0.16,
					Color(_pal["face"], 0.30))
			var m1 := PackedVector2Array([
				Vector2(0, size.y * 0.72), Vector2(size.x * 0.22, size.y * 0.46),
				Vector2(size.x * 0.46, size.y * 0.70), Vector2(size.x * 0.66, size.y * 0.52),
				Vector2(size.x, size.y * 0.74), Vector2(size.x, size.y), Vector2(0, size.y),
			])
			draw_colored_polygon(m1, Color(border_c, 0.28))
			var m2 := PackedVector2Array([
				Vector2(0, size.y * 0.88), Vector2(size.x * 0.3, size.y * 0.68),
				Vector2(size.x * 0.62, size.y * 0.9), Vector2(size.x * 0.85, size.y * 0.74),
				Vector2(size.x, size.y * 0.86), Vector2(size.x, size.y), Vector2(0, size.y),
			])
			draw_colored_polygon(m2, Color(border_c, 0.5))
			draw_rect(Rect2(0, size.y * 0.58, size.x, size.y * 0.05),
					Color(_pal["face"], 0.10))
			draw_rect(Rect2(0, size.y * 0.78, size.x, size.y * 0.04),
					Color(_pal["face"], 0.08))
		"hi":
			var cell := size.x / 7.0
			var accent := Color(_pal["red"], 0.75)
			var dark := Color(0, 0, 0, 0.4)
			for i in 7:
				for row in 2:
					var top_col := accent if (i + row) % 2 == 0 else dark
					draw_rect(Rect2(i * cell, row * cell, cell, cell), top_col)
					var yb := size.y - (row + 1) * cell
					draw_rect(Rect2(i * cell, yb, cell, cell),
							accent if (i + row) % 2 == 0 else dark)
				for col_i in 2:
					var side_col := accent if (i + col_i) % 2 == 0 else dark
					draw_rect(Rect2(col_i * cell, i * cell, cell, cell), side_col)
					var xr := size.x - (col_i + 1) * cell
					draw_rect(Rect2(xr, i * cell, cell, cell), side_col)
			var c := size / 2.0
			var flame := PackedVector2Array()
			for i in 14:
				var ang := TAU * i / 14.0 - PI * 0.5
				var rr := size.y * (0.20 if i % 2 == 0 else 0.13)
				flame.append(c + Vector2.from_angle(ang) * rr)
			draw_colored_polygon(flame, Color(_pal["red"], 0.75))
			draw_circle(c, size.y * 0.07, Color(Wafu.GOLD, 0.85))
		"umi":
			draw_circle(Vector2(size.x * 0.5, size.y * 0.30), size.y * 0.15,
					Color(_pal["red"], 0.65))
			for li in 4:
				var y := size.y * (0.48 + 0.13 * li)
				var col_a := 0.25 + 0.13 * li
				var rr := size.x * 0.22
				var xx := -rr
				while xx < size.x + rr:
					draw_arc(Vector2(xx, y), rr, PI, TAU, 12,
							Color(border_c, col_a), size.x * 0.03, true)
					xx += rr * 1.5
		_:
			var rr := size.x * 0.30
			var row_h := rr * 0.9
			var rowi := 0
			var yy := -rr * 0.4
			while yy < size.y + rr:
				var offset := 0.0 if rowi % 2 == 0 else rr
				var xx := -rr * 1.5 + offset
				while xx < size.x + rr * 1.5:
					for ring in 3:
						draw_arc(Vector2(xx, yy), rr * (0.9 - ring * 0.28),
								0, PI, 16, Color(border_c, 0.32 - ring * 0.08),
								size.x * 0.025, true)
					xx += rr * 2
				yy += row_h
				rowi += 1
			var cm := size / 2.0
			draw_circle(cm, size.y * 0.17, Color(_pal["back"], 0.9))
			for i in 5:
				var ang := TAU * i / 5.0 - PI * 0.5
				draw_circle(cm + Vector2.from_angle(ang) * size.y * 0.11,
						size.y * 0.07, Color(_pal["face"], 0.8))
			draw_circle(cm, size.y * 0.045, Color(Wafu.GOLD, 0.9))
	Wafu.corner_ticks(self, Rect2(Vector2(2, 2) * (size.y / 100.0),
			size - Vector2(4, 4) * (size.y / 100.0)), 6.0 * (size.y / 100.0),
			Color(Wafu.GOLD, 0.55))
