## 双真人格斗 PvP E2E(补玩法覆盖)。两个本脚本实例:
##   host: godot --path . --script tests/e2e_fight_pvp2.gd -- host
##   join: godot --path . --script tests/e2e_fight_pvp2.gd -- join
## host(内嵌服 24689)建 mode=fight 房并发布房间码文件 → join 读取加入 →
## 房主开局 → 双方各自驱动『二选一』抽牌与行动 → 先胜 3 回合终局回房 →
## 双方各自打印 FIGHT2_OK(退出码 0)。
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")
const CODE_FILE := "user://fight2_code.txt"

var main: Node = null
var net = null
var role := "join"
var f := 0
var started := false      # 房主已开局
var saw_over := false     # 收到终局 fight 视图
var done := false
var _join_started := false
var _code_written := false
var server = null


func _initialize() -> void:
	root.size = Vector2i(320, 200)
	for a in OS.get_cmdline_user_args():
		role = a


func _ready_hook() -> void:
	net.room_state.connect(_on_room_state)
	net.fight_state.connect(_on_fight_state)
	net.errored.connect(func(code: String, msg: String) -> void:
		print("[fp2:%s] ERR %s %s" % [role, code, msg])
		if role == "host" and server != null:
			for r in server.manager.rooms.values():
				var mc = r.get("match_ctl")
				print("[fp2:host] server phase=", str(mc.state.get("phase", "?")),
						" fighters=", str(mc.state.get("fighters", []))))
	if role == "host":
		net.connected_ok.connect(func() -> void:
			print("[fp2] 已连接, 创建格斗房间")
			net.create_room({"mode": "fight"}))
		net.connect_to("127.0.0.1", 24689)
	# 加入者的连接+入房由 _process 轮询房间码文件后触发(见下)


func _process(_delta: float) -> bool:
	f += 1
	if f == 10 and main == null:
		main = Node.new()
		main.name = "Main"
		root.add_child(main)
		net = NetNodeGd.new()
		net.name = "Net"
		net.setup(false)
		main.add_child(net)
		if role == "host":
			server = NetNodeGd.start_embedded(main, 24689)
			if server == null:
				print("[fp2] FAIL 内嵌服启动失败(端口占用?)")
				quit(1)
				return true
			server.manager.ai_delay_ms = 60
			server.manager.phase_delay_ms = 300
		_ready_hook()
	elif role == "join" and f > 0 and f % 30 == 0 and not started and not done:
		# 加入者: 房间码文件就绪后触发连接(仅一次, 由 _join_started 防重复)
		if not _join_started:
			var cf := FileAccess.open(CODE_FILE, FileAccess.READ)
			if cf != null:
				var code := cf.get_as_text().strip_edges()
				cf.close()
				if code != "":
					_join_started = true
					print("[fp2:join] 拿到房间码 ", code, ", 连接+加入")
					net.connected_ok.connect(func() -> void:
						print("[fp2:join] 已连接")
						net.join_room(code))
					net.connect_to("127.0.0.1", 24689)
	if f > 60 * 180 and not done:
		print("[fp2] FAIL 总超时 role=", role)
		quit(1)
	return false


func _on_room_state(state: Dictionary) -> void:
	if done:
		return
	if role == "host" and not _code_written:
		var cf := FileAccess.open(CODE_FILE, FileAccess.WRITE)
		cf.store_string(str(state.get("room_code", "")))
		cf.close()
		_code_written = true
	var humans := 0
	for p in state.get("players", []):
		if not bool(p.get("empty", true)) and not bool(p.get("is_bot", false)):
			humans += 1
	var host: bool = int(state.get("host_seat", -1)) == int(net.my_seat)
	if humans >= 2 and not started:
		started = true
		if role == "host" and host:
			print("[fp2] 双方到齐, 开局")
			net.start_game()
	if started and saw_over and not done:
		done = true
		print("[fp2] FIGHT2_OK —— 双真人格斗对局完整打完(回房) role=", role)
		quit(0)


var _dbg := 0
func _on_fight_state(view: Dictionary) -> void:
	if done:
		return
	_dbg += 1
	if _dbg % 10 == 1:
		print("[fp2:%s] state#%d phase=%s round=%s my_done=%s slots=%s" % [
				role, _dbg, str(view.get("phase")), str(view.get("round_num")),
				str((view.get("my", {}) as Dictionary).get("done")),
				str((view.get("my", {}) as Dictionary).get("slots", []).size())])
	var phase := str(view.get("phase", ""))
	if phase == "draft":
		var my: Dictionary = view.get("my", {})
		if not bool(my.get("done", true)):
			var pair: Array = my.get("pair", [])
			if (pair as Array).is_empty():
				return
			var cand: int = int(pair[0])
			var slot := -1
			if (my.get("slots", []) as Array).size() >= 5:
				slot = 0
			net.send_fight_pick(cand, slot)
	elif phase == "battle":
		if bool(view.get("my_turn", false)):
			net.send_fight_act("attack")
	elif phase == "over" and not saw_over:
		saw_over = true
		print("[fp2] over: 胜者座位 ", int(view.get("winner", -1)),
				" 比分 ", str(view.get("score", {})))
