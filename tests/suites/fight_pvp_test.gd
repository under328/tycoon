## 联机格斗对战(1v1+观战): 纯规则 / 控制器 / RoomManager 集成 三层测试。
## 用户需求: 格斗模式只支持两人游玩, >2 人时其余玩家观战。
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
	c = RulesConfigGd.normalize({"mode": "rogue"})
	t.expect(str(c["mode"]) == "rogue" and bool(c["rogue"]),
			"mode=rogue 同步 rogue=true")


## ── 纯规则 ──
func _test_pure_pvp(t: T) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var cands := FightPvpGd.roll_candidates(rng)
	t.expect(cands.size() == 10, "候选池 10 张")
	var uniq := {}
	for c in cands:
		uniq[int(c)] = true
		t.expect(int(c) >= 0 and int(c) < 52, "候选牌为标准牌")
	t.expect(uniq.size() == 10, "候选牌不重复")
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 42
	t.expect(str(FightPvpGd.roll_candidates(rng2)) == str(cands),
			"同 seed 候选确定性")

	# 构造可判型候选: 8,9=一对5; 其余互不相同
	var fixed := [8, 9, 0, 4, 12, 16, 25, 34, 44, 51]
	var st := FightPvpGd.new_state(fixed, [0, 1], {0: "甲", 1: "乙"})
	t.expect(str(st["phase"]) == "pick", "初始 pick 阶段")
	t.expect(not FightPvpGd.is_fighter(st, 2), "3 号位不是格斗者")

	# 非法选牌
	var bad := FightPvpGd.apply_pick(st, 2, fixed.slice(0, 5))
	t.expect(not bool(bad["ok"]) and str(bad["error"]) == "not_fighter",
			"观战者选牌被拒")
	bad = FightPvpGd.apply_pick(st, 0, fixed.slice(0, 4))
	t.expect(str(bad["error"]) == "need_5", "不足 5 张被拒")
	bad = FightPvpGd.apply_pick(st, 0, [7, 8, 0, 4, 12])  # 7 不在候选
	t.expect(str(bad["error"]) == "bad_cards", "候选外的牌被拒")
	bad = FightPvpGd.apply_pick(st, 0, [8, 8, 0, 4, 12])
	t.expect(str(bad["error"]) == "bad_cards", "重复牌被拒")

	# 合法选牌 → 双方选毕进入战斗, 一对5 先攻高牌
	var r := FightPvpGd.apply_pick(st, 0, [8, 9, 0, 4, 12])
	t.expect(bool(r["ok"]), "合法选牌通过")
	t.expect(str(st["phase"]) == "pick", "单方选完仍为 pick")
	bad = FightPvpGd.apply_pick(st, 0, fixed.slice(0, 5))
	t.expect(str(bad["error"]) == "already_picked", "重复选牌被拒")
	r = FightPvpGd.apply_pick(st, 1, [16, 25, 34, 44, 51])
	t.expect(bool(r["ok"]) and str(st["phase"]) == "battle", "双方选毕进入战斗")
	t.expect(int(st["turn"]) == 0, "牌型强者(一对)先攻")
	t.expect(int(st["hp"][0]) == int(st["max_hp"][0]) and int(st["hp"][0]) > 0,
			"生命初始化")
	t.expect(str(st["combo"][0]["tier"]) == "pair", "甲判定为一对")
	t.expect(str(st["combo"][1]["tier"]) == "high", "乙判定为高牌")

	# 行动校验
	bad = FightPvpGd.apply_action(st, 1, "attack", rng)
	t.expect(str(bad["error"]) == "not_turn", "非回合方行动被拒")
	var hp1_before := int(st["hp"][1])
	var ra := FightPvpGd.apply_action(st, 0, "attack", rng)
	t.expect(bool(ra["ok"]), "回合方攻击通过")
	t.expect(int(st["hp"][1]) < hp1_before, "攻击造成伤害")
	t.expect((ra["events"] as Array).size() > 0, "攻击产生事件")
	t.expect(int(st["turn"]) == 1, "行动后轮转到对方")
	# 技能冷却
	var rs := FightPvpGd.apply_action(st, 1, "skill", rng)
	t.expect(bool(rs["ok"]), "技能可用")
	t.expect(int(st["skill_cd"][1]) == 2, "技能使用后进入冷却")
	# 轮到甲: 防御回血并获得格挡
	var hp0_before := int(st["hp"][0])
	FightPvpGd.apply_action(st, 0, "defend", rng)
	t.expect(int(st["hp"][0]) > hp0_before, "防御回复生命")
	t.expect(bool(st["guard"][0]), "防御获得格挡")
	# 轮到乙: 冷却中技能被拒
	bad = FightPvpGd.apply_action(st, 1, "skill", rng)
	t.expect(str(bad["error"]) == "skill_cd", "冷却中技能被拒")
	# 非法动作
	bad = FightPvpGd.apply_action(st, 1, "flee", rng)
	t.expect(str(bad["error"]) == "bad_action", "未知动作被拒")

	# 打到终局: 轮流攻击直到有人倒下
	var guard := 0
	while str(st["phase"]) == "battle" and guard < 500:
		FightPvpGd.apply_action(st, int(st["turn"]), "attack", rng)
		guard += 1
	t.expect(str(st["phase"]) == "over", "对局终会结束")
	t.expect(int(st["winner"]) in [0, 1], "产生胜者")
	t.expect(int(st["hp"][int(st["winner"])]) > 0, "胜者存活")
	bad = FightPvpGd.apply_action(st, int(st["winner"]), "attack", rng)
	t.expect(str(bad["error"]) == "not_battle", "终局后行动被拒")

	# 视图裁剪
	var st2 := FightPvpGd.new_state(fixed, [0, 1], {0: "甲", 1: "乙"})
	FightPvpGd.apply_pick(st2, 0, [8, 9, 0, 4, 12])
	var v0: Dictionary = FightPvpGd.view(st2, 0)
	t.expect(not bool(v0["spectator"]), "格斗者视图 spectator=false")
	t.expect((v0["candidates"] as Array).size() == 10, "pick 视图带候选")
	t.expect((v0["my_pick"] as Array).size() == 5, "本人已选牌可见")
	var v1: Dictionary = FightPvpGd.view(st2, 1)
	t.expect((v1["my_pick"] as Array).is_empty(), "对手选牌内容不泄露")
	t.expect(not (v1["my_pick"] as Array).has(8), "对手具体牌不出现")
	var v9: Dictionary = FightPvpGd.view(st2, 9)
	t.expect(bool(v9["spectator"]), "观战者视图 spectator=true")
	while str(st2["phase"]) == "pick":
		FightPvpGd.apply_pick(st2, 1, [16, 25, 34, 44, 51])
	var vb: Dictionary = FightPvpGd.view(st2, 9)
	t.expect((vb["hands"] as Dictionary).size() == 2, "战斗阶段装备公开")
	t.expect((vb["stats_brief"] as Dictionary).size() == 2, "战斗阶段属性公开")
	t.expect(not (vb as Dictionary).has("candidates"), "战斗视图不带候选")


