## 表情包生成器: 斗地主主题像素表情包(32×32 → ImageTexture)。
## 与怪物美术同一工艺: 像素原语 + 描边 + 有限色板。可点击发送,
## 对局内以大尺寸贴纸动画呈现(联机经 emoji 通道 id≥100)。
extends RefCounted

const GRID := 32

const NAMES := ["炸弹", "王炸", "飞机", "顺子", "春天", "双倍", "加油", "谢谢"]

static var _cache := {}


static func build(idx: int) -> Dictionary:
	idx = clampi(idx, 0, NAMES.size() - 1)
	var key := "s%d" % idx
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(GRID, GRID, false, Image.FORMAT_RGBA8)
	var cells := PackedInt32Array()
	cells.resize(GRID * GRID)
	for i in GRID * GRID:
		cells[i] = -1
	match idx:
		0: _st_bomb(cells)
		1: _st_jokers(cells)
		2: _st_plane(cells)
		3: _st_run(cells)
		4: _st_spring(cells)
		5: _st_double(cells)
		6: _st_cheer(cells)
		7: _st_thanks(cells)
	_outline(cells)
	_paint(img, cells, idx)
	var tex := ImageTexture.create_from_image(img)
	var out := {"tex": tex, "size": GRID, "name": NAMES[idx]}
	_cache[key] = out
	return out


## ── 像素原语 ──
static func _px(cells: PackedInt32Array, x: int, y: int, c: int) -> void:
	if x >= 0 and y >= 0 and x < GRID and y < GRID:
		cells[y * GRID + x] = c


static func _rect(cells: PackedInt32Array, x: int, y: int, w: int, h: int, c: int) -> void:
	for yy in range(y, mini(y + h, GRID)):
		for xx in range(x, mini(x + w, GRID)):
			cells[yy * GRID + xx] = c


