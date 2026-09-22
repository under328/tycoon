## 精修像素头像库(32x32 合成器): 每个人物由图元组合(椭圆/矩形/点)在网格上
## 作画, 自动描边通道统一勾边, 按角色调色板渲染, 整数最近邻缩放。
## 工艺规范: 深梅紫描边 / 皮肤受光+阴影+腮红三阶 / 眼睛留白+瞳+高光 /
## 发丝高光 / 每角色专属剪影配件(角·耳·长鼻·高髻·头巾)。
extends RefCounted

const GRID := 32
const ART_IDS := ["skin_default", "skin_aka", "skin_ao", "skin_kitsu",
		"skin_oiran", "skin_tengu", "skin_dball", "skin_ninja", "skin_rx",
		"skin_p5", "skin_gundam", "skin_ppg"]

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
	# 龙珠战士: 刺状黑发 + 橙色武道服 + 蓝内衬腰带
	"skin_dball": {"o" = Color("1c141c"), "s" = Color("f2c8a0"), "S" = Color("d4a880"),
		"b" = Color("f0a890"), "w" = Color("f8f6f0"), "p" = Color("241c26"),
		"m" = Color("b06850"), "h" = Color("241c26"), "H" = Color("3c3440"),
		"c" = Color("f28020"), "C" = Color("c05810"), "l" = Color("2868c8"),
		"a" = Color("1c4890"), "A" = Color("143566"), "g" = Color("e0a83c"),
		"r" = Color("c93a3a")},
	# 木叶忍者: 金色刺发 + 护额(蓝带钢牌) + 颊须 + 橙色运动服
	"skin_ninja": {"o" = Color("1c1810"), "s" = Color("f2d0a8"), "S" = Color("d0a878"),
		"b" = Color("f0b090"), "w" = Color("f8f6f0"), "p" = Color("2858a8"),
		"m" = Color("b06850"), "h" = Color("e8c840"), "H" = Color("f8e888"),
		"a" = Color("98a4b4"), "A" = Color("6a7488"), "c" = Color("f07818"),
		"C" = Color("c05808"), "l" = Color("2858a8"), "g" = Color("e0a83c"),
		"r" = Color("c93a3a"), "d" = Color("b89060")},
	# RX骑士: 全黑头盔 + 绿色复眼 + 额心红晶 + 银色口栅 + 红围巾
	"skin_rx": {"o" = Color("0c0c12"), "s" = Color("d8dce0"), "S" = Color("a8b0b8"),
		"b" = Color("d8dce0"), "w" = Color("f8f6f0"), "p" = Color("0c0c12"),
		"m" = Color("000000"), "h" = Color("1a1a24"), "H" = Color("30303e"),
		"a" = Color("3ddc6c"), "A" = Color("1fa848"), "c" = Color("14141c"),
		"C" = Color("0e0e14"), "l" = Color("b8c0c8"), "g" = Color("e0a83c"),
		"r" = Color("ff4040")},
	# 怪盗J(P5): 蓬松黑长卷发 + 白色眼罩面具 + 黑风衣 + 红手套/领巾
	"skin_p5": {"o" = Color("0c0810"), "s" = Color("f2e2d4"), "S" = Color("d4bca8"),
		"b" = Color("f0a8b0"), "w" = Color("f8f6f0"), "p" = Color("2a2028"),
		"m" = Color("b86868"), "h" = Color("181420"), "H" = Color("342c40"),
		"a" = Color("f8f6f0"), "A" = Color("d8d4d0"), "c" = Color("1a1a24"),
		"C" = Color("101018"), "l" = Color("c92a44"), "g" = Color("e0a83c"),
		"r" = Color("c92a44")},
	# 高达(RX-78): 白盔 + 黄 V 字天线 + 蓝面甲 + 绿复眼 + 红下巴 + 白胸甲蓝腹
	"skin_gundam": {"o" = Color("0e0e16"), "s" = Color("e8ecf4"), "S" = Color("c0c8d8"),
		"b" = Color("e8ecf4"), "w" = Color("f8f6f0"), "p" = Color("0e0e16"),
		"m" = Color("000000"), "h" = Color("e8ecf4"), "H" = Color("f8fafc"),
		"a" = Color("f2c838"), "A" = Color("c89a10"), "c" = Color("2858a8"),
		"C" = Color("1a3c78"), "l" = Color("3ddc6c"), "g" = Color("e0a83c"),
		"r" = Color("d84040")},
	# 飞天小女警(泡泡): 金色双马尾 + 超大眼(蓝瞳) + 蓝裙子 + 元气腮红
	"skin_ppg": {"o" = Color("3a2838"), "s" = Color("f8e2d8"), "S" = Color("e8c8bc"),
		"b" = Color("f8b0c0"), "w" = Color("f8faff"), "p" = Color("58a8e0"),
		"m" = Color("d86078"), "h" = Color("f8e078"), "H" = Color("fdf0b8"),
		"a" = Color("7ac0e8"), "A" = Color("4890c8"), "c" = Color("7ac0e8"),
		"C" = Color("4890c8"), "l" = Color("f8faff"), "g" = Color("e0a83c"),
		"r" = Color("e84a78")},
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
		"skin_dball":
			_comp_dball(g)
		"skin_ninja":
			_comp_ninja(g)
		"skin_rx":
			_comp_rx(g)
		"skin_p5":
			_comp_p5(g)
		"skin_gundam":
			_comp_gundam(g)
		"skin_ppg":
			_comp_ppg(g)
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


