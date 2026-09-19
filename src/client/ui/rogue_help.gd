## 肉鸽模式规则说明: 翻页式图文(玩法流程 / 命运卡图鉴×2)。
## 图示区用面板/连线拼出命运卡卡面与流程图 — 与 lobby_help 同一工艺。
extends Control

signal closed

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const GameStateGd = preload("res://src/rules/game_state.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")

# 每页: [标题, 正文(bbcode), 图示编号]
const PAGES := [
	["肉鸽模式 · 玩法",
		"规则主体与普通模式[color=#e0a83c]完全一致[/color](换牌/革命/8切/回合制排名)。\n"
		+ "区别只有一条: [color=#7dd87d]每局开始随机抽一张『命运卡』[/color], 本局内生效。\n"
		+ "命运卡来自固定图鉴(共 [color=#ffd166]11 种[/color], 见后几页), 抽到哪张全凭运气——随机性与可玩性由此而来。
每张命运卡还有 [color=#b070e0]稀有度[/color]: 普通(白) < 史诗(紫) < 传说(金), 越稀有越强!", 0],
	["命运卡图鉴 · 发牌与规则", "发牌类与规则类命运卡:", 1],
	["命运卡图鉴 · 触发与结算", "触发类与结算类命运卡:", 2],
	["命运卡图鉴 · 我的进度", "本机记录每张命运卡的出现与选用次数:", 3],
]

var page := 0
var _title: Label
var _body: RichTextLabel
var _fig: Control
var _dots: Array = []
var _prev_btn: Button
var _next_btn: Button
var _close_lbl: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 代码 new 出的 Control 挂 Control 父下锚点不自动求值(size 停留 0×0) → 显式铺满
	size = get_parent_area_size()

	# 不透明全屏页: 从模式选择弹窗打开, 不应透出主菜单背景
	var dim := ColorRect.new()
	dim.color = AppTheme.BG
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)


	_title = _label(32, AppTheme.GOLD)
	_title.position = Vector2(0, 46)
	_title.custom_minimum_size = Vector2(size.x, 46)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_active = false
	_body.position = Vector2(160, 104)
	_body.custom_minimum_size = Vector2(960, 140)
	_body.size = Vector2(960, 140)
	_body.add_theme_font_size_override("normal_font_size", 18)
	add_child(_body)

	_fig = Control.new()
	_fig.position = Vector2(160, 252)
	_fig.custom_minimum_size = Vector2(960, 280)
	add_child(_fig)

	for i in PAGES.size():
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size = Vector2(12, 12)
		dot.position = Vector2(size.x / 2.0 - PAGES.size() * 11 + i * 22, 610)
		add_child(dot)
		_dots.append(dot)

	var prev := AppTheme.nav_button("◀ 上一页", Vector2(340, 646))
	prev.pressed.connect(func() -> void:
		if page > 0:
			_show(page - 1))
	add_child(prev)
	_prev_btn = prev
	var next := AppTheme.nav_button("下一页 ▶", Vector2(760, 646))
	next.pressed.connect(func() -> void:
		if page < PAGES.size() - 1:
			_show(page + 1)
		else:
			_close())
	add_child(next)
	_next_btn = next

	var close := _label(16, AppTheme.DIM)
	close.text = "关闭 ✕"
	close.position = Vector2(size.x - 110, 24)
	close.mouse_filter = Control.MOUSE_FILTER_STOP
	close.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close())
	add_child(close)
	_close_lbl = close

	_show(0)
	Responsive.watch(self, _relayout)


