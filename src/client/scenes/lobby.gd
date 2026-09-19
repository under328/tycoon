## 联机大厅 v2: 三步向导式新手流程 + ESC 随时返回主菜单。
extends Control

signal start_game
signal back_to_menu
signal host_requested

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const NetNodeGd = preload("res://src/protocol/net_node.gd")
const LobbyHelpScript = preload("res://src/client/ui/lobby_help.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")
const LanDisc = preload("res://src/protocol/lan_discovery.gd")

const COLOR_BG := Color("14142b")
const COLOR_GOLD := Color("e0a83c")
const COLOR_WHITE := Color("f0f0f0")
const COLOR_DIM := Color("8a8ab0")
const COLOR_GREEN := Color("7dd87d")
const COLOR_RED := Color("ff6b6b")

var net: Node = null
var fill_btn: Button
var start_btn: Button
var copy_btn: Button
var save_settings_btn: Button
var status_label: Label
var chk_joker: CheckButton
var chk_revolution: CheckButton
var rounds_option: OptionButton
var stakes_option: OptionButton
var update_btn: Button
var paste_btn: Button
var _transfer_btns: Array = []   # 房间页: 座位卡右上角转让房主按钮
var host_panel: PanelContainer
var host_ip_value: Label
var host_hint_lbl: Label      # 主机信息卡: 加入指引(随有无 Tailscale 变化)
var host_dl_btn: Button      # 未检测到 Tailscale 时显示的下载入口
var _ts_chip: PanelContainer   # 联机准备条: Tailscale 就绪状态 + 一键下载
var _ts_dot: ColorRect
var _ts_state_lbl: Label
var _ts_dl_btn: Button
var _ts_apk_url := ""          # 运行时解析的 Android APK 直链(缓存)
var rules_panel: PanelContainer   # 房间页: 规则设置卡片(金框容器整体包裹)
var stakes_row: HBoxContainer
var rounds_row: HBoxContainer
var save_row: Control             # 保存按钮行(模式联动显隐)

const TS_PKGS_URL := "https://pkgs.tailscale.com/stable/"
var host_invite_ip := ""   # 本机开房对外地址(逗号分隔候选: 局域网优先+Tailscale)
var host_invite_ips: Array = []  # 同上, 数组形式(展示用)
var auto_create_room := false # 开房后自动创建房间
var _auto_join_code := ""     # 粘贴邀请码后待自动加入的房间码
var _join_alts: Array = []    # 发现加入: 备选地址(连接失败自动切换)
var _invite_code := ""        # 当前房间的完整邀请码
# 局域网发现(同 WiFi 一键加入): 广播查询 → 主机回房间概览
var _disc: PacketPeerUDP = null
var _found := {}              # ip -> {"port": int, "rooms": Array, "seen": ms}
var _found_rows: Array = []   # found_panel 内动态行按钮
var found_panel: PanelContainer
var found_box: VBoxContainer
var discover_btn: Button
var _join_seq := 0            # 候选探测序号(用户发起新连接时作废陈旧回调)
var _cand := {"ips": [], "port": 0, "i": 0, "seq": -1}  # 多地址加入进度
var kick_btn: Button
var mode_option: OptionButton
var help_btn: Button
var host_btn: Button
var mode_lbl: Label
var back_btn: Button
var title_lbl: Label
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
	var scan_timer := Timer.new()
	scan_timer.wait_time = 3.0
	scan_timer.timeout.connect(_scan_tick)
	add_child(scan_timer)
	scan_timer.start()
	_auto_connect()


