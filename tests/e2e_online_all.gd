## 联机三模式真实 socket 综合 E2E(单进程):
##   内嵌服务器 + 客户端A(房主) + 客户端B(加入者) + 客户端C(观战者)。
## 覆盖:
##   房间: 建房/加入/非房主开局被拒/加入不存在的房/非房主改规则被拒
##   普通: 双真人+2AI 完整一场 → B 中途断线(AI 接管) → token 重连回座续打
##         → 终局回房 → 再来一局
##   肉鸽: 天选者 draft(人选/AI 选) → 命运卡生效 → 打完整场
##   格斗: 双真人+观战者 → 选牌/行动 → 观战者操作被拒 → 打到 over 回房
## 运行: godot --headless --path . --script tests/e2e_online_all.gd
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")

const PORT := 24693

var main: Node = null
var server = null
var a = null     # 房主客户端(默认 multiplayer, /root/Main/Net)
var b = null     # 加入者客户端(独立 API 根 C2)
var c = null     # 观战者客户端(独立 API 根 C3)

var phase := "boot"
var phase_frames := 0
var fails: Array = []
var t_start := 0

var room_code := ""
var a_seen_played := false
var b_seat_before := -1
var b_reconnected := false
var rogue_picked_hand := -1
var fight_driven := false
var fight_over_seen := false
var c_errored := false
var neg2_got := {"v": false}


func _initialize() -> void:
	t_start = Time.get_ticks_msec()
	print("[all] 联机三模式综合 E2E 开始")


func _fail(msg: String) -> void:
	if fails.is_empty():
		print("[all] FAIL: " + msg)
	fails.append(msg)
	_finish()


func _finish() -> void:
	if fails.is_empty():
		print("[all] ONLINE_ALL_OK —— 三模式综合验证全部通过 (%.1fs)" % [
				(Time.get_ticks_msec() - t_start) / 1000.0])
		quit(0)
	else:
		print("[all] ONLINE_ALL_FAIL —— %d 项失败: %s" % [fails.size(),
				", ".join(PackedStringArray(fails))])
		quit(1)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("[all]   ✓ " + msg)
	else:
		fails.append(msg)
		print("[all]   ✗ " + msg)


var phase_ms := 0


func _goto(p: String) -> void:
	phase = p
	phase_frames = 0
	phase_ms = Time.get_ticks_msec()


## 本阶段是否已超过 sec 秒(headless 帧率不封顶, 帧数窗口不可靠 → 用真实时间)
func _over(sec: float) -> bool:
	return Time.get_ticks_msec() - phase_ms > int(sec * 1000.0)


## 多客户端: 每客户端一个独立 MultiplayerAPI 根, 节点相对路径与
## 服务器侧 (Embed/)Main/Net 对称 → RPC 互通(同 start_embedded 机制)。
func _mk_client(root_name: String, cid: String, auto: bool):
	var croot := Node.new()
	croot.name = root_name
	main.add_child(croot)
	var tree := Engine.get_main_loop() as SceneTree
	tree.set_multiplayer(MultiplayerAPI.create_default_interface(),
			NodePath(str(croot.get_path())))
	var inner := Node.new()
	inner.name = "Main"
	croot.add_child(inner)
	var net = NetNodeGd.new()
	net.name = "Net"
	net.setup(false)
	inner.add_child(net)
	net.client_id_override = cid
	net.autoplay = auto
	return net


func _setup() -> void:
	main = Node.new()
	main.name = "Main"
	root.add_child(main)
	server = NetNodeGd.start_embedded(main, PORT)
	if server == null:
		_fail("内嵌服务器启动失败")
		return
	server.manager.ai_delay_ms = 60
	server.manager.phase_delay_ms = 250
	a = NetNodeGd.new()
	a.name = "Net"
	a.setup(false)
	main.add_child(a)
	b = _mk_client("C2", "e2e-B", false)
	c = _mk_client("C3", "e2e-C", false)
	# autoplay 延后开启: 先校验发牌 13 张, 再放行自动出牌(否则先出牌会污染校验)
	a.game_event.connect(_on_a_event)
	a.fight_state.connect(func(v: Dictionary) -> void: _fight_drive(a, v))
	b.fight_state.connect(func(v: Dictionary) -> void: _fight_drive(b, v))
	c.errored.connect(func(_code: String, _msg: String) -> void:
		c_errored = true)


