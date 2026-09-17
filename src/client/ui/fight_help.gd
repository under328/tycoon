## 格斗试炼说明: 翻页式图文(花色与属性 / 牌型协同 / 回合流程 / 战斗操作 /
## 连击与奥义 / 稀有卡与无尽)。
## 与 rogue_help/lobby_help 同一工艺: 图示区用面板/连线拼出说明卡。
extends Control

signal closed

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")
const FightModeGd = preload("res://src/rules/fight/fight_mode.gd")

const PAGES := [
	["花色与属性", "你的扑克就是你的装备, 数值越大属性越强:", 0],
	["牌型协同", "每张牌都有小幅单卡加成(♠物攻+4·暴击+5% / ♥生命 / ♦防抗 / ♣技能, 点数越高越多);
组合自动触发套装加成(越大越强), 不满 5 张也可判型:", 1],
	["五张变身", "集满 5 张装备牌即触发『变身』: 光环随主花色变色,
全属性 +5%, 冲刺距离更远, 下一层重置后重新集满再次变身:", 6],
	["回合流程", "共 5 回合: 每回合先『二选一』抽 1 张牌, 再战斗:", 2],
	["战斗操作", "回合制三选操作; 怪物意图公示, 见招拆招:", 3],
	["连击与奥义", "连击加成 + 怒气大招 + 完美格挡, 三重爽点:", 4],
	["稀有卡与无尽", "金框稀有卡 + 通关后无尽挑战:", 5],
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
	size = get_parent_area_size()  # 代码 new 挂 Control 父下锚点不自动求值

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
	_title.text = tr(PAGES[p][0])
	_body.text = tr(PAGES[p][1])
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
	nm.text = tr(name_txt)
	v.add_child(nm)
	var ds := _label(12, AppTheme.DIM)
	ds.text = tr(desc)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ds)


func _combo_row(pos: Vector2, tier: String) -> void:
	var meta: Dictionary = FightModeGd.TIERS[tier]
	_text("%s — %s" % [tr(str(meta["name"])), tr(str(meta["desc"]))], pos, AppTheme.WHITE, 15)


func _text(text: String, pos: Vector2, color := AppTheme.DIM, fsize := 15) -> void:
	var lb := _label(fsize, color)
	lb.text = tr(text)
	lb.position = pos
	_fig.add_child(lb)


func _label(size: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size)
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
			_text("数值越大属性越强 · 空手保底: 攻击 15 / 生命 100",
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
		2:  # 回合流程
			var steps := [
				["第 1 回合", "二选一抽 1 张 → 打小怪"],
				["第 2 回合", "再抽 1 张(共 2 张装备) → 打小怪"],
				["第 3 回合", "再抽 1 张(共 3 张) → 精英怪!"],
				["第 4 回合", "再抽 1 张(共 4 张) → 打小怪"],
				["第 5 回合", "集齐 5 张装备 → 决战 BOSS!"],
			]
			for i in steps.size():
				_text("%s" % steps[i][0], Vector2(160, 16 + i * 52),
						AppTheme.GOLD, 17)
				_text(str(steps[i][1]), Vector2(400, 16 + i * 52),
						AppTheme.WHITE, 15)
		3:  # 战斗操作
			var rows := [
				["⚔ 攻击", "物理伤害, 可暴击(♠ 越多越频繁/越痛)"],
				["✨ 技能", "♣ 法术伤害, 冷却 2 回合; ♣ 张数定流派: 火球/冰霜/圣光"],
				["🛡 防御", "本回合减伤 60% 并回血 — 盯紧怪物意图再决定!"],
				["意图公示", "怪物头顶公示下一手: ⚔攻击 / 💥重击 / 🔥法术 / ⚡蓄力必杀"],
				["⚡ 蓄力", "蓄力回合不攻击且承伤+50% — 全力输出的机会!"],
				["BOSS 必杀", "BOSS 蓄力后释放组别专属技能: 缠绕吸血/暗影尖啸/烈焰灼烧/极寒冰冻/亡者回复"],
			]
			for i in rows.size():
				_text("%s" % rows[i][0], Vector2(160, 16 + i * 52),
						AppTheme.GOLD, 17)
				_text(str(rows[i][1]), Vector2(400, 16 + i * 52),
						AppTheme.WHITE, 15)
		4:  # 连击与奥义
			var rows := [
				["连击", "连续进攻(攻击/技能)不断被击中 → 每层 +6% 伤害(封顶 60%)"],
				["连击清零", "防御打断连击; 被击中不清零(但蓄力回合被击中清零)"],
				["⚡ 怒气", "攻/受/击破积攒; 满 100 释放奥义: 2.5 倍攻击 + 回血 20%"],
				["完美格挡", "预读重击时防御 → 零伤害 + 全额反击 + 怒气 25!"],
				["里程碑", "连击 5 层下击必暴 / 8 层怒气 +30"],
			]
			for i in rows.size():
				_text("%s" % rows[i][0], Vector2(160, 16 + i * 52),
						AppTheme.GOLD, 17)
				_text(str(rows[i][1]), Vector2(400, 16 + i * 52),
						AppTheme.WHITE, 15)
		6:  # 五张变身: 主花色光环示意
			var suits := [["♠ 赤红战魂", Color("ff7050")], ["♥ 翠绿生机", Color("7dd87d")],
					["♦ 金刚护体", Color("ffd166")], ["♣ 苍蓝法魂", Color("7ec8ff")]]
			for i in suits.size():
				var col := 60 + (i % 2) * 420
				var row := 40 + int(i / 2.0) * 130
				var wrap := PanelContainer.new()
				var wsb := AppTheme.flat(Color(0.13, 0.13, 0.28), AppTheme.GOLD, 10, 1)
				wrap.add_theme_stylebox_override("panel", wsb)
				wrap.position = Vector2(col, row)
				wrap.custom_minimum_size = Vector2(360, 100)
				_fig.add_child(wrap)
				var hbb := HBoxContainer.new()
				hbb.add_theme_constant_override("separation", 12)
				wrap.add_child(hbb)
				var ring := _label(40, suits[i][1])
				ring.text = "◎"
				hbb.add_child(ring)
				var nm := _label(18, AppTheme.WHITE)
				nm.text = str(suits[i][0])
				nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				hbb.add_child(nm)
			_text("变身: 全属性 +5% · 冲刺更远 · 下一层重新集满再变身",
					Vector2(140, 240), AppTheme.GOLD, 16)
		5:  # 稀有卡与无尽
			var rows := [
				["金框稀有卡", "候选 12% 出现, 装备后生命上限永久 +8% + 奖励怒气"],
				["无尽模式", "R5 通关后可继续挑战, 怪物每轮 ×1.35 变强"],
				["奖励", "层数越高钻石越多; 复活币可原地复活一次"],
				["评级", "每回合按受伤量评 S/A/B; S 级奖励额外怒气"],
			]
			for i in rows.size():
				_text("%s" % rows[i][0], Vector2(160, 16 + i * 52),
						AppTheme.GOLD, 17)
				_text(str(rows[i][1]), Vector2(400, 16 + i * 52),
						AppTheme.WHITE, 15)
