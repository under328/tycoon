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
		_redraw_card()
var selected := false:
	set(v):
		selected = v
		_redraw_card()
var face_down := false:
	set(v):
		face_down = v
		# 遮罩仅牌背需要(纹样刻意出血; 牌面内容不越界) — 离屏合成逐卡
		# 开启在手机上代价高, 牌面态关闭
		clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW if v 				else CanvasItem.CLIP_CHILDREN_DISABLED
		_redraw_card()
## 显式指定卡面皮肤 id(商城预览用); 空 = 跟随已装备
var palette_id := "":
	set(v):
		palette_id = v
		_refresh_palette()
		_redraw_card()

## 牌背纹样绘制层: 纹样网格刻意越界(曲线出血到边缘), 由裁剪容器收进牌面
var _back_clip: Control = null
var _back_paint: Control = null

var _pal: Dictionary = {}
var _sb: Dictionary = {}          # 共享样式盒包(按 palette_id 缓存, 见 _styleboxes)
var _sel_sb := StyleBoxFlat.new()
var _font_ascii: Font = AppTheme.display_font() if false else null
var _font_cjk: Font = null

## 共享样式盒: 同一卡面调色板只配置一次(重建卡牌不再逐个 new StyleBoxFlat)
static var _sb_cache := {}


static func _styleboxes(pal_id: String, pal: Dictionary) -> Dictionary:
	if _sb_cache.has(pal_id):
		return _sb_cache[pal_id]
	var face := StyleBoxFlat.new()
	face.bg_color = pal["face"]
	face.set_corner_radius_all(7)
	face.set_border_width_all(2)
	face.border_color = pal["border"]
	var inner := StyleBoxFlat.new()
	inner.bg_color = Color(0, 0, 0, 0)
	inner.set_corner_radius_all(5)
	inner.set_border_width_all(1)
	inner.border_color = Color(COLOR_BORDER, 0.6)
	var joker := StyleBoxFlat.new()
	joker.bg_color = Color(0, 0, 0, 0)
	joker.set_corner_radius_all(7)
	joker.set_border_width_all(2)
	joker.border_color = COLOR_BORDER
	var back := StyleBoxFlat.new()
	back.bg_color = pal["back"]
	back.set_corner_radius_all(7)
	back.set_border_width_all(2)
	back.border_color = COLOR_BORDER
	var pack := {"face": face, "inner": inner, "joker": joker, "back": back}
	_sb_cache[pal_id] = pack
	return pack


func _init(p_card: int = -1) -> void:
	card = p_card
	custom_minimum_size = Vector2(72, 100)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 牌背纹样遮罩仅牌背需要(纹样刻意出血; 牌面内容不越界)。
	# 遮罩 = 离屏合成, 逐卡开启在手机上代价高 → face_down 切换时启停。
	# 注意: clip_contents 的裁剪区不随控件旋转, 必须用 clip_children。

	# 纹样层容器: 相对牌面板内缩一圈边框, 内含绘制子层
	_back_clip = Control.new()
	_back_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back_clip)
	_back_paint = BackPaint.new()
	_back_paint.card = self
	_back_paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_clip.add_child(_back_paint)

	_sel_sb.bg_color = Color(1, 1, 1, 0.10)
	_sel_sb.set_corner_radius_all(7)
	_sel_sb.set_border_width_all(4)
	_sel_sb.border_color = Color("ffd75e")

	_font_ascii = AppTheme.display_font()
	_font_cjk = AppTheme.title_font()
	_refresh_palette()


func _ready() -> void:
	# 裁剪容器随牌面尺寸走(边框内缩), 纹样绘制层在其中被裁剪
	resized.connect(_layout_back_paint)
	_layout_back_paint()
	_refresh_palette()  # 入树后解析 Wallet 装备卡面(_init 阶段尚不可达)


func _layout_back_paint() -> void:
	if _back_clip == null:
		return
	var m := 2.0 * (size.y / 100.0)  # 边框宽: 纹样裁剪区向内收一圈
	_back_clip.position = Vector2(m, m)
	var sz := size - Vector2(m, m) * 2.0
	_back_clip.size = Vector2(maxf(sz.x, 0.0), maxf(sz.y, 0.0))


