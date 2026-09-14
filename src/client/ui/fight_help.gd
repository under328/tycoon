## 格斗试炼说明: 翻页式图文(花色与属性 / 牌型协同 / 战斗操作与祝福)。
## 与 rogue_help/lobby_help 同一工艺: 图示区用面板/连线拼出说明卡。
extends Control

signal closed

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")
const FightModeGd = preload("res://src/rules/fight/fight_mode.gd")

const PAGES := [
	["花色与属性", "你的 5 张扑克就是你的装备, 数值越大属性越强:", 0],
	["牌型协同", "5 张牌的组合自动触发套装加成(越大越强):", 1],
	["战斗与祝福", "回合制三选操作; 怪物意图公示, 见招拆招:", 2],
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

	var bg := ColorRect.new()
	bg.color = AppTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_title = _label(32, AppTheme.GOLD)
	_title.position = Vector2(0, 46)
	_title.custom_minimum_size = Vector2(size.x, 46)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_active = false
	_body.position = Vector2(160, 120)
	_body.custom_minimum_size = Vector2(960, 130)
	_body.size = Vector2(960, 130)
	_body.add_theme_font_size_override("normal_font_size", 18)
	add_child(_body)

	_fig = Control.new()
	_fig.position = Vector2(160, 290)
	_fig.custom_minimum_size = Vector2(960, 290)
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
	_body.position = Vector2(cx, (64.0 if sq else 120.0) + dy)
	_body.size = Vector2(960, 130)
	_fig.position = Vector2(cx, (226.0 if sq else 290.0) + dy)
	_fig.size = Vector2(960, (260.0 if sq else 290.0))
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
	_title.text = PAGES[p][0]
	_body.text = PAGES[p][1]
	for i in _dots.size():
		_dots[i].color = AppTheme.GOLD if i == p else AppTheme.DIM
	_build_fig(int(PAGES[p][2]))


func _clear_fig() -> void:
	for c in _fig.get_children():
		c.queue_free()


## 花色卡(战斗属性方向)
func _suit_card(pos: Vector2, glyph: String, name_txt: String,
		desc: String, col: Color) -> void:
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(Color(0.10, 0.10, 0.24, 0.96), col, 8, 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = pos
	panel.custom_minimum_size = Vector2(220, 120)
	_fig.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var g := _label(30, col)
	g.text = glyph
	v.add_child(g)
	var nm := _label(15, AppTheme.WHITE)
	nm.text = name_txt
	v.add_child(nm)
	var ds := _label(12, AppTheme.DIM)
	ds.text = desc
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ds)


func _combo_row(pos: Vector2, tier: String) -> void:
	var meta: Dictionary = FightModeGd.TIERS[tier]
	_text("%s — %s" % [meta["name"], meta["desc"]], pos, AppTheme.WHITE, 15)


func _text(text: String, pos: Vector2, color: Color, fsize: int) -> void:
	var lb := _label(fsize, color)
	lb.text = text
	lb.position = pos
	_fig.add_child(lb)


func _label(size_num: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size_num)
	lb.add_theme_color_override("font_color", color)
	return lb


func _build_fig(kind: int) -> void:
	_clear_fig()
	match kind:
		0:  # 花色四卡
			_suit_card(Vector2(20, 16), "♠", "黑桃 · 物攻",
					"数值合计 = 物理攻击; 张数越多暴击率/爆伤越高", Color("e8ecf4"))
			_suit_card(Vector2(260, 16), "♥", "红桃 · 生命",
					"数值合计 = 生命上限加成, 越多越肉", Color("ff8896"))
			_suit_card(Vector2(500, 16), "♦", "方块 · 护甲/魔抗",
					"护甲挡物理, 魔抗挡法术, 双修最稳", Color("ffd166"))
			_suit_card(Vector2(740, 16), "♣", "梅花 · 法术",
					"数值合计 = 技能强度; 张数决定技能流派", Color("8ae88a"))
			_text("数值越大属性越强 · 每层通关后全属性 +15% 成长",
					Vector2(240, 270), AppTheme.GOLD, 15)
		1:  # 牌型协同
			var tiers := ["straight_flush", "quad", "flush", "full_house",
					"straight", "trips", "two_pair", "pair"]
			for i in tiers.size():
				var meta: Dictionary = FightModeGd.TIERS[str(tiers[i])]
				_text("%d. %s — %s" % [i + 1, meta["name"], meta["desc"]],
						Vector2(200, 16 + i * 32), AppTheme.WHITE, 15)
			_text("牌型在选牌与战斗界面实时显示", Vector2(280, 278),
					AppTheme.GOLD, 15)
		2:  # 战斗操作
			var rows := [
				["⚔ 攻击", "物理伤害, 可暴击(♠ 越多越频繁/越痛)"],
				["✨ 技能", "♣ 法术伤害, 冷却 2 回合; ♣ 张数定流派: 火球/冰霜/圣光"],
				["🛡 防御", "本回合减伤 60% 并回血 — 盯紧怪物意图再决定!"],
				["意图公示", "怪物头顶公示下一手: ⚔攻击 / 💥重击 / 🔥法术"],
				["通关祝福", "每层通关三选一祝福, 可叠加成流派"],
			]
			for i in rows.size():
				_text("%s" % rows[i][0], Vector2(160, 16 + i * 52),
						AppTheme.GOLD, 17)
				_text(str(rows[i][1]), Vector2(400, 16 + i * 52),
						AppTheme.WHITE, 15)
