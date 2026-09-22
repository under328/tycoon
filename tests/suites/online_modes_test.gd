## 联机三模式(普通/肉鸽/格斗对战)纯逻辑综合验证。
## 直接驱动 RoomManager/FightMatch(无网络, 确定性), 覆盖房间生命周期、
## 双真人对局、命运卡天选者流程、格斗选牌/行动/观战/掉线托管/重连。
## 由 tests/run_tests.gd 注册运行。
extends RefCounted

const MsgC = preload("res://src/protocol/msg.gd")
const RoomManagerGd = preload("res://src/server/room_manager.gd")
const GameStateGd = preload("res://src/rules/game_state.gd")
const BotPlayerGd = preload("res://src/rules/ai/bot_player.gd")
const ViewGd = preload("res://src/protocol/view.gd")


func run(t) -> void:
	_emoji_sticker_passthrough(t)
	_rogue_local_picker(t)
	_rogue_blitz_dead_d3(t)
	_fight_leave_and_autoend(t)
	_normal_leave_and_autoend(t)
	_rogue_shared_sync(t)
	_rogue_join_running_takeover(t)
	_normal_two_humans(t)
	_normal_afk_autopilot(t)
	_normal_rejoin_paths(t)
	_rogue_full_flow(t)
	_rogue_picker_rules(t)
	_fight_two_humans(t)
	_fight_spectator(t)
	_fight_disconnect_ai(t)
	_fight_single_human(t)


# ================================================================ 对局中加入

## 对局进行中加入共享对局: 朋友接管一个 AI 座位, AI 不再代管, 可正常出牌。
func _rogue_join_running_takeover(t) -> void:
	var m = _mgr()
	var out: Array = m.create_room(100, "甲",
			{"mode": "rogue", "rogue": true, "rounds": 3, "turn_seconds": 5}, "cid-A")
	var code := str(_rs(out, 100)["room_code"])
	m.fill_bots(100)
	m.start(100, 0)
	var room = _room_of(m, code)
	var now := 0
	var guard := 0
	while guard < 400 and str(room.match_ctl.state["phase"]) == "draft":
		guard += 1
		now += 100
		var picker: int = int(room.match_ctl.state["rogue_picker"])
		if not room.match_ctl.is_bot_seat(picker):
			m.rogue_pick(100, 0)
		m.tick(now)
	out = m.join_room(201, "乙", code, "cid-B")
	t.expect(_count(out, "s_error") == 0, "肉鸽join: 对局中加入无错误")
	var seat: int = int(_rs(out, 201)["my_seat"])
	t.expect(seat >= 0 and room.seats[seat] != null 			and not bool(room.seats[seat]["bot"]), "肉鸽join: 接管 AI 座位为真人座")
	t.expect(not room.match_ctl.is_bot_seat(seat), "肉鸽join: AI 不再代管该座位")
	t.expect(_views(out).size() >= 1, "肉鸽join: 立即收到私有视图")
	# 接管座位的回合: 人类可正常出牌(AI 不再代打)
	var acted := false
	while guard < 6000 and not acted and room.match_ctl != null 			and str(room.match_ctl.state["phase"]) == "play":
		guard += 1
		now += 100
		var v: Dictionary = ViewGd.build(room.match_ctl.state, seat)
		if str(v["phase"]) == "play" and int(v["turn"]) == seat:
			var act: Dictionary = BotPlayerGd.decide_from_view(v)
			if str(act["t"]) == "play":
				var rr: Array = m.play(201, act["cards"])
				acted = _count(rr, "s_error") == 0
		m.tick(now)
	t.expect(acted, "肉鸽join: 接管座位可正常出牌")


# ================================================================ 表情包

## 联机表情包(贴纸 id 100..107): 服务端原样转发, 不再被钳成普通表情
func _emoji_sticker_passthrough(t) -> void:
	var m = _mgr()
	var out: Array = m.create_room(100, "甲", {}, "cid-A")
	m.join_room(101, "乙", str(_rs(out, 100)["room_code"]), "cid-B")
	out = m.emoji(101, 105)
	t.expect(_count_to(out, 100, "s_emoji") == 1, "表情包: 房间收到贴纸广播")
	t.expect(int(_find(out, 100, "s_emoji")["id"]) == 105, "表情包: 贴纸 id 透传(105)")
	out = m.emoji(101, 3)
	t.expect(int(_find(out, 100, "s_emoji")["id"]) == 3, "表情: 普通表情不受影响")


# ================================================================ 本地自选