static func _ellipse(cells: PackedInt32Array, cx: float, cy: float,
		rx: float, ry: float, c: int) -> void:
	for y in range(maxi(int(cy - ry), 0), mini(int(cy + ry) + 1, GRID)):
		for x in range(maxi(int(cx - rx), 0), mini(int(cx + rx) + 1, GRID)):
			var dx := (x - cx) / rx
			var dy := (y - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				cells[y * GRID + x] = c


static func _outline(cells: PackedInt32Array) -> void:
	var add: Array = []
	for y in GRID:
		for x in GRID:
			var i := y * GRID + x
			if cells[i] != -1:
				continue
			var near := false
			if x > 0 and cells[i - 1] != -1:
				near = true
			if x < GRID - 1 and cells[i + 1] != -1:
				near = true
			if y > 0 and cells[i - GRID] != -1:
				near = true
			if y < GRID - 1 and cells[i + GRID] != -1:
				near = true
			if near:
				add.append(i)
	for i in add:
		cells[i] = 0   # 0 = 描边黑


## ── 色板约定: 0 黑边 1 白 2 红 3 黄 4 蓝 5 绿 6 橙 7 紫 8 灰 ──
static func _col(i: int) -> Color:
	var table := [Color("141419"), Color("f5f5f0"), Color("e04848"),
			Color("ffd042"), Color("4a9de0"), Color("58b849"),
			Color("ff9130"), Color("a86ae0"), Color("9a9aa8")]
	return table[clampi(i, 0, table.size() - 1)]


static func _paint(img: Image, cells: PackedInt32Array, idx: int) -> void:
	for y in GRID:
		for x in GRID:
			var c := cells[y * GRID + x]
			if c < 0:
				continue
			var col := _col(c)
			img.set_pixel(x, y, col)


## ── 0 炸弹: 黑弹体 + 引信火花 ──
static func _st_bomb(c: PackedInt32Array) -> void:
	_ellipse(c, 15.0, 21.0, 9.0, 8.0, 8)
	_ellipse(c, 12.0, 18.0, 3.5, 2.5, 1)   # 高光
	_rect(c, 14, 10, 4, 4, 8)              # 引信座
	_rect(c, 18, 6, 2, 5, 8)               # 引信
	_px(c, 20, 4, 3)
	_px(c, 21, 3, 3)
	_px(c, 19, 3, 3)
	_px(c, 22, 5, 3)


## ── 1 王炸: 黑白双王并排 ──
static func _st_jokers(c: PackedInt32Array) -> void:
	_rect(c, 4, 6, 11, 20, 1)              # 白王
	_rect(c, 17, 6, 11, 20, 8)             # 黑王
	_ellipse(c, 9.5, 13.0, 3.0, 3.0, 8)    # 白王脸
	_ellipse(c, 22.5, 13.0, 3.0, 3.0, 1)   # 黑王脸
	_px(c, 8, 12, 1)
	_px(c, 11, 12, 8)
	_px(c, 21, 12, 8)
	_px(c, 24, 12, 1)
	_rect(c, 8, 18, 4, 2, 2)               # 嘴
	_rect(c, 21, 18, 4, 2, 2)
	_px(c, 9, 22, 3)
	_px(c, 22, 22, 3)


## ── 2 飞机: 纸飞机右上飞 ──
static func _st_plane(c: PackedInt32Array) -> void:
	for k in 9:
		_rect(c, 8 + k, 18 - k, 2, 2, 4)       # 机身斜向
	_rect(c, 6, 20, 4, 3, 1)
	_rect(c, 20, 8, 6, 5, 1)               # 机翼
	_px(c, 26, 6, 3)
	_px(c, 25, 10, 3)
	_rect(c, 4, 26, 8, 2, 3)               # 航迹
	_rect(c, 15, 22, 6, 2, 3)


## ── 3 顺子: 递升箭头 + 三张小牌 ──
static func _st_run(c: PackedInt32Array) -> void:
	_rect(c, 6, 20, 5, 7, 2)
	_rect(c, 14, 15, 5, 12, 4)
	_rect(c, 22, 9, 5, 18, 3)
	for k in 5:
		_px(c, 7 + k * 4, 17 - k * 3, 1)
	for k in 6:
		_rect(c, 24 + k, 6 + k, 2, 2, 3)
		_px(c, 23 + k, 7 + k, 3)


## ── 4 春天: 花朵 + 太阳 ──
static func _st_spring(c: PackedInt32Array) -> void:
	_ellipse(c, 24.0, 8.0, 4.0, 4.0, 3)    # 太阳
	_ellipse(c, 12.0, 20.0, 6.0, 6.0, 2)   # 花心
	for k in 6:
		var a := TAU * k / 6.0
		_ellipse(c, 12.0 + cos(a) * 8.0, 20.0 + sin(a) * 8.0, 3.0, 3.0, 1)
	_rect(c, 11, 26, 2, 4, 5)              # 茎


## ── 5 双倍: 金色 ×2 ──
static func _st_double(c: PackedInt32Array) -> void:
	_ellipse(c, 16.0, 16.0, 12.0, 11.0, 3)
	# ×
	for k in 5:
		_px(c, 8 + k, 10 + k, 1)
		_px(c, 12 - k, 10 + k, 1)
	# 2
	_rect(c, 18, 10, 6, 2, 1)
	_rect(c, 22, 12, 2, 3, 1)
	_rect(c, 18, 15, 6, 2, 1)
	_rect(c, 18, 17, 2, 3, 1)
	_rect(c, 18, 20, 6, 2, 1)


## ── 6 加油: 拳头上举 + 星芒 ──
static func _st_cheer(c: PackedInt32Array) -> void:
	_rect(c, 12, 14, 9, 12, 2)             # 手臂
	_rect(c, 10, 8, 13, 7, 2)              # 拳头
	for k in 3:
		_rect(c, 12 + k * 3, 9, 1, 5, 2)
	_px(c, 6, 4, 3)
	_px(c, 25, 4, 3)
	_px(c, 5, 12, 3)
	_px(c, 26, 12, 3)
	_px(c, 16, 2, 3)


## ── 7 谢谢: 红心 + 高光 ──
static func _st_thanks(c: PackedInt32Array) -> void:
	_ellipse(c, 11.5, 12.0, 6.5, 6.5, 2)
	_ellipse(c, 20.5, 12.0, 6.5, 6.5, 2)
	for y in range(12, 27):
		var w := 27 - y
		if w < 0:
			w = 0
		_rect(c, 16 - w, y, w * 2 + 1, 1, 2)
	_ellipse(c, 9.0, 9.0, 2.5, 2.0, 1)     # 高光
	_px(c, 16, 20, 1)
	_px(c, 16, 22, 1)
