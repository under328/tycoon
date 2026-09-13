## 联机大厅 v2: 三步向导式新手流程 + ESC 随时返回主菜单。
extends Control

signal start_game
signal back_to_menu
signal host_requested

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const NetNodeGd = preload("res://src/protocol/net_node.gd")
const LobbyHelpScript = preload("res://src/client/ui/lobby_help.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")

const EMOJIS := ["👍", "😂", "😱", "😭", "😡", "👏", "🤔", "🎉"]

const COLOR_BG := Color("14142b")
const COLOR_GOLD := Color("e0a83c")
const COLOR_WHITE := Color("f0f0f0")
const COLOR_DIM := Color("8a8ab0")
const COLOR_GREEN := Color("7dd87d")
const COLOR_RED := Color("ff6b6b")

var net: Node = null
var nickname_edit: LineEdit
var code_edit: LineEdit
var quick_btn: Button
var create_btn: Button
var join_btn: Button
var fill_btn: Button
var start_btn: Button
var leave_btn: Button
var copy_btn: Button
var save_settings_btn: Button
var status_label: Label
var room_label: Label
var stats_label: Label
var chk_joker: CheckButton
var chk_revolution: CheckButton
var rounds_option: OptionButton
var stakes_option: OptionButton
var _last_room_code := ""
var host_edit: LineEdit
var port_edit: LineEdit
var connect_btn: Button
var host_btn: Button
var update_btn: Button
var paste_btn: Button
var _emoji_btns: Array = []
var host_panel: PanelContainer
var host_ip_value: Label
var host_dl_btn: Button      # 未检测到 Tailscale 时显示的下载入口
var host_invite_ip := ""   # 本机开房时对外可用的 Tailscale IP
var auto_create_room := false # 开房后自动创建房间
var _auto_join_code := ""     # 粘贴邀请码后待自动加入的房间码
var _invite_code := ""        # 当前房间的完整邀请码
var kick_btn: Button
var help_btn: Button
var back_btn: Button
var title_lbl: Label
var nick_lbl: Label
var server_lbl: Label
var rules_lbl: Label
var stakes_lbl: Label
var rounds_lbl: Label
var _room_ui: Array = []          # 仅房间内显示的控件
var _in_room := false             # 是否处于房间内(驱动房间 UI 显隐)
var _conn_fails := 0
var _placed: Array = []           # 自适应锚定表: [控件, 基准坐标, 模式, 高度分配比]


func setup(p_net: Node) -> void:
	net = p_net


func create_and_place(text: String, pos: Vector2, min_size: Vector2, font_size: int) -> Button:
	var b := AppTheme.make_button(text, min_size, font_size)
	b.position = pos
	add_child(b)
	return b


func _ready() -> void:
	if net == null:
		net = NetNodeGd.new()
		net.name = "NetLobbyFallback"
		net.setup(false)
		add_child(net)
	_build_ui()
	Responsive.watch(self, _relayout)
	_bind_net()
	_auto_connect()


## 多设备自适应(1280x720 设计基准, 见 responsive.gd):
## PC 任意窗形 / 手机横屏(多余宽度) / 平板横屏(多余高度) 统一重排。
func _reg(n: Control, mode: String, dy_frac := 0.0) -> void:
	_placed.append([n, n.position, mode, dy_frac])


func _relayout() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	var extra := maxf(w - 1280.0, 0.0)
	var eh := maxf(h - 720.0, 0.0)
	var shift := extra * 0.45
	for e: Array in _placed:
		var ctrl: Control = e[0]
		var dx := 0.0
		if str(e[2]) == "center":
			dx = shift
		elif str(e[2]) == "right":
			dx = extra
		ctrl.position = Vector2(e[1]) + Vector2(dx, float(e[3]) * eh)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		net.leave_room()
		back_to_menu.emit()


func _auto_connect() -> void:
	var host: String = AppMode.address if AppMode.address_from_cli else GameSettings.host
	var port: int = AppMode.port if AppMode.port_from_cli else GameSettings.host_port
	_conn_fails = 0
	_set_status("正在连接 %s:%d …" % [host, port], COLOR_DIM)
	net.auto_reconnect = true
	net.connect_to(host, port)
	_arm_loopback_guard()


