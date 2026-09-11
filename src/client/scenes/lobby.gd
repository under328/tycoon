## 联机大厅 v2: 三步向导式新手流程 + ESC 随时返回主菜单。
extends Control

signal start_game
signal back_to_menu
signal host_requested

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const NetNodeGd = preload("res://src/protocol/net_node.gd")

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
var chk_eight: CheckButton
var rounds_option: OptionButton
var _last_room_code := ""
var host_edit: LineEdit
var port_edit: LineEdit
var connect_btn: Button
var host_btn: Button
var update_btn: Button
var _conn_fails := 0


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
	_bind_net()
	_auto_connect()


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


## 供 main(本机开房) 推送状态/主机 IP 信息
func show_status(text: String, color: Color = COLOR_GOLD) -> void:
	_set_status(text, color)


func _manual_connect() -> void:
	var host := host_edit.text.strip_edges()
	var port := int(port_edit.text.strip_edges()) if port_edit.text.strip_edges() != "" else GameSettings.DEFAULT_PORT
	if host == "":
		_set_status("请输入服务器地址", COLOR_RED)
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
	_set_status("正在连接 %s:%d …" % [host, port], COLOR_DIM)


func _build_ui() -> void:
	theme = AppTheme.build_theme()

	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 返回主菜单按钮
	var back_btn := create_and_place("← 主菜单", Vector2(20, 16), Vector2(110, 36), 15)
	back_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.leave_room()
		back_to_menu.emit())
	add_child(back_btn)

	# 标题
	var title := AppTheme.make_label(28, COLOR_GOLD)
	title.text = "联机对战"
	title.position = Vector2(150, 22)
	add_child(title)

	# 昵称
	var c1 := AppTheme.make_label(15, COLOR_WHITE)
	c1.text = "昵称"
	c1.position = Vector2(150, 70)
	add_child(c1)
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
	quick_btn = AppTheme.make_button("🎲  快速匹配", Vector2(300, 56), 20)
	quick_btn.position = Vector2(450, 100)
	quick_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_save_nickname()
		net.quick_match(_gather_rules()))
	add_child(quick_btn)

	create_btn = AppTheme.make_button("🏠  创建房间", Vector2(300, 56), 20)
	create_btn.position = Vector2(450, 170)
	create_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_save_nickname()
		net.create_room(_gather_rules()))
	add_child(create_btn)

	code_edit = LineEdit.new()
	code_edit.position = Vector2(450, 240)
	code_edit.custom_minimum_size = Vector2(200, 44)
	code_edit.size = Vector2(200, 44)
	code_edit.placeholder_text = "输入房间码"
	code_edit.add_theme_font_size_override("font_size", 20)
	add_child(code_edit)
	join_btn = AppTheme.make_button("加入", Vector2(62, 44), 18)
	join_btn.position = Vector2(658, 240)
	join_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_save_nickname()
		net.join_room(code_edit.text.strip_edges()))
	add_child(join_btn)

	# 本机开房: 同进程内嵌服务器, 手机/PC 都能当主机, 朋友填 IP 直连
	host_btn = AppTheme.make_button("🏠 本机开房(朋友填IP直连)", Vector2(280, 44), 16)
	host_btn.position = Vector2(736, 240)
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

	# 服务器地址区(右上)
	var c2 := AppTheme.make_label(15, COLOR_GOLD)
	c2.text = "服务器"
	c2.position = Vector2(830, 66)
	add_child(c2)
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
	room_label.position = Vector2(150, 310)
	room_label.custom_minimum_size = Vector2(700, 140)
	add_child(room_label)

	# 房主操作按钮
	fill_btn = AppTheme.make_button("空位加AI", Vector2(140, 46), 17)
	fill_btn.position = Vector2(150, 470)
	fill_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.fill_bots())
	add_child(fill_btn)
	start_btn = AppTheme.make_button("开始游戏", Vector2(140, 46), 17)
	start_btn.position = Vector2(310, 470)
	start_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.start_game())
	add_child(start_btn)
	leave_btn = AppTheme.make_button("离开房间", Vector2(140, 46), 17)
	leave_btn.position = Vector2(470, 470)
	leave_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.leave_room())
	add_child(leave_btn)
	copy_btn = AppTheme.make_button("复制房间码", Vector2(140, 46), 17)
	copy_btn.position = Vector2(630, 470)
	copy_btn.pressed.connect(func() -> void:
		Audio.play("click")
		DisplayServer.clipboard_set(_last_room_code)
		_set_status("房间码已复制: " + _last_room_code, COLOR_GREEN))
	add_child(copy_btn)

	# 规则设置
	var c4 := AppTheme.make_label(15, COLOR_GOLD)
	c4.text = "规则设置"
	c4.position = Vector2(830, 310)
	add_child(c4)
	chk_joker = _check("带王", Vector2(830, 340))
	add_child(chk_joker)
	chk_revolution = _check("革命", Vector2(830, 380))
	add_child(chk_revolution)
	chk_eight = _check("8切", Vector2(830, 420))
	add_child(chk_eight)
	var rounds_lbl := AppTheme.make_label(15, COLOR_WHITE)
	rounds_lbl.text = "局数"
	rounds_lbl.position = Vector2(830, 460)
	add_child(rounds_lbl)
	rounds_option = OptionButton.new()
	for r: int in [1, 3, 5]:
		rounds_option.add_item(str(r) + " 局", r)
	rounds_option.select(1)
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

	# 状态
	status_label = AppTheme.make_label(15, COLOR_DIM)
	status_label.position = Vector2(40, 260)
	status_label.custom_minimum_size = Vector2(360, 80)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)

	stats_label = AppTheme.make_label(15, COLOR_DIM)
	stats_label.position = Vector2(40, 350)
	stats_label.custom_minimum_size = Vector2(360, 40)
	add_child(stats_label)

	for b: Button in [quick_btn, create_btn, join_btn, fill_btn, start_btn, leave_btn, copy_btn, save_settings_btn]:
		b.disabled = true
	host_btn.disabled = false
	connect_btn.disabled = false


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
		_set_status("已连接! 选一个方式开局吧", COLOR_GREEN)
		for b: Button in [quick_btn, create_btn, join_btn]:
			b.disabled = false
		net.request_stats())
	net.connection_failed.connect(func() -> void:
		_conn_fails += 1
		_set_status("无法连接 %s:%d（第 %d 次），自动重试中…\n确认服务器已启动、地址正确、防火墙放行"
				% [net.address, net.port, _conn_fails], COLOR_RED))
	net.server_disconnected.connect(func() -> void:
		_set_status("与服务器断开, 自动重连中…", COLOR_RED))
	net.errored.connect(func(code: String, msg: String) -> void:
		if code != "not_connected":
			_set_status("错误 %s: %s" % [code, msg], COLOR_RED))
	net.kicked_off.connect(func(reason: String) -> void:
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
		"eight_cut": chk_eight.button_pressed,
		"rounds": rounds_option.get_selected_metadata(),
	}


func _apply_settings(settings: Dictionary) -> void:
	chk_joker.set_pressed_no_signal(bool(settings.get("with_joker", true)))
	chk_revolution.set_pressed_no_signal(bool(settings.get("revolution", true)))
	chk_eight.set_pressed_no_signal(bool(settings.get("eight_cut", false)))
	var rounds := int(settings.get("rounds", 3))
	for i in rounds_option.item_count:
		if int(rounds_option.get_item_metadata(i)) == rounds:
			rounds_option.select(i)


func _on_room_state(state: Dictionary) -> void:
	_last_room_code = str(state.get("room_code", ""))
	var lines: Array = []
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
