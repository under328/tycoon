## 联机帮助: 居中弹窗式图文说明(三步开房 / 朋友加入 / 主机须知 / 常见问题)。
## 实底面板背景 + 滚动内容 + 图示按面板宽度等比缩放(窄屏不重叠)。
## 用法: var h = LobbyHelpScript.new(); add_child(h); h.closed.connect(...)
extends Control

signal closed

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")

# 每页: [标题, 正文(bbcode), 图示编号]
const PAGES := [
	["三步开始联机",
		"[color=#7dd87d]同一 WiFi[/color]: 房主点 [color=#e0a83c]【本机开房】[/color], 朋友点 [color=#e0a83c]【搜索附近主机】[/color]\n直接点击房间加入——最简单, 无需安装任何东西。\n[color=#7dd87d]异地联机[/color](准备一次性): 每台设备安装并登录 [color=#e0a83c]Tailscale[/color](免费),\n本页左侧【联机准备】自动检测, 未安装可一键下载。\n然后: ①房主【本机开房】 ②【复制邀请码】发给朋友 ③朋友【粘贴邀请码, 一键加入】。", 0],
	["朋友怎么连进来",
		"[color=#7dd87d]方式一 · 同一 WiFi(最简单)[/color]: 双方连同一个 WiFi,\n房主【本机开房】后, 朋友在联机页点 [color=#e0a83c]【搜索附近主机】[/color],\n看到房间直接点击即加入——无需任何账号和安装。\n[color=#7dd87d]方式二 · 异地联机[/color]: 所有设备安装 [color=#e0a83c]Tailscale[/color](免费)并用【同一个账号】登录,\n朋友点【粘贴邀请码, 一键加入】即可, 跨城市/跨运营商都没有问题。", 1],
	["主机专用说明",
		"【本机开房】会在后台启动一台内置服务器, 你的客户端自动连入本机。\n点完后信息卡会列出你的全部地址: [color=#e0a83c]局域网 192.168.x.x[/color](同 WiFi 朋友用)\n和 [color=#e0a83c]Tailscale 100.x.x.x[/color](异地朋友用), 邀请码自动包含全部地址。\n服务器地址会被记住; 朋友连你, 改的是[color=#e0a83c]朋友自己[/color]的【服务器】地址。\n房主权限: 空位加AI / 开始游戏 / 移除玩家 / 修改规则(开局前)。", 2],
	["常见问题",
		"[color=#e0a83c]搜索不到附近主机?[/color] 确认双方连同一个 WiFi、路由器未开「AP 隔离」;\n也可在【服务器】手动填主机信息卡的局域网 IP 后点【连接】。\n[color=#e0a83c]一直「无法连接」?[/color] 确认主机在线、双方 Tailscale 都已登录(异地时)。\n[color=#e0a83c]被踢出并提示版本?[/color] 主机的游戏版本更新了, 重新下载进入即可。\n[color=#e0a83c]对局中掉线?[/color] 自动凭凭证重连回座(掉线期间 AI 代打), 无需任何操作。", 3],
]

const FIG_W := 960.0   # 图示设计宽度(内部绝对坐标以此为基准, 整体等比缩放)
const FIG_H := 280.0

var page := 0
var _title: Label
var _body: RichTextLabel
var _fig: Control
var _fig_holder: Control
var _dots: Array = []
var _page_lbl: Label
var _prev_btn: Button
var _next_btn: Button
var _close_lbl: Label
var _panel: PanelContainer
var _scroll: ScrollContainer


func _ready() -> void:
	# 父级是 Control(已按安全区内缩) → FULL_RECT 锚点自适应父级
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = get_parent_area_size()  # 代码 new 挂 Control 父下锚点不自动求值

	# 半透明遮罩(点击空白关闭)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close())
	add_child(dim)

	# 居中实底弹窗面板
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	var sb := AppTheme.flat(AppTheme.PANEL, AppTheme.GOLD, 16, 2)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 16
	sb.content_margin_bottom = 18
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)

	# 头行: 标题 + ✕
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	_title = _label(26, AppTheme.GOLD)
	_title.text = PAGES[0][0]
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_title)
	# 关闭用悬浮的「关闭 ✕」Label(见 _relayout 定位), 头行不再放按钮

	# 滚动内容: 正文 + 图示(窄屏/矮屏时滚动查看, 内容不重叠)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.add_theme_font_size_override("normal_font_size", 18)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_body)
	_fig_holder = Control.new()
	_fig_holder.custom_minimum_size = Vector2(FIG_W, FIG_H)
	_fig_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_fig_holder)
	_fig = Control.new()
	_fig.size = Vector2(FIG_W, FIG_H)
	_fig_holder.add_child(_fig)

	# 底部: 圆点 + 翻页(固定面板底, 不随内容滚动)
	var dot_row := HBoxContainer.new()
	dot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dot_row.add_theme_constant_override("separation", 10)
	v.add_child(dot_row)
	for i in PAGES.size():
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size = Vector2(12, 12)
		dot_row.add_child(dot)
		_dots.append(dot)
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 16)
	v.add_child(nav)
	var prev := AppTheme.make_button("◀ 上一页", Vector2(150, 44), 15)
	prev.pressed.connect(func() -> void:
		if page > 0:
			_show(page - 1))
	nav.add_child(prev)
	_prev_btn = prev
	_page_lbl = _label(15, AppTheme.DIM)
	_page_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nav.add_child(_page_lbl)
	var next := AppTheme.make_button("下一页 ▶", Vector2(150, 44), 15)
	next.pressed.connect(func() -> void:
		if page < PAGES.size() - 1:
			_show(page + 1)
		else:
			_close())
	nav.add_child(next)
	_next_btn = next

	# 关闭 ✕(悬浮面板右上; Label 避免被遍历误按)
	var close_lbl := _label(16, AppTheme.DIM)
	close_lbl.text = "关闭 ✕"
	close_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	close_lbl.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close())
	add_child(close_lbl)
	_close_lbl = close_lbl

	_show(0)
	Responsive.watch(self, _relayout)