## 重绘卡牌本体 + 牌背纹样层
func _redraw_card() -> void:
	queue_redraw()
	if _back_paint != null:
		_back_paint.queue_redraw()


## 牌背纹样层(子节点): 绘制命令落在子层, 由 _back_clip 裁剪到牌面内
class BackPaint extends Control:
	var card = null  # CardView(脚本无全局类名, 用鸭子类型引用宿主)

	func _draw() -> void:
		if card != null and card.face_down:
			card._draw_back_pattern(self)


## 当前装备卡面皮肤的调色板(跟随商城更换)
func _refresh_palette() -> void:
	var w: Node = null
	if is_inside_tree():
		w = get_node_or_null("/root/Wallet")
	var cid := "card_washi"
	if palette_id != "":
		cid = palette_id
	elif w != null:
		cid = str(w.equipped_card)
	_pal = SkinsLib.palette(cid)
	_sb = _styleboxes(cid, _pal)


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
		# 顶部金色指示三角(选中标记)
		var tw := size.x * 0.20
		var tri := PackedVector2Array([
			Vector2(size.x / 2.0 - tw / 2, 0),
			Vector2(size.x / 2.0 + tw / 2, 0),
			Vector2(size.x / 2.0, tw * 0.55),
		])
		draw_colored_polygon(tri, COLOR_GOLD)


