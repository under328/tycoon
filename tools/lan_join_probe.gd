## 跨机联机加入探测(C3): 加入另一台电脑上已开房间, 验证真实局域网联机。
## 用法: godot --headless --path . --script tools/lan_join_probe.gd -- <IP> <房号>
## 流程: 连接 → join_room → 打印双方玩家列表 → 发一条聊天 → 观察 20s → 退出。
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")

var net = null
var address := ""
var code := ""
var joined := false
var frames := 0
var chat_sent := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if address == "":
			address = a
		elif code == "":
			code = a
	print("[lan] 目标 %s:%d 房间 %s" % [address, 24565, code])
	var main := Node.new()
	main.name = "Main"
	root.add_child(main)
	net = NetNodeGd.new()
	net.name = "Net"
	net.setup(false)
	main.add_child(net)

	net.connected_ok.connect(func() -> void:
		print("[lan] 已连接对方主机, 加入房间 ", code)
		net.join_room(code))
	net.connection_failed.connect(func() -> void:
		print("[lan] FAIL 连接失败")
		quit(1))
	net.kicked_off.connect(func(reason: String) -> void:
		print("[lan] FAIL 被踢: ", reason)
		quit(1))
	net.room_state.connect(_on_room)
	net.errored.connect(func(code2: String, msg: String) -> void:
		print("[lan] error: %s %s" % [code2, msg]))
	var guard := create_timer(60.0)
	guard.timeout.connect(func() -> void:
		print("[lan] 超时退出 joined=", joined)
		quit(0 if joined else 1))
	net.call_deferred("connect_to", address, 24565)


func _on_room(state: Dictionary) -> void:
	var names := []
	for p in state["players"]:
		if not bool(p.get("empty", true)):
			names.append("#%d %s%s" % [int(p["seat"]), str(p.get("name", "?")),
					"(bot)" if bool(p.get("is_bot", false)) else ""])
	print("[lan] 房间 %s 玩家: %s" % [str(state.get("room_code", "?")), ", ".join(names)])
	if not joined:
		joined = true
		print("[lan] CROSS_OK —— 跨机加入成功(等待对方视角)")
		net.send_chat("[BOT] 测试机已从本机加入, 联机通路正常")
	# 加入 40 帧后发聊天并保持观察; 总观察 20s 退出
	frames += 1
	if not chat_sent and frames > 10:
		chat_sent = true
	if frames > 1200:
		print("[lan] 观察 20s 结束, 退出码 0")
		quit(0)


func _process(_delta: float) -> bool:
	if joined:
		frames += 1
		if frames == 30 and not chat_sent:
			chat_sent = true
			net.send_chat("[BOT] 测试机已从本机加入, 联机通路正常")
		if frames > 1200:
			print("[lan] 观察 20s 结束, 联机通路保持正常")
			quit(0)
	return false