## 龙珠战士: 全头刺状黑发(上缘锯齿) + 战意怒眉 + 橙武道服蓝内衬 + 蓝腰带
static func _comp_dball(g: Dictionary) -> void:
	_ell(g, 16, 14, 7, 7.5, "s")
	_rect(g, 14, 21, 17, 25, "S")
	_rect(g, 10, 25, 21, 31, "c")
	_rect(g, 8, 28, 23, 31, "c")
	_rect(g, 15, 25, 16, 28, "l")            # 蓝内衬 V 领
	_px(g, 14, 26, "l")
	_px(g, 17, 26, "l")
	# 发基座 + 全头刺(锯齿向天, 侧刺外斜)
	_ell(g, 16, 9.5, 7.2, 4.2, "h")
	for tip: Array in [[6, 6], [10, 2], [14, 1], [19, 2], [23, 3], [26, 6]]:
		var tx: int = int(tip[0])
		var ty: int = int(tip[1])
		for i in 9 - ty:
			var half := (i + 1) / 2
			_rect(g, tx - half, ty + i, tx + half, ty + i, "h")
	_px(g, 12, 3, "H")                       # 刺尖高光
	_px(g, 19, 4, "H")
	_px(g, 8, 7, "H")
	_face(g, "h", 1)                         # 战意怒眉
	_rect(g, 9, 30, 22, 31, "l")             # 蓝腰带
	_px(g, 15, 30, "g")
	_px(g, 16, 30, "g")                      # 腰带金扣


## 木叶忍者: 金色刺发 + 蓝带钢牌护额 + 颊须三道 + 橙色运动服
static func _comp_ninja(g: Dictionary) -> void:
	_ell(g, 16, 14, 7, 7.5, "s")
	_rect(g, 14, 21, 17, 25, "S")
	_rect(g, 10, 25, 21, 31, "c")
	_rect(g, 8, 28, 23, 31, "c")
	_rect(g, 10, 25, 21, 26, "C")            # 深橙衣领
	_rect(g, 16, 27, 16, 31, "C")            # 中缝拉链
	# 金发基座 + 刺状发梢
	_ell(g, 16, 8.5, 7.2, 4.0, "h")
	for tip: Array in [[7, 5], [11, 2], [16, 1], [21, 2], [25, 5]]:
		var tx: int = int(tip[0])
		var ty: int = int(tip[1])
		for i in 8 - ty:
			var half := (i + 1) / 2
			_rect(g, tx - half, ty + i, tx + half, ty + i, "h")
	_px(g, 13, 2, "H")
	_px(g, 19, 3, "H")
	# 护额: 蓝带横缠 + 钢牌(叶纹刻痕) — 牌窄于脸, 与眼睛留一行的呼吸空隙
	_rect(g, 8, 12, 23, 13, "l")
	_rect(g, 13, 10, 18, 13, "a")
	_px(g, 15, 11, "A")
	_px(g, 16, 11, "A")
	_px(g, 14, 12, "A")
	_px(g, 16, 12, "A")
	_px(g, 15, 10, "w")                      # 牌面反光
	_face(g, "l")                            # 眉被护额压住, 留蓝瞳
	# 颊须三道(左右)
	for i in 3:
		_rect(g, 9, 16 + i * 2, 10, 16 + i * 2, "S")
		_rect(g, 21, 16 + i * 2, 22, 16 + i * 2, "S")