## 本地肉鸽: rogue_picker_local 开启后, 每局天选者恒为玩家(座位0),
## 联机(未开启)仍按概率掷选 — 两种模式互不影响。
func _rogue_local_picker(t) -> void:
	var local_zero := 0
	var online_nonzero := 0
	for seed in range(1, 60):
		var st: Dictionary = GameStateGd.new_match(
				{"rogue": true, "rogue_picker_local": true}, seed)
		t.expect(int(st["rogue_picker"]) == 0,
				"本地自选: 首局天选者恒为玩家 seed=%d" % seed)
		# 次局起(_do_next_round 重掷)也恒为玩家
		st["phase"] = "round_end"
		st["round"] = 1
		var r: Dictionary = GameStateGd.apply(st, {"t": "next_round"})
		t.expect(bool(r["ok"]), "本地自选: 次局进入 draft seed=%d" % seed)
		t.expect(int(r["state"]["rogue_picker"]) == 0,
				"本地自选: 次局天选者仍为玩家 seed=%d" % seed)
		# 对照组: 联机(无该开关)按概率掷选, 60 局中应出现非玩家天选者
		var st2: Dictionary = GameStateGd.new_match({"rogue": true}, seed)
		st2["phase"] = "round_end"
		st2["round"] = 1
		st2["identities"] = [0, 1, 2, 3]   # 模拟首局完成后的身份(加权掷选输入)
		var r2: Dictionary = GameStateGd.apply(st2, {"t": "next_round"})
		if int(r2["state"]["rogue_picker"]) != 0:
			online_nonzero += 1
	t.expect(online_nonzero > 0, "本地自选: 对照组联机概率机制未被波及")


# ================================================================ 肉鸽共享同步

## 联机肉鸽共享同步语义: 除命运二选一由随机一人代选外, 其余(阶段/命运卡/
## 候选/积分/行动轮)对两家客户端完全一致 — 任何时刻只可能有一个玩家轮到。
func _rogue_shared_sync(t) -> void:
	var m = _mgr()
	var out: Array = m.create_room(100, "甲",
			{"mode": "rogue", "rogue": true, "rounds": 3, "turn_seconds": 5}, "cid-A")
	var code := str(_rs(out, 100)["room_code"])
	m.hello(101, MsgC.PROTOCOL_VERSION, "", "cid-B")
	m.join_room(101, "乙", code, "cid-B")
	m.fill_bots(100)
	m.start(100, 0)
	var room = _room_of(m, code)
	var now := 0
	var guard := 0
	var checked := 0
	var both_my_turn := 0
	var phase_diverge := 0
	var mod_diverge := 0
	while guard < 80000 and room.match_ctl != null:
		guard += 1
		now += 100
		var st = room.match_ctl.state
		if str(st["phase"]) == "draft":
			var picker: int = int(st["rogue_picker"])
			if not room.match_ctl.is_bot_seat(picker):
				m.rogue_pick(100 if picker == 0 else 101, 0)
		out = m.tick(now)
		if room.match_ctl == null:
			break
		# 双客户端各自最新视图一致性(采样)
		var va: Dictionary = ViewGd.build(room.match_ctl.state, 0)
		var vb: Dictionary = ViewGd.build(room.match_ctl.state, 1)
		if str(va["phase"]) != str(vb["phase"]):
			phase_diverge += 1
		if str(va.get("rogue_mod", "")) != str(vb.get("rogue_mod", "")):
			mod_diverge += 1
		var ta: bool = str(va["phase"]) == "play" 				and int(va["turn"]) == int(va["my_seat"])
		var tb: bool = str(vb["phase"]) == "play" 				and int(vb["turn"]) == int(vb["my_seat"])
		if ta and tb:
			both_my_turn += 1
		if checked < 4000:
			checked += 1
	if phase_diverge == 0:
		t.expect(true, "肉鸽同步: 双客户端阶段全程一致")
	else:
		t.expect(false, "肉鸽同步: 阶段不一致 %d 次" % phase_diverge)
	t.expect(mod_diverge == 0, "肉鸽同步: 命运卡全程一致")
	t.expect(both_my_turn == 0, "肉鸽同步: 任何时刻不会双方同时轮到出牌")
	t.expect(room.match_ctl == null
			or str(room.match_ctl.state["phase"]) == "game_end", "肉鸽同步: 打到终局")


# ================================================================ 退出对局

