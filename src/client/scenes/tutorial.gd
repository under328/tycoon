## 新手引导：翻页式图文教程。风格与游戏一致（和风×霓虹 + 程序化卡面图示）。
## 用法: var t = TutorialScript.new(); add_child(t); t.closed.connect(...)
extends Control

const AppTheme = preload("res://src/client/theme/app_theme.gd")

signal closed

const CardsGd = preload("res://src/rules/cards.gd")
const CardViewScript = preload("res://src/client/ui/card_view.gd")


# 每页: [标题, 正文(多行), 图示编号]
const PAGES := [
	["欢迎来到大富豪", "你的目标只有一个:【尽快出完手牌】。\n最先出完的是【大富豪】, 依次为富豪、平民, 最后一名是【乞丐】。\n一场连打 3 局, 总分最高的玩家获胜。", 0],
	["牌的大小", "点序从 3 最小到 2 次大, 【王】最大。\n花色不分大小: 红桃 A 和黑桃 A 一样大。", 1],
	["牌型", "出牌必须【同牌型、同张数、点更大】, 或选择不要。\n单张 / 对子 / 三条 / 四条; 3 张以上连续点数是【顺子】;\n同花色的顺子叫【階段】, 只能被同长度更大的階段压过。", 2],
	["王牌是万能牌", "王单出时是最大的单张; 和其他牌一起出时会自动补位:\n3♥ + 王 = 对 3;  5♣ 7♥ + 王 = 顺子 5-6-7。", 3],
	["革命", "打出【四条】立刻触发革命: 点序大小反转!\n3 变成最大, 王变成最小, 直到有人再打出一次四条才恢复。\n劣势局里, 一组四条就是翻盘的号角。", 4],
	["身份与换牌", "每局结束按出完顺序结算身份。\n下一局开始前: 乞丐把最大的 2 张交给大富豪,\n平民把最大的 1 张交给富豪 —— 强者更强, 但弱者手握先出权。", 5],
	["计分", "单局积分: 大富豪 +2, 富豪 +1, 平民 -1, 乞丐 -2。\n3 局积分累加, 总分最高者赢得整场。", 6],
	["界面操作", "点选手牌使其亮起, 再点【出牌】; 跟不上就点【不要】。\n回合倒计时结束会自动托管; 联机时还能发表情和聊天。\n随时点右上角【规则】可以翻看本教程。", 7],
]

var page := 0
var _title: Label
var _body: Label
var _fig: Control
var _page_lbl: Label
var _dots: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size

	var bg := ColorRect.new()
	bg.color = AppTheme.OVERLAY_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 和风边框
	var frame := ReferenceRect.new()
	frame.border_color = Color(AppTheme.GOLD, 0.55)
	frame.border_width = 2.0
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.editor_only = false
	add_child(frame)

	_title = _label(34, AppTheme.GOLD)
	_title.position = Vector2(0, 52)
	_title.custom_minimum_size = Vector2(size.x, 50)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)

	_fig = Control.new()
	_fig.position = Vector2(240, 140)
	_fig.custom_minimum_size = Vector2(800, 300)
	add_child(_fig)

	_body = _label(19, AppTheme.WHITE)
	_body.position = Vector2(240, 470)
	_body.custom_minimum_size = Vector2(800, 130)
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_body)

	# 页码点
	for i in PAGES.size():
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size = Vector2(12, 12)
		dot.position = Vector2(size.x / 2.0 - PAGES.size() * 11 + i * 22, 618)
		add_child(dot)
		_dots.append(dot)

	var prev := _nav_button("◀ 上一页", Vector2(340, 650))
	prev.pressed.connect(func() -> void:
		if page > 0:
			_show(page - 1))
	add_child(prev)
	var next := _nav_button("下一页 ▶", Vector2(760, 650))
	next.pressed.connect(func() -> void:
		if page < PAGES.size() - 1:
			_show(page + 1)
		else:
			_close())
	add_child(next)

	var close := _label(16, AppTheme.DIM)
	close.text = "关闭 ✕"
	close.position = Vector2(size.x - 110, 24)
	close.mouse_filter = Control.MOUSE_FILTER_STOP
	close.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close())
	add_child(close)

	_show(0)