## Tailscale 就绪检测: 有 CGNAT 段地址即就绪; 未就绪显示一键下载。
## 定时刷新 — 用户从商店装完回来, 状态自动转绿, 无需重启。
## 页面不可见时跳过(每 3s 的 IP 枚举在首页/牌桌纯属空转)。
func _refresh_ts_chip() -> void:
	if _ts_state_lbl == null:
		return  # 进树时的可见性通知早于 _ready → UI 未建
	if not is_visible_in_tree():
		return
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
	# 高于 16:9 的视口(expand 拉伸逻辑高 > 720): 多余高度按 40% 基础下移,
	# 整页不再顶在上缘; 贴底控件(dy=1.0)不受影响, 底部行仍锚在底缘
	var pad := eh * 0.4 if eh > 0.0 else 0.0
	for n in _layouts:
		var lay: Array = _layouts[n].get(_view, [])
		if lay.is_empty():
			continue
		var dx := 0.0
		if str(lay[1]) == "center":
			dx = shift
		elif str(lay[1]) == "right":
			dx = extra
		var dy_frac := float(lay[2])
		var dy := pad * (1.0 - dy_frac) + dy_frac * eh
		(n as Control).position = Vector2(lay[0]) + Vector2(dx, dy)
	# ── 房间页窄屏(逻辑宽 <1100, 手机横屏)自适应 ──
	# 宽度不足两栏并排: 取消 center 负位移(否则座位/标题被推出屏幕左缘),
	# 规则设置从右列改为座位/按钮下方横排两行, 表情栏显式锚定底缘。
	if _view == "room" and w < 1100.0:
		room_title_lbl.position = Vector2(150, 22)
		copy_btn.position = Vector2(minf(330.0, w - 170.0), 14)
		invite_lbl.position = Vector2(150, 64)
		for i in 4:
			_seat_cards[i]["panel"].position = Vector2(40 + i * 160, 116)
		fill_btn.position = Vector2(40, 290)
		kick_btn.position = Vector2(190, 290)
		start_btn.position = Vector2(340, 290)
		status_label.position = Vector2(40, 360)
		rules_panel.position = Vector2(40, 424)
		rules_panel.custom_minimum_size.x = minf(380.0, w - 80.0)

	for i in 4:
		var sp: Control = _seat_cards[i]["panel"]
		_transfer_btns[i].position = sp.position + Vector2(sp.size.x - 36.0, 4.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		go_back()


## 每次进入联机页面清空上次输入的房间码(输入框跨页面残留, 避免误入旧房);
## 重新可见时立即刷新联机准备条(隐藏期间定时器空转, 不主动查地址)
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		_refresh_ts_chip()


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
	_join_seq += 1  # 作废在途的候选探测(手动连接优先)
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
			_set_status("暂时无法到达 %s(仍在自动重试)—— 请确认:\n① 对方已点【本机开房】(服务器需在运行)\n② 同一 WiFi/局域网, 或双方 Tailscale 已连接\n③ 对方防火墙已放行 UDP %d" % [host, int(net.port)], COLOR_RED))
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
		_set_status("未连接服务器(127.0.0.1 只是本机地址)。\n同一 WiFi: 点【本机开房】, 朋友在【搜索附近主机】一键加入;\n跨网联机: 安装并登录 Tailscale 后用邀请码开局。", COLOR_GOLD)


## 供 main(本机开房) 推送状态/主机 IP 信息
func show_status(text: String, color: Color = COLOR_GOLD) -> void:
	_set_status(text, color)


## 从牌桌返回大厅: 复位到入口页(离开房间语义已由桌内 _do_leave 完成,
## 这里只做页签/面板复位 —— 否则大厅残留『房间页』, 返回菜单变成两步)
func return_to_entry() -> void:
	_apply_view("entry")
	hide_host_panel()
	show_status("", COLOR_GOLD)


## 解析邀请码文本: 返回 {ips:[...], ip:首个, port, code} 或 {}(无效)。
## 地址段支持逗号分隔多候选(TC|局域网IP,TailscaleIP|端口|房码), 单地址向后兼容。
static func parse_invite(text: String) -> Dictionary:
	var t := text.strip_edges()
	var parts := t.split("|")
	if parts.size() == 4 and parts[0] == "TC" and parts[1] != "":
		var port := 24565
		if parts[2] != "":
			port = int(parts[2]) if parts[2].is_valid_int() else 0
		if port < 1 or port > 65535:
			return {}
		var ips: Array = []
		for a in parts[1].split(",", false):
			var s := a.strip_edges()
			if s != "" and not ips.has(s):
				ips.append(s)
		if ips.is_empty():
			return {}
		return {"ips": ips, "ip": ips[0], "port": port, "code": parts[3]}
	return {}


## 粘贴邀请码(TC|多地址|端口|房间码) → 找到可达地址后自动连接并进房
func _paste_join() -> void:
	var inv := parse_invite(DisplayServer.clipboard_get())
	if inv.is_empty():
		_set_status("剪贴板中没有有效的邀请码(请先复制房主发的邀请信息)", COLOR_RED)
		return
	_save_nickname()
	_join_candidates(inv["ips"], int(inv["port"]), str(inv["code"]))