## 格斗退出对局(留房): 退出者不再收战斗视图/操作被拒; 双方都退 → 自动收尾;
## 房间座位无幽灵(同一个人不会同时出现 AI 座位与真人座位)
func _fight_leave_and_autoend(t) -> void:
	var m = _mgr()
	var out: Array = m.create_room(100, "甲", {"mode": "fight"}, "cid-A")
	var code := str(_rs(out, 100)["room_code"])
	m.hello(101, MsgC.PROTOCOL_VERSION, "", "cid-B")
	m.join_room(101, "乙", code, "cid-B")
	m.start(100, 0)
	var room = _room_of(m, code)
	var now := 0
	var guard := 0
	while guard < 20000 and str(room.match_ctl.state["phase"]) == "draft":
		guard += 1
		now += 100
		for seat in [0, 1]:
			var per: Dictionary = room.match_ctl.state["per"][seat]
			if not bool(per["done"]):
				m.fight_pick(100 if seat == 0 else 101,
						{"cand": (per["pair"] as Array)[0], "slot": -1})
		m.tick(now)
	t.expect(str(room.match_ctl.state["phase"]) == "battle", "格斗leave: 进入战斗")
	out = m.fight_leave(100)
	t.expect(_count_to(out, 100, "s_room_state") >= 1, "格斗leave: 退出者收到房间状态")
	t.expect(room.match_ctl.has_left(0) and room.match_ctl.is_bot_seat(0),
			"格斗leave: 退出座位转 AI 代管")
	t.expect(str(room.match_ctl.state["log"][room.match_ctl.state["log"].size() - 1]) \
			.contains("退出对局"), "格斗leave: 对局日志提示 AI 代管")
	t.expect(bool(room.match_ctl.view_for(1)["left"][0]),
			"格斗leave: 视图向留下者暴露退出状态")
	t.expect(room.seat_of_peer(100) == 0 and room.seats[0] != null \
			and not bool(room.seats[0]["bot"]),
			"格斗leave: 无幽灵座(真人座位保留, 未另开 AI 座)")
	out = m.fight_act(100, "attack")
	t.expect(_count_to(out, 100, "s_error") == 1, "格斗leave: 退出后行动被拒")
	# 退出本场者退出房间后再重进: 只回房间页, 不被对局视图拉回竞技场
	m.leave(100)
	out = m.join_room(701, "甲", code, "cid-A")
	t.expect(int(_rs(out, 701)["my_seat"]) == 0, "格斗rejoin: 重进归位原座位")
	t.expect(_fight_states_to(out, 701).is_empty(),
			"格斗rejoin: 已退出本场者不被对局视图拉回竞技场")
	t.expect(room.match_ctl.has_left(0) and room.match_ctl.is_bot_seat(0),
			"格斗rejoin: 重进后本场仍由 AI 代管")
	# AI 代管推进战斗, 且退出者不再收到战斗视图
	var views_to_left := 0
	var views_total := 0
	for i in 200:
		now += 100
		var o: Array = m.tick(now)
		views_total += _count(o, "s_fight_state")
		views_to_left += _count_to(o, 100, "s_fight_state")
	t.expect(views_total >= 1, "格斗leave: AI 代管推进对局")
	t.expect(views_to_left == 0, "格斗leave: 退出者不再收战斗视图")
	# 乙也退出 → 全员退出 → 立即收尾回房
	out = m.fight_leave(101)
	t.expect(room.match_ctl == null, "格斗leave: 全员退出 → 对局自动结束")
	t.expect(_count_to(out, 101, "s_room_state") >= 1, "格斗leave: 收尾广播房间状态")
	var humans := 0
	for s in 4:
		var sd = room.seats[s]
		if sd != null and not bool(sd["bot"]):
			humans += 1
	t.expect(humans == 2, "格斗leave: 收尾后房间仍是两名真人(可再开)")


## 普通模式退出对局(留房): AI 代管; 全员退出 → 自动收尾
func _normal_leave_and_autoend(t) -> void:
	var m = _mgr()
	var out: Array = m.create_room(100, "甲", {"rounds": 3, "turn_seconds": 5}, "cid-A")
	var code := str(_rs(out, 100)["room_code"])
	m.hello(101, MsgC.PROTOCOL_VERSION, "", "cid-B")
	m.join_room(101, "乙", code, "cid-B")
	m.fill_bots(100)
	m.start(100, 0)
	var room = _room_of(m, code)
	t.expect(room.match_ctl != null, "普通leave: 对局开始")
	out = m.game_leave(100)
	t.expect(room.match_ctl != null, "普通leave: 对方未退, 对局继续")
	t.expect(_count_to(out, 100, "s_room_state") >= 1, "普通leave: 退出者收到房间状态")
	t.expect(room.match_ctl.is_bot_seat(0), "普通leave: 退出座位 AI 代管")
	t.expect(_count_to(out, 101, "s_chat") == 1, "普通leave: 留桌者收到退出系统提示")
	out = m.play(100, [0])
	t.expect(_count_to(out, 100, "s_error") == 1, "普通leave: 退出后出牌被拒")
	# AI 托管确实替退出者行动: 短窗口内应有持续出牌(对局仍在进行)
	var played_by_ai := 0
	var now := 0
	for i in 150:
		now += 120
		played_by_ai += _count(m.tick(now), "s_game_played")
	t.expect(room.match_ctl != null, "普通leave: 托管窗口内对局仍在进行")
	t.expect(played_by_ai > 0, "普通leave: AI 托管有实际出牌")
	# 乙也退出 → 全员退出 → 立即收尾
	out = m.game_leave(101)
	t.expect(room.match_ctl == null, "普通leave: 全员退出 → 对局自动结束")
	t.expect(_count_to(out, 101, "s_room_state") >= 1, "普通leave: 收尾广播房间状态")
	# 全员退出收尾后, 退出者退出房间再重进: 归位座位且不再收到上局视图
	m.leave(101)
	out = m.join_room(601, "乙", code, "cid-B")
	t.expect(int(_rs(out, 601)["my_seat"]) == 1, "普通rejoin: 重进归位原座位")
	t.expect(_views(out).is_empty(), "普通rejoin: 不再收到已结束对局的视图")