## RX骑士: 全黑头盔 + 额心红晶 + 双绿色复眼 + 银口栅 + 红围巾
static func _comp_rx(g: Dictionary) -> void:
	_rect(g, 14, 21, 17, 24, "C")            # 颈甲
	_rect(g, 10, 25, 21, 31, "c")
	_rect(g, 8, 28, 23, 31, "c")
	_rect(g, 15, 25, 16, 28, "l")            # 银色领口
	# 盔体(全包, 无面部皮肤)
	_ell(g, 16, 13, 7.2, 7.8, "h")
	_rect(g, 12, 19, 19, 21, "C")            # 口部护甲
	# 盔顶脊线 + 侧缘高光
	_rect(g, 16, 4, 16, 7, "H")
	_px(g, 11, 8, "H")
	_px(g, 21, 8, "H")
	# 额心红晶(菱形)
	_px(g, 16, 6, "r")
	_rect(g, 15, 7, 17, 7, "r")
	_rect(g, 14, 8, 17, 8, "r")
	_rect(g, 15, 9, 16, 9, "r")
	_px(g, 15, 7, "w")                       # 晶面反光
	# 双复眼(大椭圆绿) + 眼内高光
	_ell(g, 12.5, 15, 2.7, 2.5, "a")
	_ell(g, 19.5, 15, 2.7, 2.5, "a")
	_px(g, 11, 14, "w")
	_px(g, 18, 14, "w")
	_rect(g, 13, 17, 14, 17, "A")            # 眼下暗部
	_rect(g, 18, 17, 19, 17, "A")
	# 银色口栅(双横条)
	_rect(g, 13, 20, 18, 20, "l")
	_rect(g, 14, 21, 17, 21, "S")
	# 红围巾(颈间环 + 左侧飘尾)
	_rect(g, 9, 23, 22, 24, "r")
	_rect(g, 6, 25, 9, 29, "r")
	_px(g, 6, 29, "A")
	_px(g, 9, 25, "A")
	_rect(g, 9, 30, 22, 31, "C")

## 怪盗J(P5 主角): 蓬松黑长卷发包脸 + 白色眼罩面具 + 黑风衣红领巾
static func _comp_p5(g: Dictionary) -> void:
	_ell(g, 16, 14, 7, 7.5, "s")
	_rect(g, 14, 21, 17, 25, "S")
	_rect(g, 10, 25, 21, 31, "c")
	_rect(g, 8, 28, 23, 31, "c")
	_rect(g, 10, 25, 21, 26, "l")            # 红领巾
	# 蓬松长卷发: 大发团压顶 + 两侧长发披到肩(波浪缘)
	_ell(g, 16, 8.5, 8.2, 5.4, "h")
	_rect(g, 7, 9, 9, 24, "h")
	_rect(g, 22, 9, 24, 24, "h")
	_px(g, 6, 12, "h")
	_px(g, 6, 16, "h")
	_px(g, 25, 12, "h")
	_px(g, 25, 16, "h")
	_px(g, 6, 20, "h")
	_px(g, 25, 20, "h")
	_px(g, 7, 6, "H")
	_px(g, 16, 4, "H")
	_px(g, 24, 6, "H")
	_px(g, 8, 11, "H")
	_px(g, 23, 11, "H")
	# 刘海锯齿压眉
	_px(g, 11, 12, "h")
	_px(g, 14, 11, "h")
	_px(g, 17, 12, "h")
	_px(g, 20, 11, "h")
	# 白色眼罩面具(横贯双眼, 尖角眼缘) + 深色瞳缝
	_rect(g, 10, 14, 21, 17, "a")
	_px(g, 9, 15, "a")
	_px(g, 22, 15, "a")
	_rect(g, 12, 15, 14, 16, "A")
	_rect(g, 17, 15, 19, 16, "A")
	_px(g, 11, 14, "w")
	_px(g, 19, 14, "w")
	_px(g, 15, 19, "S")
	_rect(g, 15, 20, 16, 20, "m")
	_px(g, 10, 19, "b")
	_px(g, 21, 19, "b")
	_rect(g, 9, 30, 22, 31, "C")