func _process(_delta: float) -> bool:
	phase_frames += 1
	if Time.get_ticks_msec() - t_start > 300000:
		_fail("总超时 phase=" + phase)
		return true
	match phase:
		"boot":
			_setup()
			# connected_ok 在每次(重)连时都会触发 → 按阶段门控, 防状态机回跳
			a.connected_ok.connect(func() -> void:
				if phase == "wait_a_conn":
					_goto("a_create"))
			a.connect_to("127.0.0.1", PORT)
			_goto("wait_a_conn")
		"wait_a_conn":
			if _over(10.0):
				_fail("A 连接超时")
		"a_create":
			a.create_room({"rounds": 3, "turn_seconds": 5})
			_goto("wait_room")
		"wait_room":
			if not str(a.last_room_state.get("room_code", "")).is_empty():
				room_code = str(a.last_room_state["room_code"])
				print("[all] 普通房间已建 ", room_code, " — B 连接")
				b.connected_ok.connect(func() -> void:
					if phase == "wait_b_conn":
						_goto("b_join"))
				b.connect_to("127.0.0.1", PORT)
				_goto("wait_b_conn")
			elif _over(10.0):
				_fail("A 建房无 room_state")
		"wait_b_conn":
			if _over(10.0):
				_fail("B 连接超时")
		"b_join":
			b.join_room(room_code)
			_goto("wait_b_in")
		"wait_b_in":
			if int(b.last_room_state.get("my_seat", -1)) >= 0 \
					and str(b.last_room_state.get("room_code", "")) == room_code:
				_goto("room_full_check")   # 等 A 侧广播到齐(晚于 B 自身回执)
			elif _over(10.0):
				_fail("B 入房无 room_state")
		"room_full_check":
			if _over(0.6):
				var humans := 0
				for p in a.last_room_state.get("players", []):
					if not bool(p.get("empty", true)) \
							and not bool(p.get("is_bot", false)):
						humans += 1
				_check(humans == 2, "普通: 双真人入房(广播一致)")
				b_seat_before = int(b.my_seat)
				_goto("neg_start")
		"neg_start":
			b.start_game()   # 非房主: 应被拒
			_goto("neg_start_wait")
		"neg_start_wait":
			if _over(0.6):
				_check(server.manager.rooms[room_code].match_ctl == null,
						"普通: 非房主开局被拒(无对局)")
				b.errored.connect(func(_code: String, _msg: String) -> void:
					neg2_got["v"] = true)
				b.join_room("000000")   # 不存在的房间
				_goto("neg_join_wait")
		"neg_join_wait":
			if _over(0.6):
				_check(bool(neg2_got["v"]), "普通: 无效房间码回执 s_error")
				b.set_settings({"rounds": 9})   # 非房主: 应被拒
				_goto("neg_set_wait")
		"neg_set_wait":
			if _over(0.6):
				_check(int(a.last_room_state["settings"].get("rounds", 3)) == 3,
						"普通: 非房主改规则被拒")
				print("[all] 补 AI 开局(普通)")
				a.fill_bots()
				a.start_game()
				_goto("normal_play")
		"normal_play":
			if str(a.latest_view.get("phase", "")) == "play" \
					and not (a.latest_view.get("hand", []) as Array).is_empty():
				_check((a.latest_view["hand"] as Array).size() == 13,
						"普通: A 手牌 13 张")
				_goto("check_b_hand")
			elif _over(30.0):
				_fail("普通: 开局后未进入 play")
		"check_b_hand":
			# B 的视图 RPC 晚于 A 到达: 宽容窗口(headless 帧率不封顶, 用真实时间)
			if not (b.latest_view.get("hand", []) as Array).is_empty() \
					and str(b.latest_view.get("phase", "")) == "play":
				_check((b.latest_view["hand"] as Array).size() == 13,
						"普通: B 手牌 13 张")
				a.autoplay = true   # 校验完毕 → 放行自动出牌
				b.autoplay = true
				_goto("wait_first_played")
			elif _over(12.0):
				print("[all] B 视图诊断: phase=%s hand=%d in_room=%s welcomed=%s" % [
						str(b.latest_view.get("phase", "?")),
						(b.latest_view.get("hand", []) as Array).size(),
						str(b.in_room), str(b._welcomed)])
				_fail("普通: B 手牌视图未到达")
		"wait_first_played":
			if a_seen_played:
				print("[all] 首手已出 — B 断线(AI 接管)")
				b.disconnect_all()
				_goto("dropped")
		"dropped":
			if _over(1.5):
				var room = server.manager.rooms.get(room_code)
				var seat := -1
				for s in 4:
					var sd = room.seats[s]
					if sd != null and str(sd.get("client_id", "")) == "e2e-B":
						seat = s
				_check(seat >= 0 and not bool(room.seats[seat]["online"]),
						"普通: B 断线后座位离线(AI 代管)")
				_goto("b_reconnect")
		"b_reconnect":
			if not b_reconnected:
				b_reconnected = true
				b.connect_to("127.0.0.1", PORT)   # hello 带 session_token → 自动回座
			if not b.latest_view.is_empty() \
					and int(b.my_seat) == b_seat_before \
					and str(b.latest_view.get("phase", "")) in ["play", "exchange"]:
				_check(true, "普通: B 重连回座 %d 并收到对局视图" % b_seat_before)
				_goto("normal_finish")
			elif _over(15.0):
				_fail("普通: B 重连未恢复视图")
		"normal_finish":
			if str(a.latest_view.get("phase", "")) == "game_end":
				_check(true, "普通: 断线重连后打到终局")
				_goto("rematch")
			elif _over(120.0):
				_fail("普通: 重连后对局未到终局")
		"rematch":
			var room = server.manager.rooms.get(room_code)
			if room != null and room.match_ctl == null:
				a.fill_bots()
				a.start_game()
				print("[all] 再来一局")
				_goto("rematch_views")
			elif _over(15.0):
				_fail("普通: 终局后房间未回空闲")
		"rematch_views":
			if str(a.latest_view.get("phase", "")) == "play" \
					and not (a.latest_view.get("hand", []) as Array).is_empty() \
					and int(a.latest_view.get("round", -1)) == 0 \
					and str(a.latest_view.get("rules", {}).get("rounds", 0)) != "9":
				_check(true, "普通: 再来一局开局成功")
				a.leave_room()
				b.leave_room()
				_goto("leave_old")
			elif _over(30.0):
				_fail("普通: 再来一局未见新视图")
		"leave_old":
			if _over(0.6):
				print("[all] —— 肉鸽模式 ——")
				a.create_room({"mode": "rogue", "rogue": true,
						"rounds": 3, "turn_seconds": 5})
				_goto("rogue_room")
		"rogue_room":
			if str(a.last_room_state.get("room_code", "")) != room_code \
					and a.last_room_state.has("room_code") \
					and server.manager.rooms.has(str(a.last_room_state["room_code"])) \
					and str(server.manager.rooms[str(a.last_room_state["room_code"])]
							.settings.get("mode", "")) == "rogue":
				room_code = str(a.last_room_state["room_code"])
				b.join_room(room_code)
				_goto("rogue_join")
			elif _over(10.0):
				_fail("肉鸽: 建房失败")
		"rogue_join":
			if int(b.last_room_state.get("my_seat", -1)) >= 0 \
					and str(b.last_room_state.get("room_code", "")) == room_code:
				a.fill_bots()
				a.start_game()
				print("[all] 肉鸽开局")
				_goto("rogue_run")
			elif _over(10.0):
				_fail("肉鸽: B 入房失败")
		"rogue_run":
			_rogue_pick_tick()
			if str(a.latest_view.get("phase", "")) == "play" \
					and not (a.latest_view.get("hand", []) as Array).is_empty() \
					and not has_meta("rogue_mod_ok"):
				var mod: String = str(a.latest_view.get("rogue_mod", ""))
				if mod != "":
					set_meta("rogue_mod_ok", true)
					_check(true, "肉鸽: 命运卡已生效(" + mod + ")")
			if str(a.latest_view.get("phase", "")) == "game_end":
				_check(has_meta("rogue_mod_ok"), "肉鸽: 打到终局")
				a.leave_room()
				b.leave_room()
				_goto("fight_room")
			elif _over(120.0):
				# 诊断转储: 服务器状态 + 双客户端视图
				var room = server.manager.rooms.get(room_code)
				if room != null and room.match_ctl != null:
					var st = room.match_ctl.state
					print("[all] 肉鸽卡死诊断: phase=%s round=%s turn=%s picker=%s online=%s" % [
							str(st["phase"]), str(st["round"]), str(st["turn"]),
							str(st.get("rogue_picker", -1)),
							str(room.match_ctl.seat_online)])
				else:
					print("[all] 肉鸽卡死诊断: match_ctl=", room.match_ctl)
				print("[all] 肉鸽卡死诊断: A=", str(a.latest_view.get("phase", "?")),
						" B=", str(b.latest_view.get("phase", "?")),
						" B.in_room=", str(b.in_room))
				_fail("肉鸽: 对局未到终局")
		"fight_room":
			if _over(0.6):
				print("[all] —— 格斗对战 ——")
				a.create_room({"mode": "fight"})
				_goto("fight_room_wait")
		"fight_room_wait":
			if a.last_room_state.has("room_code") \
					and str(a.last_room_state["room_code"]) != room_code \
					and server.manager.rooms.has(str(a.last_room_state["room_code"])) \
					and str(server.manager.rooms[str(a.last_room_state["room_code"])]
							.settings.get("mode", "")) == "fight":
				room_code = str(a.last_room_state["room_code"])
				b.join_room(room_code)
				# C 全程只连一次: 连上即加入当前房间(room_code 为成员变量, 取实时值)
				c.connected_ok.connect(func() -> void:
					c.join_room(room_code))
				c.connect_to("127.0.0.1", PORT)
				_goto("fight_join")
			elif _over(10.0):
				_fail("格斗: 建房失败")
		"fight_join":
			if int(b.last_room_state.get("my_seat", -1)) >= 0 \
					and str(b.last_room_state.get("room_code", "")) == room_code \
					and int(c.last_room_state.get("my_seat", -1)) >= 0 \
					and str(c.last_room_state.get("room_code", "")) == room_code:
				_check(int(c.my_seat) == 2, "格斗: C 入观战位(座位 2)")
				a.start_game()
				_goto("fight_run")
			elif _over(15.0):
				_fail("格斗: B/C 入房失败")
		"fight_run":
			if _over(2.0) and not has_meta("spec_probe"):
				set_meta("spec_probe", true)
				c.fight_pick(0, -1)   # 观战者选牌应被拒
			if _over(3.0) and not has_meta("spec_err_checked"):
				set_meta("spec_err_checked", true)
				_check(c_errored, "格斗: 观战者选牌被拒(s_error)")
			if not c.latest_fight.is_empty() \
					and bool(c.latest_fight.get("spectator", false)) \
					and not has_meta("spec_checked"):
				set_meta("spec_checked", true)
				_check(true, "格斗: C 视图标记观战")
			if str(a.latest_fight.get("phase", "")) == "over" and not fight_over_seen:
				fight_over_seen = true
				_check(true, "格斗: 对局打到 over (胜者座位 %d)"
						% int(a.latest_fight.get("winner", -1)))
			if fight_over_seen \
					and server.manager.rooms.has(room_code) \
					and server.manager.rooms[room_code].match_ctl == null:
				_check(true, "格斗: 收尾回房")
				_finish()
			elif _over(180.0):
				_fail("格斗: 对局未到 over")
	return false


