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
var copy_btn: Button
var save_settings_btn: Button
var status_label: Label
var chk_joker: CheckButton
var chk_revolution: CheckButton
var rounds_option: OptionButton
var stakes_option: OptionButton
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
var _ts_chip: PanelContainer   # 联机准备条: Tailscale 就绪状态 + 一键下载
var _ts_dot: ColorRect
var _ts_state_lbl: Label
var _ts_dl_btn: Button
var _ts_apk_url := ""          # 运行时解析的 Android APK 直链(缓存)

const TS_PKGS_URL := "https://pkgs.tailscale.com/stable/"
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
var _view := "entry"              # 当前视图: entry=入口页 / room=房间页
var _layouts := {}                # ctrl -> {"entry": [pos,mode,dy], "room": [...]}
var _entry_set: Array = []        # 入口页可见控件
var _room_set: Array = []         # 房间页可见控件
var room_title_lbl: Label         # 房间页: 房间码标题
var invite_lbl: Label             # 房间页: 服务器 IP + 邀请引导
var _seat_cards: Array = []       # 房间页: 4 张座位卡 {name, tag}
var _host_panel_wanted := false   # 本机开房信息卡显隐意愿(跨视图管理)
var _last_room_code := ""
var _conn_fails := 0
var _loopback_hint := false   # 当前状态栏显示的是回环指引(随环境变化刷新)


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
	_refresh_ts_chip()
	var ts_timer := Timer.new()
	ts_timer.wait_time = 3.0
	ts_timer.timeout.connect(_refresh_ts_chip)
	add_child(ts_timer)
	ts_timer.start()
	_auto_connect()


## Tailscale 就绪检测: 有 CGNAT 段地址即就绪; 未就绪显示一键下载。
## 定时刷新 — 用户从商店装完回来, 状态自动转绿, 无需重启。
func _refresh_ts_chip() -> void:
	var ips: Array = Responsive.tailscale_ips()
	var ready := not ips.is_empty()
	_ts_dot.color = COLOR_GREEN if ready else COLOR_RED
	if ready:
		_ts_state_lbl.text = "✓ 已就绪  %s" % str(ips[0])
		_ts_state_lbl.add_theme_color_override("font_color", COLOR_GREEN)
	else:
		_ts_state_lbl.text = "未安装或未启动"
		_ts_state_lbl.add_theme_color_override("font_color", COLOR_DIM)
	_ts_dl_btn.visible = not ready
	# 回环指引随环境刷新(Tailscale 装好/掉线时, 指引文案同步更新)
	if _loopback_hint:
		_show_loopback_hint_for(ready)


## 多设备自适应(1280x720 设计基准, 见 responsive.gd):
## PC 任意窗形 / 手机横屏(多余宽度) / 平板横屏(多余高度) 统一重排。
## 双视图锚定: 入口页(_reg)与房间页(_reg_room)各自一张坐标表,
## _relayout 只排当前视图的控件。
func _reg(n: Control, mode: String, dy_frac := 0.0) -> void:
	_reg_at("entry", n, n.position, mode, dy_frac)
	if not _entry_set.has(n):
		_entry_set.append(n)


func _reg_room(n: Control, pos: Vector2, mode: String, dy_frac := 0.0) -> void:
	_reg_at("room", n, pos, mode, dy_frac)
	if not _room_set.has(n):
		_room_set.append(n)


func _reg_at(view: String, n: Control, pos: Vector2, mode: String, dy_frac: float) -> void:
	if not _layouts.has(n):
		_layouts[n] = {}
	_layouts[n][view] = [pos, mode, dy_frac]


## 视图切换: 入口页/房间页互斥显隐(返回按钮/状态栏两页共享)
func _apply_view(v: String) -> void:
	_view = v
	# 双集共享的控件(返回按钮/状态栏)只换位置与文案, 始终可见 —
	# 若参与两个互斥显隐循环, 后一个循环会把它们藏掉(回归过一次)
	for c in _entry_set:
		if not _room_set.has(c):
			c.visible = v == "entry"
	for c in _room_set:
		if not _entry_set.has(c):
			c.visible = v == "room"
	if host_panel != null:
		host_panel.visible = _host_panel_wanted and v == "entry"
	# 左上角按钮: 入口页=回主菜单; 房间页=离开房间
	back_btn.text = "离开房间" if v == "room" else "← 主菜单"
	back_btn.visible = true
	status_label.visible = true
	_relayout()


