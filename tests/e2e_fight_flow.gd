## E2E 单进程: 内嵌服务器 + 客户端 → 格斗对战房间(mode=fight) → 全流程。
## 验证: ① 格斗房间开局(1 人 + AI 格斗者)下发 s_fight_state;
##       ② 逐回合『二选一』抽牌(c_fight_pick)→ 5 槽编成;
##       ③ 每回合玩家之间对战(无怪), c_fight_act 行动通路 + AI 对手;
##       ④ 先胜 3 回合终局 → 服务器收尾回房(s_room_state)。
## 运行: godot --headless --path . --script tests/e2e_fight_flow.gd
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")

var client_net = null
var booted := false
var created := false       # 房间已建(mode=fight)
var started := false       # 已发 start_game
var picks := 0             # 累计选牌次数
var acts := 0              # 累计行动次数
var saw_battle := false
var max_round := 0
var ended := false         # 收到收尾后的 room_state(match_ctl 已清)
var done := false
var fail_msg := ""


func _process(_delta: float) -> bool:
	if not booted:
		booted = true
		_setup()
		return false
	return false


func _setup() -> void:
	var main := Node.new()
	main.name = "Main"
	root.add_child(main)
	var server = NetNodeGd.start_embedded(main, 24679)
	if server == null:
		_fail("内嵌服务器启动失败(端口占用?)")
		return
	server.manager.ai_delay_ms = 60
	server.manager.phase_delay_ms = 300
	client_net = NetNodeGd.new()
	client_net.name = "Net"
	client_net.setup(false)
	main.add_child(client_net)
	client_net.connected_ok.connect(func() -> void:
		print("[e2e-fight] 已连接, 创建格斗房间")
		client_net.create_room({"mode": "fight"}))
	client_net.room_state.connect(_on_room_state)
	client_net.fight_state.connect(_on_fight_state)
	client_net.errored.connect(func(code: String, msg: String) -> void:
		if code != "not_connected":
			print("[e2e-fight] server error: %s %s" % [code, msg]))
	var guard := create_timer(120.0)
	guard.timeout.connect(func() -> void:
		if not done:
			_fail("超时(acts=%d battle=%s round=%d)" % [acts, str(saw_battle),
					max_round]))
	client_net.connect_to("127.0.0.1", 24679)


func _on_room_state(state: Dictionary) -> void:
	if done or fail_msg != "":
		return
	var mode: String = str((state.get("settings", {}) as Dictionary)
			.get("mode", "normal"))
	if not created:
		created = true
		if mode != "fight":
			_fail("房间模式不是 fight: " + mode)
			return
		print("[e2e-fight] 格斗房间就绪, 开局(1 人 + AI 格斗者)")
		started = true
		client_net.start_game()
		return
	# 开局后再次收到 room_state = 对局已收尾回房
	if started and saw_battle and not ended:
		ended = true
		done = true
		print("[e2e-fight] E2E_OK —— 联机格斗全流程: %d 次选牌, %d 次行动, 最远第 %d 回合 → 终局 → 回房" % [
				picks, acts, max_round])
		quit(0)


func _on_fight_state(view: Dictionary) -> void:
	if done or fail_msg != "":
		return
	max_round = maxi(max_round, int(view.get("round_num", 1)))
	var phase := str(view.get("phase", ""))
	if phase == "draft":
		var my: Dictionary = view.get("my", {})
		if not bool(my.get("done", true)) and picks < 200:
			var pair: Array = my.get("pair", [])
			if (pair as Array).is_empty():
				return
			var cand: int = pair[0]
			var slot := -1
			if cand < 100 and ((my.get("slots", []) as Array).size() >= 5):
				slot = 0
			picks += 1
			client_net.send_fight_pick(cand, slot)
	elif phase == "battle":
		saw_battle = true
		if bool(view.get("my_turn", false)) and acts < 500:
			acts += 1
			if acts % 25 == 0:
				print("[e2e-fight] act #%d r=%s hp=%s" % [acts,
						view.get("round_num"), str(view.get("hp", {}))])
			client_net.send_fight_act("attack")
	elif phase == "over":
		var w := int(view.get("winner", -1))
		if w < 0:
			_fail("终局无胜者")
			return
		print("[e2e-fight] 终局: 胜者座位 %d (我=%s), 比分 %s" % [w,
				"是" if w == int(view.get("my_seat", -2)) else "否",
				str(view.get("score", {}))])


func _fail(msg: String) -> void:
	if done or fail_msg != "":
		return
	fail_msg = msg
	print("[e2e-fight] FAIL: " + msg)
	quit(1)