## 高达(RX-78-2 头像): 白盔体 + 黄 V 天线 + 蓝面甲 + 绿复眼 + 红下巴 + 白胸甲
static func _comp_gundam(g: Dictionary) -> void:
	_rect(g, 14, 21, 17, 24, "C")            # 颈
	_rect(g, 10, 25, 21, 31, "h")            # 白胸甲
	_rect(g, 8, 28, 23, 31, "h")
	_rect(g, 9, 30, 22, 31, "c")             # 蓝腹
	_rect(g, 15, 25, 16, 28, "c")            # 蓝领口
	# 盔体(白)先画, V 字天线压在其上
	_ell(g, 16, 12.5, 7.4, 7.6, "h")
	# 黄色 V 字天线(额前, 中央双柱 + 两侧斜刃)
	_rect(g, 15, 0, 16, 5, "a")
	_rect(g, 16, 0, 16, 5, "A")
	for side: Array in [[12, 8, 1], [19, 8, -1]]:
		var x0: int = int(side[0])
		var y0: int = int(side[1])
		for i in 4:
			var xx := x0 + i if int(side[2]) > 0 else x0 - i
			_rect(g, xx, y0 - i, xx, y0 - i + 1, "a")
	_px(g, 12, 9, "a")
	_px(g, 19, 9, "a")
	# 额心红线(盔体分缝)
	_rect(g, 15, 7, 16, 9, "S")
	# 绿色大复眼 + 眼内高光
	_rect(g, 11, 13, 13, 16, "l")
	_rect(g, 18, 13, 20, 16, "l")
	_px(g, 12, 14, "w")
	_px(g, 19, 14, "w")
	# 蓝面甲(口鼻区) + 红下巴
	_rect(g, 12, 18, 19, 20, "c")
	_rect(g, 14, 21, 17, 21, "r")
	_rect(g, 11, 17, 20, 17, "H")            # 盔缘高光
	_px(g, 10, 12, "H")
	_px(g, 21, 12, "H")


## 飞天小女警(泡泡): 大圆头 + 金色双马尾 + 超大蓝瞳 + 蓝裙
static func _comp_ppg(g: Dictionary) -> void:
	_ell(g, 16, 14, 8, 7.8, "s")             # 大圆头(比常规大一圈)
	_rect(g, 14, 22, 17, 25, "S")
	_rect(g, 11, 26, 20, 31, "c")            # 蓝裙子
	_rect(g, 10, 25, 21, 26, "a")            # 浅蓝肩带
	# 齐刘海(弧形) + 双马尾(垂在头两侧)
	_ell(g, 16, 8.5, 8.0, 4.4, "h")
	_rect(g, 8, 9, 9, 22, "h")
	_rect(g, 22, 9, 23, 22, "h")
	_px(g, 7, 12, "h")
	_px(g, 24, 12, "h")
	_px(g, 7, 16, "h")
	_px(g, 24, 16, "h")
	_rect(g, 9, 6, 12, 7, "H")
	_px(g, 19, 6, "H")
	# 发带弧线
	_px(g, 10, 5, "H")
	_px(g, 21, 5, "H")
	# 超大眼睛(PGG 风格): 大眼白 + 彩色瞳 + 黑点高光
	_ell(g, 12, 15, 3.0, 3.4, "w")
	_ell(g, 19.6, 15, 3.0, 3.4, "w")
	_ell(g, 12, 15.4, 1.5, 1.8, "p")
	_ell(g, 19.6, 15.4, 1.5, 1.8, "p")
	_px(g, 11, 13, "w")
	_px(g, 18, 13, "w")
	# 元气笑嘴 + 圆腮红
	_rect(g, 14, 20, 17, 20, "m")
	_rect(g, 13, 19, 14, 19, "m")
	_px(g, 17, 19, "m")
	_px(g, 9, 19, "b")
	_px(g, 10, 20, "b")
	_px(g, 21, 19, "b")
	_px(g, 20, 20, "b")
	_rect(g, 11, 30, 20, 31, "A")            # 裙摆深色
