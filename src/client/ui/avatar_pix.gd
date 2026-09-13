## 精修像素头像库(32x32 合成器): 每个人物由图元组合(椭圆/矩形/点)在网格上
## 作画, 自动描边通道统一勾边, 按角色调色板渲染, 整数最近邻缩放。
## 工艺规范: 深梅紫描边 / 皮肤受光+阴影+腮红三阶 / 眼睛留白+瞳+高光 /
## 发丝高光 / 每角色专属剪影配件(角·耳·长鼻·高髻·头巾)。
extends RefCounted

const GRID := 32
const ART_IDS := ["skin_default", "skin_aka", "skin_ao", "skin_kitsu",
		"skin_oiran", "skin_tengu"]

## 每角色调色板: o描边 s皮肤 S皮肤暗 b腮红 w眼白 p瞳 m嘴/红 h发 H发高光
## a 配件主色 A 配件暗 c 衣 C 衣暗 l 领/内衬 g 金 r 红
const PALETTES := {
	"skin_default": {"o" = Color("241c30"), "s" = Color("e8dcc8"), "S" = Color("c9b098"),
		"b" = Color("e0a0a0"), "w" = Color("f8f6f0"), "p" = Color("2b2b3d"),
		"m" = Color("b86868"), "h" = Color("2b2b3d"), "H" = Color("4a4a6a"),
		"c" = Color("3a4a6a"), "C" = Color("28324a"), "l" = Color("e8dcc8"),
		"g" = Color("e0a83c"), "r" = Color("c93a3a"), "a" = Color("e0a83c"),
		"A" = Color("b88744")},
	"skin_aka": {"o" = Color("1a1218"), "s" = Color("d9887c"), "S" = Color("b86055"),
		"w" = Color("f8f6f0"), "p" = Color("3a1420"), "m" = Color("7a1a14"),
		"h" = Color("2b1a2a"), "H" = Color("4a2a3a"), "a" = Color("f2e0b8"),
		"A" = Color("c8b088"), "c" = Color("7a2418"), "C" = Color("55170f"),
		"l" = Color("3a1420"), "g" = Color("e0a83c"), "r" = Color("c93a3a"),
		"b" = Color("e89080")},
	"skin_ao": {"o" = Color("101826"), "s" = Color("9db8dc"), "S" = Color("7a96c0"),
		"w" = Color("f8f6f0"), "p" = Color("14203a"), "m" = Color("4060a0"),
		"h" = Color("2a3a54"), "H" = Color("405578"), "a" = Color("d8e2f0"),
		"A" = Color("b0c0d8"), "c" = Color("2c5aa0"), "C" = Color("1e4078"),
		"l" = Color("14203a"), "g" = Color("e0a83c"), "r" = Color("c93a3a"),
		"b" = Color("8aa8cc")},
	"skin_kitsu": {"o" = Color("3a3040"), "s" = Color("f2efe6"), "S" = Color("d8d2c0"),
		"b" = Color("f0b0bc"), "w" = Color("f8f6f0"), "p" = Color("8a5426"),
		"m" = Color("c93a3a"), "h" = Color("e8e4d8"), "H" = Color("f8f6ee"),
		"d" = Color("cfc9b8"), "a" = Color("f0b0bc"), "A" = Color("e09aa8"),
		"c" = Color("d8d2c4"), "C" = Color("b8b2a0"), "l" = Color("c93030"),
		"g" = Color("e0a83c"), "r" = Color("c93030")},
	"skin_oiran": {"o" = Color("141018"), "s" = Color("f2e6d8"), "S" = Color("d8c0ac"),
		"b" = Color("f0a8b0"), "w" = Color("f8f6f0"), "p" = Color("241a28"),
		"m" = Color("c22840"), "h" = Color("241a28"), "H" = Color("3a2e40"),
		"d" = Color("141018"), "a" = Color("e0a83c"), "A" = Color("b88744"),
		"c" = Color("4a1440"), "C" = Color("340e2e"), "l" = Color("e0a83c"),
		"g" = Color("e0a83c"), "r" = Color("c22840")},
	"skin_tengu": {"o" = Color("1a1218"), "s" = Color("d95040"), "S" = Color("b83a30"),
		"w" = Color("f8f6f0"), "p" = Color("241c30"), "m" = Color("7a1a14"),
		"h" = Color("1c1c2a"), "H" = Color("2e2e44"), "a" = Color("1c1c2a"),
		"A" = Color("10101c"), "c" = Color("5a2020"), "C" = Color("3e1414"),
		"l" = Color("2a0a0a"), "g" = Color("e0a83c"), "r" = Color("f2e0b8"),
		"b" = Color("e07a6a")},
}