func _relayout() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	# 有符号压缩: 手机紧凑视口(高<720/宽<1280)时底部/右缘控件向内收
	var extra := w - 1280.0
	var eh := h - 720.0
	var shift := extra * 0.45
	for n in _layouts:
		var lay: Array = _layouts[n].get(_view, [])
		if lay.is_empty():
			continue
		var dx := 0.0
		if str(lay[1]) == "center":
			dx = shift
		elif str(lay[1]) == "right":
			dx = extra
		(n as Control).position = Vector2(lay[0]) + Vector2(dx, float(lay[2]) * eh)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		go_back()


## 每次进入联机页面清空上次输入的房间码(输入框跨页面残留, 避免误入旧房)
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible and code_edit != null:
		code_edit.text = ""


## 返回: 房间页=离开房间回入口; 入口页=回主菜单
## (左上角按钮 / ESC / Android 返回键共用)
func go_back() -> void:
	if _view == "room":
		_exit_room()
		return
	net.leave_room()
	back_to_menu.emit()


func _auto_connect() -> void:
	var host: String = AppMode.address if AppMode.address_from_cli else GameSettings.host
	var port: int = AppMode.port if AppMode.port_from_cli else GameSettings.host_port
	_conn_fails = 0
	_loopback_hint = false
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
		if a == "127.0.0.1" or a == "localhost" or a == "::1":
			net.disconnect_all()
			_loopback_hint = true
			_show_loopback_hint()
			return
		_probe_reachable(a, int(net.port) + 1))


## 可达性探测: 服务器在 游戏端口+1 上有 HTTP 状态服务, 能否打开它 =
## "对方主机 + 服务器是否在运行"的可靠判据(与联机同一条通路)。
## 远程主机不可达时 ENet 30 秒都不报错, 用探测尽快给出诊断清单。
func _probe_reachable(host: String, http_port: int) -> void:
	var http := HTTPRequest.new()
	http.timeout = 6.0
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		http.queue_free()
		if net == null or not is_inside_tree() or net._is_connected():
			return
		_loopback_hint = false  # 探测结论取代回环指引, 不被就绪条刷新覆盖
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			_set_status("主机在线, 联机协商中… 若 15 秒后仍未进入, 请点【连接】重试", COLOR_GOLD)
		else:
			_set_status("暂时无法到达 %s(仍在自动重试)—— 请确认:\n① 对方已点【本机开房】(服务器需在运行)\n② 双方 Tailscale 已连接(联机准备条均为 ✓)\n③ 对方防火墙已放行 UDP %d" % [host, int(net.port)], COLOR_RED))
	var err := http.request("http://%s:%d/status" % [host, http_port])
	if err != OK:
		http.queue_free()
		_set_status("无法发起连接探测, 请检查网络", COLOR_RED)


## 回环指引(引导而非故障, 用金色不报警): 按 Tailscale 就绪状态给出
## 对应出路, 并随联机准备条的状态变化自动刷新
func _show_loopback_hint() -> void:
	_show_loopback_hint_for(Responsive.tailscale_ips().size() > 0)


func _show_loopback_hint_for(ready: bool) -> void:
	_loopback_hint = true
	if ready:
		_set_status("Tailscale 已就绪 — 点【本机开房】创建房间, 把邀请码发给朋友;\n或点【粘贴邀请码, 一键加入】朋友的主机。", COLOR_GOLD)
	else:
		_set_status("未连接服务器(127.0.0.1 只是本机地址)。\n先在【联机准备】安装并登录 Tailscale, 再【本机开房】或【粘贴邀请码】开局。", COLOR_GOLD)


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
	_loopback_hint = false
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
func _enter_room() -> void:
	_apply_view("room")
	for b: Button in [fill_btn, start_btn, copy_btn, save_settings_btn]:
		b.disabled = false


func _exit_room() -> void:
	_apply_view("entry")
	if net != null:
		net.leave_room()
	hide_host_panel()
	show_status("", COLOR_GOLD)


## 本机开房信息卡(替代多行状态文字)
func show_host_panel(ip: String) -> void:
	_host_panel_wanted = true
	host_panel.visible = true
	status_label.visible = false
	host_ip_value.text = ip if ip != "" else "未检测到 Tailscale\n(请安装并登录 Tailscale)"
	host_dl_btn.visible = ip == ""
	host_dl_btn.text = "⬇ 一键下载\n(%s)" % Responsive.platform_label()


func hide_host_panel() -> void:
	_host_panel_wanted = false
	host_panel.visible = false
	status_label.visible = true


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
	_loopback_hint = false
	_set_status("正在连接 %s:%d …" % [host, port], COLOR_DIM)