## 回归: 肉鸽缩手牌命运卡(疾风迅雷 8 张 / 缩地成寸 10 张)首局 ♦3 可能
## 整批入死牌 → must_include 必须清空且首出者有合法动作
## (此前未清 → 出牌/pass 全非法, 整局死锁, 且 UI 仍显示"首手必须包含 ♦3")
func _rogue_blitz_dead_d3(t) -> void:
	for mod in ["blitz", "short_hands"]:
		_rogue_dead_d3_by_mod(t, mod)


func _rogue_dead_d3_by_mod(t, mod: String) -> void:
	var dead_seen := false
	var alive_seen := false
	for seed in range(1, 300):
		var st: Dictionary = GameStateGd.new_match(
				{"rogue": true, "rogue_mod": mod}, seed)
		var r: Dictionary = GameStateGd.apply(st,
				{"t": "rogue_pick", "idx": 0, "seat": -1})
		t.expect(bool(r["ok"]), "肉鸽%s: 锁定剧本选卡成功 seed=%d" % [mod, seed])
		st = r["state"]
		var d3_dead := true
		for s in 4:
			if (st["hands"][s] as Array).has(2):   # ♦3 = id 2
				d3_dead = false
				break
		if d3_dead:
			dead_seen = true
			t.expect(int(st["must_include"]) == -1,
					"肉鸽%s: ♦3 死牌时首出无限制 seed=%d" % [mod, seed])
		else:
			alive_seen = true
			var holder := -1
			for s2 in 4:
				if (st["hands"][s2] as Array).has(2):
					holder = s2
					break
			t.expect(int(st["turn"]) == holder and int(st["must_include"]) == 2,
					"肉鸽%s: ♦3 在手时持有者先出 seed=%d" % [mod, seed])
		# 首出者(bot 托管)必须能走出合法一手(死锁回归点)
		var act: Dictionary = BotPlayerGd.decide(st, int(st["turn"]))
		t.expect(str(act["t"]) == "play", "肉鸽%s: 首出托管有合法一手 seed=%d" % [mod, seed])
		var rr: Dictionary = GameStateGd.apply(st, act)
		t.expect(bool(rr["ok"]), "肉鸽%s: 首出被引擎接受 seed=%d" % [mod, seed])
	t.expect(dead_seen and alive_seen,
			"肉鸽%s: 采样覆盖 ♦3 死/活两种局面" % mod)


