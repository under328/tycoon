## 普通模式规则说明: 翻页式图文(目标与身份 / 核心规则 / 回合与结算)。
## 与 rogue_help 同一工艺: 图示区用面板/连线拼出说明卡。
extends Control

signal closed

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")

const PAGES := [
	["普通模式 · 目标与身份",
		"目标只有一个: [color=#7dd87d]尽快出完手牌[/color]!\n"
		+ "出完的先后决定身份 —— [color=#e0a83c]大富豪 → 富豪 → 贫民 → 大贫民[/color],\n"
		+ "身份带来不同积分, 多回合累积后统一结算。", 0],
	["普通模式 · 核心规则", "三条改变牌局走向的核心规则:", 1],
	["普通模式 · 回合与结算", "回合制对战, 多局累积定胜负:", 2],
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
	_title.text = tr(PAGES[p][0])
	_body.text = tr(PAGES[p][1])
	for i in _dots.size():
		_dots[i].color = AppTheme.GOLD if i == p else AppTheme.DIM
	_build_fig(int(PAGES[p][2]))


func _text(text: String, pos: Vector2, color: Color, fsize: int) -> void:
	var lb := _label(fsize, color)
	lb.text = tr(text)
	lb.position = pos
	_fig.add_child(lb)


func _label(size_num: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size_num)
	lb.add_theme_color_override("font_color", color)
	return lb


func _build_fig(kind: int) -> void:
	for c in _fig.get_children():
		c.queue_free()
	match kind:
		0:  # 身份链: 大富豪 → 富豪 → 贫民 → 大贫民
			var ids := [["大富豪", "+2", AppTheme.GOLD], ["富豪", "+1", AppTheme.WHITE],
					["贫民", "-1", Color("9fb8e8")], ["大贫民", "-2", Color("ff8896")]]
			for i in ids.size():
				var panel := PanelContainer.new()
				var sb := AppTheme.flat(Color(0.13, 0.13, 0.28), ids[i][2], 8, 1)
				panel.add_theme_stylebox_override("panel", sb)
				panel.position = Vector2(140 + i * 180, 60)
				panel.custom_minimum_size = Vector2(150, 90)
				_fig.add_child(panel)
				var v := VBoxContainer.new()
				v.alignment = BoxContainer.ALIGNMENT_CENTER
				panel.add_child(v)
				var nm := _label(19, ids[i][2])
				nm.text = str(ids[i][0])
				nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				v.add_child(nm)
				var pt := _label(17, AppTheme.WHITE)
				pt.text = str(ids[i][1])
				pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				v.add_child(pt)
				if i < ids.size() - 1:
					var ar := _label(20, AppTheme.GOLD)
					ar.text = "▶"
					ar.position = Vector2(140 + i * 180 + 152, 88)
					_fig.add_child(ar)
			_text("出完先后定身份, 积分多回合累积", Vector2(300, 200),
					AppTheme.GOLD, 16)
		1:  # 核心规则三卡: 换牌 / 革命 / 8切
			var rules := [
				["强制换牌", "大贫民→大富豪 2 张\n贫民→富豪 1 张"],
				["革命", "四条即革命\n大小顺序颠倒"],
				["8切", "打出含 8 的牌\n清空桌面续领"],
			]
			for i in rules.size():
				var panel := PanelContainer.new()
				var sb := AppTheme.flat(Color(0.10, 0.10, 0.24, 0.96),
						Color(AppTheme.GOLD, 0.7), 8, 1)
				sb.content_margin_left = 10
				sb.content_margin_right = 10
				sb.content_margin_top = 8
				sb.content_margin_bottom = 8
				panel.add_theme_stylebox_override("panel", sb)
				panel.position = Vector2(60 + i * 320, 40)
				panel.custom_minimum_size = Vector2(280, 130)
				_fig.add_child(panel)
				var v := VBoxContainer.new()
				v.alignment = BoxContainer.ALIGNMENT_CENTER
				panel.add_child(v)
				var nm := _label(18, AppTheme.GOLD)
				nm.text = str(rules[i][0])
				nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				v.add_child(nm)
				var ds := _label(12, AppTheme.WHITE)
				ds.text = str(rules[i][1])
				ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				v.add_child(ds)
			_text("三条规则环环相扣: 换牌定强弱 · 革命翻大小 · 8切抢节奏",
					Vector2(240, 220), AppTheme.GOLD, 16)
		2:  # 回合与结算: 一回合=3局, 多回合统一结算
			var flow := [["第 1 局", AppTheme.WHITE], ["第 2 局", AppTheme.WHITE],
					["第 3 局", AppTheme.WHITE], ["统一结算", AppTheme.GOLD]]
			for i in flow.size():
				var panel := PanelContainer.new()
				var sb := AppTheme.flat(Color(0.10, 0.10, 0.24, 0.96),
						Color(AppTheme.GOLD, 0.6) if i == 3 else Color(1, 1, 1, 0.2), 8, 1)
				panel.add_theme_stylebox_override("panel", sb)
				panel.position = Vector2(100 + i * 200, 50)
				panel.custom_minimum_size = Vector2(160, 74)
				_fig.add_child(panel)
				var v := VBoxContainer.new()
				v.alignment = BoxContainer.ALIGNMENT_CENTER
				panel.add_child(v)
				var nm := _label(16, AppTheme.WHITE)
				nm.text = str(flow[i][0])
				nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				v.add_child(nm)
			_text("每局按身份计分, 全部回合结束后统一结算\n胜者多拿钻石 —— 大富豪 +2 / 富豪 +1",
					Vector2(280, 200), AppTheme.GOLD, 16)
