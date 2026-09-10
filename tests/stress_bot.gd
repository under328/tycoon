## 压测机器人（客户端侧）。连上服务器后不断"建房→补AI→开局→打完→再来"。
## 运行（需先起服务器于 24575）：
##   godot --headless --path . --script tests/stress_bot.gd
## 环境变量 STRESS_SEC 控制运行秒数（默认 120），结束时打印 MATCHES=<场数> 并退出 0。
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")

var net = null
var created := false
var filled := false
var matches := 0
var fail_msg := ""


func _initialize() -> void:
	var main := Node.new()
	main.name = "Main"
	root.add_child(main)
	net = NetNodeGd.new()
	net.name = "Net"
	net.setup(false)
	net.autoplay = true
	main.add_child(net)

	net.connected_ok.connect(func() -> void: net.create_room())
	net.errored.connect(func(code: String, _msg: String) -> void:
		if code != "not_connected":
			print("[bot] error: " + code))
	net.room_state.connect(func(_state: Dictionary) -> void:
		if not created:
			created = true
			net.fill_bots()
		elif not filled:
			filled = true
			net.start_game())
	net.game_event.connect(func(event: String, _data: Dictionary) -> void:
		if event == "game_end":
			matches += 1
			# 再来一轮：回房间重新开局
			created = false
			filled = false
			net.leave_room()
			net.create_room())

	var sec := 120.0
	var env := OS.get_environment("STRESS_SEC")
	if env != "":
		sec = float(env)
	var guard := create_timer(sec)
	guard.timeout.connect(func() -> void:
		print("MATCHES=%d" % matches)
		quit(0))

	net.call_deferred("connect_to", "127.0.0.1", 24575)
