## 服务器纯逻辑测试：直接驱动 RoomManager（无网络）。
## 覆盖：版本握手、建房/加入/快速匹配、私发 view、AI 补位与推进、
## 断线 AI 接管、token 重连回座、回合超时托管。
extends RefCounted

const MsgC = preload("res://src/protocol/msg.gd")
const RoomManagerGd = preload("res://src/server/room_manager.gd")


func run(t) -> void:
	_basic_room_flow(t)
	_match_flow_with_bots(t)
	_disconnect_and_rejoin(t)
	_turn_timeout(t)
	_m3_features(t)


func _mgr():
	var m = RoomManagerGd.new()
	m.ai_delay_ms = 1
	m.phase_delay_ms = 1
	m.stats.save_path = "user://test_stats.json"
	return m


func _room_state_to(out: Array, peer: int) -> Dictionary:
	for m in out:
		if str(m["event"]) == "s_room_state" and int(m["peer"]) == peer:
			return m["data"]
	return {}


func _find(out: Array, peer: int, event: String) -> Dictionary:
	for m in out:
		if str(m["event"]) == event and int(m["peer"]) == peer:
			return m["data"]
	return {}


func _count(out: Array, event: String) -> int:
	var n := 0
	for m in out:
		if str(m["event"]) == event:
			n += 1
	return n


func _views(out: Array) -> Array:
	var vs := []
	for m in out:
		if str(m["event"]) == "s_game_view":
			vs.append(m)
	return vs


func _basic_room_flow(t) -> void:
	var m = _mgr()
	# 版本不符
	var out: Array = m.hello(100, MsgC.PROTOCOL_VERSION + 1, "")
	t.expect_eq(_count(out, "s_kicked"), 1, "版本不符 → kicked")
	t.expect_eq(str(_find(out, 100, "s_kicked")["reason"]), "version", "kicked 原因 version")
	# 正常握手
	out = m.hello(100, MsgC.PROTOCOL_VERSION, "")
	t.expect_eq(int(_find(out, 100, "s_welcome")["seat"]), -1, "无 token → 未入座")
	# 建房
	out = m.create_room(100, "甲", {})
	var rs: Dictionary = _room_state_to(out, 100)
	t.expect_eq(str(rs["room_code"]).length(), 6, "6 位房间码")
	t.expect_eq(int(rs["host_seat"]), 0, "创建者是房主")
	t.expect(rs.has("session_token"), "下发 session_token")
	var code := str(rs["room_code"])
	# 第二个人建房（独立房间），再加入甲的房间
	m.create_room(101, "乙", {})
	out = m.join_room(101, "乙改名", code)
	t.expect(_count(out, "s_room_state") >= 2, "加入后新旧两房都收到 room_state")
	t.expect(not _find(out, 100, "s_room_state").is_empty(), "甲收到成员变动")
	# 快速匹配：102 应排进甲的房
	out = m.quick_match(102, "丙", {})
	rs = _room_state_to(out, 102)
	t.expect_eq(str(rs["room_code"]), code, "快速匹配排入等待中的房")
	# 非成员出牌 → 无对局错误
	out = m.play(103, [0])
	t.expect_eq(_count(out, "s_error"), 1, "无对局时出牌报错")


func _setup_match(m, human_peers: Array) -> Dictionary:
	# human_peers[0] 建房并补 AI；其余加入。返回 {code, views_after_start}
	var out: Array = m.create_room(human_peers[0], "甲", {"turn_seconds": 5, "rounds": 1})
	var code := str(_room_state_to(out, human_peers[0])["room_code"])
	for i in range(1, human_peers.size()):
		m.join_room(human_peers[i], "玩家%d" % i, code)
	m.fill_bots(human_peers[0])
	out = m.start(human_peers[0], 0)
	return {"code": code, "out": out}


