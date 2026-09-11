## 程序化绘制的扑克牌控件（风格 A：和风×霓虹）。
## 无纹理依赖（运行时 _draw 直绘），headless 环境安全（不渲染即不执行）。
## 花色用多边形绘制；点数/JQK/王 用系统字体。
extends Control

signal picked(card: int)

const CardsGd = preload("res://src/rules/cards.gd")
const Wafu = preload("res://src/client/ui/wafu_paint.gd")
const AppTheme = preload("res://src/client/theme/app_theme.gd")

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

var _face_sb := StyleBoxFlat.new()
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
	draw_style_box(_face_sb, Rect2(Vector2.ZERO, size))
	if card < 0 or card > 53:
		return
	# 和纸颗粒与和风角饰
	Wafu.speckle(self, Rect2(Vector2(3, 3), size - Vector2(6, 6)), 22, 100 + card,
			Color(0.35, 0.28, 0.12, 0.10))
	Wafu.corner_ticks(self, Rect2(Vector2(2, 2), size - Vector2(4, 4)), 6.0,
			Color(Wafu.GOLD, 0.45))
	var ink := COLOR_BLACK
	if CardsGd.is_red(card):
		ink = COLOR_RED
	var rank: String = CardsGd.rank_label(card)
	if CardsGd.is_joker(card):
		_draw_joker()
		return
	# 左上: 点数 + 小花色
	draw_string(_font_ascii, Vector2(7, 24), rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
	_suit(card, Vector2(20, 36), 6, ink)
	# 中心
	var c := size / 2.0
	if rank == "J" or rank == "Q" or rank == "K":
		# 人头牌: 双层描金圆环 + 大字母
		draw_arc(c, 30.0, 0, TAU, 40, COLOR_BORDER, 1.6, true)
		draw_arc(c, 25.0, 0, TAU, 40, COLOR_BORDER, 0.8, true)
		draw_string(_font_ascii, c + Vector2(-11, 14), rank,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0.20, 0.16, 0.10, 0.35))
		draw_string(_font_ascii, c + Vector2(-13, 12), rank,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 34, ink)
		_suit(card, c + Vector2(-5, 24), 5, ink)
	else:
		_suit(card, c + Vector2(2.5, 2.5), 17, Color(0.20, 0.16, 0.10, 0.35))
		_suit(card, c, 17, ink)
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


func _draw_joker() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2c2440")
	sb.set_corner_radius_all(7)
	sb.set_border_width_all(2)
	sb.border_color = COLOR_GOLD
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	var c := size / 2.0
	draw_arc(c, 30.0, 0, TAU, 40, COLOR_GOLD, 1.6, true)
	draw_string(_font_cjk, c + Vector2(-20, 14), "王",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 44, COLOR_GOLD)
	draw_string(_font_ascii, Vector2(8, 22), "JOKER",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_GOLD)


func _draw_back() -> void:
	draw_style_box(_back_sb, Rect2(Vector2.ZERO, size))
	var c := size / 2.0
	# 和风云纹: 三道金弧 + 中央菱形
	for i in 3:
		draw_arc(c + Vector2(0, -18 + i * 18), 26.0, PI * 1.15, PI * 1.85, 24,
				COLOR_BACK_PAT, 2.0, true)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -8), c + Vector2(7, 0), c + Vector2(0, 8), c + Vector2(-7, 0),
	]), COLOR_GOLD)
	draw_arc(c, 36.0, 0, TAU, 40, COLOR_BACK_PAT, 1.2, true)
	draw_rect(Rect2(5, 5, size.x - 10, size.y - 10), Color(Wafu.GOLD, 0.25), false, 1.0)
	Wafu.speckle(self, Rect2(Vector2(6, 6), size - Vector2(12, 12)), 14, 900 + card,
			Color(Wafu.GOLD, 0.10))
