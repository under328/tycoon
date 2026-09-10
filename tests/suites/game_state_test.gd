## 对局状态机测试：流程、Pass/清桌、革命、身份结算、局间交换（对应 docs/规则规格.md）。
extends RefCounted

const CardsGd = preload("res://src/rules/cards.gd")
const ComboGd = preload("res://src/rules/combo.gd")
const GameStateGd = preload("res://src/rules/game_state.gd")
const ScoringGd = preload("res://src/rules/scoring.gd")
const BotPlayerGd = preload("res://src/rules/ai/bot_player.gd")
const ViewGd = preload("res://src/protocol/view.gd")


func run(t) -> void:
	_new_match_basics(t)
	_pass_and_clear(t)
	_revolution(t)
	_full_match_flow(t)
	_exchange_details(t)
	_view_privacy(t)


func _new_match_basics(t) -> void:
	var a := GameStateGd.new_match({}, 42)
	var b := GameStateGd.new_match({}, 42)
	t.expect_eq(a["hands"], b["hands"], "同种子发牌一致")
	t.expect_eq(a["phase"], "play", "开局直接进入 play")
	for s in 4:
		t.expect_eq((a["hands"][s] as Array).size(), 13, "每人 13 张")
	# 手牌互不重复
	var all_cards := []
	for s in 4:
		all_cards.append_array(a["hands"][s])
	t.expect_eq(all_cards.size(), 52, "52 张全部发出")
	var uniq := {}
	for c in all_cards:
		uniq[c] = true
	t.expect_eq(uniq.size(), 52, "无重复发牌")
	t.expect_eq((a["dead"] as Array).size(), 2, "两张死牌")
	# 首局先出规则：持♦3者先出且首手必含♦3；♦3 为死牌则随机首出无限制
	var checked_dead := false
	for seed_v in range(1000, 1050):
		var m := GameStateGd.new_match({}, seed_v)
		var holder := -1
		for s in 4:
			if (m["hands"][s] as Array).has(CardsGd.DIAMOND_3):
				holder = s
		if holder >= 0:
			t.expect_eq(m["turn"], holder, "seed %d: 持♦3者先出" % seed_v)
			t.expect_eq(int(m["must_include"]), CardsGd.DIAMOND_3, "seed %d: 限含♦3" % seed_v)
		else:
			checked_dead = true
			t.expect_eq(m["turn"], seed_v % 4, "seed %d: ♦3死牌 → 随机首出" % seed_v)
			t.expect_eq(int(m["must_include"]), -1, "seed %d: 无♦3限制" % seed_v)
	t.expect(checked_dead, "样本中覆盖到 ♦3 为死牌的分支")
	# 首手不含♦3 被拒（seed 42 存在持♦3者）
	if int(a["must_include"]) >= 0:
		var h2 := -1
		for s in 4:
			if (a["hands"][s] as Array).has(CardsGd.DIAMOND_3):
				h2 = s
		var bad := GameStateGd.apply(a, {"t": "play", "seat": h2, "cards": [48]})
		t.expect(not bool(bad["ok"]), "首手不含♦3 被拒")
		t.expect_eq(str(bad["error"]), "must_include_diamond3", "错误码 must_include")


func _pass_and_clear(t) -> void:
	var st := GameStateGd.new_match({}, 7)
	# 构造微场景：0 出了单3，轮到 1
	st["phase"] = "play"
	st["must_include"] = -1
	st["finish_order"] = []
	st["turn"] = 1
	st["lead"] = {"type": ComboGd.Type.SINGLE, "key": 3, "len": 1, "cards": [1]}
	st["field"] = [{"seat": 0, "combo": st["lead"]}]
	st["last_player"] = 0
	var r1 := GameStateGd.apply(st, {"t": "pass", "seat": 1})
	t.expect(bool(r1["ok"]), "1 号 pass")
	t.expect_eq(int(r1["state"]["turn"]), 2, "轮到 2 号")
	t.expect(not bool(GameStateGd.apply(r1["state"], {"t": "pass", "seat": 3})["ok"]),
			"未轮到时 pass 被拒")
	var r2 := GameStateGd.apply(r1["state"], {"t": "pass", "seat": 2})
	var r3 := GameStateGd.apply(r2["state"], {"t": "pass", "seat": 3})
	t.expect_eq((r3["state"]["field"] as Array).size(), 0, "全员不要 → 清桌")
	t.expect(bool(r3["state"]["lead"].is_empty()), "清桌后无跟牌要求")
	t.expect_eq(int(r3["state"]["turn"]), 0, "最后出牌者 0 号领出")
	# 自由领出不可 pass
	t.expect_eq(str(GameStateGd.apply(r3["state"], {"t": "pass", "seat": 0})["error"]),
			"cannot_pass_on_lead", "领出 pass 被拒")


