## 联机肉鸽死锁复现: 内嵌服务器 → 建肉鸽房 → 补 AI → 开局 → 采样 phase 30 秒
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")

var main: Node = null
var client_net = null
var booted := false
var created := false
var filled := false
var started := false
var samples := {}
var f := 0
var done := false


func _process(_delta: float) -> bool:
	if not booted:
		booted = true
		_setup()
		return false
	if done:
		return false
	f += 1
	if created and disc_ok(f) and not filled:
		filled = true
		print("[t=%d] room created — fill bots + start" % f)
		client_net.fill_bots()
		client_net.start_game()
	if filled and f % 60 == 0:
		var v: Dictionary = client_net.latest_view
		var ph := str(v.get("phase", "none"))
		samples[ph] = int(samples.get(ph, 0)) + 1
		print("[t=%d] phase=%s" % [f, ph])
	if f >= 2400:
		done = true
		var v: Dictionary = client_net.latest_view
		var final_ph := str(v.get("phase", "none"))
		if final_ph == "draft":
			print("[repro] CONFIRMED: 联机肉鸽死锁在 draft — AI 不选卡, 无推进")
		elif final_ph == "play":
			print("[repro] PASS: 已进入 play")
		else:
			print("[repro] final=%s samples=%s" % [final_ph, str(samples)])
		quit(0)
	return false


## room_state 已到即视为建房成功(首帧后再启动流程)
var started_poll := false
func disc_ok(_f: int) -> bool:
	if not started_poll:
		started_poll = true
		return false
	return created


func _setup() -> void:
	main = Node.new()
	main.name = "Main"
	root.add_child(main)
	var server = NetNodeGd.start_embedded(main, 24679)
	if server == null:
		print("[repro] FAIL: 内嵌服务器启动失败")
		quit(1)
		return
	server.manager.ai_delay_ms = 60
	server.manager.phase_delay_ms = 250
	client_net = NetNodeGd.new()
	client_net.name = "Net"
	client_net.setup(false)
	main.add_child(client_net)
	client_net.autoplay = true
	client_net.connected_ok.connect(func() -> void:
		print("[e2e] 已连接 — 建肉鸽房")
		client_net.create_room({"mode": "rogue", "rogue": true, "with_joker": true,
				"revolution": true, "rounds": 3, "stakes": 1}))
	client_net.room_state.connect(func(_s: Dictionary) -> void:
		if not created:
			created = true)
	client_net.connect_to("127.0.0.1", 24679)
