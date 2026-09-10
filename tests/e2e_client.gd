## E2E 双进程实测（客户端侧）。前置：无头服务器已在 127.0.0.1:24575 运行。
## 运行（Git Bash）：
##   godot --headless --path . --server --port 24575 --ai-delay 60 --phase-delay 250 &
##   godot --headless --path . --script tests/e2e_client.gd
## 流程：连接 → 建房 → 补AI → 开局 → 自动打牌 → 第6手后模拟断网 →
##       token 自动重连回座 → 继续打完 → E2E_OK 退出码 0。
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")

var net = null
var created := false
var filled := false
var played_count := 0
var dropped := false
var done := false
var fail_msg := ""


func _initialize() -> void:
	var main := Node.new()
	main.name = "Main"
	root.add_child(main)
	net = NetNodeGd.new()
	net.name = "Net"
	net.setup(false)
	main.add_child(net)
	net.autoplay = true

	net.connected_ok.connect(func() -> void:
		print("[e2e] 已连接")
		net.create_room())
	net.connection_failed.connect(func() -> void:
		_fail("连接失败（服务器没起来？）"))
	net.errored.connect(func(code: String, msg: String) -> void:
		if code != "not_connected":
			print("[e2e] error: %s %s" % [code, msg]))
	net.kicked_off.connect(func(reason: String) -> void:
		_fail("被踢: " + reason))
	net.welcomed.connect(func(seat: int) -> void:
		print("[e2e] welcomed seat=", seat))
	net.rejoined.connect(func() -> void:
		print("[e2e] REJOIN OK（token 回座成功）"))
	net.server_disconnected.connect(func() -> void:
		if dropped:
			print("[e2e] 已断开，等待自动重连…")
		else:
			_fail("非预期断线"))
	net.room_state.connect(func(_state: Dictionary) -> void:
		if not created:
			created = true
			print("[e2e] 房间就绪，补 AI")
			net.fill_bots()
		elif not filled:
			filled = true
			print("[e2e] AI 已补满，开局")
			net.start_game())
	net.game_event.connect(func(event: String, _data: Dictionary) -> void:
		if event == "played":
			played_count += 1)
	net.view_changed.connect(_on_view)

	var guard := create_timer(90.0)
	guard.timeout.connect(func() -> void:
		if not done:
			_fail("超时 stage played=%d dropped=%s" % [played_count, str(dropped)]))

	# 延迟到树就绪后再连接（SceneTree._initialize 阶段 multiplayer 尚不可用）
	net.call_deferred("connect_to", "127.0.0.1", 24575)


func _on_view(view: Dictionary) -> void:
	if done or fail_msg != "":
		return
	var phase := str(view["phase"])
	if phase == "game_end":
		done = true
		if dropped:
			print("[e2e] E2E_OK —— 断线重连后完整打完整场")
		else:
			print("[e2e] E2E_OK —— 完整打完整场（未测断线）")
		quit(0)
		return
	if phase == "play" and not dropped and played_count >= 6:
		dropped = true
		print("[e2e] 第 %d 手后模拟断网" % played_count)
		net.drop_connection()


func _fail(msg: String) -> void:
	if done or fail_msg != "":
		return
	fail_msg = msg
	print("[e2e] FAIL: " + msg)
	quit(1)