## 回环地址快速止损: 4 秒仍未连上 → 停止重试并给出联机指引。
## (手机默认设置会连 127.0.0.1, 那里没有服务器; ENet 自身的失败信号
## 要 ~30 秒才到, 玩家等不起, 需要立刻给出"本机开房/填主机IP"指引)
func _arm_loopback_guard() -> void:
	var timer := get_tree().create_timer(4.0)
	timer.timeout.connect(func() -> void:
		if auto_create_room or net == null or not is_inside_tree():
			return  # 本机开房流程自己管理连接
		if net._is_connected():
			return
		var a := str(net.address)
		if a != "127.0.0.1" and a != "localhost" and a != "::1":
			return
		net.disconnect_all()
		_set_status("127.0.0.1 是本机回环地址, 这里没有服务器。\n① 点【本机开房】自己当主机\n② 或右上角填主机 IP(Tailscale 100.x.x.x)点【连接】\n③ 或点【粘贴邀请码, 一键加入】", COLOR_RED))


## 供 main(本机开房) 推送状态/主机 IP 信息
func show_status(text: String, color: Color = COLOR_GOLD) -> void:
	_set_status(text, color)


## 解析邀请码文本: 返回 {ip, port, code} 或 {}(无效)。
static func parse_invite(text: String) -> Dictionary:
	var t := text.strip_edges()
	var parts := t.split("|")
	if parts.size() == 4 and parts[0] == "TC" and parts[1] != "":
		var port := 24565
		if parts[2] != "":
			port = int(parts[2]) if parts[2].is_valid_int() else 0
		if port < 1 or port > 65535:
			return {}
		return {"ip": parts[1], "port": port, "code": parts[3]}
	return {}


## 粘贴邀请码(TC|IP|端口|房间码) → 自动连接主机并加入房间
func _paste_join() -> void:
	var inv := parse_invite(DisplayServer.clipboard_get())
	if inv.is_empty():
		_set_status("剪贴板中没有有效的邀请码(请先复制房主发的邀请信息)", COLOR_RED)
		return
	var ip: String = str(inv["ip"])
	var port: int = int(inv["port"])
	var code: String = str(inv["code"])
	var g := get_node_or_null("/root/GameSettings")
	if g != null:
		g.host = ip
		g.host_port = port
		g.save_settings()
	host_edit.text = ip
	port_edit.text = str(port)
	_auto_join_code = code
	_conn_fails = 0
	net.disconnect_all()
	net.auto_reconnect = true
	net.connect_to(ip, port)
	_set_status("正在连接主机 %s:%d, 连上后自动进房…" % [ip, port], COLOR_DIM)


## 生成本房间邀请码(本机开房时用 Tailscale IP; 连远程服务器时用服务器地址)
func _refresh_invite(state: Dictionary) -> void:
	var code := str(state.get("room_code", ""))
	if code == "":
		_invite_code = ""
		return
	var ip := host_invite_ip if host_invite_ip != "" else str(GameSettings.host)
	_invite_code = "TC|%s|%d|%s" % [ip, int(GameSettings.host_port), code]


## 房间内专属 UI 的显隐切换
func _set_room_ui(v: bool) -> void:
	for n in _room_ui:
		n.visible = v
	if v:
		for b: Button in [fill_btn, start_btn, leave_btn, copy_btn, save_settings_btn]:
			b.disabled = false


func _enter_room() -> void:
	_in_room = true
	_set_room_ui(true)


func _exit_room() -> void:
	_in_room = false
	_set_room_ui(false)
	if net != null:
		net.leave_room()
	hide_host_panel()
	show_status("", COLOR_GOLD)


## 本机开房信息卡(替代多行状态文字)
func show_host_panel(ip: String) -> void:
	host_panel.visible = true
	status_label.visible = false
	stats_label.visible = false
	host_ip_value.text = ip if ip != "" else "未检测到 Tailscale\n(请安装并登录 Tailscale)"
	host_dl_btn.visible = ip == ""


func hide_host_panel() -> void:
	host_panel.visible = false
	status_label.visible = true
	stats_label.visible = true


