## 联机大厅: 进入即自动连接官方服务器, 玩家只需选"快速匹配/创建/加入"。
## 自建服务器地址收在"自建服务器"高级折叠区。
extends Control

signal start_game
signal back_to_menu

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const P5Header = preload("res://src/client/ui/p5_header.gd")
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
var adv_btn: Button
var status_label: Label
var room_label: Label
var stats_label: Label
var chk_joker: CheckButton
var chk_revolution: CheckButton
var chk_stairs: CheckButton
var chk_eight: CheckButton
var rounds_option: OptionButton
var adv_box: Control
var host_edit: LineEdit
var port_edit: LineEdit
var custom_connect_btn: Button
var official_btn: Button
var _last_room_code := ""


func setup(p_net: Node) -> void:
	net = p_net


func _ready() -> void:
	if net == null:
		net = NetNodeGd.new()
		net.name = "NetLobbyFallback"
		net.setup(false)
		add_child(net)
	_build_ui()
	_bind_net()
	Audio.play_bgm("lobby")
	# ★ 进入大厅自动连接(默认官方服务器; CLI --address 可覆盖用于测试)
	_auto_connect()


func _auto_connect() -> void:
	var host: String = AppMode.address if AppMode.address_from_cli else GameSettings.DEFAULT_HOST
	var port: int = AppMode.port if AppMode.port_from_cli else GameSettings.DEFAULT_PORT
	host_edit.text = host
	port_edit.text = str(port)
	_set_status("正在连接服务器…", COLOR_DIM)
	net.auto_reconnect = true
	net.connect_to(host, port)


# ---------------------------------------------------------------- UI 构建

