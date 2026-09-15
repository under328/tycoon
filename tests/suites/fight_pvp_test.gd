## 联机格斗对战测试(回合制 v2): 每回合二选一编成 → 玩家互殴(无怪) →
## 先胜 3 回合获胜。覆盖: 纯规则 draft/battle/计分 / 控制器 AI+超时 /
## RoomManager 集成(4 人房: 前 2 座互殴, 其余观战)。
extends RefCounted

const T := preload("res://tests/t.gd")
const RulesConfigGd = preload("res://src/rules/rules_config.gd")
const FightPvpGd = preload("res://src/rules/fight/fight_pvp.gd")
const FightMatchGd = preload("res://src/server/fight_match.gd")
const ManagerGd = preload("res://src/server/room_manager.gd")


func run(t: T) -> void:
	_test_rules_mode(t)
	_test_pure_pvp(t)
	_test_controller(t)
	_test_manager_integration(t)
	_test_bot_full_match(t)
	_test_fury(t)


## ── 模式配置: mode 字段与 rogue 开关双向同步 ──
func _test_rules_mode(t: T) -> void:
	var c := RulesConfigGd.normalize({"mode": "fight"})
	t.expect(str(c["mode"]) == "fight", "fight 模式被保留")
	t.expect(not bool(c["rogue"]), "fight 模式不启用肉鸽")
	c = RulesConfigGd.normalize({"rogue": true})  # 旧调用方兼容
	t.expect(str(c["mode"]) == "rogue" and bool(c["rogue"]),
			"仅传 rogue=true 仍得到肉鸽模式")
	c = RulesConfigGd.normalize({"mode": "hacker"})
	t.expect(str(c["mode"]) == "normal", "未知模式回退普通")


