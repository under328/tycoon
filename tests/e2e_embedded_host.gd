## E2E 单进程: 本机开房(内嵌服务器分支) + 本机客户端 → 局域网发现验证 →
## 建房 → 补 AI → 打完整场。
## 验证: ① start_embedded 的 MultiplayerAPI 分支 RPC 通路(本机开房核心机制);
##       ② 局域网发现: UDP 广播+回环单播查询 → 主机回包含本房间(一键加入通路)。
## 运行: godot --headless --path . --script tests/e2e_embedded_host.gd
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")
const LanDisc = preload("res://src/protocol/lan_discovery.gd")

var client_net = null
var booted := false        # 一次性 setup 闩
var created := false       # 收到首个 room_state(房间已建, 尚未补 AI)
var disc_sent := false
var disc_frames := 0
var disc_ok := false       # 发现回包已确认包含本房间
var filled := false
var started := false       # 已发 start_game
var done := false
var fail_msg := ""
var disc: PacketPeerUDP = null


func _process(_delta: float) -> bool:
	if not booted:
		booted = true
		_setup()
		return false
	if fail_msg != "":
		return false
	# 阶段闸门: 房间建好(仍空位) → 探测发现 → 确认可见 → 补 AI → 开局
	if created and not disc_ok:
		_disc_poll()
	elif created and disc_ok and not filled:
		filled = true
		print("[e2e-host] 局域网发现 OK — 补 AI")
		client_net.fill_bots()
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
			print("[e2e-host] 房间就绪，探测局域网发现(空位房间应可见)")
		elif filled and not started:
			started = true
			print("[e2e-host] AI 已补满，开局")
			client_net.start_game())
	client_net.view_changed.connect(_on_view)
	var guard := create_timer(75.0)
	guard.timeout.connect(func() -> void:
		if not done:
			_fail("超时"))
	client_net.connect_to("127.0.0.1", 24678)


## 局域网发现: 广播 + 本机回环单播查询 → 等回包含自己刚建的房间
func _disc_poll() -> void:
	if disc == null:
		disc = PacketPeerUDP.new()
		disc.bind(0)  # 绑定随机端口收应答(未 bind 的 socket 不收包)
		disc.set_broadcast_enabled(true)
	if not disc_sent:
		disc.set_dest_address("255.255.255.255", 24678 + LanDisc.PORT_OFFSET)
		disc.put_packet(LanDisc.make_query())
		disc.set_dest_address("127.0.0.1", 24678 + LanDisc.PORT_OFFSET)
		disc.put_packet(LanDisc.make_query())
		disc_sent = true
		return
	disc_frames += 1
	while disc.get_available_packet_count() > 0:
		var r := LanDisc.parse_reply(disc.get_packet())
		for room in r.get("rooms", []):
			if str(room["code"]) == str(client_net.last_room_state.get("room_code", "-")) \
					and bool(room["open"]):
				disc_ok = true
	if disc_frames > 1200 and not disc_ok:
		_fail("局域网发现无应答(端口 %d)" % (24678 + LanDisc.PORT_OFFSET))


func _on_view(view: Dictionary) -> void:
	if done or fail_msg != "":
		return
	if str(view["phase"]) == "game_end":
		if not disc_ok:
			_fail("对局打完但局域网发现未通过")
			return
		done = true
		print("[e2e-host] E2E_OK —— 本机开房完整打完一整场")
		quit(0)


func _fail(msg: String) -> void:
	if done or fail_msg != "":
		return
	fail_msg = msg
	print("[e2e-host] FAIL: " + msg)
	quit(1)
