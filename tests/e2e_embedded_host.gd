## E2E 单进程: 本机开房(内嵌服务器分支) + 本机客户端 → 建房 → 补 AI → 打完整场。
## 验证 net_node.start_embedded 的 MultiplayerAPI 分支 RPC 通路(本机开房核心机制)。
## 运行: godot --headless --path . --script tests/e2e_embedded_host.gd
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")

var client_net = null
var created := false
var filled := false
var done := false
var fail_msg := ""
var started := false


func _process(_delta: float) -> bool:
	if not started:
		started = true
		_setup()
	return false


func _setup() -> void:
	var main := Node.new()
	main.name = "Main"
	root.add_child(main)
	var server = NetNodeGd.start_embedded(main, 24678)
	if server == null:
		_fail("内嵌服务器启动失败(端口占用?)")
		return
	server.manager.ai_delay_ms = 60
	server.manager.phase_delay_ms = 250
	client_net = NetNodeGd.new()
	client_net.name = "Net"
	client_net.setup(false)
	main.add_child(client_net)
	client_net.autoplay = true
	client_net.connected_ok.connect(func() -> void:
		print("[e2e-host] 已连接内嵌服务器")
		client_net.create_room())
	client_net.room_state.connect(func(_s: Dictionary) -> void:
		if not created:
			created = true
			print("[e2e-host] 房间就绪，补 AI")
			client_net.fill_bots()
		elif not filled:
			filled = true
			print("[e2e-host] AI 已补满，开局")
			client_net.start_game())
	client_net.view_changed.connect(_on_view)
	var guard := create_timer(75.0)
	guard.timeout.connect(func() -> void:
		if not done:
			_fail("超时"))
	client_net.connect_to("127.0.0.1", 24678)


func _on_view(view: Dictionary) -> void:
	if done or fail_msg != "":
		return
	if str(view["phase"]) == "game_end":
		done = true
		print("[e2e-host] E2E_OK —— 本机开房完整打完一整场")
		quit(0)


func _fail(msg: String) -> void:
	if done or fail_msg != "":
		return
	fail_msg = msg
	print("[e2e-host] FAIL: " + msg)
	quit(1)