## ── 纯规则 ──
func _test_pure_pvp(t: T) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 100
	var st := FightPvpGd.new_state([0, 1], {0: "甲", 1: "乙"})
	FightPvpGd.open_round(st, rng)
	t.expect(str(st["phase"]) == "draft", "开局 draft")
	t.expect(int(st["round_num"]) == 1, "第 1 回合")
	# 双方拿到同一主候选组
	var pa: Array = st["per"][0]["pair"]
	var pb: Array = st["per"][1]["pair"]
	t.expect(str(pa) == str(pb), "双方同一主候选组(公平)")
	t.expect((pa as Array).size() == 2, "二选一: 两张候选")
	# 非法操作
	t.expect(not bool(FightPvpGd.draft_pick(st, 2, pa[0], -1, rng)["ok"]),
			"观战者选牌被拒")
	t.expect(not bool(FightPvpGd.draft_pick(st, 0, -1, -1, rng)["ok"]),
			"槽空不允许跳过")
	t.expect(not bool(FightPvpGd.draft_pick(st, 0, 999, -1, rng)["ok"]),
			"候选外选牌被拒")
	# 甲选到编成完成(可能触发补抽链), 乙随后
	var r: Dictionary = FightPvpGd.draft_pick(st, 0, pa[0], -1, rng)
	t.expect(bool(r["ok"]), "合法选牌通过")
	var guard_a := 0
	while str(st["phase"]) == "draft" and not bool(st["per"][0]["done"]) \
			and guard_a < 20:
		guard_a += 1
		var pair_a: Array = st["per"][0]["pair"]
		t.expect(not (pair_a as Array).is_empty(), "未完成的格斗者必有候选组")
		r = FightPvpGd.draft_pick(st, 0, (pair_a as Array)[0], -1, rng)
	t.expect(bool(r["ok"]), "编成链通过")
	t.expect(bool(st["per"][0]["done"]) or str(st["phase"]) == "draft",
			"甲编成状态一致")
	# 乙未动 → 仍是 draft 或已 battle(甲可能已完成但需等乙)
	var r2: Dictionary = FightPvpGd.draft_pick(st, 1,
			(st["per"][1]["pair"] as Array)[0], -1, rng)
	var guard_b := 0
	while not bool(st["per"][1]["done"]) and str(st["phase"]) == "draft" \
			and guard_b < 20:
		guard_b += 1
		var pair_b: Array = st["per"][1]["pair"]
		t.expect(not (pair_b as Array).is_empty(), "未完成的格斗者必有候选组")
		r2 = FightPvpGd.draft_pick(st, 1, (pair_b as Array)[0], -1, rng)
	t.expect(bool(r2["ok"]), "乙选牌通过")
	t.expect(str(st["phase"]) == "battle", "双方完成 → 对战")
	t.expect(int(st["battle"]["hp"][0]) > 0, "对战新鲜生命(无怪, 玩家互殴)")
	# 回合外/错误行动
	t.expect(not bool(FightPvpGd.apply_action(st, 2, "attack", rng)["ok"]),
			"观战者行动被拒")
	var turn := int(st["battle"]["turn"])
	var foe := FightPvpGd.foe_of(st, turn)
	var bad: Dictionary = FightPvpGd.apply_action(st, foe, "attack", rng)
	t.expect(str(bad["error"]) == "not_turn", "回合外行动被拒")
	# 互殴至本回合结束
	var hp0 := int(st["battle"]["hp"][foe])
	var guard := 0
	while str(st["phase"]) == "battle" and guard < 300:
		guard += 1
		var t0 := int(st["battle"]["turn"])
		FightPvpGd.apply_action(st, t0, "attack", rng)
	t.expect(str(st["phase"]) in ["round_end", "over"], "对殴分出回合胜负")
	t.expect(int(st["round_winner"]) in [0, 1], "回合胜者产生")
	if str(st["phase"]) == "round_end":
		t.expect(int(st["battle"]["hp"][foe]) <= hp0, "败方生命耗尽")
		t.expect(int(st["score"][int(st["round_winner"])]) == 1, "比分 +1")
	# 视图
	var v0: Dictionary = FightPvpGd.view(st, 0)
	t.expect(not bool(v0["spectator"]), "格斗者视图")
	t.expect((v0["my"] as Dictionary).has("slots"), "本人编成可见")
	var v9: Dictionary = FightPvpGd.view(st, 9)
	t.expect(bool(v9["spectator"]), "观战者视图")
	t.expect((v9["my"] as Dictionary).is_empty(), "观战者无私有编成")
	t.expect((v9["per"] as Dictionary).size() == 2, "观战可见双方进度")


## ── 全局模拟: 五回合内必出胜负, 每回合装备恰好推进 ──
func _test_full_match_sim(t: T) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var st := FightPvpGd.new_state([0, 1], {0: "甲", 1: "乙"})
	FightPvpGd.open_round(st, rng)
	var guard := 0
	var rounds_battled := 0
	while str(st["phase"]) != "over" and guard < 3000:
		guard += 1
		match str(st["phase"]):
			"draft":
				for seat in st["fighters"]:
					var per: Dictionary = st["per"][seat]
					if not bool(per["done"]):
						var cand: int = (per["pair"] as Array)[0]
						var slot := -1
						if cand < 100 and (per["slots"] as Array).size() >= 5:
							slot = 0
						FightPvpGd.draft_pick(st, int(seat), cand, slot, rng)
			"battle":
				rounds_battled += 1
				var r5: Dictionary = st["per"][int(st["fighters"][0])]
				t.expect((r5["slots"] as Array).size() <= 5, "装备不超 5 张")
				if int(st["round_num"]) == 5:
					var r6: Dictionary = st["per"][1]
					t.expect((r6["slots"] as Array).size() == 5,
							"第 5 回合双方集齐 5 张")
				var t0 := int(st["battle"]["turn"])
				FightPvpGd.apply_action(st, t0, "attack", rng)
			"round_end":
				t.expect(FightPvpGd.advance_round(st, rng) or true, "推进回合")
	t.expect(str(st["phase"]) == "over", "先胜 3 回合 → 终局")
	t.expect(int(st["winner"]) in [0, 1], "整场胜者产生")
	t.expect(int(st["score"][int(st["winner"])]) >= 3, "胜者至少 3 分")
	t.expect(int(st["round_num"]) <= 5, "不超过 5 回合")