func _match_flow_with_bots(t) -> void:
	var m = _mgr()
	var s = _setup_match(m, [100])
	var out: Array = s["out"]
	# 只有 1 个人类 → 只有 1 份私有 view
	t.expect_eq(_views(out).size(), 1, "仅人类收到 game_view")
	var v: Dictionary = _views(out)[0]["data"]["view"]
	t.expect_eq((v["hand"] as Array).size(), 13, "开局 13 张手牌")
	t.expect_eq(int(v["my_seat"]), 0, "view 归属座位 0")
	t.expect_eq((v["counts"] as Array).size(), 4, "4 家牌数")
	# AI 推进到整场结束（以"房间回到空闲"为终点）
	var room = null
	for c in m.rooms:
		room = m.rooms[c]
	var now := 0
	var seen_round_end := 0
	var seen_exchange := 0
	var seen_game_end := 0
	var end_scores: Array = []
	var guard := 0
	while guard < 30000 and room.match_ctl != null:
		guard += 1
		now += 5
		out = m.tick(now)
		seen_round_end += _count(out, "s_round_end")
		seen_exchange += _count(out, "s_exchange")
		if _count(out, "s_game_end") > 0:
			seen_game_end += 1
			for msg in out:
				if str(msg["event"]) == "s_game_end":
					end_scores = msg["data"]["scores"]
	t.expect(room.match_ctl == null, "AI 自打整场到达 game_end 且房间空闲")
	t.expect(guard < 30000, "tick 有界")
	t.expect_eq(seen_round_end, 1, "1 局制 → 1 次 round_end")
	t.expect_eq(seen_exchange, 0, "1 局制 → 无交换")
	t.expect_eq(seen_game_end, 1, "1 次 game_end")
	var total := 0
	for p in end_scores:
		total += int(p)
	t.expect_eq(total, 0, "终局积分和为 0")


func _disconnect_and_rejoin(t) -> void:
	var m = _mgr()
	var s = _setup_match(m, [100, 101])
	var room = null
	for c in m.rooms:
		room = m.rooms[c]
	var token_1 := str(room.seats[1]["token"])
	# 101 掉线 → AI 接管，对局继续
	m.peer_gone(101)
	t.expect(bool(room.seats[1]["online"]) == false, "掉线座位标记离线")
	var now := 0
	var guard := 0
	var plays := 0
	while guard < 30000:
		guard += 1
		now += 5
		plays += _count(m.tick(now), "s_game_played")
		if plays >= 6:
			break
	t.expect(plays >= 6, "人类掉线后对局由 AI 接管继续进行")
	# ★ 对局中 token 重连：新 peer 999 拿回座位 1 并立即收到私有 view
	var out: Array = m.hello(999, MsgC.PROTOCOL_VERSION, token_1)
	t.expect_eq(int(_find(out, 999, "s_welcome")["seat"]), 1, "token → 回到原座位")
	t.expect(not _find(out, 999, "s_room_state").is_empty(), "重连收到 room_state")
	t.expect(_views(out).size() >= 1, "对局中重连立即收到私有 view")
	var v: Dictionary = _views(out)[0]["data"]["view"]
	t.expect_eq(int(v["my_seat"]), 1, "重连 view 归属座位 1")
	t.expect(bool(room.seats[1]["online"]), "重连后座位恢复在线")
	# 继续推进到打完 → 房间回到空闲（可再来一局）
	guard = 0
	var idle := false
	while guard < 30000:
		guard += 1
		now += 5
		m.tick(now)
		if room.match_ctl == null:
			idle = true
			break
	t.expect(idle, "对局结束房间空闲")


func _turn_timeout(t) -> void:
	var m = _mgr()
	_setup_match(m, [100])
	var room = null
	for c in m.rooms:
		room = m.rooms[c]
	var now := 0
	var view: Dictionary = {}
	# 推进到轮到人类（座位0）为止
	var guard := 0
	while guard < 5000:
		guard += 1
		var out: Array = m.tick(now)
		if not _views(out).is_empty():
			view = _views(out)[0]["data"]["view"]
		if not view.is_empty() and int(view["turn"]) == 0 \
				and str(view["phase"]) == "play":
			break
		now += 5
	t.expect(guard < 5000, "推进到人类回合")
	# 静置超过 turn_seconds(5s) → 托管接管（能压则出牌，压不过则 Pass）
	now += 6000
	var out2: Array = m.tick(now)
	t.expect(not _views(out2).is_empty(), "超时后广播新 view")
	var acted := _count(out2, "s_game_played") + _count(out2, "s_game_cleared")
	if not _views(out2).is_empty():
		var v2: Dictionary = _views(out2)[0]["data"]["view"]
		t.expect(acted > 0 or int(v2["turn"]) != 0 or str(v2["phase"]) != "play",
				"人类超时被托管接管")