func _draw_face() -> void:
	draw_style_box(_sb["face"], Rect2(Vector2.ZERO, size))
	if card < 0 or card > 53:
		return
	# 全部元素按牌面高度等比缩放(标准 100 高 → s=1.0)
	var s := size.y / 100.0
	# 内框细线(双框)
	draw_style_box(_sb["inner"], Rect2(Vector2(4, 4) * s, size - Vector2(8, 8) * s))
	# 和纸纵向微渐变(顶部微亮)
	for gi in 4:
		draw_rect(Rect2(0, size.y * gi / 4.0, size.x, size.y / 4.0 + 1.0),
				Color(1, 1, 1, 0.030 * (4 - gi)))
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
	# 左上: 斜切点数牌匾(底色=花色) + 白字, P5 语言
	var pw: float = 21 * s
	var ph: float = 23 * s
	var px: float = 5 * s
	var py: float = 3 * s
	var skew: float = 4 * s
	var fsize := int(16.0 * s)
	if rank.length() > 1:
		fsize = int(13.5 * s)  # 双字符点数(10): 略缩字号
	# 牌匾宽度随点数文字实测宽度伸展 — 防"10"溢出牌匾
	# (白字落在米白牌面上不可见, 看起来只剩"1")
	var rank_fw: float = _font_ascii.get_string_size(
			rank, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	pw = maxf(pw, skew + rank_fw + 7.0 * s)
	var pl_pts := PackedVector2Array([
		Vector2(px + skew, py), Vector2(px + pw, py),
		Vector2(px + pw - skew, py + ph), Vector2(px, py + ph),
	])
	draw_colored_polygon(pl_pts, ink)
	var pl_line := pl_pts.duplicate()
	pl_line.append(pl_pts[0])
	draw_polyline(pl_line, Color(_pal["face"], 0.35), 1.0 * s, true)
	draw_string(_font_ascii, Vector2(px + skew + 3 * s, py + ph - 6.0 * s), rank,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, _pal["face"])
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
	draw_style_box(_sb["joker"], Rect2(Vector2.ZERO, size))
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
		"wukong":
			_pixel_art(PIX_WUKONG, _pix_pal_wukong(), c, size)
		"cyber":
			_pixel_art(PIX_CYBER, _pix_pal_cyber(), c, size)
		"dball":
			_pixel_art(PIX_DBALL, _pix_pal_dball(), c, size)
		"ninja":
			_pixel_art(PIX_NINJA, _pix_pal_ninja(), c, size)
		"rx":
			_pixel_art(PIX_RX, _pix_pal_rx(), c, size)
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


func _pix_pal_wukong() -> Dictionary:
	return {"G": Color("f2c14e"), "F": Color("4a3423"), "T": Color("d9a878"),
		"W": Color("f8f6f0"), "E": Color("ffe98a"), "B": Color("181018"),
		"M": Color("7a1a14"), "R": Color("c8742a"), "Y": Color("e8d8b0")}


func _pix_pal_cyber() -> Dictionary:
	return {"D": Color("23262e"), "V": Color("fcee0a"), "E": Color("ffffff"),
		"C": Color("30e0df"), "B": Color("0d0f16"), "M": Color("ff2e88")}


func _pix_pal_dball() -> Dictionary:
	return {"O": Color("f5a623"), "Y": Color("ffe9a0"), "R": Color("d43a2a")}


func _pix_pal_ninja() -> Dictionary:
	return {"D": Color("30303c"), "S": Color("b8c0c8"), "E": Color("6a7280")}


func _pix_pal_rx() -> Dictionary:
	return {"B": Color("1a1a24"), "G": Color("3ddc6c"), "R": Color("ff4040"),
		"S": Color("b8c0c8"), "T": Color("8a94a4"), "W": Color("d8fce4")}


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

## 悟空: 金箍 + 猴脸金瞳 + 虎皮纹(裙)
const PIX_WUKONG := [
	"...GGGGGG...",
	".GGGGGGGGGG.",
	".FFFFFFFFFF.",
	"FFFTTTTTTFFF",
	"FFTTTTTTTTFF",
	"FTWWETTEWWTF",
	"FTTTTTTTTTTF",
	"FTTBTTTBTTTF",
	"FTTTTTTTTTTF",
	".FTTMMMMTTF.",
	"..FTTTTTTF..",
	".RRYRRRRYRR.",
]

## 赛博义体: 金属头壳 + 额电路 + 霓虹目镜 + 散热栅
const PIX_CYBER := [
	"..DDDDDDDD..",
	".DDDDDDDDDD.",
	".DCDCCCCDCD.",
	"DDDDDDDDDDDD",
	"DVVVVVVVVVVD",
	"DVEVVEVVEVVD",
	"DDDDDDDDDDDD",
	".DDBDBDBBDD.",
	"..DDDDDDDD..",
	".CDDDDDDDDC.",
	"..DDMMDDDD..",
	"............",
]

## 四星球: 橙色晶球 + 2x2 排布的四枚红星 + 左上高光
const PIX_DBALL := [
	"....OOOO....",
	"..OOYYOOOO..",
	".OOYOOOOOOO.",
	".OOROOOOROO.",
	".ORRROORRRO.",
	".OOROOOOROO.",
	".OOOOOOOOOO.",
	".OOROOOOROO.",
	".ORRROORRRO.",
	".OOROOOOROO.",
	"..OOOOOOOO..",
	"....OOOO....",
]

## 风魔手里剑: 四刃回旋镖 + 中心铆钉
const PIX_NINJA := [
	"DD........DD",
	"DDD......DDD",
	".DDD.DD.DDD.",
	"..DDDDDDDD..",
	"....DDDD....",
	".DDDEDDEDDD.",
	".DDDEDDEDDD.",
	"....DDDD....",
	"..DDDDDDDD..",
	".DDD.DD.DDD.",
	"DDD......DDD",
	"DD........DD",
]

## RX骑士头盔: 银缘黑盔 + 额心红晶 + 双绿复眼 + 银口栅(银缘勾轮廓, 防融进深色卡底)
const PIX_RX := [
	"....TTTT....",
	"..TTBBBBTT..",
	".TTBBBBBBTT.",
	".TBBBBRBBBT.",
	".TBBBRRRBBT.",
	".TBBBBRBBBT.",
	"TBGGGBBGGGBT",
	"TBGWGBBWGBGT",
	".TBBSSSSBBT.",
	"..TTBBBBTT..",
	"............",
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
		"wukong":  # 金箍环: 双环 + 四如意云头
			draw_arc(c, r, 0, TAU, 40, col, 2.4, true)
			draw_arc(c, r * 0.62, 0, TAU, 32, Color(col, col.a * 0.7), 1.6, true)
			for i in 4:
				var ang := TAU * i / 4.0 + PI * 0.25
				draw_circle(c + Vector2.from_angle(ang) * r * 0.82, r * 0.14, col)
		"cyber":  # 全息六边 + 数据断流
			var hex := PackedVector2Array()
			for i in 6:
				var ang := TAU * i / 6.0 + PI * 0.5
				hex.append(c + Vector2.from_angle(ang) * r)
			hex.append(hex[0])
			draw_polyline(hex, col, 2.2, true)
			draw_line(c + Vector2(-r * 0.5, -r * 0.15), c + Vector2(-r * 0.1, -r * 0.15),
					Color(_pal["red"], col.a), 1.8, true)
			draw_line(c + Vector2(r * 0.1, r * 0.15), c + Vector2(r * 0.5, r * 0.15),
					Color(_pal["red"], col.a), 1.8, true)
			draw_circle(c, r * 0.16, col)
		"dball":  # 珠环 + 内嵌四星(红)
			draw_arc(c, r, 0, TAU, 36, col, 2.4, true)
			draw_arc(c, r * 0.85, 0, TAU, 32, Color(col, col.a * 0.5), 1.2, true)
			for p: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var sp := c + p * r * 0.42
				draw_line(sp + Vector2(-r * 0.12, 0), sp + Vector2(r * 0.12, 0),
						Color(_pal["red"], col.a), 1.6, true)
				draw_line(sp + Vector2(0, -r * 0.12), sp + Vector2(0, r * 0.12),
						Color(_pal["red"], col.a), 1.6, true)
		"ninja":  # 查克拉螺旋(内起外放)
			var pts := PackedVector2Array()
			for i in 46:
				var t := float(i) / 45.0
				pts.append(c + Vector2.from_angle(t * TAU * 1.75) * (r * (0.15 + 0.85 * t)))
			draw_polyline(pts, col, 2.0, true)
		"rx":  # 复眼环: 双眼弧 + 额心红晶
			draw_arc(c + Vector2(-r * 0.45, 0), r * 0.52, PI * 0.5, PI * 1.5, 18,
					col, 2.2, true)
			draw_arc(c + Vector2(r * 0.45, 0), r * 0.52, -PI * 0.5, PI * 0.5, 18,
					col, 2.2, true)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 0.3), c + Vector2(r * 0.18, 0),
				c + Vector2(0, r * 0.3), c + Vector2(-r * 0.18, 0),
			]), Color(_pal["red"], col.a))
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
			draw_polyline(pts, col, s * 0.16, true)  # 单次提交(原 24 条线)
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
		"wukong":
			# 金箍棒斜置(两端箍) + 脚下祥云
			var a := c + Vector2(-s * 0.75, s * 0.8)
			var b := c + Vector2(s * 0.75, -s * 0.8)
			draw_line(a, b, col, s * 0.16, true)
			var dir := (b - a).normalized()
			for p: Vector2 in [a, b]:
				draw_line(p - dir * s * 0.12, p + dir * s * 0.12,
						Color(_pal["face"], 0.7), s * 0.3, true)
			draw_arc(c + Vector2(-s * 0.55, s * 0.65), s * 0.3,
					PI * 1.1, PI * 1.9, 12, col, s * 0.07, true)
			draw_arc(c + Vector2(s * 0.35, s * 0.72), s * 0.26,
					PI * 1.15, PI * 1.85, 12, col, s * 0.07, true)
		"cyber":
			# 义眼: 六边框 + 扫描横线 + 品红故障残影
			var hex := PackedVector2Array()
			for i in 6:
				var ang := TAU * i / 6.0 + PI * 0.5
				hex.append(c + Vector2.from_angle(ang) * s * 0.85)
			hex.append(hex[0])
			draw_polyline(hex, Color(_pal["red"], col.a * 0.5), s * 0.07, true)
			draw_polyline(hex, col, s * 0.05, true)
			draw_line(c + Vector2(-s * 0.55, -s * 0.1), c + Vector2(s * 0.55, -s * 0.1),
					col, s * 0.08, true)
			draw_line(c + Vector2(-s * 0.35, s * 0.12), c + Vector2(s * 0.3, s * 0.12),
					Color(_pal["face"], 0.7), s * 0.06, true)
			draw_circle(c, s * 0.14, col)
		"dball":
			# 龙珠纹章: 大晶珠 + 内嵌四星(红) + 左上高光弧
			draw_circle(c, s * 0.95, col)
			draw_arc(c, s * 0.72, PI * 1.05, PI * 1.6, 14, light, s * 0.08, true)
			for p: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var sp := c + p * s * 0.4
				draw_line(sp + Vector2(-s * 0.14, 0), sp + Vector2(s * 0.14, 0),
						Color(_pal["red"], col.a), s * 0.09, true)
				draw_line(sp + Vector2(0, -s * 0.14), sp + Vector2(0, s * 0.14),
						Color(_pal["red"], col.a), s * 0.09, true)
		"ninja":
			# 苦无: 斜置菱刃 + 直柄 + 环首
			var dir := Vector2(0.707, 0.707)
			var tip2 := c + dir * s * 1.0
			var root := c - dir * s * 0.15
			var wid := Vector2(0.707, -0.707) * s * 0.17
			draw_colored_polygon(PackedVector2Array([
				tip2, root + wid, c - dir * s * 0.35 - wid, root - wid,
			]), col)
			draw_line(root, c - dir * s * 0.8, col, s * 0.13, true)
			draw_arc(c - dir * s * 1.0, s * 0.16, 0, TAU, 12, col, s * 0.07, true)
		"rx":
			# 骑士头盔: 盔体剪影 + 双复眼(亮) + 额心红晶
			var helm := PackedVector2Array([
				c + Vector2(-s * 0.7, -s * 0.2), c + Vector2(-s * 0.45, -s * 0.85),
				c + Vector2(s * 0.45, -s * 0.85), c + Vector2(s * 0.7, -s * 0.2),
				c + Vector2(s * 0.5, s * 0.55), c + Vector2(0, s * 0.9),
				c + Vector2(-s * 0.5, s * 0.55),
			])
			draw_colored_polygon(helm, col)
			draw_circle(c + Vector2(-s * 0.3, 0), s * 0.2, light)
			draw_circle(c + Vector2(s * 0.3, 0), s * 0.2, light)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -s * 0.62), c + Vector2(s * 0.12, -s * 0.45),
				c + Vector2(0, -s * 0.3), c + Vector2(-s * 0.12, -s * 0.45),
			]), Color(_pal["red"], col.a))
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
	draw_style_box(_sb["back"], Rect2(Vector2.ZERO, size))


