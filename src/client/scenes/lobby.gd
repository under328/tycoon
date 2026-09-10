## 联机大厅（占位美术，M4 换皮）：连接 → 建房/加入/快速匹配 → 规则设置 → 开局。
extends Control

signal start_game

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
var address_edit: LineEdit
var port_edit: LineEdit
var code_edit: LineEdit
var connect_btn: Button
var quick_btn: Button
var create_btn: Button
var join_btn: Button
var fill_btn: Button
var start_btn: Button
var leave_btn: Button
var save_settings_btn: Button
var status_label: Label
var room_label: Label
var stats_label: Label
var chk_joker: CheckButton
var chk_revolution: CheckButton
var chk_stairs: CheckButton
var chk_eight: CheckButton
var rounds_option: OptionButton


func setup(p_net: Node) -> void:
	net = p_net


func _ready() -> void:
	if net == null:
		# 直接 F5 运行 lobby 场景时的兜底（正常由 main 创建并注入）
		net = NetNodeGd.new()
		net.name = "NetLobbyFallback"
		net.setup(false)
		add_child(net)
	_build_ui()
	_bind_net()
	Audio.play_bgm("lobby")


func _build_ui() -> void:
	var theme_res := Theme.new()
	var sys_font := SystemFont.new()
	sys_font.font_names = PackedStringArray([
		"Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC", "SimHei", "Arial",
	])
	theme_res.default_font = sys_font
	theme_res.default_font_size = 18
	theme = theme_res

	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := _label(28, COLOR_GOLD)
	title.text = "大富豪 · Tycoon"
	title.position = Vector2(40, 24)
	add_child(title)

	var sub := _label(15, COLOR_DIM)
	sub.text = "本地调试大厅（M3 占位界面）"
	sub.position = Vector2(40, 62)
	add_child(sub)

	var c1 := _label(16, COLOR_WHITE)
	c1.text = "昵称"
	c1.position = Vector2(40, 130)
	add_child(c1)
	nickname_edit = _edit(Vector2(40, 158), Vector2(320, 40))
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		nickname_edit.text = str(gs.nickname)
	add_child(nickname_edit)

	var c2 := _label(16, COLOR_WHITE)
	c2.text = "服务器"
	c2.position = Vector2(40, 220)
	add_child(c2)
	address_edit = _edit(Vector2(40, 248), Vector2(220, 40))
	address_edit.text = AppMode.address
	add_child(address_edit)
	port_edit = _edit(Vector2(272, 248), Vector2(88, 40))
	port_edit.text = str(AppMode.port)
	add_child(port_edit)

	connect_btn = _button("连接", Vector2(40, 310))
	connect_btn.pressed.connect(_on_connect)
	add_child(connect_btn)

	status_label = _label(15, COLOR_DIM)
	status_label.position = Vector2(40, 370)
	status_label.custom_minimum_size = Vector2(340, 80)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)

	stats_label = _label(15, COLOR_DIM)
	stats_label.position = Vector2(40, 470)
	stats_label.custom_minimum_size = Vector2(340, 40)
	add_child(stats_label)

	# ---- 音量设置 ----
	var vc := _label(15, COLOR_WHITE)
	vc.text = "音乐"
	vc.position = Vector2(40, 528)
	add_child(vc)
	var bgm_slider := HSlider.new()
	bgm_slider.position = Vector2(90, 532)
	bgm_slider.custom_minimum_size = Vector2(260, 20)
	bgm_slider.max_value = 1.0
	bgm_slider.step = 0.05
	add_child(bgm_slider)
	var vc2 := _label(15, COLOR_WHITE)
	vc2.text = "音效"
	vc2.position = Vector2(40, 566)
	add_child(vc2)
	var sfx_slider := HSlider.new()
	sfx_slider.position = Vector2(90, 570)
	sfx_slider.custom_minimum_size = Vector2(260, 20)
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	add_child(sfx_slider)
	var gs2 := get_node_or_null("/root/GameSettings")
	if gs2 != null:
		bgm_slider.value = float(gs2.bgm_volume)
		sfx_slider.value = float(gs2.sfx_volume)
	bgm_slider.value_changed.connect(func(v: float) -> void:
		var g := get_node_or_null("/root/GameSettings")
		if g != null:
			g.bgm_volume = v
			g.save_settings()
		Audio.apply_volumes())
	sfx_slider.value_changed.connect(func(v: float) -> void:
		var g := get_node_or_null("/root/GameSettings")
		if g != null:
			g.sfx_volume = v
			g.save_settings()
		Audio.apply_volumes()
		Audio.play("click"))

	var c3 := _label(18, COLOR_GOLD)
	c3.text = "房间"
	c3.position = Vector2(430, 120)
	add_child(c3)

	quick_btn = _button("快速匹配", Vector2(430, 158))
	quick_btn.pressed.connect(func() -> void: net.quick_match(_gather_rules()))
	add_child(quick_btn)
	create_btn = _button("创建房间", Vector2(548, 158))
	create_btn.pressed.connect(func() -> void: net.create_room(_gather_rules()))
	add_child(create_btn)
	code_edit = _edit(Vector2(666, 162), Vector2(140, 38))
	code_edit.placeholder_text = "房间码"
	add_child(code_edit)
	join_btn = _button("加入", Vector2(820, 158))
	join_btn.pressed.connect(func() -> void: net.join_room(code_edit.text.strip_edges()))
	add_child(join_btn)

	room_label = _label(17, COLOR_WHITE)
	room_label.position = Vector2(430, 226)
	room_label.custom_minimum_size = Vector2(700, 150)
	add_child(room_label)

	fill_btn = _button("空位加AI", Vector2(430, 386))
	fill_btn.pressed.connect(func() -> void: net.fill_bots())
	add_child(fill_btn)
	start_btn = _button("开始游戏", Vector2(548, 386))
	start_btn.pressed.connect(func() -> void: net.start_game())
	add_child(start_btn)
	leave_btn = _button("离开房间", Vector2(666, 386))
	leave_btn.pressed.connect(func() -> void: net.leave_room())
	add_child(leave_btn)

	# ---- 规则设置（房主可改，开局前生效）----
	var c4 := _label(16, COLOR_GOLD)
	c4.text = "规则设置"
	c4.position = Vector2(430, 446)
	add_child(c4)
	chk_joker = _check("带王", Vector2(430, 478))
	add_child(chk_joker)
	chk_revolution = _check("革命", Vector2(530, 478))
	add_child(chk_revolution)
	chk_stairs = _check("階段", Vector2(630, 478))
	add_child(chk_stairs)
	chk_eight = _check("8切", Vector2(730, 478))
	add_child(chk_eight)
	var rounds_lbl := _label(15, COLOR_WHITE)
	rounds_lbl.text = "局数"
	rounds_lbl.position = Vector2(830, 484)
	add_child(rounds_lbl)
	rounds_option = OptionButton.new()
	for r: int in [1, 3, 5]:
		rounds_option.add_item(str(r) + " 局", r)
	rounds_option.select(1)
	rounds_option.position = Vector2(872, 478)
	rounds_option.custom_minimum_size = Vector2(90, 34)
	add_child(rounds_option)
	save_settings_btn = _button("保存设置", Vector2(430, 530))
	save_settings_btn.pressed.connect(func() -> void:
		net.set_settings(_gather_rules())
		_set_status("已提交设置（房主）", COLOR_DIM))
	add_child(save_settings_btn)

	# ---- 快捷表情（房间内）----
	var c5 := _label(16, COLOR_GOLD)
	c5.text = "表情"
	c5.position = Vector2(430, 600)
	add_child(c5)
	for i in EMOJIS.size():
		var id := i
		var eb := _button(EMOJIS[i], Vector2(430 + i * 58, 632))
		eb.custom_minimum_size = Vector2(48, 44)
		eb.pressed.connect(func() -> void:
			net.send_emoji(id)
			_set_status("你: " + EMOJIS[id], COLOR_DIM))
		add_child(eb)

	for b: Button in [quick_btn, create_btn, join_btn, fill_btn, start_btn, leave_btn, save_settings_btn]:
		b.disabled = true