func _build_ui() -> void:
	theme = AppTheme.build_theme()

	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := _label(28, COLOR_GOLD)
	title.text = "联机大厅"
	title.position = Vector2(40, 24)
	add_child(title)

	var sub := _label(15, COLOR_DIM)
	sub.text = "和大朋友远程来一局"
	sub.position = Vector2(40, 62)
	add_child(sub)

	var c1 := _label(16, COLOR_WHITE)
	c1.text = "你的昵称"
	c1.position = Vector2(40, 118)
	add_child(c1)
	nickname_edit = _edit(Vector2(40, 146), Vector2(320, 40))
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		nickname_edit.text = str(gs.nickname)
	add_child(nickname_edit)

	# ---- 三个主入口 ----
	quick_btn = AppTheme.make_button("🎲  快速匹配", Vector2(360, 52), 19)
	quick_btn.position = Vector2(430, 118)
	quick_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.quick_match(_gather_rules()))
	add_child(quick_btn)
	create_btn = AppTheme.make_button("🏠  创建房间", Vector2(360, 52), 19)
	create_btn.position = Vector2(430, 182)
	create_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.create_room(_gather_rules()))
	add_child(create_btn)
	code_edit = _edit(Vector2(806, 186), Vector2(170, 44))
	code_edit.placeholder_text = "房间码"
	code_edit.add_theme_font_size_override("font_size", 22)
	add_child(code_edit)
	join_btn = AppTheme.make_button("加入", Vector2(110, 52), 19)
	join_btn.position = Vector2(988, 182)
	join_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.join_room(code_edit.text.strip_edges()))
	add_child(join_btn)

	room_label = _label(17, COLOR_WHITE)
	room_label.position = Vector2(430, 260)
	room_label.custom_minimum_size = Vector2(700, 150)
	add_child(room_label)

	fill_btn = AppTheme.make_button("空位加AI", Vector2(130, 46), 17)
	fill_btn.position = Vector2(430, 420)
	fill_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.fill_bots())
	add_child(fill_btn)
	start_btn = AppTheme.make_button("开始游戏", Vector2(130, 46), 17)
	start_btn.position = Vector2(574, 420)
	start_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.start_game())
	add_child(start_btn)
	leave_btn = AppTheme.make_button("离开房间", Vector2(130, 46), 17)
	leave_btn.position = Vector2(718, 420)
	leave_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.leave_room())
	add_child(leave_btn)
	copy_btn = AppTheme.make_button("复制房间码", Vector2(140, 46), 17)
	copy_btn.position = Vector2(862, 420)
	copy_btn.pressed.connect(func() -> void:
		Audio.play("click")
		DisplayServer.clipboard_set(_last_room_code)
		_set_status("房间码已复制: " + _last_room_code, COLOR_GREEN))
	add_child(copy_btn)

	# ---- 规则设置(房主开局前) ----
	var c4 := _label(16, COLOR_GOLD)
	c4.text = "规则设置"
	c4.position = Vector2(430, 486)
	add_child(c4)
	chk_joker = _check("带王", Vector2(430, 518))
	add_child(chk_joker)
	chk_revolution = _check("革命", Vector2(530, 518))
	add_child(chk_revolution)
	chk_stairs = _check("階段", Vector2(630, 518))
	add_child(chk_stairs)
	chk_eight = _check("8切", Vector2(730, 518))
	add_child(chk_eight)
	var rounds_lbl := _label(15, COLOR_WHITE)
	rounds_lbl.text = "局数"
	rounds_lbl.position = Vector2(830, 524)
	add_child(rounds_lbl)
	rounds_option = OptionButton.new()
	for r: int in [1, 3, 5]:
		rounds_option.add_item(str(r) + " 局", r)
	rounds_option.select(1)
	rounds_option.position = Vector2(872, 518)
	rounds_option.custom_minimum_size = Vector2(90, 34)
	add_child(rounds_option)
	save_settings_btn = AppTheme.make_button("保存设置", Vector2(130, 40), 16)
	save_settings_btn.position = Vector2(430, 568)
	save_settings_btn.pressed.connect(func() -> void:
		Audio.play("click")
		net.set_settings(_gather_rules())
		_set_status("已提交设置(房主生效)", COLOR_GREEN))
	add_child(save_settings_btn)

	# ---- 表情 ----
	for i in EMOJIS.size():
		var id := i
		var eb := AppTheme.make_button(EMOJIS[i], Vector2(48, 44))
		eb.position = Vector2(430 + i * 58, 630)
		eb.add_theme_font_size_override("font_size", 20)
		eb.pressed.connect(func() -> void:
			Audio.play("pop")
			net.send_emoji(id))
		add_child(eb)

	# ---- 状态栏 ----
	status_label = _label(15, COLOR_DIM)
	status_label.position = Vector2(40, 210)
	status_label.custom_minimum_size = Vector2(340, 90)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)

	stats_label = _label(15, COLOR_DIM)
	stats_label.position = Vector2(40, 320)
	stats_label.custom_minimum_size = Vector2(340, 40)
	add_child(stats_label)

	# ---- 自建服务器(高级, 默认折叠) ----
	adv_box = Control.new()
	adv_box.position = Vector2(40, 380)
	adv_box.visible = false
	add_child(adv_box)
	var adv_title := _label(14, COLOR_DIM)
	adv_title.text = "自建服务器(进阶)"
	adv_title.position = Vector2(0, 0)
	adv_box.add_child(adv_title)
	host_edit = _edit(Vector2(0, 26), Vector2(180, 36))
	adv_box.add_child(host_edit)
	port_edit = _edit(Vector2(192, 26), Vector2(70, 36))
	adv_box.add_child(port_edit)
	custom_connect_btn = AppTheme.make_button("连接", Vector2(70, 36), 14)
	custom_connect_btn.position = Vector2(270, 26)
	custom_connect_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_do_connect_custom())
	adv_box.add_child(custom_connect_btn)
	official_btn = AppTheme.make_button("用官方服", Vector2(96, 36), 14)
	official_btn.position = Vector2(348, 26)
	official_btn.position = Vector2(348, 26)
	official_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_auto_connect()
		_set_status("已切回官方服务器", COLOR_GREEN))
	adv_box.add_child(official_btn)

	adv_btn = AppTheme.make_button("自建服务器 ▸", Vector2(130, 30), 13)
	adv_btn.position = Vector2(40, 340)
	adv_btn.position = Vector2(40, 340)
	adv_btn.toggle_mode = true
	adv_btn.pressed.connect(func() -> void:
		adv_box.visible = adv_btn.button_pressed)
	add_child(adv_btn)

	for b: Button in [quick_btn, create_btn, join_btn, fill_btn, start_btn, leave_btn, copy_btn, save_settings_btn]:
		b.disabled = true


