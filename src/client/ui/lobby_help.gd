## 联机帮助: 翻页式图文说明(三步开房 / 朋友加入 / 主机须知 / 常见问题)。
## 用法: var h = LobbyHelpScript.new(); add_child(h); h.closed.connect(...)
extends Control

signal closed

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")

# 每页: [标题, 正文(bbcode), 图示编号]
const PAGES := [
	["三步开始联机",
		"[color=#7dd87d]准备(一次性)[/color]: 每台设备安装并登录 [color=#e0a83c]Tailscale[/color](免费)。\n本页左侧 [color=#e0a83c]【联机准备】[/color]会自动检测状态, 未安装可 [color=#e0a83c]一键下载[/color](按设备直达)。\n[color=#e0a83c]① 房主[/color] 点 [color=#e0a83c]【本机开房】[/color], 会自动建房并显示你的 100.x.x.x 地址。\n[color=#e0a83c]② 房主[/color] 点 [color=#e0a83c]【复制邀请码】[/color], 把邀请码发给朋友。\n[color=#e0a83c]③ 朋友[/color] 点 [color=#e0a83c]【粘贴邀请码, 一键加入】[/color], 自动连主机进房间。", 0],
	["朋友怎么连进来",
		"所有设备安装 [color=#e0a83c]Tailscale[/color](免费), 并用【同一个账号】登录,\n即可组成同一虚拟局域网, 每台设备获得 100.x.x.x 专用地址。\n朋友操作: 右上角【服务器】填主机的 100.x.x.x → 【连接】→ 状态变绿 → 输入房间码【加入】。\n不在同一 WiFi 也能玩, 跨城市/跨运营商都没有问题。", 1],
	["主机专用说明",
		"【本机开房】会在后台启动一台内置服务器, 你的客户端自动连入本机。\n点完后状态栏会显示你的 Tailscale IP(100.x.x.x), 把它和房间码一起发给朋友。\n服务器地址会被记住; 朋友连你, 改的是[color=#e0a83c]朋友自己[/color]的【服务器】地址。\n房主权限: 空位加AI / 开始游戏 / 移除玩家 / 修改规则(开局前)。", 2],
	["常见问题",
		"[color=#e0a83c]一直「无法连接」?[/color] 确认主机在线、双方 Tailscale 都已登录、填的是 100.x.x.x。\n[color=#e0a83c]被踢出并提示版本?[/color] 主机的游戏版本更新了, 重新下载进入即可。\n[color=#e0a83c]对局中掉线?[/color] 自动凭凭证重连回座(掉线期间 AI 代打), 无需任何操作。\n[color=#e0a83c]想换服务器?[/color] 右上角改地址点【连接】, 地址会自动保存。", 3],
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
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var frame := ReferenceRect.new()
	frame.border_color = Color(AppTheme.GOLD, 0.55)
	frame.border_width = 2.0
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.editor_only = false
	add_child(frame)

	_title = _label(32, AppTheme.GOLD)
	_title.position = Vector2(0, 46)
	_title.custom_minimum_size = Vector2(size.x, 46)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_active = false
	_body.position = Vector2(160, 120)
	_body.custom_minimum_size = Vector2(960, 150)
	_body.size = Vector2(960, 150)
	_body.add_theme_font_size_override("normal_font_size", 18)
	add_child(_body)

	_fig = Control.new()
	_fig.position = Vector2(160, 300)
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


## 多设备自适应: 内容列(960 宽)水平居中, 平板加高时整块下移居中, 关闭锚右上。
func _relayout() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	var cx := (w - 960.0) / 2.0
	var dy := maxf(h - 720.0, 0.0) * 0.4
	_title.custom_minimum_size = Vector2(w, 46)
	_title.size = Vector2(w, 46)
	_body.position = Vector2(cx, 120 + dy)
	_fig.position = Vector2(cx, 300 + dy)
	for i in _dots.size():
		_dots[i].position = Vector2(w / 2.0 - PAGES.size() * 11.0 + i * 22.0, 610 + dy)
	_prev_btn.position = Vector2(w / 2.0 - 300.0, 646 + dy)
	_next_btn.position = Vector2(w / 2.0 + 120.0, 646 + dy)
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


func _box(pos: Vector2, box_size: Vector2, text: String, color: Color,
		fsize := 16, fill := Color(0.13, 0.13, 0.28)) -> void:
	var panel := ColorRect.new()
	panel.color = fill
	panel.position = pos
	panel.custom_minimum_size = box_size
	panel.size = box_size
	_fig.add_child(panel)
	var lb := _label(fsize, color)
	lb.text = text
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
	lb.text = text
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
		3:  # FAQ 图: 问号 + 状态色说明
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