func _manual_connect() -> void:
	var host := host_edit.text.strip_edges()
	var port_text := port_edit.text.strip_edges()
	var port := int(port_text) if port_text.is_valid_int() else 0
	if host == "":
		_set_status("请输入服务器地址", COLOR_RED)
		return
	if port < 1 or port > 65535:
		_set_status("端口需为 1-65535 的数字", COLOR_RED)
		return
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		gs.host = host
		gs.host_port = port
		gs.save_settings()
	_conn_fails = 0
	net.disconnect_all()
	net.auto_reconnect = true
	net.connect_to(host, port)
	_arm_loopback_guard()
	_set_status("正在连接 %s:%d …" % [host, port], COLOR_DIM)


func _build_ui() -> void:
	theme = AppTheme.build_theme()

	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 返回主菜单按钮
	back_btn = create_and_place("← 主菜单", Vector2(20, 16), Vector2(110, 36), 15)
	back_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.leave_room()
		back_to_menu.emit())

	# 标题
	title_lbl = AppTheme.make_label(28, COLOR_GOLD)
	title_lbl.text = "联机对战"
	title_lbl.position = Vector2(150, 22)
	add_child(title_lbl)

	# 昵称
	nick_lbl = AppTheme.make_label(15, COLOR_WHITE)
	nick_lbl.text = "昵称"
	nick_lbl.position = Vector2(150, 70)
	add_child(nick_lbl)
	nickname_edit = LineEdit.new()
	nickname_edit.position = Vector2(200, 66)
	nickname_edit.custom_minimum_size = Vector2(220, 36)
	nickname_edit.size = Vector2(220, 36)
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		nickname_edit.text = str(gs.nickname)
	nickname_edit.add_theme_font_size_override("font_size", 16)
	add_child(nickname_edit)

	# 三大主按钮(大尺寸, 好按)
	quick_btn = AppTheme.make_button("🎲  快速匹配", Vector2(300, 52), 19)
	quick_btn.position = Vector2(450, 96)
	quick_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_save_nickname()
		net.quick_match(_gather_rules()))
	add_child(quick_btn)

	create_btn = AppTheme.make_button("🏠  创建房间", Vector2(300, 52), 19)
	create_btn.position = Vector2(450, 160)
	create_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_save_nickname()
		net.create_room(_gather_rules()))
	add_child(create_btn)

	# 邀请码一键加入: 粘贴房主发的 TC|IP|端口|房间码, 自动连接并进房
	paste_btn = AppTheme.make_button("📋 粘贴邀请码, 一键加入", Vector2(300, 52), 18)
	paste_btn.position = Vector2(450, 228)
	paste_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_save_nickname()
		_paste_join())
	add_child(paste_btn)

	# 手动输房间码(已连接时使用)
	code_edit = LineEdit.new()
	code_edit.position = Vector2(450, 294)
	code_edit.custom_minimum_size = Vector2(200, 44)
	code_edit.size = Vector2(200, 44)
	code_edit.placeholder_text = "或输入房间码"
	var gs4 := get_node_or_null("/root/GameSettings")
	if gs4 != null and str(gs4.last_room_code) != "":
		code_edit.text = str(gs4.last_room_code)  # 预填最近房间码, 方便回房
	code_edit.add_theme_font_size_override("font_size", 18)
	add_child(code_edit)
	join_btn = AppTheme.make_button("加入", Vector2(62, 44), 18)
	join_btn.position = Vector2(658, 294)
	join_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_save_nickname()
		net.join_room(code_edit.text.strip_edges()))
	add_child(join_btn)

	# 本机开房: 同进程内嵌服务器并自动建房, 朋友粘贴邀请码即可加入
	host_btn = AppTheme.make_button("🏠 本机开房(当主机)", Vector2(264, 52), 17)
	host_btn.position = Vector2(770, 228)
	host_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_save_nickname()
		host_requested.emit())
	add_child(host_btn)

	# 发现新版本: 版本握手不匹配时显示, 点击打开下载页
	update_btn = AppTheme.make_button("⬇ 发现新版本, 点击更新", Vector2(260, 46), 16)
	update_btn.position = Vector2(40, 220)
	update_btn.visible = false
	update_btn.pressed.connect(func() -> void:
		Audio.play("click")
		OS.shell_open(GameSettings.DOWNLOAD_URL))
	add_child(update_btn)

	# 联机帮助(图文, 四页: 三步开房/朋友加入/主机须知/常见问题)
	help_btn = AppTheme.make_button("? 联机帮助", Vector2(150, 36), 15)
	help_btn.position = Vector2(990, 138)
	help_btn.pressed.connect(func() -> void:
		Audio.play("click")
		var help := LobbyHelpScript.new()
		help.closed.connect(func() -> void: help.queue_free())
		add_child(help))
	add_child(help_btn)

	# 服务器地址区(右上)
	server_lbl = AppTheme.section_label("服务器")
	server_lbl.position = Vector2(830, 66)
	add_child(server_lbl)
	host_edit = LineEdit.new()
	host_edit.position = Vector2(830, 94)
	host_edit.custom_minimum_size = Vector2(200, 36)
	host_edit.size = Vector2(200, 36)
	host_edit.placeholder_text = "IP 或域名"
	var gs2 := get_node_or_null("/root/GameSettings")
	if gs2 != null:
		host_edit.text = str(gs2.host)
	host_edit.add_theme_font_size_override("font_size", 15)
	add_child(host_edit)
	port_edit = LineEdit.new()
	port_edit.position = Vector2(1040, 94)
	port_edit.custom_minimum_size = Vector2(90, 36)
	port_edit.size = Vector2(90, 36)
	var gs3 := get_node_or_null("/root/GameSettings")
	port_edit.text = str(int(gs3.host_port) if gs3 != null else 24565)
	port_edit.add_theme_font_size_override("font_size", 15)
	add_child(port_edit)
	connect_btn = AppTheme.make_button("连接", Vector2(140, 36), 15)
	connect_btn.position = Vector2(830, 138)
	connect_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_manual_connect())
	add_child(connect_btn)

	# 房间面板
	room_label = AppTheme.make_label(17, COLOR_WHITE)
	_room_ui.append(room_label)
	room_label.position = Vector2(150, 310)
	room_label.custom_minimum_size = Vector2(700, 140)
	add_child(room_label)

	# 房主操作按钮
	fill_btn = AppTheme.make_button("空位加AI", Vector2(140, 46), 17)
	_room_ui.append(fill_btn)
	fill_btn.position = Vector2(150, 470)
	fill_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.fill_bots())
	add_child(fill_btn)

	kick_btn = AppTheme.make_button("移除玩家", Vector2(140, 46), 17)
	_room_ui.append(kick_btn)
	kick_btn.position = Vector2(10, 470)
	kick_btn.visible = false
	kick_btn.pressed.connect(func() -> void:
		Audio.play("click")
		var target := _kickable_seat()
		if target >= 0:
			net.kick_seat(target)
		else:
			_set_status("没有可移除的玩家(仅房主可移除非自己的人类玩家)", COLOR_RED))
	add_child(kick_btn)
	start_btn = AppTheme.make_button("开始游戏", Vector2(140, 46), 17)
	_room_ui.append(start_btn)
	start_btn.position = Vector2(310, 470)
	start_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.start_game())
	add_child(start_btn)
	leave_btn = AppTheme.make_button("离开房间", Vector2(140, 46), 17)
	_room_ui.append(leave_btn)
	leave_btn.position = Vector2(470, 470)
	leave_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_exit_room())
	add_child(leave_btn)
	copy_btn = AppTheme.make_button("复制邀请码", Vector2(140, 46), 17)
	_room_ui.append(copy_btn)
	copy_btn.position = Vector2(630, 470)
	copy_btn.pressed.connect(func() -> void:
		Audio.play("click")
		var payload := _invite_code if _invite_code != "" else _last_room_code
		if payload == "":
			return
		DisplayServer.clipboard_set(payload)
		_set_status("已复制: " + payload + " , 发给朋友即可加入", COLOR_GREEN))
	add_child(copy_btn)

	# 规则设置
	rules_lbl = AppTheme.section_label("规则设置")
	rules_lbl.position = Vector2(830, 310)
	add_child(rules_lbl)
	_room_ui.append(rules_lbl)
	chk_joker = _check("带王", Vector2(830, 340))
	_room_ui.append(chk_joker)
	chk_revolution = _check("革命", Vector2(830, 380))
	_room_ui.append(chk_revolution)
	stakes_lbl = AppTheme.make_label(15, COLOR_WHITE)
	stakes_lbl.text = "输赢"
	stakes_lbl.position = Vector2(830, 414)
	add_child(stakes_lbl)
	_room_ui.append(stakes_lbl)
	stakes_option = OptionButton.new()
	for item: Array in [["小 ×1", 1], ["中 ×2", 2], ["大 ×3", 3]]:
		stakes_option.add_item(str(item[0]), int(item[1]))
	stakes_option.select(0)
	stakes_option.position = Vector2(880, 410)
	stakes_option.custom_minimum_size = Vector2(90, 34)
	add_child(stakes_option)
	_room_ui.append(stakes_option)
	rounds_lbl = AppTheme.make_label(15, COLOR_WHITE)
	rounds_lbl.text = "局数"
	rounds_lbl.position = Vector2(830, 460)
	add_child(rounds_lbl)
	_room_ui.append(rounds_lbl)
	rounds_option = OptionButton.new()
	for r: int in [1, 3, 5]:
		rounds_option.add_item(str(r) + " 局", r)
	rounds_option.select(1)
	rounds_option.position = Vector2(880, 456)
	rounds_option.custom_minimum_size = Vector2(90, 34)
	add_child(rounds_option)
	_room_ui.append(rounds_option)
	save_settings_btn = AppTheme.make_button("保存设置", Vector2(140, 38), 15)
	save_settings_btn.position = Vector2(830, 496)
	_room_ui.append(save_settings_btn)
	save_settings_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.set_settings(_gather_rules()))
	add_child(save_settings_btn)

	# 表情
	for i in EMOJIS.size():
		var id := i
		var eb := AppTheme.make_button(EMOJIS[i], Vector2(44, 40), 20)
		eb.position = Vector2(830 + i * 52, 550)
		eb.pressed.connect(func() -> void:
			Audio.play("pop")
			net.send_emoji(id))
		add_child(eb)
		_emoji_btns.append(eb)
		_room_ui.append(eb)

	# 状态
	status_label = AppTheme.make_label(15, COLOR_DIM)
	status_label.position = Vector2(40, 260)
	status_label.custom_minimum_size = Vector2(360, 80)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(status_label)

	stats_label = AppTheme.make_label(15, COLOR_DIM)
	stats_label.position = Vector2(40, 350)
	stats_label.custom_minimum_size = Vector2(360, 40)
	stats_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	stats_label.add_theme_constant_override("shadow_offset_x", 1)
	stats_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(stats_label)

	# 主机信息卡(本机开房后显示: Tailscale IP + 加入指引)
	host_panel = PanelContainer.new()
	var hp_sb := AppTheme.flat(Color(0.06, 0.06, 0.14, 0.96), Color(AppTheme.GOLD, 0.55), 12, 2)
	hp_sb.content_margin_left = 16
	hp_sb.content_margin_right = 16
	hp_sb.content_margin_top = 12
	hp_sb.content_margin_bottom = 12
	host_panel.add_theme_stylebox_override("panel", hp_sb)
	host_panel.position = Vector2(40, 240)
	host_panel.custom_minimum_size = Vector2(360, 0)
	host_panel.visible = false
	add_child(host_panel)
	var hp_box := VBoxContainer.new()
	hp_box.add_theme_constant_override("separation", 8)
	host_panel.add_child(hp_box)
	var hp_title := AppTheme.make_label(18, AppTheme.GOLD)
	hp_title.text = "本机服务器已启动"
	hp_box.add_child(hp_title)
	host_ip_value = AppTheme.make_label(20, COLOR_WHITE)
	host_ip_value.text = "-"
	host_ip_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host_ip_value.custom_minimum_size = Vector2(328, 0)  # 自动换行必须有宽度约束, 否则容器测高爆炸
	hp_box.add_child(host_ip_value)
	var hp_hint := AppTheme.make_label(14, COLOR_DIM)
	hp_hint.text = "把上面的 IP 发给朋友\n朋友在右上【服务器】填 IP 点【连接】\n再输房间码【加入】"
	hp_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hp_hint.custom_minimum_size = Vector2(328, 0)
	hp_box.add_child(hp_hint)
	var hp_dl := AppTheme.make_button("⬇ 下载 Tailscale", Vector2(220, 38), 15)
	hp_dl.visible = false
	hp_dl.pressed.connect(func() -> void:
		Audio.play("click")
		OS.shell_open("https://tailscale.com/download"))
	hp_box.add_child(hp_dl)
	host_dl_btn = hp_dl

	# 自适应锚定注册(基准坐标 = 创建时的 position; 模式含义见 _reg/_relayout)
	_reg(back_btn, "left")
	_reg(update_btn, "left")
	_reg(host_panel, "left", 0.1)
	_reg(status_label, "left", 0.1)
	_reg(stats_label, "left", 0.15)
	_reg(title_lbl, "center")
	_reg(nick_lbl, "center")
	_reg(nickname_edit, "center")
	_reg(quick_btn, "center")
	_reg(create_btn, "center")
	_reg(paste_btn, "center")
	_reg(host_btn, "center")
	_reg(code_edit, "center")
	_reg(join_btn, "center")
	_reg(room_label, "center", 0.2)
	_reg(server_lbl, "right")
	_reg(host_edit, "right")
	_reg(port_edit, "right")
	_reg(connect_btn, "right")
	_reg(help_btn, "right")
	_reg(rules_lbl, "right")
	_reg(chk_joker, "right")
	_reg(chk_revolution, "right")
	_reg(stakes_lbl, "right")
	_reg(stakes_option, "right")
	_reg(rounds_lbl, "right")
	_reg(rounds_option, "right")
	_reg(save_settings_btn, "right")
	for i in _emoji_btns.size():
		_reg(_emoji_btns[i], "right", 1.0)  # 表情栏贴底缘(平板加高时跟随)
	_reg(fill_btn, "center", 0.45)
	_reg(kick_btn, "center", 0.45)
	_reg(start_btn, "center", 0.45)
	_reg(leave_btn, "center", 0.45)
	_reg(copy_btn, "center", 0.45)

	for b: Button in [quick_btn, create_btn, join_btn, fill_btn, start_btn, leave_btn, copy_btn, save_settings_btn]:
		b.disabled = true
	host_btn.disabled = false
	connect_btn.disabled = false
	paste_btn.disabled = false
	_set_room_ui(false)


