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
	_eight_cut_last_card(t)
	_joker_last_ban(t)
	_fall_from_grace(t)
	_full_match_flow(t)
	_exchange_details(t)
	_view_privacy(t)


## 禁止最后单张出王: 手中只剩一张王时不能单出获胜。
func _joker_last_ban(t) -> void:
	# 手中只剩一张王 → 不能单出(禁止最后单张出王)
	var st := GameStateGd.new_match({}, 7)
	st["phase"] = "play"
	st["turn"] = 0
	st["lead"] = {}
	st["must_include"] = -1
	st["finish_order"] = []
	st["hands"][0] = [52]
	st["hands"][1] = [20, 21]
	st["hands"][2] = [40, 41]
	st["hands"][3] = [44, 45]
	var r := GameStateGd.apply(st, {"t": "play", "seat": 0, "cards": [52]})
	t.expect(not bool(r["ok"]), "最后一张王被禁止单出")
	t.expect_eq(str(r["error"]), "joker_last_ban", "错误码 joker_last_ban")
	# 对照: 最后一张普通牌可以出完
	var st2 := GameStateGd.new_match({}, 7)
	st2["phase"] = "play"
	st2["turn"] = 0
	st2["lead"] = {}
	st2["must_include"] = -1
	st2["finish_order"] = []
	st2["hands"][0] = [20]
	st2["hands"][1] = [21, 22]
	st2["hands"][2] = [40, 41]
	st2["hands"][3] = [44, 45]
	var r2 := GameStateGd.apply(st2, {"t": "play", "seat": 0, "cards": [20]})
	t.expect(bool(r2["ok"]), "最后一张普通牌可正常出完")
	# 两张牌(含王)时, 先出普通牌合法
	var st3 := GameStateGd.new_match({}, 7)
	st3["phase"] = "play"
	st3["turn"] = 0
	st3["lead"] = {}
	st3["must_include"] = -1
	st3["finish_order"] = []
	st3["hands"][0] = [20, 52]
	st3["hands"][1] = [21, 22]
	st3["hands"][2] = [40, 41]
	st3["hands"][3] = [44, 45]
	var r3 := GameStateGd.apply(st3, {"t": "play", "seat": 0, "cards": [20]})
	t.expect(bool(r3["ok"]), "两张牌先出普通牌合法")
## 一落千丈: 上局大富豪未保住第一 → 与本局末位互换身份。
func _fall_from_grace(t) -> void:
	var st := GameStateGd.new_match({}, 7)
	# 上局身份: 座位3 = 大富豪
	st["identities"] = [1, 3, 2, 0]
	# 本局完牌顺序: 0→3→1, 剩 2
	# 一落千丈(非互换): 3 直接垫底为大贫民; 其余按出完顺序 0=大富豪,1=富豪,2=贫民
	st["finish_order"] = [0, 3]
	var r := GameStateGd._finish_player(st, 1)
	t.expect(bool(r["ok"]), "一落千丈结算成功")
	var ids: Array = r["state"]["identities"]
	t.expect_eq(int(ids[3]), 3, "上局大富豪掉到大贫民")
	t.expect_eq(int(ids[0]), 0, "完牌第1名获得大富豪")
	t.expect_eq(int(ids[1]), 1, "完牌第3名(座位1)获得富豪")
	t.expect_eq(int(ids[2]), 2, "未出完者(座位2)获得贫民")
	var uniq := {}
	for id in ids:
		uniq[int(id)] = true
	t.expect_eq(uniq.size(), 4, "身份仍 4 种各一")
	# 上局大富豪保住第一 → 不触发
	var st2 := GameStateGd.new_match({}, 7)
	st2["identities"] = [1, 3, 2, 0]
	st2["finish_order"] = [3, 0]
	var r2 := GameStateGd._finish_player(st2, 1)
	t.expect_eq(int(r2["state"]["identities"][3]), 0, "保住第一不降位")