func _on_a_event(event: String, _data: Dictionary) -> void:
	if event == "played":
		a_seen_played = true


## 肉鸽: 轮到人类天选者选卡时选 0(每手只选一次)
func _rogue_pick_tick() -> void:
	var v_a: Dictionary = a.latest_view
	var v_b: Dictionary = b.latest_view
	for pair in [[a, v_a], [b, v_b]]:
		var net = pair[0]
		var v: Dictionary = pair[1]
		if v.is_empty() or str(v.get("phase", "")) != "draft":
			continue
		var hand := int(v.get("round", -1))
		if hand == rogue_picked_hand:
			continue
		if int(v.get("rogue_picker", -1)) == int(net.my_seat):
			rogue_picked_hand = hand
			net.send_rogue_pick(0)
			print("[all] 肉鸽: 座位 %d 选卡(第 %d 局)" % [int(net.my_seat), hand + 1])


## 格斗: 选牌/行动脚本(A/B 共用, 按各自视图驱动)
func _fight_drive(net, view: Dictionary) -> void:
	var phase := str(view.get("phase", ""))
	var my: Dictionary = view.get("my", {})
	if phase == "draft" and not bool(my.get("done", true)):
		var pair: Array = my.get("pair", [])
		if (pair as Array).is_empty():
			return
		var slot := 0 if (my.get("slots", []) as Array).size() >= 5 else -1
		net.send_fight_pick(int(pair[0]), slot)
	elif phase == "battle" and bool(view.get("my_turn", false)):
		net.send_fight_act("attack")