static var _cache := {}


## 绘制像素头像; 返回 false 表示该 skin 无像素画(调用方回退旧矢量)
static func draw(ci: CanvasItem, skin_id: String, center: Vector2, r: float) -> bool:
	if not ART_IDS.has(skin_id):
		return false
	var g: Dictionary = _grid(skin_id)
	var pal: Dictionary = PALETTES[skin_id]
	var px: float = r * 2.0 * 0.96 / float(GRID)
	var org: Vector2 = center - Vector2(GRID, GRID) * px * 0.5
	for key in g:
		var col: Color = pal.get(g[key], Color.MAGENTA)
		ci.draw_rect(Rect2(org + Vector2(key) * px, Vector2(px + 0.35, px + 0.35)), col)
	return true


## 组合缓存
static func _grid(skin_id: String) -> Dictionary:
	if _cache.has(skin_id):
		return _cache[skin_id]
	var g := {}
	match skin_id:
		"skin_aka":
			_comp_oni(g, true)
		"skin_ao":
			_comp_oni(g, false)
		"skin_kitsu":
			_comp_kitsu(g)
		"skin_oiran":
			_comp_oiran(g)
		"skin_tengu":
			_comp_tengu(g)
		_:
			_comp_momoso(g)
	_outline(g)
	_cache[skin_id] = g
	return g


# ---------------------------------------------------------------- 图元

static func _px(g: Dictionary, x: int, y: int, ch: String) -> void:
	if x >= 0 and x < GRID and y >= 0 and y < GRID:
		g[Vector2i(x, y)] = ch


static func _rect(g: Dictionary, x0: int, y0: int, x1: int, y1: int, ch: String) -> void:
	for y in range(maxi(y0, 0), mini(y1, GRID - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, GRID - 1) + 1):
			g[Vector2i(x, y)] = ch


