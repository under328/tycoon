## 程序化像素怪物画生成器(怪物美术路线 v2)。
## 路线: 32×32 画布 · 原型骨架(团块/兽形/飞行/人形/龙形) · 主题三阶调色板
## · 特征件(角/翼/刺/眼/肚皮) · 顶左受光明暗 · 自动深色描边。
## build(theme, kind, variant) → {tex: ImageTexture, size: 32} 带静态缓存。
extends RefCounted

const GRID := 32

## 主题三阶调色板: base 主体 / light 顶左受光 / dark 暗部 / belly 腹部 /
## accent 眼与特征发光 / out 描边
const THEMES := [
	{  # 0 翡翠森林
		"base": Color("63a852"), "light": Color("93d17c"), "dark": Color("33682c"),
		"belly": Color("d9e6b5"), "accent": Color("ffd94a"), "out": Color("16220f"),
	},
	{  # 1 回声洞穴
		"base": Color("7d81c9"), "light": Color("aaadde"), "dark": Color("464984"),
		"belly": Color("c9c9e8"), "accent": Color("ffe066"), "out": Color("131327"),
	},
	{  # 2 熔火之心
		"base": Color("e07030"), "light": Color("ffaa58"), "dark": Color("933a12"),
		"belly": Color("ffd9a2"), "accent": Color("ffec44"), "out": Color("280d03"),
	},
	{  # 3 冰封雪原
		"base": Color("9cc8e8"), "light": Color("d4edfb"), "dark": Color("5786ae"),
		"belly": Color("eaf5fc"), "accent": Color("57cfe0"), "out": Color("192736"),
	},
	{  # 4 幽暗墓地
		"base": Color("9a9aa8"), "light": Color("c4c4ce"), "dark": Color("5c5c6a"),
		"belly": Color("c7d7bf"), "accent": Color("8af0c8"), "out": Color("121219"),
	},
]

static var _cache := {}


## 生成(带缓存): theme 0..4, kind "mob"/"elite"/"boss", variant 0/1 换色
static func build(theme: int, kind: String, variant: int) -> Dictionary:
	var key := "%d_%s_%d" % [clampi(theme, 0, 4), kind, clampi(variant, 0, 1)]
	if _cache.has(key):
		return _cache[key]
	var pal: Dictionary = THEMES[clampi(theme, 0, 4)].duplicate()
	if variant == 1:
		for k in ["base", "light", "dark", "belly"]:
			pal[k] = _shift(pal[k], 0.55)   # 换色变体: 偏红
	var img := Image.create(GRID, GRID, false, Image.FORMAT_RGBA8)
	var cells := PackedInt32Array()
	cells.resize(GRID * GRID)   # -1 空, 0=base 1=light 2=dark 3=belly 4=accent 5=outline
	for i in GRID * GRID:
		cells[i] = -1
	var kind_s := "boss" if kind == "boss" else ("elite" if kind == "elite" else "mob")
	match kind_s:
		"mob":
			_mob(cells, pal, theme)
		"elite":
			_elite(cells, pal, theme)
		"boss":
			_boss(cells, pal, theme)
	_shade(cells)
	_outline(cells)
	_paint(img, cells, pal)
	var tex := ImageTexture.create_from_image(img)
	var out := {"tex": tex, "size": GRID}
	_cache[key] = out
	return out


## ── 像素写入口 ──
static func _px(cells: PackedInt32Array, x: int, y: int, c: int) -> void:
	if x >= 0 and y >= 0 and x < GRID and y < GRID:
		cells[y * GRID + x] = c