## 多地址加入: 邀请码可含多个候选 IP(局域网优先, Tailscale 兜底)。
## 用主机内置 HTTP 探测(游戏端口+1)逐个快速试, 命中即 ENet 连接;
## 全部探测失败仍按首个地址发起连接(探测不通≠游戏端口不通)。
func _join_candidates(ips: Array, port: int, code: String) -> void:
	_auto_join_code = code
	_conn_fails = 0
	_loopback_hint = false
	_join_seq += 1
	_cand = {"ips": ips, "port": port, "i": 0, "seq": _join_seq}
	_try_next_candidate()


func _try_next_candidate() -> void:
	var ips: Array = _cand["ips"]
	var i := int(_cand["i"])
	var port := int(_cand["port"])
	if i >= ips.size():
		_connect_join(str(ips[0]), port,
				"未能确认主机可达, 仍尝试连接 %s:%d …" % [ips[0], port])
		return
	var ip := str(ips[i])
	_set_status("正在寻找主机…(%d/%d: %s)" % [i + 1, ips.size(), ip], COLOR_DIM)
	var http := HTTPRequest.new()
	http.timeout = 3.0
	add_child(http)
	var seq := int(_cand["seq"])
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		http.queue_free()
		if seq != _join_seq or not is_inside_tree():
			return  # 用户已发起新的连接, 陈旧探测结果作废
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			_connect_join(ip, port, "已找到主机 %s, 连接中, 连上后自动进房…" % ip)
		else:
			_cand["i"] = i + 1
			_try_next_candidate())
	var err := http.request("http://%s:%d/status" % [ip, port + 1])
	if err != OK:
		http.queue_free()
		_cand["i"] = i + 1
		_try_next_candidate()


## 候选定案: 保存地址并发起 ENet 连接(连上后由 connected_ok 自动进房)
func _connect_join(ip: String, port: int, msg: String) -> void:
	var g := get_node_or_null("/root/GameSettings")
	if g != null:
		g.host = ip
		g.host_port = port
		g.save_settings()
	_join_seq += 1  # 作废仍在途的探测回调
	net.disconnect_all()
	net.auto_reconnect = true
	net.connect_to(ip, port)
	_set_status(msg, COLOR_DIM)


## 生成本房间邀请码(地址段=全部对外地址: 局域网优先+Tailscale, 客户端逐个试)
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
	_sync_rules_visibility()


## 规则设置按模式联动: 普通/肉鸽显示全部规则行,
## 格斗对战无规则设置 — 卡片内仅保留模式选择行。
func _sync_rules_visibility() -> void:
	if _view != "room" or mode_option == null:
		return
	var fight: bool = mode_option.selected == 2
	rules_lbl.visible = not fight
	for w: Control in [chk_joker, chk_revolution, stakes_row, rounds_row,
			save_row]:
		w.visible = not fight


## 转让房主确认弹窗: 点击座位右上角 👑 后二次确认(成员 overlay, 可靠关闭)
var _xfer_overlay: Control = null   # 转让确认弹窗(自持, 可靠关闭)


func _close_xfer_overlay() -> void:
	if _xfer_overlay != null and is_instance_valid(_xfer_overlay):
		_xfer_overlay.queue_free()
	_xfer_overlay = null


func _confirm_transfer(seat: int, name: String) -> void:
	_close_xfer_overlay()
	_xfer_overlay = CenterContainer.new()
	_xfer_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_xfer_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_xfer_overlay.add_child(dim)
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(AppTheme.PANEL, AppTheme.GOLD, 16, 2)
	sb.content_margin_left = 44
	sb.content_margin_right = 44
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", sb)
	_xfer_overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var t := AppTheme.make_label(24, AppTheme.GOLD)
	t.text = "转让房主"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var b := AppTheme.make_label(15, AppTheme.WHITE)
	b.text = "确定将房主转让给 %s 吗？\n转让后你将不再是房主" % name
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(b)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var ok := AppTheme.make_button("确认转让", Vector2(170, 46), 16)
	ok.pressed.connect(func() -> void:
		Audio.play("click")
		net.transfer_host(seat)
		_close_xfer_overlay())
	row.add_child(ok)
	var cancel := AppTheme.make_button("取 消", Vector2(140, 46), 16)
	cancel.pressed.connect(func() -> void:
		Audio.play("click")
		_close_xfer_overlay())
	row.add_child(cancel)
	add_child(_xfer_overlay)
	_xfer_overlay.position = Vector2.ZERO
	_xfer_overlay.size = size


func _exit_room() -> void:
	_apply_view("entry")
	for tb: Button in _transfer_btns:
		tb.visible = false
	_close_xfer_overlay()
	if net != null:
		net.leave_room()
	hide_host_panel()
	show_status("", COLOR_GOLD)