func _close() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		gs.tutorial_seen = true
		gs.save_settings()
	closed.emit()
	queue_free()


func _show(p: int) -> void:
	page = p
	_title.text = PAGES[p][0]
	_body.text = PAGES[p][1]
	for i in _dots.size():
		_dots[i].color = AppTheme.GOLD if i == p else AppTheme.DIM
	_dots[p].size = Vector2(12, 12)
	_page_lbl = null
	_build_fig(int(PAGES[p][2]))


# ---------------------------------------------------------------- 图示

func _clear_fig() -> void:
	for c in _fig.get_children():
		c.queue_free()


func _mini(card: int, pos: Vector2, s := 0.8) -> void:
	var cv := CardViewScript.new(card)
	cv.custom_minimum_size = Vector2(58, 80) * s
	cv.size = cv.custom_minimum_size
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.position = pos
	_fig.add_child(cv)


func _fig_label(text: String, pos: Vector2, color := AppTheme.DIM, fsize := 15) -> void:
	var lb := _label(fsize, color)
	lb.text = text
	lb.position = pos
	_fig.add_child(lb)


func _arrow(x0: float, y: float, x1: float, color := AppTheme.GOLD) -> void:
	var ln := Line2D.new()
	ln.points = PackedVector2Array([Vector2(x0, y), Vector2(x1 - 12, y)])
	ln.width = 2.5
	ln.default_color = color
	_fig.add_child(ln)
	var tri := Line2D.new()
	tri.points = PackedVector2Array([Vector2(x1 - 22, y - 7), Vector2(x1 - 12, y), Vector2(x1 - 22, y + 7)])
	tri.width = 2.5
	tri.default_color = color
	_fig.add_child(tri)


