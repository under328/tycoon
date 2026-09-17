## 怪物像素画控件: 按主题组(group 0..2) × 类别(mob/elite/boss) 直绘。
## 每组一套形象: 森林=蘑菇/树妖/巨鹿, 洞穴=蝙蝠/傀儡/魔王, 熔岩=史莱姆/炎卫士/龙王。
## 同族小怪第二名字用 variant 变色(换色不换形)。
extends Control

const AppTheme = preload("res://src/client/theme/app_theme.gd")

var group := 0: set = _setv_group
var kind := "mob": set = _setv_kind
var variant := 0: set = _setv_variant

func _setv_group(v: int) -> void:
	group = clampi(v, 0, 4)
	queue_redraw()


func _setv_kind(v: String) -> void:
	kind = v
	queue_redraw()


func _setv_variant(v: int) -> void:
	variant = v
	queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(120, 120)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if size.x < 8:
		return
	var art: Dictionary = _art(group)
	var grid: Array = art["mob"] if kind == "mob" else (
			art["elite"] if kind == "elite" else art["boss"])
	var pal: Dictionary = (art["pal"]).duplicate()
	if variant == 1:
		# 同族小怪换色: 偏红变体
		for k in pal:
			pal[k] = pal[k].lerp(Color("d84848"), 0.35)
	var cell := minf(size.x, size.y) / 12.0
	var rows := grid.size()
	var cols := (grid[0] as String).length()
	var origin := (size - Vector2(cols, rows) * cell) / 2.0
	for y in rows:
		var row: String = grid[y]
		for x in row.length():
			var ch := row[x]
			if ch == "." or not pal.has(ch):
				continue
			draw_rect(Rect2(origin + Vector2(x, y) * cell,
					Vector2(cell + 0.5, cell + 0.5)), pal[ch])


# ── 翡翠森林: 毒蘑菇 / 古树妖 / 森林巨鹿 ──
const GRID_MUSHROOM := [
	"...PPPPPP...",
	"..PPWPPWPP..",
	".PPPPPPPPPP.",
	"PPWPPPPPPWPP",
	"PPPPWWWWPPPP",
	"PPPPPPPPPPPP",
	".FFFFFFFFFF.",
	".FEFFFFFFEF.",
	".FFFFKKFFFF.",
	"..FFFFFFFF..",
	"..FF....FF..",
	"..FF....FF..",
]

const GRID_TREANT := [
	"..LLLLLL....",
	".LLLLLLLLL..",
	"LLLLLLLLLLL.",
	"LLGLLLLLGLL.",
	".LLLLLLLLL..",
	"..LLLLLLL...",
	"...TTTT.....",
	"..TTTTTT....",
	".TETTTTET...",
	".TTTKKTTTT..",
	"..TTTTTT....",
	"..TT..TT....",
]

const GRID_STAG := [
	".L........L.",
	".LL..LL..LL.",
	"..LL.LL.LL..",
	"...BBBBBB...",
	"..BBBBBBBB..",
	".BREBBBBERB.",
	".BBBBBBBBBB.",
	"..BBWWWWBB..",
	"..BBBBBBBB..",
	".BBBBBBBBBB.",
	".BB.BBBB.BB.",
	".B...BB...B.",
]

# ── 回声洞穴: 洞穴蝙蝠 / 岩石傀儡 / 深渊魔王 ──
const GRID_BAT := [
	".W........W.",
	"WW........WW",
	"WWW..WW..WWW",
	".WWWWWWWWWW.",
	".WWREWWERWW.",
	".WWWWWWWWWW.",
	"..WWWKKWWW..",
	"...WWWWWW...",
	"....WWWW....",
	"....W..W....",
	"............",
	"............",
]

const GRID_GOLEM := [
	".SSSSSSSSSS.",
	"SSSSSSSSSSSS",
	"SSESSSSSESS.",
	"SSSSSSSSSSSS",
	"SS.SSSSSS.SS",
	"...SSSSSS...",
	"..SSSSSSSS..",
	".SSSSSSSSSS.",
	".SSDSSSSDSS.",
	".SSSSSSSSSS.",
	"..SSS..SSS..",
	"..SSS..SSS..",
]

const GRID_DEMON := [
	"..H......H..",
	"..HH....HH..",
	"...HHHHHH...",
	"..HHHHHHHH..",
	".HREHHHERHH.",
	".HHHHHHHHHH.",
	".HHHKKKKHHH.",
	"..HHHHHHHH..",
	".HHHHHHHHHH.",
	"HHHHHHHHHHHH",
	".HH.HH.HH.H.",
	".H........H.",
]

# ── 熔火之心: 熔岩史莱姆 / 炎魔卫士 / 熔岩龙王 ──
const GRID_SLIME := [
	"............",
	"............",
	"...OOOOOO...",
	"..OOOOOOOO..",
	".OOEOOOOEOO.",
	".OOOOOOOOOO.",
	"OOYOOOOOYOOO",
	"OOOOOOOOOOOO",
	"OOOOOOOOOOOO",
	".OOOOOOOOOO.",
	"..OOOOOOOO..",
	"............",
]

const GRID_FLAME := [
	"..F......F..",
	".FFF....FFF.",
	".FFFFFFFFFF.",
	"..FFFFFFFF..",
	".FFEFFFEFFF.",
	".FFFFFFFFFF.",
	"..FFKKKKFF..",
	".FFFFFFFFFF.",
	".FFFFFFFFFF.",
	"..FFFFFFFF..",
	"..FF....FF..",
	"..FF....FF..",
]