## 牌背纹样(绘制在 _back_paint 子层, 坐标可越界, 由 _back_clip 裁进牌面)
func _draw_back_pattern(host: CanvasItem) -> void:
	var motif := str(_pal.get("motif", "washi"))
	var border_c: Color = _pal["border"]
	match motif:
		"sumi":
			host.draw_circle(Vector2(size.x * 0.72, size.y * 0.26), size.y * 0.16,
					Color(_pal["face"], 0.30))
			var m1 := PackedVector2Array([
				Vector2(0, size.y * 0.72), Vector2(size.x * 0.22, size.y * 0.46),
				Vector2(size.x * 0.46, size.y * 0.70), Vector2(size.x * 0.66, size.y * 0.52),
				Vector2(size.x, size.y * 0.74), Vector2(size.x, size.y), Vector2(0, size.y),
			])
			host.draw_colored_polygon(m1, Color(border_c, 0.28))
			var m2 := PackedVector2Array([
				Vector2(0, size.y * 0.88), Vector2(size.x * 0.3, size.y * 0.68),
				Vector2(size.x * 0.62, size.y * 0.9), Vector2(size.x * 0.85, size.y * 0.74),
				Vector2(size.x, size.y * 0.86), Vector2(size.x, size.y), Vector2(0, size.y),
			])
			host.draw_colored_polygon(m2, Color(border_c, 0.5))
			host.draw_rect(Rect2(0, size.y * 0.58, size.x, size.y * 0.05),
					Color(_pal["face"], 0.10))
			host.draw_rect(Rect2(0, size.y * 0.78, size.x, size.y * 0.04),
					Color(_pal["face"], 0.08))
		"hi":
			var cell := size.x / 7.0
			var accent := Color(_pal["red"], 0.75)
			var dark := Color(0, 0, 0, 0.4)
			for i in 7:
				for row in 2:
					var top_col := accent if (i + row) % 2 == 0 else dark
					host.draw_rect(Rect2(i * cell, row * cell, cell, cell), top_col)
					var yb := size.y - (row + 1) * cell
					host.draw_rect(Rect2(i * cell, yb, cell, cell),
							accent if (i + row) % 2 == 0 else dark)
				for col_i in 2:
					var side_col := accent if (i + col_i) % 2 == 0 else dark
					host.draw_rect(Rect2(col_i * cell, i * cell, cell, cell), side_col)
					var xr := size.x - (col_i + 1) * cell
					host.draw_rect(Rect2(xr, i * cell, cell, cell), side_col)
			var c := size / 2.0
			var flame := PackedVector2Array()
			for i in 14:
				var ang := TAU * i / 14.0 - PI * 0.5
				var rr := size.y * (0.20 if i % 2 == 0 else 0.13)
				flame.append(c + Vector2.from_angle(ang) * rr)
			host.draw_colored_polygon(flame, Color(_pal["red"], 0.75))
			host.draw_circle(c, size.y * 0.07, Color(Wafu.GOLD, 0.85))
		"umi":
			host.draw_circle(Vector2(size.x * 0.5, size.y * 0.30), size.y * 0.15,
					Color(_pal["red"], 0.65))
			for li in 4:
				var y := size.y * (0.48 + 0.13 * li)
				var col_a := 0.25 + 0.13 * li
				var rr := size.x * 0.22
				var xx := -rr
				while xx < size.x + rr:
					host.draw_arc(Vector2(xx, y), rr, PI, TAU, 12,
							Color(border_c, col_a), size.x * 0.03, true)
					xx += rr * 1.5
		"wukong":
			# 山文甲: 交错金鳞(半圆盘叠压) + 中央云纹圆
			var rr := size.x * 0.18
			var row_h := rr * 0.78
			var rowi := 0
			var yy := -rr * 0.3
			while yy < size.y + rr:
				var offset := 0.0 if rowi % 2 == 0 else rr
				var xx := -rr + offset
				while xx < size.x + rr:
					var scale := PackedVector2Array([
						Vector2(xx - rr, yy + rr * 0.9),
						Vector2(xx, yy - rr * 0.35),
						Vector2(xx + rr, yy + rr * 0.9),
					])
					host.draw_colored_polygon(scale, Color(border_c, 0.10))
					host.draw_arc(Vector2(xx, yy), rr * 0.82, PI * 1.05, PI * 1.95, 12,
							Color(border_c, 0.30), size.x * 0.025, true)
					xx += rr * 1.9
				yy += row_h
				rowi += 1
			var cw := size / 2.0
			host.draw_arc(cw, size.y * 0.16, 0, TAU, 28, Color(border_c, 0.5),
					size.x * 0.03, true)
			host.draw_circle(cw, size.y * 0.05, Color(_pal["red"], 0.6))
		"cyber":
			# 电路走线: 横线 + 直角折线 + 节点 + 扫描/故障条
			var line_c := Color(_pal["black"], 0.30)   # 霓虹主色
			var acc_c := Color(_pal["red"], 0.55)
			for li in 5:
				var y := size.y * (0.14 + 0.18 * li)
				host.draw_line(Vector2(0, y), Vector2(size.x, y),
						Color(line_c, 0.16), size.x * 0.015, true)
				var x0 := size.x * (0.12 + 0.2 * ((li * 3) % 4))
				var x1 := size.x * (0.45 + 0.12 * ((li * 7) % 3))
				var ym := y - size.y * 0.07 if li % 2 == 0 else y + size.y * 0.07
				host.draw_line(Vector2(x0, y), Vector2(x0, ym), line_c,
						size.x * 0.02, true)
				host.draw_line(Vector2(x0, ym), Vector2(x1, ym), line_c,
						size.x * 0.02, true)
				host.draw_circle(Vector2(x1, ym), size.x * 0.028, line_c)
				host.draw_circle(Vector2(x0, y), size.x * 0.035,
						acc_c if li % 3 == 0 else line_c)
			host.draw_rect(Rect2(0, size.y * 0.52, size.x, size.y * 0.02),
					Color(_pal["red"], 0.35))
			host.draw_rect(Rect2(size.x * 0.62, size.y * 0.66, size.x * 0.38,
					size.y * 0.014), Color(_pal["black"], 0.4))
		"dball":
			# 龙珠牌背: 环形气浪 + 中央四星球
			for i in 4:
				var yy := size.y * (0.14 + 0.22 * i)
				var cc := Vector2(size.x * (0.5 if i % 2 == 0 else 0.06), yy)
				host.draw_arc(cc, size.y * 0.15, 0, TAU, 20,
						Color(border_c, 0.16 + 0.06 * i), size.x * 0.02, true)
			var cb := size / 2.0
			host.draw_circle(cb, size.y * 0.17, Color(_pal["face"], 0.7))
			for p: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var sp: Vector2 = cb + p * size.y * 0.075
				host.draw_line(sp + Vector2(-size.y * 0.026, 0),
						sp + Vector2(size.y * 0.026, 0),
						Color(_pal["red"], 0.9), size.y * 0.016, true)
				host.draw_line(sp + Vector2(0, -size.y * 0.026),
						sp + Vector2(0, size.y * 0.026),
						Color(_pal["red"], 0.9), size.y * 0.016, true)
		"ninja":
			# 火影牌背: 木叶漩涡 + 四向刃角
			var cn := size / 2.0
			var pts := PackedVector2Array()
			for i in 40:
				var t := float(i) / 39.0
				pts.append(cn + Vector2.from_angle(t * TAU * 1.6 + PI * 0.4)
						* (size.y * (0.03 + 0.14 * t)))
			host.draw_polyline(pts, Color(border_c, 0.55), size.x * 0.028, true)
			for q in 4:
				var ang := TAU * q / 4.0 + PI / 4.0
				var tip2 := cn + Vector2.from_angle(ang) * size.y * 0.31
				var b1 := cn + Vector2.from_angle(ang + 0.55) * size.y * 0.20
				var b2 := cn + Vector2.from_angle(ang - 0.55) * size.y * 0.20
				host.draw_colored_polygon(PackedVector2Array([tip2, b1, b2]),
						Color(border_c, 0.35))
			host.draw_circle(cn, size.y * 0.035, Color(_pal["red"], 0.8))
		"rx":
			# RX牌背: 蝉翼斜线速纹 + 腰带红灯(三层同心)
			for i in 6:
				var xx := size.x * (0.08 + 0.16 * i)
				host.draw_line(Vector2(xx, 0), Vector2(xx + size.x * 0.07, size.y),
						Color(border_c, 0.13), size.x * 0.022, true)
			var cr := size / 2.0
			host.draw_circle(cr, size.y * 0.14, Color(border_c, 0.28))
			host.draw_circle(cr, size.y * 0.085, Color(_pal["red"], 0.85))
			host.draw_circle(cr, size.y * 0.032, Color(_pal["black"], 0.9))
		_:
			# 小牌(对手牌背扇 40px): 单环大格纹样, 绘制量 -70%
			var small := size.x < 60.0
			var rr := size.x * (0.44 if small else 0.30)
			var row_h := rr * 0.9
			var rowi := 0
			var yy := -rr * 0.4
			while yy < size.y + rr:
				var offset := 0.0 if rowi % 2 == 0 else rr
				var xx := -rr * 1.5 + offset
				while xx < size.x + rr * 1.5:
					if small:
						host.draw_arc(Vector2(xx, yy), rr * 0.9, 0, PI, 10,
								Color(border_c, 0.30), size.x * 0.03, true)
					else:
						for ring in 3:
							host.draw_arc(Vector2(xx, yy), rr * (0.9 - ring * 0.28),
									0, PI, 16, Color(border_c, 0.32 - ring * 0.08),
									size.x * 0.025, true)
					xx += rr * 2
				yy += row_h
				rowi += 1
			var cm := size / 2.0
			host.draw_circle(cm, size.y * 0.17, Color(_pal["back"], 0.9))
			for i in 5:
				var ang := TAU * i / 5.0 - PI * 0.5
				host.draw_circle(cm + Vector2.from_angle(ang) * size.y * 0.11,
						size.y * 0.07, Color(_pal["face"], 0.8))
			host.draw_circle(cm, size.y * 0.045, Color(Wafu.GOLD, 0.9))
	var s2 := size.y / 100.0
	host.draw_rect(Rect2(Vector2(5, 5) * s2, size - Vector2(10, 10) * s2),
			Color(_pal["border"], 0.4), false, 1.5 * s2)
	Wafu.corner_ticks(host, Rect2(Vector2(2, 2) * s2, size - Vector2(4, 4) * s2),
			6.0 * s2, Color(Wafu.GOLD, 0.55))