## 本机开房信息卡(替代多行状态文字): 列出全部对外地址(局域网+Tailscale)
func show_host_panel(ips: Array) -> void:
	_host_panel_wanted = true
	host_invite_ips = ips
	var pas := PackedStringArray()
	for a in ips:
		pas.append(str(a))
	host_invite_ip = ",".join(pas)
	host_panel.visible = true
	status_label.visible = false
	var ts_set := {}
	for ip in Responsive.tailscale_ips():
		ts_set[str(ip)] = true
	var lines: Array = []
	for ip in ips:
		lines.append(("Tailscale  %s" if ts_set.has(str(ip)) else "局域网  %s") % str(ip))
	host_ip_value.text = "\n".join(PackedStringArray(lines)) \
			if lines.size() > 0 else "未检测到局域网/Tailscale 地址"
	host_hint_lbl.text = "同一 WiFi 的朋友: 联机页点【搜索附近主机】一键加入\n异地朋友: 点【复制邀请码】发给他(含全部地址)"
	var ts := Responsive.tailscale_ips()
	host_dl_btn.visible = ts.is_empty()
	host_dl_btn.text = "⬇ 异地联机装 Tailscale\n(%s)" % Responsive.platform_label()


func hide_host_panel() -> void:
	_host_panel_wanted = false
	host_panel.visible = false
	status_label.visible = true


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

	# 昵称统一使用设置页内配置的昵称(入口页不再提供输入框)

	# 核心联机三动作(主列, 大尺寸好按):
	#   ① 本机开房(当主机, 随 create_room 带上当前所选模式)
	host_btn = AppTheme.make_button("🏠 本机开房(当主机)", Vector2(360, 56), 18)
	host_btn.position = Vector2(470, 150)
	host_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_save_nickname()
		host_requested.emit())
	add_child(host_btn)
	#   ② 搜索附近主机(同 WiFi 一键加入)
	discover_btn = AppTheme.make_button("🔍 搜索附近主机", Vector2(360, 56), 18)
	discover_btn.position = Vector2(470, 244)
	discover_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_scan_tick())
	add_child(discover_btn)
	#   ③ 粘贴邀请码(异地一键加入)
	paste_btn = AppTheme.make_button("📋 粘贴邀请码, 一键加入", Vector2(360, 56), 18)
	paste_btn.position = Vector2(470, 338)
	paste_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_save_nickname()
		_paste_join())
	add_child(paste_btn)
	# 对局模式: 入口页不再展示 — 进房后在房间页规则设置卡片内由房主选择
	# (控件加入 rules_panel 的模式行, 见 _build_ui 尾部)
	mode_lbl = AppTheme.make_label(15, AppTheme.WHITE)
	mode_lbl.text = "模式"
	mode_option = OptionButton.new()
	mode_option.add_item("普通模式")
	mode_option.add_item("肉鸽模式")
	mode_option.add_item("格斗对战(2人)")
	mode_option.select(0)
	mode_option.custom_minimum_size = Vector2(160, 36)
	mode_option.item_selected.connect(func(_i: int) -> void:
		Audio.play("click")
		_sync_rules_visibility()
		# 房主改模式立即推送(服务端校验房主身份); 建房前选好则随 create_room 带上
		net.set_settings(_gather_rules()))

	# 发现新版本: 版本握手不匹配时显示, 点击打开下载页
	update_btn = AppTheme.make_button("⬇ 发现新版本, 点击更新", Vector2(260, 46), 16)
	update_btn.position = Vector2(40, 96)
	update_btn.visible = false
	update_btn.pressed.connect(func() -> void:
		Audio.play("click")
		OS.shell_open(_update_url()))
	add_child(update_btn)

	# 联机帮助(图文, 四页: 三步开房/朋友加入/主机须知/常见问题)
	help_btn = AppTheme.make_button("? 联机帮助", Vector2(150, 36), 15)
	help_btn.position = Vector2(1100, 22)
	help_btn.pressed.connect(func() -> void:
		Audio.play("click")
		var help := LobbyHelpScript.new()
		help.closed.connect(func() -> void: help.queue_free())
		add_child(help))
	add_child(help_btn)

	# 附近主机结果列表(搜索按钮已并入主列; 扫描到才有内容)(扫描到才有内容; 每行=一个可加入的房间)
	found_panel = PanelContainer.new()
	var fp_sb := AppTheme.flat(Color(0.06, 0.06, 0.14, 0.92), Color(AppTheme.GOLD, 0.4), 10, 1)
	fp_sb.content_margin_left = 12
	fp_sb.content_margin_right = 12
	fp_sb.content_margin_top = 10
	fp_sb.content_margin_bottom = 10
	found_panel.add_theme_stylebox_override("panel", fp_sb)
	# 右列(与中列『本机开房』顶边对齐, y=150): 搜索到才有内容,
	# 每行=一个可加入的房间
	found_panel.position = Vector2(840, 150)
	found_panel.custom_minimum_size = Vector2(368, 0)
	found_panel.visible = false
	add_child(found_panel)
	found_box = VBoxContainer.new()
	found_box.add_theme_constant_override("separation", 6)
	found_panel.add_child(found_box)
	var fp_title := AppTheme.make_label(14, COLOR_GOLD)
	fp_title.text = "附近主机(同一 WiFi)"
	found_box.add_child(fp_title)

	# ── 房间页: 标题 / 邀请行 / 座位卡 ──
	room_title_lbl = AppTheme.make_label(26, COLOR_GOLD)
	room_title_lbl.text = "房间"
	room_title_lbl.position = Vector2(150, 20)
	add_child(room_title_lbl)
	invite_lbl = AppTheme.make_label(14, COLOR_DIM)
	invite_lbl.position = Vector2(110, 64)
	invite_lbl.custom_minimum_size = Vector2(660, 24)
	invite_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # 限宽换行, 不再压到右列
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

	# 转让房主按钮(座位卡右上角 👑, 仅房主可见; 点击弹窗二次确认)
	for i in 4:
		var tb := AppTheme.make_button("👑", Vector2(30, 24), 13)
		tb.position = Vector2(40 + i * 160 + 114, 120)
		var tb_sb := AppTheme.flat(Color(0.10, 0.09, 0.20, 0.95),
				Color(AppTheme.GOLD, 0.55), 5, 1)
		tb.add_theme_stylebox_override("normal", tb_sb)
		var tb_sb_h: StyleBoxFlat = tb_sb.duplicate()
		tb_sb_h.set_border_width_all(2)
		tb.add_theme_stylebox_override("hover", tb_sb_h)
		tb.add_theme_stylebox_override("pressed", tb_sb_h)
		tb.visible = false
		tb.tooltip_text = "将房主转让给该玩家"
		var idx := i
		tb.pressed.connect(func() -> void:
			Audio.play("click")
			var nm_lbl: Label = _seat_cards[idx]["name"]
			_confirm_transfer(idx, str(nm_lbl.text)))
		add_child(tb)
		_transfer_btns.append(tb)

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

	# 规则设置卡片(仅房间页): 金色边框容器整体包裹, 行内"左标签+右控件"
	# 统一对齐; 模式选择也在卡片内(进房后由房主选择)。格斗对战仅保留模式行。
	chk_joker = _check("带王")
	chk_revolution = _check("革命")
	stakes_lbl = AppTheme.make_label(15, COLOR_WHITE)
	stakes_lbl.text = "输赢"
	stakes_option = OptionButton.new()
	for item: Array in [["小 ×1", 1], ["中 ×2", 2], ["大 ×3", 3]]:
		stakes_option.add_item(str(item[0]), int(item[1]))
	stakes_option.select(0)
	rounds_lbl = AppTheme.make_label(15, COLOR_WHITE)
	rounds_lbl.text = "回合数"
	rounds_option = OptionButton.new()
	for r: Array in [[3, "一回合"], [9, "三回合"], [15, "五回合"]]:
		rounds_option.add_item(str(r[1]) + "（%d 局）" % r[0], r[0])
	rounds_option.select(0)
	save_settings_btn = AppTheme.make_button("保存设置", Vector2(140, 38), 15)
	save_settings_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.set_settings(_gather_rules()))
	rules_panel = PanelContainer.new()
	var rp_sb := AppTheme.flat(AppTheme.PANEL, AppTheme.GOLD, 12, 2)
	rp_sb.content_margin_left = 18
	rp_sb.content_margin_right = 18
	rp_sb.content_margin_top = 12
	rp_sb.content_margin_bottom = 14
	rules_panel.add_theme_stylebox_override("panel", rp_sb)
	rules_panel.position = Vector2(820, 20)
	rules_panel.custom_minimum_size = Vector2(380, 0)
	add_child(rules_panel)
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 10)
	rules_panel.add_child(rbox)
	rules_lbl = AppTheme.section_label("规则设置")
	rbox.add_child(rules_lbl)
	# 模式行
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	rbox.add_child(mode_row)
	mode_lbl.custom_minimum_size = Vector2(64, 36)
	mode_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mode_row.add_child(mode_lbl)
	mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(mode_option)
	# 开关行(整行宽度, 开关圆点贴右, 视觉与行对齐)
	rbox.add_child(chk_joker)
	rbox.add_child(chk_revolution)
	# 输赢行
	stakes_row = HBoxContainer.new()
	stakes_row.add_theme_constant_override("separation", 8)
	rbox.add_child(stakes_row)
	stakes_lbl.custom_minimum_size = Vector2(64, 0)
	stakes_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stakes_row.add_child(stakes_lbl)
	stakes_option.custom_minimum_size = Vector2(0, 34)
	stakes_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stakes_row.add_child(stakes_option)
	# 回合数行
	rounds_row = HBoxContainer.new()
	rounds_row.add_theme_constant_override("separation", 8)
	rbox.add_child(rounds_row)
	rounds_lbl.custom_minimum_size = Vector2(64, 0)
	rounds_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rounds_row.add_child(rounds_lbl)
	rounds_option.custom_minimum_size = Vector2(0, 34)
	rounds_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rounds_row.add_child(rounds_option)
	# 保存按钮(居中收尾)
	var save_cc := CenterContainer.new()
	save_cc.add_child(save_settings_btn)
	rbox.add_child(save_cc)
	save_row = save_cc

	# 状态(联机准备条之下, 自动换行多行)
	status_label = AppTheme.make_label(15, COLOR_DIM)
	status_label.position = Vector2(40, 234)
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
	# 顶边与中列『本机开房』等按钮对齐(y=150): 左右两列同一起始线
	_ts_chip.position = Vector2(40, 150)
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
	host_panel.position = Vector2(40, 234)
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
	host_hint_lbl = hp_hint
	hp_hint.text = "同一 WiFi 的朋友: 联机页点【搜索附近主机】一键加入\n异地朋友: 点【复制邀请码】发给他(含全部地址)"
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
	_reg(host_btn, "center")
	_reg(discover_btn, "center")
	_reg(paste_btn, "center")
	_reg(found_panel, "left", 0.1)
	_reg(help_btn, "right")

	# ── 房间页锚定(独立子页面布局; 1280×720 设计基准) ──
	# 顶部: 离开 | 房号+复制邀请码 | 说明(限宽 660, 与右列留出间隔)
	# 左列: 4 座位卡(40 起步, 间距 10) + 操作按钮行 + 状态行
	# 右列: 规则设置卡片(金框容器, 内部行自对齐)
	_reg_room(back_btn, Vector2(20, 16), "left")
	_reg_room(status_label, Vector2(40, 360), "left")
	_reg_room(room_title_lbl, Vector2(150, 22), "center")
	_reg_room(copy_btn, Vector2(330, 14), "center")
	_reg_room(invite_lbl, Vector2(150, 64), "center")
	for i in 4:
		_reg_room(_seat_cards[i]["panel"], Vector2(40 + i * 160, 116), "center")
	_reg_room(fill_btn, Vector2(40, 290), "center")
	_reg_room(kick_btn, Vector2(190, 290), "center")
	_reg_room(start_btn, Vector2(340, 290), "center")
	_reg_room(rules_panel, Vector2(820, 20), "right")

	for b: Button in [fill_btn, start_btn, copy_btn, save_settings_btn]:
		b.disabled = true
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


