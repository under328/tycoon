## 新手引导：翻页式图文教程。风格与游戏一致（和风×霓虹 + 程序化卡面图示）。
## 用法: var t = TutorialScript.new(); add_child(t); t.closed.connect(...)
extends Control

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")

signal closed

const CardsGd = preload("res://src/rules/cards.gd")
const CardViewScript = preload("res://src/client/ui/card_view.gd")


# 每页: [标题, 正文(多行), 图示编号]
const PAGES := [
	["欢迎来到大富豪", "你的目标只有一个:【尽快出完手牌】\n最先出完的是【大富豪】, 依次为富豪、贫民, 最后一名是【大贫民】\n按所选回合数对战(一回合=3 局), 全部回合结束后统一结算", 0],
	["牌的大小", "点序从 3 最小到 2 次大, 【王】最大\n最强单牌: 【黑桃3】单出时比王大\n花色不分大小: 红桃 A 和黑桃 A 一样大", 1],
	["牌型与8切", "出牌必须【同牌型、同张数、点更大】, 或选择不要\n只有四种牌型: 单张 / 对子 / 三条 / 四条(触发革命)\n打出任何带 8 的组合, 立即清桌并继续领出(8切)", 2],
	["王牌是万能牌", "王单出时是最大的单张; 和其他牌一起出时会自动补位:\n3♥ + 王 = 对 3;  3♥ 3♦ + 王 = 三条 3\n注意: 两张王不能组成对子; 最后一张若是王, 不能单出获胜", 3],
	["革命", "打出【四条】立刻触发革命: 反转只作用于数字牌——3 变成最大, 2 变成最小\n王依然大, ♠3 单出仍比王大\n四条还是炸弹, 能压任何非四条牌型。劣势局的翻盘号角!", 4],
	["身份与换牌", "下一局开始前换牌: 大贫民把最大的 2 张交给大富豪\n贫民把最大的 1 张交给富豪; 收到牌的强者需【自选等量牌】返还\n另外: 上局大富豪若没保住第一, 直接跌到大贫民(一落千丈)!\n作为补偿, 大贫民手握下一局的先出权", 5],
	["计分", "单局积分: 大富豪 +2, 富豪 +1, 贫民 -1, 大贫民 -2\n各局积分累加, 打完全部回合后统一结算", 6],
	["界面操作", "点选手牌使其亮起, 再点【出牌】; 跟不上就点【不要】\n回合倒计时结束会自动托管; 联机时还能发表情和聊天\n随时点右上角【规则】可以翻看本教程", 7],
]

var page := 0
var _title: Label
var _body: Label
var _fig: Control
var _prev_btn: Button
var _next_btn: Button
var _close_lbl: Label
var _dots: Array = []


func _ready() -> void:
	# 父级是 Control(已按安全区内缩) → FULL_RECT 锚点自适应父级,
	# 不再手动赋视口尺寸(那会溢出父级边界, 手机上按钮超界)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 代码 new 出的 Control 挂 Control 父下锚点不自动求值(size 停留 0×0) → 显式铺满
	size = get_parent_area_size()

	var bg := ColorRect.new()
	bg.color = AppTheme.BG  # 不透明全屏页: 不透出主菜单背景
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


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

	var prev := AppTheme.nav_button("◀ 上一页", Vector2(340, 650))
	prev.pressed.connect(func() -> void:
		if page > 0:
			_show(page - 1))
	add_child(prev)
	_prev_btn = prev
	var next := AppTheme.nav_button("下一页 ▶", Vector2(760, 650))
	next.pressed.connect(func() -> void:
		if page < PAGES.size() - 1:
			_show(page + 1)
		else:
			_close())
	add_child(next)
	_next_btn = next

	var close := _label(20, AppTheme.DIM)
	close.text = "✕"
	close.position = Vector2(size.x - 110, 24)
	close.mouse_filter = Control.MOUSE_FILTER_STOP
	close.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close())
	add_child(close)
	_close_lbl = close

	_show(0)
	Responsive.watch(self, _relayout)


