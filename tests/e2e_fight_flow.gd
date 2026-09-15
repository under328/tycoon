## E2E 单进程: 内嵌服务器 + 客户端 → 格斗对战房间(mode=fight) → 全流程。
## 验证: ① 格斗房间开局(1 人 + AI 格斗者)下发 s_fight_state;
##       ② c_fight_pick 选牌通路 → battle;  ③ c_fight_act 行动通路 + AI 对手;
##       ④ 终局 over(胜者产生) → 服务器收尾回房(s_room_state)。
## 运行: godot --headless --path . --script tests/e2e_fight_flow.gd
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")

var client_net = null
var booted := false
var created := false       # 房间已建(mode=fight)
var started := false       # 已发 start_game
var picked := false        # 已提交选牌
var acts := 0              # 已执行的行动数
var saw_battle := false
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
	var guard := create_timer(90.0)
	guard.timeout.connect(func() -> void:
		if not done:
			_fail("超时(acts=%d battle=%s)" % [acts, str(saw_battle)]))
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
		print("[e2e-fight] E2E_OK —— 联机格斗全流程: 选牌→战斗→终局→回房")
		quit(0)


func _on_fight_state(view: Dictionary) -> void:
	if done or fail_msg != "":
		return
	var phase := str(view.get("phase", ""))
	if phase == "pick" and not picked:
		picked = true
		var cands: Array = view.get("candidates", [])
		if cands.size() != 10:
			_fail("候选应为 10 张: %d" % cands.size())
			return
		print("[e2e-fight] 选牌阶段, 提交 5 张")
		client_net.send_fight_pick((cands as Array).slice(0, 5))
	elif phase == "battle":
		saw_battle = true
		if bool(view.get("my_turn", false)) and acts < 500:
			acts += 1
			client_net.send_fight_act("attack")
	elif phase == "over":
		if int(view.get("winner", -1)) < 0:
			_fail("终局无胜者")
			return
		print("[e2e-fight] 终局: 胜者座位 %d (我=%s)" % [
				int(view.get("winner", -1)),
				"是" if int(view.get("winner", -1)) == int(view.get("my_seat", -2))
						else "否"])


func _fail(msg: String) -> void:
	if done or fail_msg != "":
		return
	fail_msg = msg
	print("[e2e-fight] FAIL: " + msg)
	quit(1)
