## 双真人肉鸽在线 E2E(补玩法覆盖)。两个本脚本实例:
##   host: godot --headless --path . --script tests/e2e_rogue_pvp2.gd -- host
##   join: 同 -- join
## host(内嵌服 24691)建 mode=rogue 房并发布房间码 → join 加入 →
## 房主补 2 AI 开局 → 命运卡 draft 双方抢选(先到先得) + autoplay 打牌 →
## game_end 后双方打印 ROGUE2_OK(分数一致)。
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")
const CODE_FILE := "user://rogue2_code.txt"

var main: Node = null
var net = null
var role := "join"
var f := 0
var started := false
var done := false
var my_score := 9999
var _join_started := false
var _code_written := false
var server = null
var _last_phase := ""


func _initialize() -> void:
	root.size = Vector2i(320, 200)
	for a in OS.get_cmdline_user_args():
		role = a


func _process(_delta: float) -> bool:
	f += 1
	if f == 10 and main == null:
		main = Node.new()
		main.name = "Main"
		root.add_child(main)
		net = NetNodeGd.new()
		net.name = "Net"
		net.setup(false)
		net.autoplay = true   # 出牌/换牌自动代打(命运卡 draft 由脚本驱动)
		main.add_child(net)
		net.room_state.connect(_on_room_state)
		net.view_changed.connect(_on_view)
		net.errored.connect(func(code: String, msg: String) -> void:
			print("[rg2:%s] ERR %s %s" % [role, code, msg]))
		if role == "host":
			server = NetNodeGd.start_embedded(main, 24691)
			if server == null:
				print("[rg2] FAIL 内嵌服启动失败")
				quit(1)
				return true
			server.manager.ai_delay_ms = 60
			server.manager.phase_delay_ms = 250
			net.connected_ok.connect(func() -> void:
				# turn_seconds=5: 缩短人类回合托管等待, 加速 E2E
				net.create_room({"mode": "rogue", "turn_seconds": 5}))
			net.connect_to("127.0.0.1", 24691)
	elif role == "host" and server != null and f > 120 and f % 60 == 0:
		for r in server.manager.rooms.values():
			var mc = r.get("match_ctl")
			if mc != null:
				print("[probe] t=%d phase=%s choices=%s next_act=%d now=%d" % [
						f, str(mc.state.get("phase")), str(mc.state.get("rogue_choices")),
						int(mc._next_act_ms), int(Time.get_ticks_msec())])
	elif role == "join" and f % 30 == 0 and not _code_written and not done:
		var cf := FileAccess.open(CODE_FILE, FileAccess.READ)
		if cf == null:
			return false
		var code := cf.get_as_text().strip_edges()
		cf.close()
		if code == "":
			return false
		_code_written = true
		net.connected_ok.connect(func() -> void:
			print("[rg2:join] 已连接, 加入 ", code)
			net.join_room(code))
		net.connect_to("127.0.0.1", 24691)
	if f > 60 * 540 and not done:
		print("[rg2] FAIL 总超时 role=", role)
		quit(1)
	return false


func _on_room_state(state: Dictionary) -> void:
	if done:
		return
	if role == "host" and not _code_written:  # 房间码写入(乙侧轮询读取)
		var cf := FileAccess.open(CODE_FILE, FileAccess.WRITE)
		cf.store_string(str(state.get("room_code", "")))
		cf.close()
		_code_written = true
	var humans := 0
	for p in state.get("players", []):
		if not bool(p.get("empty", true)) and not bool(p.get("is_bot", false)):
			humans += 1
	var host: bool = int(state.get("host_seat", -1)) == int(net.my_seat)
	if role == "host" and host and humans >= 2 and not started:
		started = true
		print("[rg2] 双方到齐, 补 2 AI 开局")
		net.fill_bots()
		net.start_game()


var _dbg := 0
func _on_view(view: Dictionary) -> void:
	if done:
		return
	_dbg += 1
	if _dbg % 20 == 1:
		print("[rg2:%s] view#%d phase=%s round=%s rogue_mod=%s" % [
				role, _dbg, str(view.get("phase")), str(view.get("round")),
				str(view.get("rogue_mod", ""))])
	var phase := str(view.get("phase", ""))
	if phase != _last_phase:
		_last_phase = phase
		print("[rg2:%s] phase -> %s (f=%d)" % [role, phase, f])
	if phase == "draft":
		# 命运二选一: 抢选第一张(后到者被服务端拒绝属正常, 视图会刷新)
		net.send_rogue_pick(0)
	elif phase == "game_end":
		done = true
		my_score = int(view.get("scores", [])[int(view.get("my_seat", 0))])
		print("[rg2] ROGUE2_OK role=%s scores=%s" % [role, str(view.get("scores", []))])
		quit(0)
