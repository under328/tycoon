## E2E 三真人同房 + 1AI 整场（B5）。专用服务器(24595)上:
##   host 实例建房并把房间码写入 user://quad_code.txt;
##   两个 join 实例轮询房间码加入 → 房主见 3 人后补 1 AI → 开局 →
##   三方 autoplay 打完整场。三方各自打印 QUAD_OK(座位/人数/分数)。
## 运行: godot --headless --path . --script tests/e2e_quad.gd -- role=host|join
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")

var net = null
var role := "join"
var created := false
var joined := false
var filled := false
var started := false
var humans_seen := -1
var done := false
var fail_msg := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("role="):
			role = a.substr(5)
	var main := Node.new()
	main.name = "Main"
	root.add_child(main)
	net = NetNodeGd.new()
	net.name = "Net"
	net.setup(false)
	main.add_child(net)
	net.autoplay = true

	net.connected_ok.connect(func() -> void:
		print("[quad:%s] 已连接" % role)
		if role == "host":
			net.create_room())
	net.connection_failed.connect(func() -> void:
		_fail("连接失败"))
	net.errored.connect(func(code: String, msg: String) -> void:
		if code != "not_connected":
			print("[quad] error: %s %s" % [code, msg]))
	net.kicked_off.connect(func(reason: String) -> void:
		_fail("被踢: " + reason))
	net.room_state.connect(_on_room)
	net.view_changed.connect(_on_view)

	var guard := create_timer(240.0)
	guard.timeout.connect(func() -> void:
		if not done:
			_fail("超时 role=%s" % role))

	if role != "host":
		# 加入者: 轮询房主发布的房间码文件, 拿到即 join
		var poll := create_timer(1.0)
		poll.timeout.connect(_poll_code)

	net.call_deferred("connect_to", "127.0.0.1", 24595)


func _poll_code() -> void:
	if joined or done or fail_msg != "":
		return
	var f := FileAccess.open("user://quad_code.txt", FileAccess.READ)
	if f == null:
		return
	var code := f.get_as_text().strip_edges()
	f.close()
	if code == "":
		return
	joined = true
	print("[quad:join] 拿到房间码 %s, 加入" % code)
	net.join_room(code)


func _on_room(state: Dictionary) -> void:
	if done or fail_msg != "":
		return
	var humans := 0
	for p in state["players"]:
		if not bool(p.get("empty", true)) and not bool(p.get("is_bot", false)):
			humans += 1
	humans_seen = humans
	var host: bool = int(state.get("host_seat", -1)) == net.my_seat
	if role == "host":
		if not created:
			created = true
			var f := FileAccess.open("user://quad_code.txt", FileAccess.WRITE)
			f.store_string(str(state.get("room_code", "")))
			f.close()
			print("[quad:host] 房间码 %s 已发布" % str(state.get("room_code", "")))
		elif host and humans == 3 and not filled:
			filled = true
			print("[quad:host] 三人到齐, 补 1 AI")
			net.fill_bots()
		elif host and filled and not started:
			started = true
			print("[quad:host] 开局")
			net.start_game()
	else:
		print("[quad:%s] 已入房 humans=%d" % [role, humans])


func _on_view(view: Dictionary) -> void:
	if done or fail_msg != "":
		return
	if str(view["phase"]) == "game_end":
		done = true
		var scores: Array = view["scores"]
		if scores.size() != 4:
			_fail("分数座位数=%d 应为 4" % scores.size())
			return
		if humans_seen != 3:
			_fail("终局视角 humans=%d 应为 3" % humans_seen)
			return
		print("[quad:%s] QUAD_OK seat=%d humans=%d scores=%s" % [
				role, int(view["my_seat"]), humans_seen, str(scores)])
		quit(0)


func _fail(msg: String) -> void:
	if done or fail_msg != "":
		return
	fail_msg = msg
	print("[quad] FAIL: " + msg)
	quit(1)