## 双真人+双AI 完整两场(含换牌局): 事件双方可见、积分守恒、房间回空闲、再来一局
func _normal_two_humans(t) -> void:
	var m = _mgr()
	var out: Array = m.create_room(100, "甲", {"rounds": 9, "turn_seconds": 5}, "cid-A")
	var code := str(_rs(out, 100)["room_code"])
	m.hello(101, MsgC.PROTOCOL_VERSION, "", "cid-B")
	out = m.join_room(101, "乙", code, "cid-B")
	t.expect(_count(out, "s_room_state") >= 2, "普通: 双人入房广播")
	m.fill_bots(100)
	out = m.start(100, 0)
	t.expect(_views(out).size() == 2, "普通: 两名真人各收一份私有 view")
	# 非房主开局被拒(在房空闲态下 start 仅房主可用)
	var m2 = _mgr()
	var out2: Array = m2.create_room(200, "丙", {}, "cid-C")
	var code2 := str(_rs(out2, 200)["room_code"])
	m2.join_room(201, "丁", code2, "cid-D")
	out2 = m2.start(201, 0)
	t.expect(_room_of(m2, code2).match_ctl == null, "普通: 非房主开局被拒")
	# 第一场: 双真人不动作, 全靠超时托管 → 打到终局(9 局太久, 改 3 局房间)
	var room = _room_of(m, code)
	var seen_played_a := 0
	var seen_played_b := 0
	var seen_exchange := 0
	var seen_round_end := 0
	var seen_game_end := 0
	var scores := []
	var now := 0
	var guard := 0
	while guard < 60000 and room.match_ctl != null:
		guard += 1
		now += 120
		out = m.tick(now)
		seen_played_a += _count_to(out, 100, "s_game_played")
		seen_played_b += _count_to(out, 101, "s_game_played")
		seen_exchange += _count(out, "s_exchange")
		seen_round_end += _count_to(out, 100, "s_round_end")
		if _count(out, "s_game_end") > 0:
			seen_game_end += 1
			for msg in out:
				if str(msg["event"]) == "s_game_end":
					scores = msg["data"]["scores"]
	t.expect(room.match_ctl == null, "普通: 双真人对局打到终局且回空闲")
	t.expect(guard < 60000, "普通: tick 有界")
	t.expect(seen_played_a > 0 and seen_played_b > 0, "普通: 出牌事件双方可见")
	t.expect(seen_exchange >= 1, "普通: 第 2 局起触发换牌阶段")
	t.expect(seen_round_end >= 1, "普通: 局结束事件")
	t.expect(seen_game_end == 1, "普通: 恰一次 game_end")
	var total := 0
	for p in scores:
		total += int(p)
	t.expect(total == 0, "普通: 终局积分守恒")
	t.expect(not room.is_empty(), "普通: 终局后真人座位保留(可再来一局)")
	# 再来一局: 房主再次开局成功
	m.fill_bots(100)
	out = m.start(100, 0)
	t.expect(room.match_ctl != null, "普通: 再来一局开局成功")


## 人类全程 AFK: 超时托管驱动完整对局(含换牌返还托管)
func _normal_afk_autopilot(t) -> void:
	var m = _mgr()
	var out: Array = m.create_room(100, "甲", {"rounds": 3, "turn_seconds": 5}, "cid-A")
	var code := str(_rs(out, 100)["room_code"])
	m.fill_bots(100)
	m.start(100, 0)
	var room = _room_of(m, code)
	var now := 0
	var guard := 0
	var played := 0
	var exchanges := 0
	while guard < 60000 and room.match_ctl != null:
		guard += 1
		now += 150
		played += _count(m.tick(now), "s_game_played")
		exchanges += _count(m.tick(now - 1), "s_exchange")
	t.expect(room.match_ctl == null, "普通: AFK 玩家由托管驱动打完整场")
	t.expect(played > 0, "普通: 托管对局有出牌广播")


## 对局中断线两条回归路径: token 重连回座 + 换连接 join_room 归位(补私有视图)
func _normal_rejoin_paths(t) -> void:
	var m = _mgr()
	var out: Array = m.create_room(100, "甲", {"rounds": 3, "turn_seconds": 5}, "cid-A")
	var code := str(_rs(out, 100)["room_code"])
	m.hello(101, MsgC.PROTOCOL_VERSION, "", "cid-B")
	m.join_room(101, "乙", code, "cid-B")
	m.fill_bots(100)
	m.start(100, 0)
	var room = _room_of(m, code)
	t.expect(room.match_ctl != null, "普通: 对局已开始")
	var token := str(room.seats[1]["token"])
	# 路径1: 掉线(AI 接管) → token 重连
	m.peer_gone(101)
	t.expect(bool(room.seats[1]["online"]) == false, "普通: 掉线座位转离线")
	var now := 0
	var guard := 0
	# 只推进 ~4s 模拟时间: 足够 AI 接管出几手, 但对局必未结束
	# (turn_seconds=5 下打完一场需 100s+, 打完会清离线座位使 token 失效)
	while guard < 32:
		guard += 1
		now += 120
		m.tick(now)
	t.expect(room.match_ctl != null, "普通: 断线窗口内对局仍在进行")
	out = m.hello(999, MsgC.PROTOCOL_VERSION, token, "cid-B")
	t.expect(int(_find(out, 999, "s_welcome")["seat"]) == 1, "普通: token 重连回原座")
	t.expect(_views(out).size() >= 1, "普通: 重连即收私有视图")
	t.expect(bool(room.seats[1]["online"]), "普通: 重连后座位恢复在线")
	# 路径2: 换新连接 join_room(client_id 归位, 对局中不再被 in_game 拒绝)
	m.peer_gone(999)
	out = m.join_room(888, "乙", code, "cid-B")
	t.expect(_count(out, "s_error") == 0, "普通: 对局中 join_room 归位无错误")
	t.expect(int(_rs(out, 888)["my_seat"]) == 1, "普通: join_room 归位原座位")
	t.expect(_views(out).size() >= 1, "普通: 归位补发私有视图")