func _revolution(t) -> void:
	var st := GameStateGd.new_match({}, 7)
	st["phase"] = "play"
	st["must_include"] = -1
	st["turn"] = 1
	st["lead"] = {}
	# 1 号手牌换成 四条3 + 四条5 + 杂牌，确保能先后打出两组四条
	st["hands"][1] = [0, 1, 2, 3, 8, 9, 10, 11, 24, 28, 32, 36, 40]
	var r := GameStateGd.apply(st, {"t": "play", "seat": 1, "cards": [0, 1, 2, 3]})
	t.expect(bool(r["ok"]), "打出四条3")
	t.expect(bool(r["state"]["revolution"]), "革命开启")
	t.expect_eq(int(r["state"]["quads"]), 1, "四条计数 1")
	# 再打一次四条 → 反转恢复
	r["state"]["turn"] = 1
	r["state"]["lead"] = {}
	var r2 := GameStateGd.apply(r["state"], {"t": "play", "seat": 1, "cards": [8, 9, 10, 11]})
	t.expect(not bool(r2["state"]["revolution"]), "两次革命恢复点序")
	# 关闭革命配置时不触发
	var cfg := {"revolution": false}
	var st2 := GameStateGd.new_match(cfg, 7)
	st2["phase"] = "play"
	st2["must_include"] = -1
	st2["turn"] = 1
	st2["hands"][1] = [0, 1, 2, 3, 8, 12, 16, 20, 24, 28, 32, 36, 40]
	var r3 := GameStateGd.apply(st2, {"t": "play", "seat": 1, "cards": [0, 1, 2, 3]})
	t.expect(not bool(r3["state"]["revolution"]), "关闭革命时不反转")


## 用 AI 打完一整场（3 局）验证全流程与结算。
func _full_match_flow(t) -> void:
	var st := GameStateGd.new_match({}, 123)
	var rounds_seen := 0
	var guard := 0
	while str(st["phase"]) != "game_end" and guard < 20000:
		guard += 1
		var action := {}
		match str(st["phase"]):
			"play":
				action = BotPlayerGd.decide(st, int(st["turn"]))
			"exchange":
				action = {"t": "exchange_done", "seat": int(st["turn"])}
			"round_end":
				rounds_seen += 1
				t.expect_eq((st["finish_order"] as Array).size(), 4, "局终名次齐 4 人")
				var sum := 0
				for p in st["last_points"]:
					sum += int(p)
				t.expect_eq(sum, 0, "单局积分和为 0")
				action = {"t": "next_round"}
		var r := GameStateGd.apply(st, action)
		if not bool(r["ok"]):
			t.expect(false, "AI 全流程非法动作: %s @%s" % [str(r["error"]), str(st["phase"])])
			return
		st = r["state"]
	t.expect_eq(str(st["phase"]), "game_end", "到达 game_end")
	t.expect_eq(rounds_seen, 3, "默认打 3 局")
	var total := 0
	for p in st["scores"]:
		total += int(p)
	t.expect_eq(total, 0, "三局总分和为 0")
	var uniq_id := {}
	for id in st["identities"]:
		uniq_id[int(id)] = true
	t.expect_eq(uniq_id.size(), 4, "身份 4 种各一")


func _exchange_details(t) -> void:
	# 先用 AI 打到第一次 round_end
	var st := GameStateGd.new_match({}, 555)
	var guard := 0
	while str(st["phase"]) != "round_end" and guard < 5000:
		guard += 1
		var act := BotPlayerGd.decide(st, int(st["turn"])) if str(st["phase"]) == "play" \
				else {"t": "next_round"}
		st = GameStateGd.apply(st, act)["state"]
	var ids: Array = st["identities"]
	var beggar := -1
	var millionaire := -1
	var commoner := -1
	for s in 4:
		if int(ids[s]) == 3:
			beggar = s
		elif int(ids[s]) == 0:
			millionaire = s
		elif int(ids[s]) == 2:
			commoner = s
	var r := GameStateGd.apply(st, {"t": "next_round"})
	t.expect(bool(r["ok"]), "进入下一局")
	var st2: Dictionary = r["state"]
	# 复现新局发牌（与 game_state._deal_round 同种子规则），用于校验"交最大牌"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(st2["seed"], ":", int(st2["round"])))
	var deck := CardsGd.full_deck(true)
	CardsGd.shuffle(deck, rng)
	var fresh := [[], [], [], []]
	for s in 4:
		for i in 13:
			fresh[s].append(deck[s * 13 + i])
		CardsGd.sort_cards(fresh[s])
	t.expect_eq(str(st2["phase"]), "exchange", "交换阶段")
	t.expect_eq((st2["exchange"] as Array).size(), 2, "两笔交换")
	var ex: Array = st2["exchange"]
	t.expect_eq(int(ex[0]["from"]), beggar, "乞丐交 2 张")
	t.expect_eq(int(ex[0]["to"]), millionaire, "交给大富豪")
	t.expect_eq((ex[0]["cards"] as Array), (fresh[beggar] as Array).slice(-2), "交出的是新手牌最大 2 张")
	t.expect_eq(int(ex[1]["from"]), commoner, "平民交 1 张")
	t.expect_eq((ex[1]["cards"] as Array), (fresh[commoner] as Array).slice(-1), "交出的是新手牌最大 1 张")
	t.expect((st2["hands"][millionaire] as Array).has(ex[0]["cards"][0]), "大富豪收到牌")
	t.expect(not (st2["hands"][beggar] as Array).has(ex[0]["cards"][0]), "乞丐失去最大牌")
	# 交换完成 → 乞丐先出
	var r2 := GameStateGd.apply(st2, {"t": "exchange_done", "seat": beggar})
	t.expect_eq(str(r2["state"]["phase"]), "play", "交换完成进入 play")
	t.expect_eq(int(r2["state"]["turn"]), beggar, "乞丐先出")
	t.expect(not bool(r2["state"]["revolution"]), "新局革命重置")


func _view_privacy(t) -> void:
	var st := GameStateGd.new_match({}, 99)
	for seat in 4:
		var v := ViewGd.build(st, seat)
		t.expect(not v.has("hands"), "view 不含 hands 字段")
		t.expect_eq(v["hand"], st["hands"][seat], "view.hand = 本人手牌")
		t.expect_eq(int(v["counts"][seat]), 13, "view 计数正确")