static func _ellipse(cells: PackedInt32Array, cx: float, cy: float,
		rx: float, ry: float, c: int) -> void:
	for y in range(maxi(int(cy - ry), 0), mini(int(cy + ry) + 1, GRID)):
		for x in range(maxi(int(cx - rx), 0), mini(int(cx + rx) + 1, GRID)):
			var dx := (x - cx) / rx
			var dy := (y - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				cells[y * GRID + x] = c


static func _rect(cells: PackedInt32Array, x: int, y: int, w: int, hh: int, c: int) -> void:
	for yy in range(y, mini(y + hh, GRID)):
		for xx in range(x, mini(x + w, GRID)):
			cells[yy * GRID + xx] = c


## ── 小怪: 圆滚滚团块 + 短足 + 大眼 + 主题头饰 ──
static func _mob(cells: PackedInt32Array, p: Dictionary, theme: int) -> void:
	var cx := 16.0
	_ellipse(cells, cx, 20.0, 9.0, 8.0, 0)            # 身体
	_ellipse(cells, cx, 24.0, 5.5, 3.5, 3)            # 肚皮
	_rect(cells, 10, 27, 3, 3, 2)                     # 左足
	_rect(cells, 19, 27, 3, 3, 2)                     # 右足
	# 主题头饰
	match theme:
		0:   # 森林: 蘑菇帽
			_ellipse(cells, cx, 12.5, 11.0, 4.5, 2)
			_ellipse(cells, cx, 11.0, 8.0, 3.0, 1)
		1:   # 洞穴: 小翼
			_rect(cells, 5, 15, 4, 7, 2)
			_rect(cells, 23, 15, 4, 7, 2)
			_px(cells, 4, 14, 2)
			_px(cells, 27, 14, 2)
		2:   # 熔岩: 头顶火苗
			_ellipse(cells, cx, 10.5, 2.5, 3.5, 4)
			_px(cells, 16, 6, 1)
		3:   # 雪原: 耳朵
			_rect(cells, 9, 9, 3, 5, 0)
			_rect(cells, 20, 9, 3, 5, 0)
			_px(cells, 10, 10, 4)
			_px(cells, 21, 10, 4)
		4:   # 墓地: 小角
			_px(cells, 11, 10, 2)
			_px(cells, 10, 9, 2)
			_px(cells, 20, 10, 2)
			_px(cells, 21, 9, 2)
	# 眼睛(白底黑瞳 + 高光)
	_eyes(cells, cx, 18.0, 5.0)


## ── 精英: 人形武士 — 头 + 宽肩 + 臂 + 腿 + 角 ──
static func _elite(cells: PackedInt32Array, p: Dictionary, theme: int) -> void:
	var cx := 16.0
	_rect(cells, 10, 20, 12, 6, 0)                    # 躯干
	_ellipse(cells, cx, 21.5, 6.5, 3.0, 3)            # 腰腹
	_rect(cells, 11, 26, 4, 4, 2)                     # 腿
	_rect(cells, 17, 26, 4, 4, 2)
	_rect(cells, 6, 14, 4, 8, 0)                      # 左臂
	_rect(cells, 22, 14, 4, 8, 0)                     # 右臂
	_rect(cells, 5, 21, 5, 3, 4)                      # 爪(亮色)
	_rect(cells, 22, 21, 5, 3, 4)
	_rect(cells, 9, 9, 14, 8, 0)                      # 头
	_ellipse(cells, cx, 10.0, 7.0, 2.5, 1)            # 头顶受光
	# 主题头部特征
	match theme:
		0:   # 森林: 树叶冠
			_ellipse(cells, cx, 8.0, 9.0, 2.5, 1)
			_px(cells, 9, 6, 1)
			_px(cells, 16, 5, 1)
			_px(cells, 23, 6, 1)
		1:   # 洞穴: 双角
			_rect(cells, 8, 4, 2, 6, 1)
			_rect(cells, 22, 4, 2, 6, 1)
		2:   # 熔岩: 火焰冠
			_ellipse(cells, cx, 6.0, 4.0, 3.0, 4)
			_px(cells, 13, 3, 1)
			_px(cells, 19, 3, 1)
		3:   # 雪原: 冰晶盔
			_ellipse(cells, cx, 7.0, 8.0, 2.0, 4)
		4:   # 墓地: 骨冠
			for k in 5:
				_px(cells, 10 + k * 3, 6 + (k % 2), 3)
	# 眼睛(横排发光双眼)
	_eyes(cells, cx, 12.5, 4.5)


## ── BOSS: 龙形巨兽 — 大头 + 宽身 + 双翼/巨角 + 发光眼 ──
static func _boss(cells: PackedInt32Array, p: Dictionary, theme: int) -> void:
	var cx := 16.0
	_ellipse(cells, cx, 21.0, 11.0, 9.0, 0)           # 巨躯
	_ellipse(cells, cx, 25.0, 7.0, 4.0, 3)            # 腹
	_rect(cells, 8, 28, 5, 3, 2)                      # 爪足
	_rect(cells, 19, 28, 5, 3, 2)
	_rect(cells, 9, 6, 14, 10, 0)                     # 头
	_ellipse(cells, cx, 7.0, 7.5, 3.0, 1)
	# 双翼/巨角(主题差异)
	match theme:
		0:   # 森林: 巨鹿角
			for k in 4:
				_px(cells, 6, 8 - k, 1)
				_px(cells, 25, 8 - k, 1)
			_rect(cells, 4, 4, 4, 2, 1)
			_rect(cells, 24, 4, 4, 2, 1)
		1, 2, 4:   # 洞穴/熔岩/墓地: 蝙蝠巨翼
			for k in 7:
				_rect(cells, 2, 8 + k, 6 - k / 2, 2, 2)
				_rect(cells, 24 + k / 2, 8 + k, 6 - k / 2, 2, 2)
		3:   # 雪原: 冰鬃
			for k in 5:
				_rect(cells, 10 + k * 3, 3 + (k % 2) * 2, 2, 4, 4)
	# 发光巨眼
	_rect(cells, 11, 9, 4, 3, 4)
	_rect(cells, 17, 9, 4, 3, 4)
	_px(cells, 12, 10, 5)
	_px(cells, 19, 10, 5)


## ── 眼睛: 白底 + 深瞳 + 高光 ──
static func _eyes(cells: PackedInt32Array, cx: float, y: float, half: float) -> void:
	var lx := int(cx - half)
	var rx := int(cx + half) - 2
	var iy := int(y)
	for dx in 2:
		_px(cells, lx + dx, iy, 5)
		_px(cells, rx + dx, iy, 5)
		_px(cells, lx + dx, iy + 1, 5)
		_px(cells, rx + dx, iy + 1, 5)
	_px(cells, lx, iy, 4)
	_px(cells, rx + 1, iy, 4)   # 高光


## ── 明暗: 顶左受光 → light; 底右 → dark ──
static func _shade(cells: PackedInt32Array) -> void:
	for y in GRID:
		for x in GRID:
			var i := y * GRID + x
			var c := cells[i]
			if c != 0:   # 只调 base
				continue
			var up_empty := y <= 0 or cells[i - GRID] == -1
			var left_empty := x <= 0 or cells[i - 1] == -1
			var down_empty := y >= GRID - 1 or cells[i + GRID] == -1
			var right_empty := x >= GRID - 1 or cells[i + 1] == -1
			if up_empty or left_empty:
				cells[i] = 1
			elif down_empty or right_empty:
				cells[i] = 2


## ── 描边: 空像素与实心相邻 → 深色描边 ──
static func _outline(cells: PackedInt32Array) -> void:
	var add: Array = []
	for y in GRID:
		for x in GRID:
			var i := y * GRID + x
			if cells[i] != -1:
				continue
			var near := false
			if x > 0 and cells[i - 1] != -1 and cells[i - 1] != 5:
				near = true
			if x < GRID - 1 and cells[i + 1] != -1 and cells[i + 1] != 5:
				near = true
			if y > 0 and cells[i - GRID] != -1 and cells[i - GRID] != 5:
				near = true
			if y < GRID - 1 and cells[i + GRID] != -1 and cells[i + GRID] != 5:
				near = true
			if near:
				add.append(i)
	for i in add:
		cells[i] = 5


## ── 色阶索引 → 颜色 ──
static func _paint(img: Image, cells: PackedInt32Array, p: Dictionary) -> void:
	var cols := [p["base"], p["light"], p["dark"], p["belly"], p["accent"], p["out"]]
	for y in GRID:
		for x in GRID:
			var c := cells[y * GRID + x]
			if c < 0:
				continue
			img.set_pixel(x, y, cols[clampi(c, 0, cols.size() - 1)])


## 换色变体: 色相偏移
static func _shift(c: Color, amount: float) -> Color:
	var out := Color(c)
	out.h = fmod(out.h + amount, 1.0)
	return out