# ================================================================ 肉鸽模式

## 肉鸽全流程: draft 候选/天选者 → 选卡生效 → 打完整场每局都有命运卡
func _rogue_full_flow(t) -> void:
	var m = _mgr()
	var out: Array = m.create_room(100, "甲",
			{"mode": "rogue", "rogue": true, "rounds": 3, "turn_seconds": 5}, "cid-A")
	var code := str(_rs(out, 100)["room_code"])
	m.hello(101, MsgC.PROTOCOL_VERSION, "", "cid-B")
	m.join_room(101, "乙", code, "cid-B")
	m.fill_bots(100)
	out = m.start(100, 0)
	var room = _room_of(m, code)
	t.expect(room.match_ctl != null, "肉鸽: 开局成功")
	t.expect(str(room.match_ctl.state["phase"]) == "draft", "肉鸽: 首局进入 draft")
	var st = room.match_ctl.state
	t.expect((st["rogue_choices"] as Array).size() == 2, "肉鸽: 候选恰两张")
	t.expect(st["rogue_picker"] != null and int(st["rogue_picker"]) in [0, 1, 2, 3],
			"肉鸽: 天选者座位合法")
	# 视图携带候选与稀有度
	var v: Dictionary = _views(out)[0]["data"]["view"]
	t.expect((v["rogue_choices"] as Array).size() == 2, "肉鸽: 视图带候选")
	t.expect((v["rogue_rar"] as Array).size() == 2, "肉鸽: 视图带稀有度")
	# 打完整场: 天选者为人类时用 rogue_pick 选 0, AI 自动选
	var mods := {}
	var now := 0
	var guard := 0
	var drafts := 0
	while guard < 80000 and room.match_ctl != null:
		guard += 1
		now += 100
		st = room.match_ctl.state
		if str(st["phase"]) == "draft":
			var picker: int = int(st["rogue_picker"])
			if not room.match_ctl.is_bot_seat(picker):
				m.rogue_pick(100 if picker == 0 else 101, 0)
				drafts += 1
		out = m.tick(now)
		if str(room.match_ctl.state.get("cfg", {}).get("rogue_mod", "")) != "":
			mods[str(room.match_ctl.state["cfg"]["rogue_mod"])] = true
		if _count(out, "s_game_end") > 0:
			break
	t.expect(room.match_ctl != null and str(room.match_ctl.state["phase"]) == "game_end"
			or room.match_ctl == null, "肉鸽: 打到终局 (phase=%s mods=%d drafts=%d guard=%d)"
			% [str(room.match_ctl.state.get("phase", "已收尾")) if room.match_ctl != null
					else "已收尾", mods.size(), drafts, guard])
	t.expect(guard < 80000, "肉鸽: tick 有界")
	t.expect(mods.size() >= 1, "肉鸽: 每局命运卡生效(有 mod 写入 cfg)")


## 天选者规则: 非天选者选卡被拒; 人类天选者超时由服务器托管代选
func _rogue_picker_rules(t) -> void:
	var m = _mgr()
	var out: Array = m.create_room(100, "甲",
			{"mode": "rogue", "rogue": true, "rounds": 3, "turn_seconds": 5}, "cid-A")
	var code := str(_rs(out, 100)["room_code"])
	m.hello(101, MsgC.PROTOCOL_VERSION, "", "cid-B")
	m.join_room(101, "乙", code, "cid-B")
	m.fill_bots(100)
	m.start(100, 0)
	var room = _room_of(m, code)
	var st = room.match_ctl.state
	var picker: int = int(st["rogue_picker"])
	var other := 101 if picker == 0 else 100
	out = m.rogue_pick(other, 0)
	t.expect(_count(out, "s_error") == 1, "肉鸽: 非天选者选卡被明确拒绝")
	# 人类天选者不选: 推进时钟 → 5s 窗口 + 2.5s 宽限后托管代选
	var now := 0
	var guard := 0
	while guard < 20000 and str(room.match_ctl.state["phase"]) == "draft":
		guard += 1
		now += 100
		m.tick(now)
	t.expect(str(room.match_ctl.state["phase"]) != "draft", "肉鸽: 天选者超时由服务器代选")
	t.expect(str(room.match_ctl.state["cfg"]["rogue_mod"]) != "", "肉鸽: 代选后命运卡生效")


# ================================================================ 格斗对战