const GRID_DRAGON := [
	"..Y......Y..",
	"..YY.YY.YY..",
	"...OOOOOO...",
	"..OOEOOEOO..",
	".OOOOOOOOOO.",
	"OKKOOOOOOKKO",
	".OOOOOOOOOO.",
	"..OOOOOOOO..",
	"...OOOOOO...",
	".OOOOOOOOOO.",
	"OO.OO..OO.OO",
	"O...OO..O..O",
]


# ── 冰封雪原: 雪原狼 / 冰晶卫士 / 极寒霜龙 ──
const GRID_WOLF := [
	"............",
	".WW......WW.",
	".WWW....WWW.",
	"..WWWWWWWW..",
	".WWEWWWWWWW.",
	".WWWWWWWWWW.",
	"..WWKKWWWW..",
	"..WWWWWWWW..",
	"...WWWWWW...",
	"..WW.WW.WW..",
	"..W...W..W..",
	"............",
]

const GRID_ICEGUARD := [
	"...CCCCCC...",
	"..CCWCCWCC..",
	".CCCCCCCCCC.",
	".CCECCCCECC.",
	"..CCCCCCCC..",
	"...CCCCCC...",
	".CCCCCCCCCC.",
	".CCWCCCCWCC.",
	".CCCCCCCCCC.",
	"..CCCCCCCC..",
	"..CC....CC..",
	"..CC....CC..",
]

const GRID_FROSTDRAGON := [
	"..I......I..",
	"..II.II.II..",
	"...IIIIII...",
	"..IIEIIEII..",
	".IIIIIIIIII.",
	"IKKIIIIIIKII",
	".IIIIIIIIII.",
	"..IIIIIIII..",
	"...IIIIII...",
	".IIIIIIIIII.",
	"II.II..II.II",
	"I...II..I..I",
]

# ── 幽暗墓地: 骷髅兵 / 死灵法师 / 亡灵君王 ──
const GRID_SKELETON := [
	"...BBBBBB...",
	"..BBKBBKBB..",
	"..BBBBBBBB..",
	"...BBBBBB...",
	"....BBBB....",
	"..BBBBBBBB..",
	".BEBBBBKBBB.",
	".BBBBBBBBBB.",
	"..BBBBBBBB..",
	"..BB.BB.BB..",
	"..B..B..B...",
	"............",
]

const GRID_NECRO := [
	"...PPPPPP...",
	"..PPKKKKPP..",
	".PPPPPPPPPP.",
	".PPEPPPPEPP.",
	"..PPPPPPPP..",
	".PPPPPPPPPP.",
	".PPPPPPPPPP.",
	"PPPPPPPPPPPP",
	".PPPPPPPPPP.",
	"..PPPPPPPP..",
	"...PP..PP...",
	"............",
]

const GRID_LICH := [
	"..Y..YY..Y..",
	"..YYYYYYYY..",
	"...PPPPPP...",
	"..PPKPPKPP..",
	".PPPPPPPPPP.",
	".PPPPPPPPPP.",
	"..PPPPPPPP..",
	".PPPPPPPPPP.",
	"PPPPPPPPPPPP",
	".PP.PPPP.PP.",
	"..PP....PP..",
	"............",
]


func _art(g: int) -> Dictionary:
	match g:
		0:
			return {"mob": GRID_MUSHROOM, "elite": GRID_TREANT,
					"boss": GRID_STAG, "pal": {
						"P": Color("7a4a9a"), "W": Color("e8e0f0"),
						"F": Color("f0e8c8"), "E": Color("2a1a2a"),
						"K": Color("8a4a5a"), "L": Color("6ac86a"),
						"G": Color("3a8a4a"), "T": Color("8a6239"),
						"B": Color("9a7248"), "R": Color("d04040"),
					}}
		1:
			return {"mob": GRID_BAT, "elite": GRID_GOLEM,
					"boss": GRID_DEMON, "pal": {
						"W": Color("8a8ab8"), "R": Color("ff5050"),
						"E": Color("ffd040"), "K": Color("f0f0f0"),
						"S": Color("9a9aa8"), "D": Color("4a4a58"),
						"H": Color("4a2a6a"),
					}}
		3:
			return {"mob": GRID_WOLF, "elite": GRID_ICEGUARD,
					"boss": GRID_FROSTDRAGON, "pal": {
						"W": Color("dce8f5"), "E": Color("1a2a3a"),
						"K": Color("3a4a5a"), "C": Color("9fd8e8"),
						"I": Color("b8e0f0"),
					}}
		4:
			return {"mob": GRID_SKELETON, "elite": GRID_NECRO,
					"boss": GRID_LICH, "pal": {
						"B": Color("d8d4c0"), "E": Color("70e0e8"),
						"K": Color("2a1a1a"), "P": Color("5a3a8a"),
						"Y": Color("e8d040"),
					}}
		_:
			return {"mob": GRID_SLIME, "elite": GRID_FLAME,
					"boss": GRID_DRAGON, "pal": {
						"O": Color("ff7830"), "Y": Color("ffd040"),
						"E": Color("3a1a0a"), "K": Color("3a1408"),
						"F": Color("e04828"),
					}}