## 多设备自适应: 面板尺寸钳在视口内; 图示按面板内宽等比缩放(不重叠不越界)
func _relayout() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	var pw := minf(1000.0, w - 24.0)
	var ph := minf(700.0, h - 24.0)
	_panel.custom_minimum_size = Vector2(pw, ph)
	var inner_w := pw - 48.0
	var fs := minf(1.0, inner_w / FIG_W)
	_fig.scale = Vector2(fs, fs)
	_fig_holder.custom_minimum_size = Vector2(FIG_W * fs, FIG_H * fs)
	_close_lbl.position = Vector2((w - pw) / 2.0 + pw - 92.0, (h - ph) / 2.0 + 12.0)


func _close() -> void:
	closed.emit()
	queue_free()


func _show(p: int) -> void:
	page = p
	_title.text = tr(PAGES[p][0])
	_body.text = tr(PAGES[p][1])
	_page_lbl.text = "%d / %d" % [p + 1, PAGES.size()]
	for i in _dots.size():
		_dots[i].color = AppTheme.GOLD if i == p else AppTheme.DIM
	_build_fig(int(PAGES[p][2]))
	if _scroll != null:
		_scroll.scroll_vertical = 0   # 翻页回到内容顶部


func _clear_fig() -> void:
	for c in _fig.get_children():
		c.queue_free()


func _box(pos: Vector2, box_size: Vector2, text: String, color: Color,
		fsize := 16, fill := Color(0.13, 0.13, 0.28)) -> void:
	var panel := ColorRect.new()
	panel.color = fill
	panel.position = pos
	panel.custom_minimum_size = box_size
	panel.size = box_size
	_fig.add_child(panel)
	var lb := _label(fsize, color)
	lb.text = tr(text)
	lb.position = Vector2(10, box_size.y / 2.0 - fsize * 0.7)
	panel.add_child(lb)


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


func _build_fig(kind: int) -> void:
	_clear_fig()
	match kind:
		0:  # 三步总览
			var steps := [
				["① 本机开房(自动建房)", AppTheme.GOLD], ["② 复制邀请码 → 发给朋友", AppTheme.WHITE],
				["③ 朋友粘贴邀请码, 一键加入", AppTheme.GREEN],
			]
			for i in steps.size():
				_box(Vector2(240, 20 + i * 84), Vector2(560, 60), str(steps[i][0]),
						steps[i][1], 18)
				if i < steps.size() - 1:
					_line(Vector2(520, 80 + i * 84), Vector2(520, 104 + i * 84))
		1:  # 朋友加入: 设备连线图
			_box(Vector2(60, 90), Vector2(240, 90), "朋友 A\n填 100.x.x.x → 连接", AppTheme.WHITE, 16)
			_box(Vector2(380, 70), Vector2(240, 100), "主机(你) 100.y.y.y\n本机开房 · 房间码", AppTheme.GOLD, 16)
			_box(Vector2(700, 90), Vector2(240, 90), "朋友 B\n填 100.x.x.x → 连接", AppTheme.WHITE, 16)
			_line(Vector2(300, 135), Vector2(380, 120))
			_line(Vector2(620, 120), Vector2(700, 135))
			_text("所有设备装 Tailscale", Vector2(150, 210))
			_text("tailscale.com 免费下载", Vector2(600, 210))
			_text("朋友在大厅右上角【服务器】里填 IP", Vector2(240, 250), AppTheme.GOLD, 16)
		2:  # 主机流程链
			var flow := ["本机开房", "创建房间", "复制房间码", "空位加AI", "开始游戏"]
			for i in flow.size():
				var col := i % 3
				var row := i / 3
				_box(Vector2(60 + col * 300, 30 + row * 120), Vector2(250, 70),
						str(flow[i]), AppTheme.WHITE, 17)
				if i < flow.size() - 1 and col < 2:
					_line(Vector2(310 + col * 300, 65), Vector2(356 + col * 300, 65))
			_text("房主专属: 开始游戏 / 空位加AI / 移除玩家 / 规则设置", Vector2(140, 200),
					AppTheme.GOLD, 16)
		3:  # FAQ 图: 状态色说明
			var rows := [
				["无法连接 → 看红字提示与目标地址", AppTheme.RED],
				["已连接 → 三大按钮解锁", AppTheme.GREEN],
				["版本不符 → 弹出更新按钮", AppTheme.GOLD],
				["掉线 → 自动重连回座", AppTheme.WHITE],
			]
			for i in rows.size():
				_text(str(rows[i][0]), Vector2(180, 30 + i * 52), rows[i][1], 17)
			_text("连接失败会每 2 秒自动重试, 无需手动操作", Vector2(180, 250),
					AppTheme.DIM, 15)




func _label(size: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", color)
	return lb