## 双真人格斗: 选牌→对战→终局→回房; 怒气不足奥义被拒
func _fight_two_humans(t) -> void:
	var m = _mgr()
	var out: Array = m.create_room(100, "甲", {"mode": "fight"}, "cid-A")
	var code := str(_rs(out, 100)["room_code"])
	m.hello(101, MsgC.PROTOCOL_VERSION, "", "cid-B")
	m.join_room(101, "乙", code, "cid-B")
	out = m.start(100, 0)
	var room = _room_of(m, code)
	t.expect(room.match_ctl != null and str(room.match_ctl.kind) == "fight",
			"格斗: 开局进入格斗控制器")
	t.expect(_fight_states(out).size() == 2, "格斗: 双方收到战斗视图")
	var now := 0
	var guard := 0
	var rounds_won := {"a": 0, "b": 0}
	var ult_rejected := 0
	var finished := false
	while guard < 120000 and not finished:
		guard += 1
		now += 100
		var phase := str(room.match_ctl.state["phase"])
		if phase == "draft":
			for seat in [0, 1]:
				var per: Dictionary = room.match_ctl.state["per"][seat]
				if not bool(per["done"]):
					var cand: int = (per["pair"] as Array)[0]
					var slot := 0 if (per["slots"] as Array).size() >= 5 else -1
					out = m.fight_pick(100 if seat == 0 else 101,
							{"cand": cand, "slot": slot})
		elif phase == "battle":
			var turn: int = int(room.match_ctl.state["battle"]["turn"])
			if turn == 0:
				var fury: int = int(room.match_ctl.state["battle"]["fury"][0])
				out = m.fight_act(100, "ult")
				if _count(out, "s_error") > 0:
					ult_rejected += 1
				out = m.fight_act(100, "attack")
			else:
				out = m.fight_act(101, "attack")
		elif phase == "round_end":
			var rw: int = int(room.match_ctl.state["round_winner"])
			if rw == 0:
				rounds_won["a"] += 1
			elif rw == 1:
				rounds_won["b"] += 1
		m.tick(now)
		if room.match_ctl == null:
			finished = true
	t.expect(finished, "格斗: 对局打到 over 并收尾回房")
	t.expect(guard < 120000, "格斗: tick 有界")
	t.expect(ult_rejected >= 1, "格斗: 怒气不足时奥义被拒")
	t.expect(int(rounds_won["a"]) + int(rounds_won["b"]) >= 3, "格斗: 先胜 3 回合制生效")


## 观战者: 第 3 人入格斗房 → 观战位; 收视图无操作权; 选牌/行动被拒
func _fight_spectator(t) -> void:
	var m = _mgr()
	var out: Array = m.create_room(100, "甲", {"mode": "fight"}, "cid-A")
	var code := str(_rs(out, 100)["room_code"])
	m.hello(101, MsgC.PROTOCOL_VERSION, "", "cid-B")
	m.join_room(101, "乙", code, "cid-B")
	m.hello(102, MsgC.PROTOCOL_VERSION, "", "cid-C")
	out = m.join_room(102, "丙", code, "cid-C")
	t.expect(int(_rs(out, 102)["my_seat"]) == 2, "格斗: 第 3 人入观战位(座位 2)")
	out = m.start(100, 0)
	t.expect(_fight_states(out).size() == 3, "格斗: 观战者也收战斗视图")
	var spec_vs: Array = _fight_states_to(out, 102)
	t.expect(bool(spec_vs[0]["data"]["view"]["spectator"]), "格斗: 观战者标记 spectator")
	# 观战者选牌/行动被拒
	out = m.fight_pick(102, {"cand": 0, "slot": -1})
	t.expect(_count_to(out, 102, "s_error") == 1, "格斗: 观战者选牌被拒")
	out = m.fight_act(102, "attack")
	t.expect(_count_to(out, 102, "s_error") == 1, "格斗: 观战者行动被拒")
	# 双格斗者推进到 battle, 观战者持续收状态
	var room = _room_of(m, code)
	var now := 0
	var guard := 0
	var spec_updates := 0
	while guard < 120000 and room.match_ctl != null:
		guard += 1
		now += 100
		var phase := str(room.match_ctl.state["phase"])
		if phase == "draft":
			for seat in [0, 1]:
				var per: Dictionary = room.match_ctl.state["per"][seat]
				if not bool(per["done"]):
					m.fight_pick(100 if seat == 0 else 101,
							{"cand": (per["pair"] as Array)[0], "slot": -1})
		elif phase == "battle":
			var turn: int = int(room.match_ctl.state["battle"]["turn"])
			m.fight_act(100 if turn == 0 else 101, "attack")
		spec_updates += _count_to(m.tick(now), 102, "s_fight_state")
	t.expect(room.match_ctl == null, "格斗: 观战局打到收尾回房")
	t.expect(spec_updates >= 1, "格斗: 观战者持续收到状态广播")