## 房主可移除的第一个人类座位(不能移除自己/机器人)
func _kickable_seat() -> int:
	for p in net.last_room_state.get("players", []):
		if int(p.get("seat", -1)) == net.my_seat:
			continue
		if not bool(p.get("empty", true)) and not bool(p.get("is_bot", false)):
			return int(p["seat"])
	return -1


func _save_nickname() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		gs.nickname = nickname_edit.text.strip_edges()
		if gs.nickname == "":
			gs.nickname = "玩家"
		gs.save_settings()


func _bind_net() -> void:
	net.connected_ok.connect(func() -> void:
		update_btn.visible = false
		_conn_fails = 0
		_set_status("已连接! 选一个方式开局吧", COLOR_GREEN)
		if _auto_join_code != "":
			var join_code := _auto_join_code
			_auto_join_code = ""
			net.join_room(join_code)  # 粘贴邀请码: 连上后自动进房
		if auto_create_room:
			auto_create_room = false
			net.create_room(_gather_rules())  # 本机开房: 连上后自动建房
		for b: Button in [quick_btn, create_btn, join_btn]:
			b.disabled = false
		net.request_stats())
	net.connection_failed.connect(func() -> void:
		_conn_fails += 1
		# 手机连 127.0.0.1 = 连自己, 那里没有服务器; 停止无休止重试, 给出明确指引
		# (本机开房流程不受影响: 它带 auto_create_room 标记且连的是内嵌服务器)
		var loopback: bool = str(net.address) in ["127.0.0.1", "localhost", "::1"]
		if loopback and not auto_create_room:
			net.disconnect_all()
			_set_status("127.0.0.1 是本机回环地址, 这里没有服务器。\n① 点【本机开房】自己当主机\n② 或右上角填主机 IP(Tailscale 100.x.x.x)点【连接】\n③ 或点【粘贴邀请码, 一键加入】", COLOR_RED)
			return
		_set_status("无法连接 %s:%d（第 %d 次），自动重试中…\n确认服务器已启动、地址正确、防火墙放行"
				% [net.address, net.port, _conn_fails], COLOR_RED))
	net.server_disconnected.connect(func() -> void:
		_exit_room()
		_set_status("与服务器断开, 自动重连中…", COLOR_RED))
	net.errored.connect(func(code: String, msg: String) -> void:
		if code != "not_connected":
			_set_status("错误 %s: %s" % [code, msg], COLOR_RED))
	net.kicked_off.connect(func(reason: String) -> void:
		_exit_room()
		if reason == "version":
			_set_status("服务器版本更高, 请更新客户端", COLOR_RED)
			update_btn.visible = true
		else:
			_set_status("已被移出房间(%s)" % reason, COLOR_RED))
	net.stats_updated.connect(func(entry: Dictionary) -> void:
		if entry.is_empty():
			stats_label.text = "战绩: 暂无"
		else:
			stats_label.text = "战绩: %d 场 / 胜 %d / %+d 分" % [
				int(entry.get("matches", 0)), int(entry.get("wins", 0)),
				int(entry.get("total_points", 0))])
	net.room_state.connect(_on_room_state)
	net.view_changed.connect(func(_view: Dictionary) -> void:
		start_game.emit())