## ── 局域网发现(同 WiFi 一键加入) ──
## 每 3 秒广播一次查询, 主机(游戏端口+2)单播回房间概览; 超时 12s 未回包移除。
## 本机开房/已进房/整页不可见(首页或牌桌)时不搜 — 空转定时器耗电且无意义。
func _scan_tick() -> void:
	if not is_visible_in_tree():
		return
	_scan_send()
	_scan_read()
	_rebuild_found_rows()


func _scan_send() -> void:
	if _view != "entry" or _host_panel_wanted or auto_create_room:
		return
	var dport: int = int(GameSettings.host_port) + LanDisc.PORT_OFFSET
	if _disc == null:
		_disc = PacketPeerUDP.new()
		if _disc.bind(0) != OK:
			_disc = null
			return
		_disc.set_broadcast_enabled(true)
	var q := LanDisc.make_query()
	# ① 全网广播: 同子网主机一次命中
	_disc.set_dest_address("255.255.255.255", dport)
	_disc.put_packet(q)
	# ② 单播补盲: 广播在部分路由器(AP 隔离除外)与手机(组播过滤)上收不到,
	#    对本机所在 /24 逐地址单播 + 本机回环。UDP 无连接一次性发出, 开销可忽略。
	_disc.set_dest_address("127.0.0.1", dport)
	_disc.put_packet(q)
	for ip in Responsive.local_ips()["lan"]:
		var p: PackedStringArray = str(ip).split(".")
		if p.size() != 4:
			continue
		for h in range(1, 255):
			_disc.set_dest_address("%s.%s.%s.%d" % [p[0], p[1], p[2], h], dport)
			_disc.put_packet(q)