## 版本更新地址: 优先从当前联机主机的内置下载服务获取
## (http://主机:健康端口/download — 与联机同一条 Tailscale/局域网通路,
## 国内无障碍); 无主机信息时退回配置的 DOWNLOAD_URL。
func _update_url() -> String:
	if net != null and str(net.address) != "":
		return "http://%s:%d/download" % [str(net.address), int(net.port) + 1]
	return GameSettings.DOWNLOAD_URL


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
		go_back())

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
	update_btn.position = Vector2(40, 200)
	update_btn.visible = false
	update_btn.pressed.connect(func() -> void:
		Audio.play("click")
		OS.shell_open(_update_url()))
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

	# ── 房间页: 标题 / 邀请行 / 座位卡 ──
	room_title_lbl = AppTheme.make_label(26, COLOR_GOLD)
	room_title_lbl.text = "房间"
	room_title_lbl.position = Vector2(150, 20)
	add_child(room_title_lbl)
	invite_lbl = AppTheme.make_label(14, COLOR_DIM)
	invite_lbl.position = Vector2(150, 62)
	invite_lbl.custom_minimum_size = Vector2(660, 24)
	add_child(invite_lbl)
	for i in 4:
		var sp := PanelContainer.new()
		var sp_sb := AppTheme.flat(Color(0.08, 0.08, 0.18, 0.92),
				Color(AppTheme.GOLD, 0.45), 12, 2)
		sp_sb.content_margin_left = 12
		sp_sb.content_margin_right = 12
		sp_sb.content_margin_top = 12
		sp_sb.content_margin_bottom = 12
		sp.add_theme_stylebox_override("panel", sp_sb)
		sp.position = Vector2(150 + i * 166, 104)
		sp.custom_minimum_size = Vector2(150, 150)
		add_child(sp)
		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 10)
		sp.add_child(sv)
		var cap := AppTheme.make_label(13, AppTheme.DIM)
		cap.text = "座位 %d" % (i + 1)
		sv.add_child(cap)
		var nm := AppTheme.make_label(17, AppTheme.WHITE)
		nm.text = "(空位)"
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.custom_minimum_size = Vector2(124, 0)
		sv.add_child(nm)
		var tag := AppTheme.make_label(13, COLOR_DIM)
		sv.add_child(tag)
		_seat_cards.append({"panel": sp, "name": nm, "tag": tag})

	# 房主操作按钮
	fill_btn = AppTheme.make_button("空位加AI", Vector2(140, 46), 17)
	fill_btn.position = Vector2(150, 470)
	fill_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.fill_bots())
	add_child(fill_btn)

	kick_btn = AppTheme.make_button("移除玩家", Vector2(140, 46), 17)
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
	start_btn.position = Vector2(310, 470)
	start_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.start_game())
	add_child(start_btn)
	copy_btn = AppTheme.make_button("复制邀请码", Vector2(140, 46), 17)
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
	chk_joker = _check("带王", Vector2(830, 340))
	chk_revolution = _check("革命", Vector2(830, 380))
	stakes_lbl = AppTheme.make_label(15, COLOR_WHITE)
	stakes_lbl.text = "输赢"
	stakes_lbl.position = Vector2(830, 414)
	add_child(stakes_lbl)
	stakes_option = OptionButton.new()
	for item: Array in [["小 ×1", 1], ["中 ×2", 2], ["大 ×3", 3]]:
		stakes_option.add_item(str(item[0]), int(item[1]))
	stakes_option.select(0)
	stakes_option.position = Vector2(880, 410)
	stakes_option.custom_minimum_size = Vector2(90, 34)
	add_child(stakes_option)
	rounds_lbl = AppTheme.make_label(15, COLOR_WHITE)
	rounds_lbl.text = "回合数"
	rounds_lbl.position = Vector2(830, 460)
	add_child(rounds_lbl)
	rounds_option = OptionButton.new()
	for r: Array in [[3, "一回合"], [9, "三回合"], [15, "五回合"]]:
		rounds_option.add_item(str(r[1]) + "（%d 局）" % r[0], r[0])
	rounds_option.select(0)
	rounds_option.position = Vector2(880, 456)
	rounds_option.custom_minimum_size = Vector2(90, 34)
	add_child(rounds_option)
	save_settings_btn = AppTheme.make_button("保存设置", Vector2(140, 38), 15)
	save_settings_btn.position = Vector2(830, 496)
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

	# 状态(左列独立分区: 联机准备条之下、更新按钮之下, 自动换行多行)
	status_label = AppTheme.make_label(15, COLOR_DIM)
	status_label.position = Vector2(40, 258)
	status_label.custom_minimum_size = Vector2(368, 90)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(status_label)

	# 联机准备条: Tailscale 就绪检测(定时刷新) + 按设备一键下载
	_ts_chip = PanelContainer.new()
	var ts_sb := AppTheme.flat(Color(0.06, 0.06, 0.14, 0.92), Color(AppTheme.GOLD, 0.4), 10, 1)
	ts_sb.content_margin_left = 14
	ts_sb.content_margin_right = 14
	ts_sb.content_margin_top = 10
	ts_sb.content_margin_bottom = 10
	_ts_chip.add_theme_stylebox_override("panel", ts_sb)
	_ts_chip.position = Vector2(40, 108)
	_ts_chip.custom_minimum_size = Vector2(368, 0)
	add_child(_ts_chip)
	var ts_row := HBoxContainer.new()
	ts_row.add_theme_constant_override("separation", 10)
	_ts_chip.add_child(ts_row)
	_ts_dot = ColorRect.new()
	_ts_dot.custom_minimum_size = Vector2(12, 12)
	_ts_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ts_row.add_child(_ts_dot)
	var ts_col := VBoxContainer.new()
	ts_col.add_theme_constant_override("separation", 2)
	ts_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ts_row.add_child(ts_col)
	var ts_title := AppTheme.make_label(14, AppTheme.DIM)
	ts_title.text = "联机准备 · Tailscale"
	ts_col.add_child(ts_title)
	_ts_state_lbl = AppTheme.make_label(15, COLOR_WHITE)
	_ts_state_lbl.text = "检测中…"
	ts_col.add_child(_ts_state_lbl)
	_ts_dl_btn = AppTheme.make_button(
			"⬇ 一键下载\n(%s)" % Responsive.platform_label(), Vector2(120, 0), 13)
	_ts_dl_btn.pressed.connect(_open_ts_download)
	ts_row.add_child(_ts_dl_btn)

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
	var hp_dl := AppTheme.make_button("⬇ 一键下载", Vector2(220, 38), 15)
	hp_dl.visible = false
	hp_dl.pressed.connect(_open_ts_download)
	hp_box.add_child(hp_dl)
	host_dl_btn = hp_dl

	# ── 入口页锚定 ──
	_reg(back_btn, "left")
	_reg(update_btn, "left")
	_reg(_ts_chip, "left")
	_reg(host_panel, "left", 0.1)
	_reg(status_label, "left", 0.1)
	_reg(title_lbl, "center")
	_reg(nick_lbl, "center")
	_reg(nickname_edit, "center")
	_reg(quick_btn, "center")
	_reg(create_btn, "center")
	_reg(paste_btn, "center")
	_reg(host_btn, "center")
	_reg(code_edit, "center")
	_reg(join_btn, "center")
	_reg(server_lbl, "right")
	_reg(host_edit, "right")
	_reg(port_edit, "right")
	_reg(connect_btn, "right")
	_reg(help_btn, "right")

	# ── 房间页锚定(独立子页面布局) ──
	_reg_room(back_btn, Vector2(20, 16), "left")
	_reg_room(status_label, Vector2(150, 386), "center", 0.08)
	_reg_room(room_title_lbl, Vector2(150, 20), "center")
	_reg_room(copy_btn, Vector2(660, 16), "center")
	_reg_room(invite_lbl, Vector2(150, 62), "center")
	for i in 4:
		_reg_room(_seat_cards[i]["panel"], Vector2(150 + i * 166, 104), "center")
	_reg_room(fill_btn, Vector2(150, 306), "center", 0.05)
	_reg_room(kick_btn, Vector2(310, 306), "center", 0.05)
	_reg_room(start_btn, Vector2(470, 306), "center", 0.05)
	_reg_room(rules_lbl, Vector2(830, 66), "right")
	_reg_room(chk_joker, Vector2(830, 100), "right")
	_reg_room(chk_revolution, Vector2(830, 140), "right")
	_reg_room(stakes_lbl, Vector2(830, 184), "right")
	_reg_room(stakes_option, Vector2(880, 180), "right")
	_reg_room(rounds_lbl, Vector2(830, 224), "right")
	_reg_room(rounds_option, Vector2(880, 220), "right")
	_reg_room(save_settings_btn, Vector2(830, 264), "right")
	for i in _emoji_btns.size():
		_reg_room(_emoji_btns[i], Vector2(150 + i * 52, 662), "left", 1.0)  # 贴底缘

	for b: Button in [quick_btn, create_btn, join_btn, fill_btn, start_btn, copy_btn, save_settings_btn]:
		b.disabled = true
	host_btn.disabled = false
	connect_btn.disabled = false
	paste_btn.disabled = false
	_apply_view("entry")