func _bind_net() -> void:
	net.connected_ok.connect(func() -> void:
		_set_status("已连接，可以创建或加入房间", COLOR_GREEN)
		for b: Button in [quick_btn, create_btn, join_btn]:
			b.disabled = false
		net.request_stats())
	net.connection_failed.connect(func() -> void:
		_set_status("连接失败，请检查地址端口", COLOR_RED))
	net.server_disconnected.connect(func() -> void:
		_set_status("与服务器断开，自动重连中…", COLOR_RED))
	net.errored.connect(func(code: String, msg: String) -> void:
		_set_status("错误 %s: %s" % [code, msg], COLOR_RED))
	net.kicked_off.connect(func(reason: String) -> void:
		if reason == "version":
			_set_status("版本不符，请更新客户端", COLOR_RED)
		else:
			_set_status("已被移出房间（%s）" % reason, COLOR_RED))
	net.stats_updated.connect(func(entry: Dictionary) -> void:
		if entry.is_empty():
			stats_label.text = "战绩：暂无（打完一场后生成）"
		else:
			stats_label.text = "战绩：%d 场 / 胜 %d / 累计 %+d 分" % [
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


func _on_connect() -> void:
	Audio.play("click")
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		gs.nickname = nickname_edit.text.strip_edges()
		if gs.nickname == "":
			gs.nickname = "玩家"
		gs.save_settings()
	var port := int(port_edit.text.strip_edges())
	if port <= 0:
		port = 24565
	_set_status("连接中 %s:%d …" % [address_edit.text.strip_edges(), port], COLOR_DIM)
	net.connect_to(address_edit.text.strip_edges(), port)


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


func _on_room_state(state: Dictionary) -> void:
	var lines: Array = []
	lines.append("房间码：%s    （把码发给朋友加入）" % str(state.get("room_code", "------")))
	for p in state["players"]:
		if bool(p.get("empty", false)):
			lines.append("  座位%d：（空位）" % (int(p["seat"]) + 1))
			continue
		var mark := "房主 " if int(p["seat"]) == int(state.get("host_seat", 0)) else ""
		var on := "" if bool(p.get("online", true)) else "（离线→AI托管）"
		var bot := " [AI]" if bool(p.get("is_bot", false)) else ""
		lines.append("  座位%d：%s%s%s%s" % [
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


func _button(text: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size = Vector2(96, 38)
	b.add_theme_font_size_override("font_size", 16)
	return b


func _check(text: String, pos: Vector2) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.position = pos
	return c