func _relayout() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	var cx := (w - 960.0) / 2.0
	var dy := maxf(h - 720.0, 0.0) * 0.4
	var sq := h < 660.0
	_title.custom_minimum_size = Vector2(w, 46)
	_title.size = Vector2(w, 46)
	_body.position = Vector2(cx, (60.0 if sq else 104.0) + dy)
	_body.size = Vector2(960, (132.0 if not sq else 128.0))
	_fig.position = Vector2(cx, (204.0 if sq else 252.0) + dy)
	_fig.size = Vector2(960, (210.0 if sq else 280.0))
	for i in _dots.size():
		_dots[i].position = Vector2(w / 2.0 - PAGES.size() * 11.0 + i * 22.0,
				(h - 132.0 if sq else 610.0) + dy)
	_prev_btn.position = Vector2(w / 2.0 - 300.0, (h - 78.0 if sq else 646.0) + dy)
	_next_btn.position = Vector2(w / 2.0 + 120.0, (h - 78.0 if sq else 646.0) + dy)
	_close_lbl.position = Vector2(w - 110.0, 24)


func _close() -> void:
	closed.emit()
	queue_free()


func _show(p: int) -> void:
	page = p
	_prev_btn.disabled = p <= 0
	_next_btn.text = ("下一页 ▶" if p < PAGES.size() - 1 else "关 闭")
	_title.text = tr(PAGES[p][0])
	_body.text = tr(PAGES[p][1])
	for i in _dots.size():
		_dots[i].color = AppTheme.GOLD if i == p else AppTheme.DIM
	_build_fig(int(PAGES[p][2]))


func _clear_fig() -> void:
	for c in _fig.get_children():
		c.queue_free()


## 命运卡卡面: 竖直小卡(金框) = 字符章 + 名 + 短句
func _card(pos: Vector2, meta: Dictionary) -> void:
	var card := PanelContainer.new()
	var sb := AppTheme.flat(Color(0.10, 0.10, 0.24, 0.96), Color(AppTheme.GOLD, 0.8), 10, 2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)
	card.position = pos
	card.custom_minimum_size = Vector2(280, 190)
	_fig.add_child(card)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var glyph := _label(40, AppTheme.GOLD)
	glyph.add_theme_font_override("font", AppTheme.title_font())
	glyph.text = str(meta["glyph"])
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(glyph)
	var nm := _label(20, AppTheme.WHITE)
	nm.text = str(meta["name"])
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var ds := _label(13, AppTheme.DIM)
	ds.text = str(meta["desc"])
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ds)


func _card_small(pos: Vector2, m: Dictionary) -> void:
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(Color(0.10, 0.10, 0.24, 0.96), Color(AppTheme.GOLD, 0.7), 8, 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = pos
	panel.custom_minimum_size = Vector2(300, 116)
	_fig.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	panel.add_child(h)
	var glyph := _label(34, AppTheme.GOLD)
	glyph.add_theme_font_override("font", AppTheme.title_font())
	glyph.text = str(m["glyph"])
	glyph.custom_minimum_size = Vector2(40, 0)
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(glyph)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var nm := _label(16, AppTheme.WHITE)
	nm.text = "%s · %s" % [str(m["name"]), str(m["cat"])]
	v.add_child(nm)
	var ds := _label(12, AppTheme.DIM)
	ds.text = str(m["desc"])
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ds)


func _line(a: Vector2, b: Vector2, color := AppTheme.GOLD) -> void:
	var ln := Line2D.new()
	ln.points = PackedVector2Array([a, b])
	ln.width = 2.5
	ln.default_color = color
	_fig.add_child(ln)


func _text(text: String, pos: Vector2, color := AppTheme.DIM, fsize := 15) -> void:
	var lb := _label(fsize, color)
	lb.text = tr(text)
	lb.position = pos
	_fig.add_child(lb)


func _mod(id: String) -> Dictionary:
	for m in GameStateGd.ROGUE_MODS:
		if str(m["id"]) == id:
			return m
	return {}


