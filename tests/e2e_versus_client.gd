## 双真人对战 E2E（客户端侧）。两个本脚本实例先后运行：
##   都 quick_match 进入同一房间 → 房主补 2 个 AI → 开局 → 双方自动打完整场。
## 两者都打印 VERSUS_OK 且退出码 0 才算通过。
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")

var net = null
var filled := false
var started := false
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
		print("[pvp] 已连接, 快速匹配")
		net.quick_match())
	net.errored.connect(func(code: String, msg: String) -> void:
		if code != "not_connected":
			print("[pvp] error: %s %s" % [code, msg]))
	net.kicked_off.connect(func(reason: String) -> void:
		_fail("被踢: " + reason))
	net.welcomed.connect(func(seat: int) -> void:
		print("[pvp] welcomed seat=", seat))
	net.server_disconnected.connect(func() -> void:
		print("[pvp] 断线, 自动重连…"))
	net.room_state.connect(_on_room_state)
	net.view_changed.connect(_on_view)

	var guard := create_timer(150.0)
	guard.timeout.connect(func() -> void:
		if not done:
			_fail("超时"))

	net.call_deferred("connect_to", "127.0.0.1", 24585)


func _on_room_state(state: Dictionary) -> void:
	if done or fail_msg != "":
		return
	var humans := 0
	for p in state["players"]:
		if not bool(p.get("empty", true)) and not bool(p.get("is_bot", false)):
			humans += 1
	var host: bool = int(state.get("host_seat", -1)) == net.my_seat
	if host and humans == 2 and not filled:
		filled = true
		print("[pvp] 两人到齐, 房主补 AI")
		net.fill_bots()
	elif host and filled and not started:
		started = true
		print("[pvp] 开局")
		net.start_game()


func _on_view(view: Dictionary) -> void:
	if done or fail_msg != "":
		return
	if str(view["phase"]) == "game_end":
		done = true
		print("[pvp] VERSUS_OK —— 双真人对局完整打完 (我=%d分)" %
				int(view["scores"][int(view["my_seat"])]))
		quit(0)


func _fail(msg: String) -> void:
	if done or fail_msg != "":
		return
	fail_msg = msg
	print("[pvp] FAIL: " + msg)
	quit(1)