func _gather_rules() -> Dictionary:
	return {
		"with_joker": chk_joker.button_pressed,
		"revolution": chk_revolution.button_pressed,
		"rounds": rounds_option.get_selected_id(),
		"stakes": stakes_option.get_selected_id(),
	}


func _apply_settings(settings: Dictionary) -> void:
	chk_joker.set_pressed_no_signal(bool(settings.get("with_joker", true)))
	chk_revolution.set_pressed_no_signal(bool(settings.get("revolution", true)))
	var st := clampi(int(settings.get("stakes", 1)), 1, 3)
	for i in stakes_option.item_count:
		if int(stakes_option.get_item_id(i)) == st:
			stakes_option.select(i)
	var rounds := int(settings.get("rounds", 3))
	for i in rounds_option.item_count:
		if int(rounds_option.get_item_id(i)) == rounds:
			rounds_option.select(i)


func _on_room_state(state: Dictionary) -> void:
	_last_room_code = str(state.get("room_code", ""))
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and str(gs.last_room_code) != _last_room_code:
		gs.last_room_code = _last_room_code  # 记住最近房间码, 下次进大厅预填
		gs.save_settings()
	_refresh_invite(state)
	_apply_settings(state.get("settings", {}))
	_enter_room()
	hide_host_panel()
	kick_btn.visible = net.in_room and int(state.get("host_seat", -1)) == net.my_seat
	var lines: Array = []
	if host_invite_ip != "":
		lines.append("服务器IP: %s  (发朋友)" % host_invite_ip)
	lines.append("房间码: %s  (发给朋友)" % _last_room_code)
	for p in state["players"]:
		if bool(p.get("empty", false)):
			lines.append("  座位%d:(空位)" % (int(p["seat"]) + 1))
			continue
		var mark := "房主 " if int(p["seat"]) == int(state.get("host_seat", 0)) else ""
		var on := "" if bool(p.get("online", true)) else "(AI)"
		var bot := "[AI] " if bool(p.get("is_bot", false)) else ""
		lines.append("  座位%d: %s%s%s%s" % [
			int(p["seat"]) + 1, mark, bot, str(p.get("name", "")), on])
	room_label.text = "\n".join(lines)
	var host: bool = int(state.get("host_seat", -1)) == int(net.my_seat)
	fill_btn.disabled = not host
	start_btn.disabled = not host
	leave_btn.disabled = false


func _set_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)


func _check(text: String, pos: Vector2) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.position = pos
	add_child(c)
	return c