func _build_fig(kind: int) -> void:
	_clear_fig()
	match kind:
		0:  # 玩法流程: 抽卡 → 对局 → 结算 → 循环
			var steps := [
				["抽命运卡", AppTheme.GOLD], ["本局对局(普通规则)", AppTheme.WHITE],
				["结算(积分×命运卡)", AppTheme.GREEN], ["下一局 · 再抽", AppTheme.GOLD],
			]
			for i in steps.size():
				var col := i % 2
				var row := i / 2
				var panel := PanelContainer.new()
				var sb := AppTheme.flat(Color(0.13, 0.13, 0.28), steps[i][1], 8, 1)
				panel.add_theme_stylebox_override("panel", sb)
				panel.position = Vector2(180 + col * 420, 30 + row * 120)
				panel.custom_minimum_size = Vector2(280, 74)
				_fig.add_child(panel)
				var lb := _label(19, steps[i][1])
				lb.text = str(steps[i][0])
				lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				panel.add_child(lb)
			_line(Vector2(460, 67), Vector2(600, 67))
			_line(Vector2(460, 187), Vector2(600, 187))
			_line(Vector2(320, 104), Vector2(320, 187))   # 左列下行
			_line(Vector2(740, 187), Vector2(740, 104))   # 右列回环
			_text("每局必定抽一张; 11 种命运卡见后几页", Vector2(240, 250),
					AppTheme.GOLD, 16)
		1:
			# 发牌类×3(上排) + 规则类×3(下排)
			var ids1 := ["joker_x2", "short_hands", "joker_ban", "blitz",
					"revolution_start", "chaos_exchange", "no_exchange"]
			for i in ids1.size():
				var m1: Dictionary = _mod(str(ids1[i]))
				_card_small(Vector2(20 + (i % 3) * 320, 12 + (i / 3) * 124), m1)
			_text("发牌类改牌堆构成; 规则类改当局长打法", Vector2(280, 250),
					AppTheme.GOLD, 15)
		2:
			# 触发类×2 + 结算类×2
			var ids2 := ["joker_rage", "eight_gift", "double_stakes", "score_negate"]
			for i in ids2.size():
				var m2: Dictionary = _mod(str(ids2[i]))
				_card_small(Vector2(80 + (i % 2) * 440, 12 + (i / 2) * 124), m2)
			_text("触发类在对局中实时播报; 结算奖励与普通模式完全一致",
					Vector2(240, 292), AppTheme.GOLD, 15)
		3:
			# 图鉴进度: 全部命运卡的出现/选用计数(双列)
			for i in GameStateGd.ROGUE_MODS.size():
				var m3: Dictionary = GameStateGd.ROGUE_MODS[i]
				var mid := str(m3["id"])
				var seen: int = int(Wallet.mod_seen.get(mid, 0))
				var taken: int = int(Wallet.mod_taken.get(mid, 0))
				var col := i % 2
				var row := i / 2
				var lb := _label(15, AppTheme.WHITE if seen > 0 else AppTheme.DIM)
				var rar_tag: String = str({"legend": "★", "epic": "◆", "common": ""}.get(
						str(m3.get("rar", "common")), ""))
				var rar_col: Color = {"legend": Color("ffd166"),
						"epic": Color("b070e0"), "common": AppTheme.WHITE}.get(
						str(m3.get("rar", "common")), AppTheme.WHITE)
				lb.text = "%s%s %s — 出现 %d · 选用 %d" % [rar_tag,
						str(m3.get("glyph", "?")), str(m3.get("name", "")),
						seen, taken]
				lb.add_theme_color_override("font_color",
						rar_col if seen > 0 else AppTheme.DIM)
				lb.position = Vector2(60 + col * 480, 20 + row * 52)
				_fig.add_child(lb)
			var done := 0
			for m4 in GameStateGd.ROGUE_MODS:
				if int(Wallet.mod_seen.get(str(m4["id"]), 0)) > 0:
					done += 1
			_text("收集进度 %d/%d — 见齐全部命运卡解锁隐藏成就" % [done,
					GameStateGd.ROGUE_MODS.size()], Vector2(240, 292),
					AppTheme.GOLD, 15)


func _label(size: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", color)
	return lb