## 多设备自适应: 内容列(800 宽)水平居中, 平板加高时整块下移居中, 关闭锚右上。
func _relayout() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	# 内容列宽自适应: 窄屏几乎满宽, 宽屏封顶 900 居中
	var col_w := minf(w - 80.0, 900.0)
	var cx := (w - col_w) / 2.0
	var dy := maxf(h - 720.0, 0.0) * 0.4
	var sq := h < 660.0
	_title.custom_minimum_size = Vector2(w, 50)
	_title.size = Vector2(w, 50)
	_fig.position = Vector2(cx, (96.0 if sq else 140.0) + dy)
	_fig.size = Vector2(col_w, (290.0 if sq else 300.0))
	_body.position = Vector2(cx, (402.0 if sq else 470.0) + dy)
	_body.custom_minimum_size = Vector2(col_w, 130)
	_body.size = Vector2(col_w, 130)
	_body.add_theme_font_size_override("font_size", 21 if Responsive.is_touch() else 19)
	for i in _dots.size():
		_dots[i].position = Vector2(w / 2.0 - PAGES.size() * 11.0 + i * 22.0,
				(502.0 if sq else 618.0) + dy)
	_prev_btn.position = Vector2(w / 2.0 - 300.0, (522.0 if sq else 650.0) + dy)
	_next_btn.position = Vector2(w / 2.0 + 120.0, (522.0 if sq else 650.0) + dy)
	_close_lbl.position = Vector2(w - 110.0, 24)


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
			_fig_label("最先出完手牌 → 大富豪!", Vector2(240, 230), AppTheme.GREEN, 20)
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
				{"cards": [32], "label": "单张"},
				{"cards": [16, 17], "label": "对子"},
				{"cards": [24, 25, 26], "label": "三条"},
				{"cards": [36, 37, 38, 39], "label": "四条→革命!"},
			]
			for gi in groups.size():
				var col := gi % 2
				var row := gi / 2
				var bx := 90.0 + col * 380.0
				var by := 30.0 + row * 140.0
				var cards: Array = groups[gi]["cards"]
				for ci in cards.size():
					_mini(cards[ci], Vector2(bx + ci * 40.0, by), 0.68)
				var col2 := AppTheme.RED if gi == 3 else AppTheme.DIM
				_fig_label(str(groups[gi]["label"]), Vector2(bx + 4, by + 84), col2, 16)
			_fig_label("带 8 的组合一出即清桌(8切)", Vector2(200, 268), AppTheme.GOLD, 16)
		3:
			_mini(52, Vector2(200, 40), 1.3)
			_mini(1, Vector2(330, 70), 0.9)
			_mini(2, Vector2(382, 70), 0.9)
			_fig_label("+", Vector2(302, 96), AppTheme.GOLD, 26)
			_fig_label("+", Vector2(354, 96), AppTheme.GOLD, 26)
			_fig_label("=", Vector2(444, 96), AppTheme.GOLD, 26)
			_mini(1, Vector2(474, 70), 0.9)
			_mini(2, Vector2(526, 70), 0.9)
			_mini(52, Vector2(578, 70), 0.9)
			_fig_label("三条 3", Vector2(486, 168), AppTheme.GREEN, 18)
			_fig_label("王自动补位, 缺什么补什么(两王不可成对)", Vector2(200, 224), AppTheme.DIM, 16)
			_mini(0, Vector2(640, 200), 0.75)
			_fig_label("但 ♠3 单出比王大!", Vector2(560, 288), AppTheme.RED, 15)
		4:
			_mini(0, Vector2(60, 40), 0.9)
			_fig_label("♠3 单出比王大", Vector2(24, 150), AppTheme.GOLD, 15)
			_mini(53, Vector2(170, 40), 0.9)
			_fig_label("王 仍大", Vector2(176, 150), AppTheme.DIM, 15)
			_mini(2, Vector2(300, 40), 0.9)
			_fig_label("革命后 3 最强", Vector2(272, 150), AppTheme.RED, 15)
			_mini(51, Vector2(430, 40), 0.9)
			_fig_label("2 最弱", Vector2(428, 150), AppTheme.DIM, 15)
			_mini(48, Vector2(560, 40), 0.9)
			_mini(49, Vector2(628, 40), 0.9)
			_mini(50, Vector2(696, 40), 0.9)
			_mini(51, Vector2(764, 40), 0.9)
			_fig_label("打出四条 = 革命!", Vector2(610, 150), AppTheme.RED, 17)
		5:
			var steps := [["大富豪", AppTheme.GOLD], ["富豪", AppTheme.WHITE], ["贫民", AppTheme.DIM], ["大贫民", AppTheme.RED]]
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
			_fig_label("大贫民 —2张→ 大富豪      贫民 —1张→ 富豪", Vector2(60, 230), AppTheme.GOLD, 16)
			_fig_label("收到牌的强者自选等量牌返还", Vector2(150, 262), AppTheme.DIM, 15)
		6:
			var rows := [["大富豪", "+2", AppTheme.GOLD], ["富豪", "+1", AppTheme.GREEN], ["贫民", "-1", AppTheme.DIM], ["大贫民", "-2", AppTheme.RED]]
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
			_fig_label("打完全部回合, 统一结算", Vector2(310, 260), AppTheme.GOLD, 17)
		7:
			_fig_label("① 点选手牌(亮起金框)", Vector2(150, 30), AppTheme.WHITE, 17)
			_fig_label("② 点【出牌】打出, 或【不要】跳过", Vector2(150, 80), AppTheme.WHITE, 17)
			_fig_label("③ 联机时: 底部表情栏 / 聊天框随时可用", Vector2(150, 130), AppTheme.WHITE, 17)
			_fig_label("④ 倒计时归零自动托管, 不会卡死牌局", Vector2(150, 180), AppTheme.WHITE, 17)
			_fig_label("中途退出: 点【返回大厅】需二次确认", Vector2(150, 240), AppTheme.DIM, 15)




func _label(size: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", color)
	return lb