## 回归：8切开启时，最后一张牌恰好是 8 也必须正常登记出完（曾死循环）。
func _eight_cut_last_card(t) -> void:
	var st := GameStateGd.new_match({"eight_cut": true, "rounds": 1}, 7)
	st["phase"] = "play"
	st["must_include"] = -1
	st["finish_order"] = []
	st["turn"] = 1
	st["lead"] = {}
	# 1 号手牌只剩一张 8（id 20 = 8♠）
	st["hands"][1] = [20]
	var r := GameStateGd.apply(st, {"t": "play", "seat": 1, "cards": [20]})
	t.expect(bool(r["ok"]), "打出单 8")
	t.expect((r["state"]["finish_order"] as Array).has(1), "8切最后一张仍登记出完")
	t.expect_eq((r["state"]["hands"][1] as Array).size(), 0, "手牌已空")


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
				action = BotPlayerGd.decide(st, int(st["turn"]))
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
	var rich := -1
	for s in 4:
		if int(ids[s]) == 3:
			beggar = s
		elif int(ids[s]) == 0:
			millionaire = s
		elif int(ids[s]) == 1:
			rich = s
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
	t.expect_eq((st2["exchange"] as Array).size(), 2, "两笔交牌(返还待玩家选择)")
	var ex: Array = st2["exchange"]
	t.expect_eq(int(ex[0]["from"]), beggar, "乞丐交 2 张")
	t.expect_eq(int(ex[0]["to"]), millionaire, "交给大富豪")
	t.expect_eq((ex[0]["cards"] as Array), (fresh[beggar] as Array).slice(-2), "交出的是新手牌最大 2 张")
	t.expect_eq(int(ex[1]["from"]), commoner, "平民交 1 张")
	t.expect_eq((ex[1]["cards"] as Array), (fresh[commoner] as Array).slice(-1), "交出的是新手牌最大 1 张")
	t.expect((st2["hands"][millionaire] as Array).has(ex[0]["cards"][0]), "大富豪收到牌")
	t.expect(not (st2["hands"][beggar] as Array).has(ex[0]["cards"][0]), "乞丐失去最大牌")
	# 返还环节: 大富豪先选 2 张, 再轮富豪选 1 张
	t.expect_eq(int(st2["turn"]), millionaire, "大富豪先返还")
	# 错误数量被拒
	var bad := GameStateGd.apply(st2, {"t": "exchange_return", "seat": millionaire, "cards": []})
	t.expect(not bool(bad["ok"]), "返还数量错误被拒")
	# 非当前接收者被拒
	var not_turn := GameStateGd.apply(st2, {"t": "exchange_return", "seat": rich, "cards": []})
	t.expect(not bool(not_turn["ok"]), "非当前返还者被拒")
	var ret_hand: Array = st2["hands"][millionaire].duplicate()
	CardsGd.sort_cards(ret_hand)
	var give_back: Array = ret_hand.slice(0, 2)
	var r2 := GameStateGd.apply(st2, {"t": "exchange_return", "seat": millionaire, "cards": give_back})
	t.expect(bool(r2["ok"]), "大富豪返还 2 张")
	var st3: Dictionary = r2["state"]
	t.expect_eq(int(st3["turn"]), rich, "轮到富豪返还 1 张")
	t.expect((st3["hands"][beggar] as Array).has(give_back[0]), "乞丐收到返还牌")
	var rich_hand: Array = st3["hands"][rich].duplicate()
	CardsGd.sort_cards(rich_hand)
	var r3 := GameStateGd.apply(st3, {"t": "exchange_return", "seat": rich,
			"cards": [rich_hand[0]]})
	t.expect(bool(r3["ok"]), "富豪返还 1 张")
	t.expect_eq(str(r3["state"]["phase"]), "play", "交换完成进入 play")
	t.expect_eq(int(r3["state"]["turn"]), beggar, "乞丐先出")
	t.expect_eq((r3["state"]["exchange"] as Array).size(), 4, "交换记录含 2 笔返还")
	t.expect(not bool(r3["state"]["revolution"]), "新局革命重置")


func _view_privacy(t) -> void:
	var st := GameStateGd.new_match({}, 99)
	for seat in 4:
		var v := ViewGd.build(st, seat)
		t.expect(not v.has("hands"), "view 不含 hands 字段")
		t.expect_eq(v["hand"], st["hands"][seat], "view.hand = 本人手牌")
		t.expect_eq(int(v["counts"][seat]), 13, "view 计数正确")
