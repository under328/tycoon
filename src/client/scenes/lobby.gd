## 联机大厅（占位美术，M4 换皮）：连接 → 建房/加入/快速匹配 → 开局。
extends Control

signal start_game

const NetNodeGd = preload("res://src/protocol/net_node.gd")

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
var status_label: Label
var room_label: Label


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
	sub.text = "本地调试大厅（M2 占位界面）"
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
	status_label.custom_minimum_size = Vector2(340, 60)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)

	var c3 := _label(18, COLOR_GOLD)
	c3.text = "房间"
	c3.position = Vector2(430, 130)
	add_child(c3)

	quick_btn = _button("快速匹配", Vector2(430, 170))
	quick_btn.pressed.connect(func() -> void: net.quick_match())
	add_child(quick_btn)
	create_btn = _button("创建房间", Vector2(548, 170))
	create_btn.pressed.connect(func() -> void: net.create_room())
	add_child(create_btn)
	code_edit = _edit(Vector2(666, 174), Vector2(140, 38))
	code_edit.placeholder_text = "房间码"
	add_child(code_edit)
	join_btn = _button("加入", Vector2(820, 170))
	join_btn.pressed.connect(func() -> void: net.join_room(code_edit.text.strip_edges()))
	add_child(join_btn)

	room_label = _label(17, COLOR_WHITE)
	room_label.position = Vector2(430, 250)
	room_label.custom_minimum_size = Vector2(700, 160)
	add_child(room_label)

	fill_btn = _button("空位加AI", Vector2(430, 420))
	fill_btn.pressed.connect(func() -> void: net.fill_bots())
	add_child(fill_btn)
	start_btn = _button("开始游戏", Vector2(548, 420))
	start_btn.pressed.connect(func() -> void: net.start_game())
	add_child(start_btn)
	leave_btn = _button("离开房间", Vector2(666, 420))
	leave_btn.pressed.connect(func() -> void: net.leave_room())
	add_child(leave_btn)

	for b: Button in [quick_btn, create_btn, join_btn, fill_btn, start_btn, leave_btn]:
		b.disabled = true


func _bind_net() -> void:
	net.connected_ok.connect(func() -> void:
		_set_status("已连接，可以创建或加入房间", COLOR_GREEN)
		for b: Button in [quick_btn, create_btn, join_btn]:
			b.disabled = false)
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
	net.room_state.connect(_on_room_state)
	net.view_changed.connect(func(_view: Dictionary) -> void:
		start_game.emit())


func _on_connect() -> void:
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
	leave_btn.disabled = false
	for b: Button in [quick_btn, create_btn, join_btn]:
		b.disabled = false


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