## 格斗中掉线: AI 立即接管; token 重连回座并收到当前视图
func _fight_disconnect_ai(t) -> void:
	var m = _mgr()
	var out: Array = m.create_room(100, "甲", {"mode": "fight"}, "cid-A")
	var code := str(_rs(out, 100)["room_code"])
	m.hello(101, MsgC.PROTOCOL_VERSION, "", "cid-B")
	m.join_room(101, "乙", code, "cid-B")
	m.start(100, 0)
	var room = _room_of(m, code)
	var token := str(room.seats[1]["token"])
	# 双方选完牌进入 battle 后乙掉线
	var now := 0
	var guard := 0
	while guard < 20000 and str(room.match_ctl.state["phase"]) == "draft":
		guard += 1
		now += 100
		var per: Dictionary = room.match_ctl.state["per"][0]
		if not bool(per["done"]):
			m.fight_pick(100, {"cand": (per["pair"] as Array)[0], "slot": -1})
		m.tick(now)
	m.peer_gone(101)
	t.expect(room.match_ctl.is_bot_seat(1), "格斗: 掉线者座位转 AI 代管")
	# AI 代管能推进战斗(不掉死)
	var saw_events := 0
	while guard < 80000 and room.match_ctl != null \
			and str(room.match_ctl.state["phase"]) == "battle":
		guard += 1
		now += 100
		saw_events += _count(m.tick(now), "s_fight_state")
	t.expect(saw_events >= 1 or room.match_ctl == null
			or str(room.match_ctl.state["phase"]) != "battle",
			"格斗: AI 代管推进战斗")
	# 重连: token 回座 + 收当前视图
	out = m.hello(999, MsgC.PROTOCOL_VERSION, token, "cid-B")
	t.expect(int(_find(out, 999, "s_welcome")["seat"]) == 1, "格斗: token 重连回原座")
	t.expect(_fight_states(out).size() >= 1, "格斗: 重连收当前战斗视图")
	t.expect(not room.match_ctl.is_bot_seat(1), "格斗: 重连后恢复真人接管")


## 单人格斗: 房主开局 → 2 号位自动补 AI, 可打完整场
func _fight_single_human(t) -> void:
	var m = _mgr()
	var out: Array = m.create_room(100, "甲", {"mode": "fight"}, "cid-A")
	var code := str(_rs(out, 100)["room_code"])
	out = m.start(100, 0)
	var room = _room_of(m, code)
	t.expect(room.match_ctl != null, "格斗: 单人开局成功")
	t.expect(room.seats[1] != null and bool(room.seats[1]["bot"]),
			"格斗: 2 号位自动补 AI")
	var now := 0
	var guard := 0
	while guard < 120000 and room.match_ctl != null:
		guard += 1
		now += 100
		var phase := str(room.match_ctl.state["phase"])
		if phase == "draft":
			var per: Dictionary = room.match_ctl.state["per"][0]
			if not bool(per["done"]):
				m.fight_pick(100, {"cand": (per["pair"] as Array)[0], "slot": -1})
		elif phase == "battle":
			var turn: int = int(room.match_ctl.state["battle"]["turn"])
			if turn == 0:
				m.fight_act(100, "attack")
		m.tick(now)
	t.expect(room.match_ctl == null, "格斗: 单人局打完收尾回房")


# ================================================================ 工具

func _mgr():
	var m = RoomManagerGd.new()
	m.ai_delay_ms = 60
	m.phase_delay_ms = 250
	m.stats.save_path = "user://test_stats.json"
	return m


func _room_of(m, code: String):
	return m.rooms.get(code)


func _rs(out: Array, peer: int) -> Dictionary:
	for msg in out:
		if str(msg["event"]) == "s_room_state" and int(msg["peer"]) == peer:
			return msg["data"]
	return {}


func _find(out: Array, peer: int, event: String) -> Dictionary:
	for msg in out:
		if str(msg["event"]) == event and int(msg["peer"]) == peer:
			return msg["data"]
	return {}


func _count(out: Array, event: String) -> int:
	var n := 0
	for msg in out:
		if str(msg["event"]) == event:
			n += 1
	return n


func _count_to(out: Array, peer: int, event: String) -> int:
	var n := 0
	for msg in out:
		if str(msg["event"]) == event and int(msg["peer"]) == peer:
			n += 1
	return n


func _views(out: Array) -> Array:
	var vs := []
	for msg in out:
		if str(msg["event"]) == "s_game_view":
			vs.append(msg)
	return vs


func _fight_states(out: Array) -> Array:
	var vs := []
	for msg in out:
		if str(msg["event"]) == "s_fight_state":
			vs.append(msg)
	return vs


func _fight_states_to(out: Array, peer: int) -> Array:
	var vs := []
	for msg in out:
		if str(msg["event"]) == "s_fight_state" and int(msg["peer"]) == peer:
			vs.append(msg)
	return vs