func _scan_read() -> void:
	if _disc == null:
		return
	while _disc.get_available_packet_count() > 0:
		var pkt := _disc.get_packet()
		var ip := _disc.get_packet_ip()
		var r := LanDisc.parse_reply(pkt)
		if r.is_empty():
			continue
		_found[ip] = {"port": int(r["port"]), "rooms": r["rooms"],
				"seen": Time.get_ticks_msec()}


## 重建附近主机列表(行数封顶 5, 过期条目清除; 全空则整卡隐藏)。
## 同一房间的多网卡地址合并为一行, 地址按可达性排序(局域网优先,
## 回环/虚拟网卡殿后), 点击后自动逐个回退尝试。
func _addr_score(ip: String) -> int:
	if ip.begins_with("127."):
		return 90   # 回环: 多半是主机本机, 仅作兜底
	if ip.begins_with("192.168.") or ip.begins_with("10."):
		return 0    # 局域网最优先
	if ip.begins_with("100."):
		return 10   # Tailscale
	return 20        # 其余(172. 私有段等)


func _rebuild_found_rows() -> void:
	if _view != "entry":
		found_panel.visible = false   # 房间页不显示附近主机模块
		return
	var now := Time.get_ticks_msec()
	for ip in _found.keys():
		if now - int(_found[ip]["seen"]) > LanDisc.TTL_MS:
			_found.erase(ip)
	for r in _found_rows:
		(r as Control).queue_free()
	_found_rows.clear()
	# 按房间码合并多地址, 每房间选可达性最好的地址为首选
	var by_code := {}
	for ip in _found.keys():
		var e: Dictionary = _found[ip]
		for room in e["rooms"]:
			var code := str(room["code"])
			if not by_code.has(code):
				by_code[code] = {"addrs": [], "open": bool(room["open"]),
						"players": int(room["players"]), "cap": int(room["cap"])}
			var rec: Dictionary = by_code[code]
			rec["addrs"].append({"ip": str(ip), "port": int(e["port"]),
					"score": _addr_score(str(ip))})
			rec["open"] = rec["open"] or bool(room["open"])
	var shown := 0
	for code in by_code.keys():
		if shown >= 5:
			break
		var rec: Dictionary = by_code[code]
		var addrs: Array = rec["addrs"]
		addrs.sort_custom(func(a, b): return int(a["score"]) < int(b["score"]))
		var best: Dictionary = addrs[0]
		var open := bool(rec["open"])
		var txt := "🏠 %s  %d/%d人  %s" % [code, int(rec["players"]),
				int(rec["cap"]), str(best["ip"])]
		if not open:
			txt += " · 游戏中"
		var b := AppTheme.make_button(txt, Vector2(340, 42), 13)
		b.disabled = not open
		var rcode := str(code)
		var alts: Array = addrs.duplicate(true)
		b.pressed.connect(func() -> void:
			Audio.play("click")
			_join_found_best(str(best["ip"]), int(best["port"]), rcode,
					alts.duplicate(true)))
		found_box.add_child(b)
		_found_rows.append(b)
		shown += 1
	found_panel.visible = shown > 0


