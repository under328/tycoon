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
const COLOR_BACK_PAT := Color("3a3a6e")    # 牌背纹样
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
	if w != null:
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
	# 内框细线(双框)
	draw_style_box(_inner_sb, Rect2(Vector2(4, 4), size - Vector2(8, 8)))
	# 和纸颗粒与和风角饰
	Wafu.speckle(self, Rect2(Vector2(5, 5), size - Vector2(10, 10)), 20, 100 + card,
			_pal["speckle"])
	Wafu.corner_ticks(self, Rect2(Vector2(2, 2), size - Vector2(4, 4)), 6.0,
			Color(Wafu.GOLD, 0.5))
	var ink: Color = _pal["red"] if CardsGd.is_red(card) else _pal["black"]
	var rank: String = CardsGd.rank_label(card)
	if CardsGd.is_joker(card):
		_draw_joker()
		return
	# 左上: 点数牌匾(底色=花色) + 白字
	var plaque := AppTheme.flat(ink, Color(0, 0, 0, 0), 3, 0)
	plaque.set_content_margin_all(2)
	plaque.draw(get_canvas_item(), Rect2(Vector2(4, 3), Vector2(19, 22)))
	draw_string(_font_ascii, Vector2(8, 20), rank,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, _pal["face"])
	_suit(card, Vector2(13, 38), 5.5, ink)
	# 中心: 大花色(投影 + 内芯环)
	var c := size / 2.0
	_suit(card, c + Vector2(2.5, 2.5), 17, Color(0.20, 0.16, 0.10, 0.35))
	_suit(card, c, 17, ink)
	_suit(card, c, 17 * 0.42, _pal["face"])
	# 右下: 小点数
	var rank_w: float = _font_ascii.get_string_size(
			rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(_font_ascii, size - Vector2(rank_w + 7, 6),
			rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)


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


## JOKER 花牌: 深靛夜空底, 描金放射线, 红日居中, 毛笔"王"字。
## 大王(53)带十二道光芒, 小王(52)素面红日 —— 便于玩家区分。
func _draw_joker() -> void:
	var big := card == 53
	# 深靛渐变底(竖向)
	var strips := 10
	var sh := size.y / strips
	for i in strips:
		draw_rect(Rect2(0, i * sh, size.x, sh + 1.0),
				Color("2c2450").lerp(Color("181830"), float(i) / (strips - 1)))
	# 和纸颗粒 + 描金边框角饰
	Wafu.speckle(self, Rect2(Vector2(3, 3), size - Vector2(6, 6)), 16, 500 + card,
			Color(Wafu.GOLD, 0.12))
	draw_style_box(_joker_sb, Rect2(Vector2.ZERO, size))
	Wafu.corner_ticks(self, Rect2(Vector2(2, 2), size - Vector2(4, 4)), 6.0,
			Color(Wafu.GOLD, 0.6))
	# 中心: 放射光芒 + 红日
	var c := size / 2.0
	if big:
		for i in 12:
			var ang := TAU * i / 12.0
			var r1 := 24.0 if i % 2 == 0 else 19.0
			draw_line(c + Vector2.from_angle(ang) * 9.0,
					c + Vector2.from_angle(ang) * r1,
					Color(Wafu.GOLD, 0.75), 1.5, true)
	draw_circle(c, 13.5, Color(Wafu.RED, 0.95))
	# 毛笔"王"(白)
	draw_string(_font_cjk, c + Vector2(-11, 8), "王",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, COLOR_FACE)
	# 角标: JOKER
	draw_string(_font_ascii, Vector2(6, 15), "JOKER",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Wafu.GOLD, 0.85))
	var jw: float = _font_ascii.get_string_size(
			"JOKER", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(_font_ascii, size - Vector2(jw + 6, 6), "JOKER",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Wafu.GOLD, 0.85))


func _draw_back() -> void:
	_refresh_palette()
	draw_style_box(_back_sb, Rect2(Vector2.ZERO, size))
	var c := size / 2.0
	var s := size.y / 100.0  # 纹样随牌面尺寸缩放(对手牌背为小尺寸)
	for i in 3:
		draw_arc(c + Vector2(0, (-18 + i * 18) * s), 26.0 * s, PI * 1.15, PI * 1.85, 24,
				COLOR_BACK_PAT, 2.0, true)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -8 * s), c + Vector2(7 * s, 0),
		c + Vector2(0, 8 * s), c + Vector2(-7 * s, 0),
	]), COLOR_GOLD)
	draw_arc(c, 36.0, 0, TAU, 40, COLOR_BACK_PAT, 1.2, true)
	draw_rect(Rect2(5, 5, size.x - 10, size.y - 10), Color(Wafu.GOLD, 0.25), false, 1.0)
	Wafu.speckle(self, Rect2(Vector2(6, 6), size - Vector2(12, 12)), 14, 900 + card,
			Color(Wafu.GOLD, 0.10))