static func _ell(g: Dictionary, cx: float, cy: float, rx: float, ry: float,
		ch: String) -> void:
	for y in range(maxi(int(cy - ry), 0), mini(int(cy + ry) + 1, GRID - 1) + 1):
		for x in range(maxi(int(cx - rx), 0), mini(int(cx + rx) + 1, GRID - 1) + 1):
			var dx: float = (x + 0.5 - cx) / rx
			var dy: float = (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				g[Vector2i(x, y)] = ch


## 自动描边: 空格且四邻有内容 → 勾边
static func _outline(g: Dictionary) -> void:
	var add: Array = []
	for y in GRID:
		for x in GRID:
			if g.has(Vector2i(x, y)):
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if g.has(Vector2i(x, y) + d):
					add.append(Vector2i(x, y))
					break
	for key in add:
		g[key] = "o"


## 五官(共享): 眼白+瞳+高光 / 眉 / 鼻影 / 嘴 / 腮红
static func _face(g: Dictionary, brow: String, angry := 0) -> void:
	for side: Array in [[12, 18], [17, 19]]:
		var x0: int = side[0]
		var x1: int = side[1]
		_rect(g, x0, 15, x1, 17, "w")
		_rect(g, x0 + 1, 15, x1, 17, "p")
		_px(g, x0 + 1, 15, "w")  # 高光
	# 眉: angry=1 内端下压, -1 外端下压(哀)
	for side: Array in [[12, 14], [17, 19]]:
		for x in range(side[0], side[1] + 1):
			var yy := 13
			if angry > 0 and x == side[1]:
				yy = 14
			elif angry < 0 and x == side[0]:
				yy = 14
			_px(g, x, yy, brow)
	_px(g, 16, 18, "S")   # 鼻影
	_px(g, 15, 20, "m")
	_px(g, 16, 20, "m")
	_rect(g, 10, 18, 11, 19, "b")
	_rect(g, 20, 18, 21, 19, "b")


# ---------------------------------------------------------------- 人物

## 墨客(默认): 黑发覆额 + 顶髻 + 金头带 + 藏青羽织
static func _comp_momoso(g: Dictionary) -> void:
	_ell(g, 16, 14, 7, 7.5, "s")
	_rect(g, 14, 21, 17, 25, "S")            # 颈
	_rect(g, 10, 25, 21, 31, "c")            # 肩
	_rect(g, 8, 28, 23, 31, "c")
	_rect(g, 15, 25, 16, 28, "l")            # 领口 V
	_px(g, 14, 26, "l")
	_px(g, 17, 26, "l")
	# 发: 覆额刘海 + 鬓角 + 顶髻 + 金头带
	_ell(g, 16, 10, 7.6, 5.6, "h")           # 发际压到眼上
	_rect(g, 9, 12, 10, 18, "h")
	_rect(g, 21, 12, 22, 18, "h")
	_px(g, 12, 11, "h")
	_px(g, 19, 11, "h")
	_rect(g, 14, 1, 17, 4, "h")              # 顶髻
	_rect(g, 13, 4, 18, 4, "g")              # 髻带
	_rect(g, 10, 6, 13, 7, "H")              # 发丝高光
	_px(g, 19, 6, "H")
	_px(g, 20, 8, "H")
	_face(g, "h")
	_px(g, 13, 22, "h")                      # 山羊须
	_px(g, 18, 22, "h")
	_rect(g, 9, 28, 22, 29, "C")             # 衣纹


## 赤鬼/青鬼: 角 + 獠牙 + 怒/哀眉
static func _comp_oni(g: Dictionary, is_aka: bool) -> void:
	_ell(g, 16, 14, 7, 7.5, "s")
	_rect(g, 14, 21, 17, 25, "S")
	_rect(g, 10, 25, 21, 31, "c")
	_rect(g, 8, 28, 23, 31, "c")
	_rect(g, 15, 25, 16, 28, "l")
	# 乱发(双角之间, 向两侧炸开)
	_ell(g, 16, 7, 7, 3.8, "h")
	_px(g, 7, 8, "h")
	_px(g, 6, 9, "h")
	_px(g, 24, 8, "h")
	_px(g, 25, 9, "h")
	_px(g, 9, 6, "H")
	_px(g, 22, 6, "H")
	# 双角: 向外上收尖(更外扩)
	for i in 7:
		var x0 := 10 - (i >> 1)
		var y := 7 - i
		_rect(g, x0, y, x0 + 1, y + 1, "a")
		_px(g, x0 + 1, y, "A")
		var xr0 := 20 + (i >> 1)
		_rect(g, xr0, y, xr0 + 1, y + 1, "a")
		_px(g, xr0, y, "A")
	_face(g, "h", 1 if is_aka else -1)
	# 怒目红瞳 / 獠牙 / 嘴
	if is_aka:
		_px(g, 13, 16, "r")
		_px(g, 18, 16, "r")
		_rect(g, 14, 20, 17, 20, "m")        # 咧嘴
		_rect(g, 12, 10, 19, 10, "A")        # 眉间皱纹
		_rect(g, 12, 11, 19, 11, "S")
	else:
		_rect(g, 15, 20, 16, 20, "m")        # 抿嘴
		_px(g, 14, 22, "S")                  # 冷汗
		_px(g, 14, 23, "S")
	_rect(g, 13, 20, 13, 21, "w")            # 獠牙
	_rect(g, 18, 20, 18, 21, "w")
	_rect(g, 9, 28, 22, 29, "C")


## 狐妖: 短宽狐耳(斜向外) + 琥珀瞳 + 红鼻 + 颊须 + 白衣红领
static func _comp_kitsu(g: Dictionary) -> void:
	_ell(g, 16, 14, 7, 7.5, "s")
	_rect(g, 14, 21, 17, 25, "S")
	_rect(g, 10, 25, 21, 31, "c")
	_rect(g, 8, 28, 23, 31, "c")
	_rect(g, 10, 27, 21, 29, "l")            # 红领巾
	# 刘海锯齿(先画发, 耳朵压在发上避免被覆盖)
	_ell(g, 16, 9, 7.4, 4.6, "h")
	_px(g, 11, 12, "h")
	_px(g, 16, 12, "h")
	_px(g, 21, 12, "h")
	_rect(g, 11, 6, 12, 7, "H")
	# 狐耳: 短宽三角, 尖朝上外, 外廓用发色与脸区分
	for y in range(4, 11):
		var w := 2 + (y - 4)
		var xl := 6 - ((y - 4) >> 1)
		_rect(g, xl, y, xl + w, y, "h")
		var xr := 31 - xl - w
		_rect(g, xr, y, xr + w, y, "h")
	# 耳内粉(下层 2/3)
	for y in range(7, 11):
		var w := 2 + (y - 4)
		var xl := 6 - ((y - 4) >> 1)
		_rect(g, xl + 1, y, xl + w - 1, y, "a")
		var xr := 31 - xl - w
		_rect(g, xr + 1, y, xr + w - 1, y, "a")
	_px(g, 6, 5, "H")
	_px(g, 25, 5, "H")
	_px(g, 9, 20, "h")
	_px(g, 8, 19, "h")
	_px(g, 22, 20, "h")
	_px(g, 23, 19, "h")
	_face(g, "d")
	# 狐鼻 + 颊须
	_px(g, 16, 19, "m")
	_px(g, 8, 17, "d")
	_px(g, 7, 18, "d")
	_px(g, 23, 17, "d")
	_px(g, 24, 18, "d")


## 花魁: 圆润高髻 + 侧直发(姬发) + 金簪 + 红唇美人痣 + 盛装
static func _comp_oiran(g: Dictionary) -> void:
	_ell(g, 16, 14, 7, 7.5, "s")
	_rect(g, 14, 21, 17, 25, "S")
	_rect(g, 10, 25, 21, 31, "c")
	_rect(g, 8, 28, 23, 31, "c")
	_rect(g, 9, 26, 22, 27, "g")             # 金领
	# 发: 圆润大髻 + 两侧姬发直垂 + 中分刘海
	_ell(g, 16, 6, 8.6, 5.8, "h")
	_rect(g, 7, 9, 9, 21, "h")               # 左侧发
	_rect(g, 22, 9, 24, 21, "h")             # 右侧发
	_rect(g, 10, 9, 21, 10, "h")             # 刘海带
	_px(g, 12, 11, "h")
	_px(g, 19, 11, "h")
	_rect(g, 13, 2, 18, 3, "H")              # 髻光
	# 金簪(右侧斜出) + 红玉
	_rect(g, 23, 6, 26, 6, "g")
	_px(g, 26, 5, "g")
	_px(g, 27, 4, "r")
	# 细眉 + 红唇 + 美人痣 + 红眼尾
	_face(g, "h")
	_px(g, 12, 14, "r")
	_px(g, 19, 14, "r")
	_rect(g, 15, 20, 16, 21, "m")
	_px(g, 20, 21, "o")                      # 美人痣


## 天狗: 红面具 + 垂长鼻(异色可辨) + 白粗眉须 + 黑羽发 + 皂角帽
static func _comp_tengu(g: Dictionary) -> void:
	_ell(g, 16, 14, 7, 7.5, "s")
	_rect(g, 14, 21, 17, 25, "S")
	_rect(g, 10, 25, 21, 31, "c")
	_rect(g, 8, 28, 23, 31, "c")
	_rect(g, 15, 25, 16, 28, "l")
	# 黑羽发: 上弧 + 两侧羽尖
	_ell(g, 16, 9, 7.4, 4.4, "h")
	for i in 4:
		_rect(g, 7 + i, 7 - (i >> 1), 8 + i, 8 - (i >> 1), "H")
	# 皂角帽(小黑帽)
	_rect(g, 13, 1, 18, 3, "a")
	_rect(g, 12, 3, 19, 4, "a")
	# 长鼻: 从眉心垂过下颌(伸出轮廓 → 自动描边勾出), 侧缘暗部可辨
	_rect(g, 15, 14, 17, 20, "s")
	_rect(g, 15, 20, 16, 25, "s")
	_px(g, 15, 25, "s")
	_rect(g, 17, 14, 17, 20, "S")
	_px(g, 16, 22, "S")
	_px(g, 14, 14, "S")
	# 白粗眉(压鼻根)
	_rect(g, 11, 12, 14, 13, "w")
	_rect(g, 17, 12, 20, 13, "w")
	_px(g, 11, 14, "w")
	_px(g, 20, 14, "w")
	# 眼(眉下小眼)
	_rect(g, 12, 15, 13, 16, "w")
	_rect(g, 13, 15, 13, 16, "p")
	_rect(g, 18, 15, 19, 16, "w")
	_rect(g, 18, 15, 18, 16, "p")
	# 白髭(鼻侧垂下)
	_rect(g, 12, 21, 14, 23, "w")
	_rect(g, 18, 21, 20, 23, "w")
	_rect(g, 9, 28, 22, 29, "C")