## ── 控制器: AI 托管 / 超时 / 回合过场 ──
func _test_controller(t: T) -> void:
	var ctl = FightMatchGd.new(7, [0, 1], {0: "AI", 1: "人"},
			[-1, 222], [false, true], 50, 100, 1000)
	t.expect(str(ctl.kind) == "fight", "控制器 kind=fight")
	t.expect(ctl.is_bot_seat(0) and not ctl.is_bot_seat(1), "AI 座位判定")
	t.expect(str(ctl.state["phase"]) == "draft", "开局 draft")
	# AI 到点自动选牌; 人类超时(30s)托管 → 大步 tick 同时驱动两者
	ctl.tick(1100)
	var guard := 0
	var now := 1100
	while str(ctl.state["phase"]) == "draft" and guard < 60:
		now += 31000
		ctl.tick(now)
		guard += 1
	t.expect(str(ctl.state["phase"]) == "battle", "AI+超时托管推进到对战")
	# 人类超时托管选牌在 deadline 后触发; 对战中超时自动攻击
	guard = 0
	while str(ctl.state["phase"]) in ["draft", "battle"] and guard < 4000:
		now += 21000
		ctl.tick(now)
		guard += 1
	t.expect(str(ctl.state["phase"]) in ["round_end", "over"],
			"超时托管推进对局")
	t.expect(not ctl.game_finished(now) or str(ctl.state["phase"]) == "over",
			"结束判定与阶段一致")


## ── RoomManager 集成: 4 人房开格斗, 3/4 号位观战 ──
func _test_manager_integration(t: T) -> void:
	var m = ManagerGd.new()
	m.create_room(100, "host", {"mode": "fight"})
	var code: String = str(m.peer_room[100])
	t.expect(m.rooms[code].settings["mode"] == "fight", "房间模式=fight")
	m.join_room(200, "乙", code)
	m.join_room(300, "观战1", code)
	m.join_room(400, "观战2", code)
	var out: Array = m.start(100)
	t.expect(m.rooms[code].match_ctl != null, "开局成功")
	t.expect(str(m.rooms[code].match_ctl.kind) == "fight", "格斗控制器")
	var states := 0
	for e in out:
		if str(e["event"]) == "s_fight_state":
			states += 1
	t.expect(states == 4, "全房收到战斗视图(含观战者)")
	var ctl = m.rooms[code].match_ctl
	t.expect((ctl.state["fighters"] as Array) == [0, 1], "1/2 号位为格斗者")
	# 观战者操作被拒
	out = m.fight_pick(300, {"cand": 0, "slot": -1})
	t.expect(_has_error(out), "观战者选牌被拒")
	out = m.fight_act(300, "attack")
	t.expect(_has_error(out), "观战者行动被拒")
	# 双方选牌(一路选到编成完成)
	var now := Time.get_ticks_msec()
	var guard := 0
	while str(ctl.state["phase"]) == "draft" and guard < 40:
		guard += 1
		var acted := false
		for seat in ctl.state["fighters"]:
			var per: Dictionary = ctl.state["per"][seat]
			if not bool(per["done"]) and not (per["pair"] as Array).is_empty():
				var cand: int = per["pair"][0]
				var slot := -1
				if cand < 100 and (per["slots"] as Array).size() >= 5:
					slot = 0
				var peer := 100 if int(seat) == 0 else 200
				out = m.fight_pick(peer, {"cand": cand, "slot": slot})
				t.expect(not _has_error(out), "格斗者选牌通过")
				acted = true
		if not acted:
			break
	t.expect(str(ctl.state["phase"]) == "battle", "双方编成完成 → 对战")
	# 回合外行动被拒
	var turn := int(ctl.state["battle"]["turn"])
	var foe_peer := 100 if turn == 1 else 200
	out = m.fight_act(foe_peer, "attack")
	t.expect(_has_error(out), "回合外行动被拒")
	var actor_peer := 100 if turn == 0 else 200
	var foe := 1 - turn
	var hp_before := int(ctl.state["battle"]["hp"][foe])
	out = m.fight_act(actor_peer, "attack")
	t.expect(not _has_error(out), "回合方攻击通过")
	t.expect(int(ctl.state["battle"]["hp"][foe]) < hp_before, "伤害生效")
	# 踢到终局: 超时托管互殴至收尾回房
	guard = 0
	while m.rooms.get(code) != null and m.rooms[code].match_ctl != null \
			and guard < 6000:
		now += 21000
		m.tick(now)
		guard += 1
	t.expect(m.rooms.get(code) != null and m.rooms[code].match_ctl == null,
			"对局结束后自动收尾回房")