## M3：规则设置 / 表情 / 战绩记录与查询 / 再来一局。
func _m3_features(t) -> void:
	var m = _mgr()
	var out: Array = m.create_room(100, "甲", {"rounds": 1}, "cid-A")
	var rs: Dictionary = _room_state_to(out, 100)
	var code := str(rs["room_code"])
	m.join_room(101, "乙", code, "cid-B")

	# --- 规则设置：非房主拒绝，房主生效 ---
	out = m.set_settings(101, {"eight_cut": true})
	t.expect_eq(_count(out, "s_room_state"), 0, "非房主改设置被拒")
	out = m.set_settings(100, {"eight_cut": true, "rounds": 2})
	rs = _room_state_to(out, 101)
	t.expect(bool(rs["settings"]["eight_cut"]), "房主改设置生效")
	t.expect_eq(int(rs["settings"]["rounds"]), 2, "局数设置生效")

	# --- 表情广播（对局前）---
	out = m.emoji(101, 3)
	t.expect_eq(_count(out, "s_emoji"), 2, "表情广播给房内两人")
	t.expect_eq(int(_find(out, 100, "s_emoji")["seat"]), 1, "表情带发送者座位")

	# --- 第一场：打完 → 战绩记录 + game_end 附带统计 ---
	m.fill_bots(100)
	out = m.start(100, 0)
	var now := 0
	var guard := 0
	var room = null
	for c in m.rooms:
		room = m.rooms[c]
	var end_data: Dictionary = {}
	while guard < 30000 and room.match_ctl != null:
		guard += 1
		now += 250  # 大步长：人类在线时超时托管需等 turn_seconds
		out = m.tick(now)
		for msg in out:
			if str(msg["event"]) == "s_game_end":
				end_data = msg["data"]
	t.expect(room.match_ctl == null, "带人类对局完整结束")
	t.expect(end_data.has("stats"), "game_end 附带战绩统计")
	t.expect_eq((end_data["stats"] as Dictionary).size(), 2, "两个人类有战绩条目")
	# cid-A 要么胜（总分最高）要么不胜，但一定有 1 场记录
	var my_stats: Dictionary = m.stats.get_entry("cid-A")
	t.expect_eq(int(my_stats["matches"]), 1, "cid-A 记 1 场")
	t.expect(int(my_stats["total_points"]) != 0 or int(my_stats["wins"]) > 0,
			"cid-A 积分入账")
	t.expect_eq(int(m.stats.get_entry("cid-B")["matches"]), 1, "cid-B 记 1 场")
	var wins_a := int(my_stats["wins"])
	var wins_b := int(m.stats.get_entry("cid-B")["wins"])
	t.expect(wins_a == 0 or wins_a == 1, "cid-A 胜场标记有效")
	t.expect(wins_b == 0 or wins_b == 1, "cid-B 胜场标记有效")

	# --- 战绩查询 ---
	out = m.stats_get(100)
	var st: Dictionary = _find(out, 100, "s_stats")["your"]
	t.expect_eq(int(st["matches"]), 1, "s_stats 查询返回本人战绩")

	# --- 再来一局（同一房间直接再开）---
	out = m.start(100, now)
	t.expect(_views(out).size() >= 1, "再来一局重新发私有 view")
	now += 5
	guard = 0
	var second_end := 0
	while guard < 30000 and room.match_ctl != null:
		guard += 1
		now += 250  # 与第一场相同：大步长等超时托管
		out = m.tick(now)
		second_end += _count(out, "s_game_end")
	t.expect(second_end >= 1, "第二场完整打完（按人广播计 ≥1）")
	t.expect(room.match_ctl == null, "第二场结束房间空闲")
	t.expect_eq(int(m.stats.get_entry("cid-A")["matches"]), 2, "战绩累计到 2 场")
	# 对局中也能发表情
	out = m.create_room(200, "丙", {}, "cid-C")
	m.fill_bots(200)
	m.start(200, now)
	out = m.emoji(200, 0)
	t.expect_eq(_count(out, "s_emoji"), 1, "对局中表情可发")