func _build_fig(kind: int) -> void:
	_clear_fig()
	match kind:
		0:
			_mini(53, Vector2(240, 60), 1.15)
			_mini(51, Vector2(340, 90), 1.15)
			_mini(48, Vector2(440, 60), 1.15)
			_fig_label("出完手牌 → 大富豪!", Vector2(240, 230), AppTheme.GREEN, 20)
		1:
			var order := [0, 20, 32, 44, 48, 53]
			var names := ["3", "…", "J", "A", "2", "王"]
			for i in order.size():
				var x := 20.0 + i * 128.0
				if i < order.size() - 1:
					_mini(order[i], Vector2(x, 40), 0.9)
				else:
					_mini(53, Vector2(x, 34), 1.05)
				_fig_label(names[i], Vector2(x + 14, 152), AppTheme.GOLD, 18)
				if i < order.size() - 1:
					_arrow(x + 62, 100, x + 126)
			_fig_label("小", Vector2(30, 190), AppTheme.DIM, 16)
			_fig_label("大", Vector2(736, 190), AppTheme.DIM, 16)
		2:
			var groups := [
				{"cards": [8], "label": "单张"},
				{"cards": [16, 20], "label": "对子"},
				{"cards": [24, 28, 32], "label": "三条"},
				{"cards": [36, 37, 38, 39], "label": "四条→革命!"},
				{"cards": [4, 8, 12], "label": "顺子(混花)"},
				{"cards": [0, 4, 8], "label": "階段(同花)"},
			]
			for gi in groups.size():
				var col := gi % 3
				var row := gi / 3
				var bx := 30.0 + col * 264.0
				var by := 16.0 + row * 140.0
				var cards: Array = groups[gi]["cards"]
				for ci in cards.size():
					_mini(cards[ci], Vector2(bx + ci * 34.0, by), 0.62)
				var col2 := AppTheme.RED if gi == 3 else AppTheme.DIM
				_fig_label(str(groups[gi]["label"]), Vector2(bx + 4, by + 78), col2, 15)
		3:
			_mini(52, Vector2(300, 40), 1.3)
			_mini(1, Vector2(420, 70), 0.9)
			_fig_label("+", Vector2(392, 96), AppTheme.GOLD, 26)
			_fig_label("=", Vector2(500, 96), AppTheme.GOLD, 26)
			_mini(1, Vector2(530, 70), 0.9)
			_fig_label("对 3", Vector2(556, 96), AppTheme.GREEN, 18)
			_fig_label("王自动补位, 缺什么补什么", Vector2(240, 210), AppTheme.DIM, 16)
		4:
			_mini(0, Vector2(200, 40), 0.95)
			_arrow(258, 96, 380)
			_fig_label("3 最强", Vector2(200, 150), AppTheme.RED, 17)
			_mini(48, Vector2(420, 40), 0.95)
			_fig_label("王最弱", Vector2(416, 150), AppTheme.DIM, 17)
			_mini(48, Vector2(540, 40), 0.95)
			_mini(49, Vector2(568, 40), 0.95)
			_mini(50, Vector2(596, 40), 0.95)
			_mini(51, Vector2(624, 40), 0.95)
			_fig_label("打出四条 = 革命!", Vector2(520, 150), AppTheme.RED, 17)
		5:
			var steps := [["大富豪", AppTheme.GOLD], ["富豪", AppTheme.WHITE], ["平民", AppTheme.DIM], ["乞丐", AppTheme.RED]]
			for i in steps.size():
				var bx := 60.0 + i * 185.0
				var by := 30.0 + i * 42.0
				var panel := ColorRect.new()
				panel.color = Color(0.13, 0.13, 0.28)
				panel.position = Vector2(bx, by)
				panel.custom_minimum_size = Vector2(150, 40)
				panel.size = Vector2(150, 40)
				_fig.add_child(panel)
				var lb := _label(18, steps[i][1])
				lb.text = str(steps[i][0])
				lb.position = Vector2(35, 6)
				panel.add_child(lb)
			_fig_label("乞丐 —2张→ 大富豪      平民 —1张→ 富豪", Vector2(70, 230), AppTheme.GOLD, 17)
		6:
			var rows := [["大富豪", "+2", AppTheme.GOLD], ["富豪", "+1", AppTheme.GREEN], ["平民", "-1", AppTheme.DIM], ["乞丐", "-2", AppTheme.RED]]
			for i in rows.size():
				var y := 18.0 + i * 58.0
				var panel := ColorRect.new()
				panel.color = Color(0.13, 0.13, 0.28)
				panel.position = Vector2(220, y)
				panel.custom_minimum_size = Vector2(360, 48)
				panel.size = Vector2(360, 48)
				_fig.add_child(panel)
				var lb := _label(18, AppTheme.WHITE)
				lb.text = str(rows[i][0])
				lb.position = Vector2(40, 10)
				panel.add_child(lb)
				var pts := _label(22, rows[i][2])
				pts.text = str(rows[i][1])
				pts.position = Vector2(280, 8)
				panel.add_child(pts)
			_fig_label("3 局总分定胜负", Vector2(310, 260), AppTheme.GOLD, 17)
		7:
			_fig_label("① 点选手牌(亮起金框)", Vector2(150, 30), AppTheme.WHITE, 17)
			_fig_label("② 点【出牌】打出, 或【不要】跳过", Vector2(150, 80), AppTheme.WHITE, 17)
			_fig_label("③ 联机时: 底部表情栏 / 聊天框随时可用", Vector2(150, 130), AppTheme.WHITE, 17)
			_fig_label("④ 倒计时归零自动托管, 不会卡死牌局", Vector2(150, 180), AppTheme.WHITE, 17)
			_fig_label("中途退出: 点【返回大厅】需二次确认", Vector2(150, 240), AppTheme.DIM, 15)


func _nav_button(text: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size = Vector2(180, 46)
	b.add_theme_font_size_override("font_size", 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.22, 0.9)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = Color(AppTheme.GOLD, 0.5)
	b.add_theme_stylebox_override("normal", sb)
	var hv := sb.duplicate()
	hv.border_color = AppTheme.GOLD
	b.add_theme_stylebox_override("hover", hv)
	return b


func _label(size: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", color)
	return lb