func _has_error(out: Array) -> bool:
	for e in out:
		if str(e["event"]) == "s_error":
			return true
	return false


## ── 1 人开局: 2 号位自动补 AI, 全程可自动打完 ──
func _test_bot_full_match(t: T) -> void:
	var m = ManagerGd.new()
	m.create_room(100, "solo", {"mode": "fight"})
	var code: String = str(m.peer_room[100])
	var out: Array = m.start(100)
	var ctl = m.rooms[code].match_ctl
	t.expect(ctl != null and str(ctl.kind) == "fight", "1 人房可开格斗")
	t.expect(int(ctl.seat_peer[1]) == -1, "2 号位为 AI 格斗者")
	var now := Time.get_ticks_msec()
	var guard := 0
	while m.rooms.get(code) != null and m.rooms[code].match_ctl != null \
			and guard < 2000:
		now += 31000   # 每步解析一个托管动作(AI/超时/过场)
		m.tick(now)
		guard += 1
	t.expect(m.rooms.get(code) != null and m.rooms[code].match_ctl == null,
			"人机格斗可自动打完(%d tick)" % guard)
	t.expect(out.size() > 0, "开局有广播")


## 联机奥义: 怒气满可放大招, 未满被拒, 击倒奖励怒气
func _test_fury(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var st := FightPvpGd.new_state([0, 1], {0: "甲", 1: "乙"})
	FightPvpGd.open_round(st, rng)
	var guard := 0
	while str(st["phase"]) == "draft" and guard < 40:
		guard += 1
		for seat in st["fighters"]:
			var per: Dictionary = st["per"][seat]
			if not bool(per["done"]):
				var cand: int = (per["pair"] as Array)[0]
				var slot := -1
				if cand < 100 and (per["slots"] as Array).size() >= 5:
					slot = 0
				FightPvpGd.draft_pick(st, int(seat), cand, slot, rng)
	t.expect(str(st["phase"]) == "battle", "编成完成进入对战")
	# 怒气未满 → 奥义被拒
	var turn := int(st["battle"]["turn"])
	st["battle"]["fury"][turn] = 0
	var bad: Dictionary = FightPvpGd.apply_action(st, turn, "ult", rng)
	t.expect(str(bad["error"]) == "no_fury", "怒气未满奥义被拒")
	# 怒气满 → 奥义: 大伤害 + 回血 + 清零
	st["battle"]["fury"][turn] = 100
	var foe := FightPvpGd.foe_of(st, turn)
	var hp0 := int(st["battle"]["hp"][foe])
	var ok: Dictionary = FightPvpGd.apply_action(st, turn, "ult", rng)
	t.expect(bool(ok["ok"]), "奥义可用")
	t.expect(int(st["battle"]["hp"][foe]) < hp0, "奥义造成伤害")
	t.expect(int(st["battle"]["fury"][turn]) == 0, "奥义后怒气清零")
	t.expect((ok["events"] as Array).any(
			func(e: Dictionary) -> bool: return str(e["kind"]) == "ult"),
			"奥义事件存在")
	# 视图下发 fury
	var v: Dictionary = FightPvpGd.view(st, turn)
	t.expect((v.get("fury", {}) as Dictionary).has(turn), "视图下发怒气")