func _bind_net() -> void:
	net.connected_ok.connect(func() -> void:
		_set_status("已连接! 选一个方式开局吧", COLOR_GREEN)
		for b: Button in [quick_btn, create_btn, join_btn]:
			b.disabled = false
		net.request_stats())
	net.connection_failed.connect(func() -> void:
		_set_status("连接失败, 自动重试中…", COLOR_RED))
	net.server_disconnected.connect(func() -> void:
		_set_status("与服务器断开, 自动重连中…", COLOR_RED))
	net.errored.connect(func(code: String, msg: String) -> void:
		if code != "not_connected":
			_set_status("错误 %s: %s" % [code, msg], COLOR_RED))
	net.kicked_off.connect(func(reason: String) -> void:
		if reason == "version":
			_set_status("版本不符, 请到 %s 下载新版本" % GameSettings.DOWNLOAD_URL, COLOR_RED)
		else:
			_set_status("已被移出房间(%s)" % reason, COLOR_RED))
	net.stats_updated.connect(func(entry: Dictionary) -> void:
		if entry.is_empty():
			stats_label.text = "战绩: 暂无(打完一场后生成)"
		else:
			stats_label.text = "战绩: %d 场 / 胜 %d / 累计 %+d 分" % [
				int(entry.get("matches", 0)), int(entry.get("wins", 0)),
				int(entry.get("total_points", 0))])
	net.game_event.connect(func(event: String, data: Dictionary) -> void:
		if event == "emoji":
			_set_status("座位 %d: %s" % [int(data.get("seat", 0)) + 1,
					EMOJIS[clampi(int(data.get("id", 0)), 0, EMOJIS.size() - 1)]], COLOR_GOLD)
		elif event == "chat":
			_set_status("座位 %d 说: %s" % [int(data.get("seat", 0)) + 1,
					str(data.get("text", ""))], COLOR_WHITE))
	net.room_state.connect(_on_room_state)
	net.view_changed.connect(func(_view: Dictionary) -> void:
		start_game.emit())


func _gather_rules() -> Dictionary:
	return {
		"with_joker": chk_joker.button_pressed,
		"revolution": chk_revolution.button_pressed,
		"stairs": chk_stairs.button_pressed,
		"eight_cut": chk_eight.button_pressed,
		"rounds": rounds_option.get_selected_metadata(),
	}


func _apply_settings(settings: Dictionary) -> void:
	chk_joker.set_pressed_no_signal(bool(settings.get("with_joker", true)))
	chk_revolution.set_pressed_no_signal(bool(settings.get("revolution", true)))
	chk_stairs.set_pressed_no_signal(bool(settings.get("stairs", true)))
	chk_eight.set_pressed_no_signal(bool(settings.get("eight_cut", false)))
	var rounds := int(settings.get("rounds", 3))
	for i in rounds_option.item_count:
		if int(rounds_option.get_item_metadata(i)) == rounds:
			rounds_option.select(i)


func _do_connect_custom() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		gs.nickname = nickname_edit.text.strip_edges()
		if gs.nickname == "":
			gs.nickname = "玩家"
		gs.save_settings()
	var port := int(port_edit.text.strip_edges())
	if port <= 0:
		port = GameSettings.DEFAULT_PORT
	_set_status("连接 %s:%d …" % [host_edit.text.strip_edges(), port], COLOR_DIM)
	net.auto_reconnect = true
	net.connect_to(host_edit.text.strip_edges(), port)


func _on_room_state(state: Dictionary) -> void:
	_last_room_code = str(state.get("room_code", ""))
	var lines: Array = []
	lines.append("房间码: %s   (把数字发给朋友)" % _last_room_code)
	for p in state["players"]:
		if bool(p.get("empty", false)):
			lines.append("  座位%d:(空位)" % (int(p["seat"]) + 1))
			continue
		var mark := "房主 " if int(p["seat"]) == int(state.get("host_seat", 0)) else ""
		var on := "" if bool(p.get("online", true)) else "(离线→AI托管)"
		var bot := " [AI]" if bool(p.get("is_bot", false)) else ""
		lines.append("  座位%d: %s%s%s%s" % [
			int(p["seat"]) + 1, mark, str(p.get("name", "")), bot, on])
	room_label.text = "\n".join(lines)
	var host: bool = int(state.get("host_seat", -1)) == int(net.my_seat)
	fill_btn.disabled = not host
	start_btn.disabled = not host
	save_settings_btn.disabled = not host
	leave_btn.disabled = false
	for b: Button in [quick_btn, create_btn, join_btn]:
		b.disabled = false
	_apply_settings(state.get("settings", {}))


func _set_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)


func _label(size: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", color)
	return lb


func _edit(pos: Vector2, size: Vector2) -> LineEdit:
	var e := LineEdit.new()
	e.position = pos
	e.custom_minimum_size = size
	e.size = size
	e.add_theme_font_size_override("font_size", 17)
	return e


func _check(text: String, pos: Vector2) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.position = pos
	return c