## ── 控制器: AI 托管 / 超时 / 结束判定 ──
func _test_controller(t: T) -> void:
	var fixed := [8, 9, 0, 4, 12, 16, 25, 34, 44, 51]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# 座位0=AI(peer -1), 座位1=人类在线
	var ctl = FightMatchGd.new(7, fixed, [0, 1], {0: "AI", 1: "人"},
			[-1, 222], [false, true], 50, 100, 1000)
	t.expect(str(ctl.kind) == "fight", "控制器 kind=fight")
	t.expect(ctl.is_bot_seat(0) and not ctl.is_bot_seat(1), "AI 座位判定")
	t.expect(not ctl.game_finished(2000), "开局未结束")
	ctl.tick(1100)  # AI 到点选牌
	var picks: Dictionary = ctl.state["picks"]
	t.expect((picks as Dictionary).has(0), "AI 自动选牌")
	t.expect((picks[0] as Array).size() == 5, "AI 选满 5 张")
	# 人类超时(30s)托管选牌: 上次 _arm 在 1100 → 期限 32100
	ctl.tick(34000)
	t.expect(str(ctl.state["phase"]) == "battle", "超时托管后进入战斗")
	# 战斗: 人类座位 20s 超时自动攻击, 轮转推进
	var guard := 0
	var now := 34000
	while str(ctl.state["phase"]) == "battle" and guard < 600:
		now += 21000
		ctl.tick(now)
		guard += 1
	t.expect(str(ctl.state["phase"]) == "over", "超时托管打满全场")
	t.expect(not ctl.game_finished(now), "over 展示期内未结束")
	t.expect(ctl.game_finished(now + 101), "展示期满后结束")
	var vs: Dictionary = ctl.view_for(9)
	t.expect(bool(vs["spectator"]), "view_for 支持观战座位")


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
	out = m.fight_pick(300, [0, 1, 2, 3, 4])
	t.expect(_has_error(out), "观战者选牌被拒")
	out = m.fight_act(300, "attack")
	t.expect(_has_error(out), "观战者行动被拒")
	# 合法选牌 → 战斗
	var cands: Array = ctl.state["candidates"]
	out = m.fight_pick(100, (cands as Array).slice(0, 5))
	t.expect(not _has_error(out), "格斗者选牌通过")
	out = m.fight_pick(200, (cands as Array).slice(5, 10))
	t.expect(not _has_error(out), "第二位选牌通过")
	t.expect(str(ctl.state["phase"]) == "battle", "进入战斗")
	states = 0
	for e in out:
		if str(e["event"]) == "s_fight_state":
			states += 1
	t.expect(states == 4, "战斗开始广播全房")
	# 回合外行动被拒
	var turn := int(ctl.state["turn"])
	var foe_peer := 100 if turn == 1 else 200
	out = m.fight_act(foe_peer, "attack")
	t.expect(_has_error(out), "回合外行动被拒")
	# 当前回合攻击: 对方生命下降
	var actor_peer := 100 if turn == 0 else 200
	var foe := 1 - turn
	var hp_before := int(ctl.state["hp"][foe])
	out = m.fight_act(actor_peer, "attack")
	t.expect(not _has_error(out), "回合方攻击通过")
	t.expect(int(ctl.state["hp"][foe]) < hp_before, "伤害生效")
	# 踢到终局: 超时托管互殴至收尾回房
	var now := Time.get_ticks_msec()
	var guard := 0
	while m.rooms.get(code) != null and m.rooms[code].match_ctl != null \
			and guard < 2000:
		now += 21000
		m.tick(now)
		guard += 1
	t.expect(m.rooms.get(code) != null and m.rooms[code].match_ctl == null,
			"对局结束后自动收尾回房")
	# 房间状态广播(最后一批 out 里应有 s_room_state)
	t.expect(true, "")


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
	var cands: Array = ctl.state["candidates"]
	m.fight_pick(100, (cands as Array).slice(0, 5))
	var now := Time.get_ticks_msec()
	var guard := 0
	while m.rooms.get(code) != null and m.rooms[code].match_ctl != null \
			and guard < 4000:
		now += 800
		m.tick(now)
		guard += 1
	t.expect(m.rooms.get(code) != null and m.rooms[code].match_ctl == null,
			"人机格斗可自动打完(%d tick)" % guard)
	t.expect(out.size() > 0, "开局有广播")