## 点击附近主机: 发现应答本身已证明可达, 直接发起 ENet 连接并自动进房。
## 携带全部候选地址: 连接失败时自动切换下一地址(修复多网卡环境点击
## 虚拟网卡地址导致"连接后不进房")。
func _join_found_best(ip: String, port: int, room_code: String,
		alts: Array = []) -> void:
	_save_nickname()
	_auto_join_code = room_code
	_join_alts = alts.duplicate(true)
	_conn_fails = 0
	_loopback_hint = false
	var g := get_node_or_null("/root/GameSettings")
	if g != null:
		g.host = ip
		g.host_port = port
		g.save_settings()
	_join_seq += 1
	net.disconnect_all()
	net.auto_reconnect = true
	net.connect_to(ip, port)
	_set_status("正在连接附近主机 %s:%d, 连上后自动进房 %s…" % [ip, port, room_code], COLOR_DIM)


## 房主可移除的第一个人类座位(不能移除自己/机器人)
func _kickable_seat() -> int:
	for p in net.last_room_state.get("players", []):
		if int(p.get("seat", -1)) == net.my_seat:
			continue
		if not bool(p.get("empty", true)) and not bool(p.get("is_bot", false)):
			return int(p["seat"])
	return -1


## 昵称统一在设置页配置; 这里只兜底确保非空并持久化
func _save_nickname() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		if str(gs.nickname).strip_edges() == "":
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
	)
	net.connection_failed.connect(func() -> void:
		_conn_fails += 1
		if _auto_join_code != "" and not _join_alts.is_empty():
			var nxt: Dictionary = _join_alts.pop_front()
			_set_status("地址不可达, 尝试备用地址 %s:%d…" % [
					str(nxt["ip"]), int(nxt["port"])], COLOR_DIM)
			net.disconnect_all()
			net.auto_reconnect = true
			_join_seq += 1
			net.connect_to(str(nxt["ip"]), int(nxt["port"]))
			return
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
	var mode := "normal"
	if mode_option != null:
		match mode_option.selected:
			1: mode = "rogue"
			2: mode = "fight"
	return {
		"with_joker": chk_joker.button_pressed,
		"revolution": chk_revolution.button_pressed,
		"rounds": rounds_option.get_selected_id(),
		"stakes": stakes_option.get_selected_id(),
		"mode": mode,
		"rogue": mode == "rogue",
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
	if mode_option != null:
		match str(settings.get("mode", "normal")):
			"rogue": mode_option.select(1)
			"fight": mode_option.select(2)
			_: mode_option.select(0)


func _on_room_state(state: Dictionary) -> void:
	if net == null or not net.in_room:
		return  # 已离开房间后的迟到广播: 不把页签拉回房间页
	_last_room_code = str(state.get("room_code", ""))
	_refresh_invite(state)
	_apply_settings(state.get("settings", {}))
	_enter_room()
	_sync_rules_visibility()
	var host_seat := int(state.get("host_seat", -1))
	kick_btn.visible = net.in_room and host_seat == net.my_seat
	# 房间页标题 + 邀请行
	room_title_lbl.text = "房间  %s" % (_last_room_code if _last_room_code != "" else "——")
	var ip_txt := ""
	if host_invite_ips.size() > 0:
		var ip_show := str(host_invite_ips[0])
		if host_invite_ips.size() > 1:
			ip_show += " 等%d个地址" % host_invite_ips.size()
		ip_txt = "服务器 %s · " % ip_show
	invite_lbl.text = ip_txt + "点【复制邀请码】发给朋友 → 朋友点【粘贴邀请码, 一键加入】或【搜索附近主机】"
	# 座位卡(格斗对战房间: 1/2 号位=格斗者, 3/4 号位=观战)
	var fight_room: bool = str((state.get("settings", {}) as Dictionary)
			.get("mode", "normal")) == "fight"
	for i in 4:
		var nm: Label = _seat_cards[i]["name"]
		var tag: Label = _seat_cards[i]["tag"]
		nm.text = "(空位)"
		nm.add_theme_color_override("font_color", COLOR_DIM)
		tag.text = "等待加入" if not fight_room else ("格斗位" if i < 2 else "观战位")
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
			if fight_room:
				bits.append("格斗者" if i < 2 else "观战中")
			tag.text = " · ".join(bits)
			tag.add_theme_color_override("font_color",
					COLOR_GOLD if i == host_seat else COLOR_DIM)
			break
	var host: bool = host_seat == int(net.my_seat)
	fill_btn.disabled = not host
	start_btn.disabled = not host
	# 转让按钮: 我是房主时, 每个真人座位右上角显示(自己的座位/机器人除外)
	for i in 4:
		var occupied_human := false
		for p in state.get("players", []):
			if int(p.get("seat", -1)) == i and not bool(p.get("empty", true)) 					and not bool(p.get("is_bot", false)):
				occupied_human = true
				break
		_transfer_btns[i].visible = host and occupied_human and i != host_seat


func _set_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)


func _check(text: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = true   # 默认开启(与服务端默认规则一致: 带王/革命)
	return c