## 打开 Tailscale 下载(两个下载按钮共用)。
## Android 不跳 Google Play(国内无法访问): 运行时从官方包列表解析
## 最新通用版 APK 直链(pkgs.tailscale.com 官方源), 解析失败退回列表页。
func _open_ts_download() -> void:
	Audio.play("click")
	if not OS.has_feature("android"):
		OS.shell_open(Responsive.tailscale_url())
		return
	if _ts_apk_url != "":
		OS.shell_open(_ts_apk_url)
		return
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	http.request_completed.connect(func(result: int, code: int,
			_headers: PackedStringArray, body: PackedByteArray) -> void:
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_open_ts_fallback()
			return
		var re := RegEx.new()
		re.compile("tailscale-android-universal-[0-9.]+\\.apk")
		var m := re.search(body.get_string_from_utf8())
		if m == null:
			_open_ts_fallback()
			return
		_ts_apk_url = TS_PKGS_URL + m.get_string(0)
		OS.shell_open(_ts_apk_url))
	var err := http.request(TS_PKGS_URL)
	if err != OK:
		http.queue_free()
		_open_ts_fallback()


func _open_ts_fallback() -> void:
	OS.shell_open(TS_PKGS_URL + "#android")  # 列表页锚点, 用户手点 APK 链接


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
		_loopback_hint = false
		_set_status("已连接! 选一个方式开局吧", COLOR_GREEN)
		if _auto_join_code != "":
			var join_code := _auto_join_code
			_auto_join_code = ""
			net.join_room(join_code)  # 粘贴邀请码: 连上后自动进房
		if auto_create_room:
			auto_create_room = false
			net.create_room(_gather_rules())  # 本机开房: 连上后自动建房
		for b: Button in [quick_btn, create_btn, join_btn]:
			b.disabled = false)
	net.connection_failed.connect(func() -> void:
		_conn_fails += 1
		# 手机连 127.0.0.1 = 连自己, 那里没有服务器; 停止无休止重试, 给出明确指引
		# (本机开房流程不受影响: 它带 auto_create_room 标记且连的是内嵌服务器)
		var loopback: bool = str(net.address) in ["127.0.0.1", "localhost", "::1"]
		if loopback and not auto_create_room:
			net.disconnect_all()
			_show_loopback_hint()
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
	_refresh_invite(state)
	_apply_settings(state.get("settings", {}))
	_enter_room()
	var host_seat := int(state.get("host_seat", -1))
	kick_btn.visible = net.in_room and host_seat == net.my_seat
	# 房间页标题 + 邀请行
	room_title_lbl.text = "房间  %s" % (_last_room_code if _last_room_code != "" else "——")
	var ip_txt := ""
	if host_invite_ip != "":
		ip_txt = "服务器 %s · " % host_invite_ip
	invite_lbl.text = ip_txt + "点【复制邀请码】发给朋友 → 朋友点【粘贴邀请码, 一键加入】"
	# 座位卡
	for i in 4:
		var nm: Label = _seat_cards[i]["name"]
		var tag: Label = _seat_cards[i]["tag"]
		nm.text = "(空位)"
		nm.add_theme_color_override("font_color", COLOR_DIM)
		tag.text = "等待加入"
		tag.add_theme_color_override("font_color", COLOR_DIM)
		for p in state.get("players", []):
			if int(p.get("seat", -1)) != i:
				continue
			if bool(p.get("empty", true)):
				break
			nm.text = str(p.get("name", ""))
			nm.add_theme_color_override("font_color", COLOR_WHITE)
			var bits: Array = []
			if i == host_seat:
				bits.append("房主")
			if bool(p.get("is_bot", false)):
				bits.append("AI")
			elif not bool(p.get("online", true)):
				bits.append("离线·AI 代管")
			tag.text = " · ".join(bits)
			tag.add_theme_color_override("font_color",
					COLOR_GOLD if i == host_seat else COLOR_DIM)
			break
	var host: bool = host_seat == int(net.my_seat)
	fill_btn.disabled = not host
	start_btn.disabled = not host


func _set_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)


func _check(text: String, pos: Vector2) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.position = pos
	c.button_pressed = true   # 默认开启(与服务端默认规则一致: 带王/革命)
	add_child(c)
	return c
