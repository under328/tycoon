## 对局状态机（纯逻辑，客户端/服务器共用）。契约见 docs/规则规格.md。
## 状态为 Dictionary；apply() 入口深拷贝，返回全新状态，绝不变动入参。
## 返回格式：{ "ok": bool, "error": String, "state": Dictionary }
class_name GameState
extends RefCounted

const CardsGd = preload("res://src/rules/cards.gd")
const ComboGd = preload("res://src/rules/combo.gd")
const RulesConfigGd = preload("res://src/rules/rules_config.gd")
const ScoringGd = preload("res://src/rules/scoring.gd")

const SEATS := 4
const HAND_SIZE := 13


## 开新一场对局。seed_v<0 时随机。第 1 局直接进入 play：
## 持 ♦3 者先出且首手必含 ♦3；♦3 为死牌时随机首出、无限制。
static func new_match(cfg: Dictionary, seed_v: int = -1) -> Dictionary:
	cfg = RulesConfigGd.normalize(cfg)
	if seed_v < 0:
		seed_v = int(Time.get_unix_time_from_system() * 1000.0) % 1000000007
	var st := _empty_state(cfg, seed_v)
	_deal_round(st, 0)
	st["phase"] = "play"
	var holder := -1
	for s in SEATS:
		if (st["hands"][s] as Array).has(CardsGd.DIAMOND_3):
			holder = s
			break
	if holder >= 0:
		st["turn"] = holder
		st["must_include"] = CardsGd.DIAMOND_3
	else:
		st["turn"] = seed_v % SEATS  # ♦3 进了死牌（规格 §5）
		st["must_include"] = -1
	return st


## 动作: play{seat,cards} / pass{seat} / exchange_return{seat,cards} / next_round
static func apply(state: Dictionary, action: Dictionary) -> Dictionary:
	var st: Dictionary = state.duplicate(true)
	st["error"] = ""
	var t: String = str(action.get("t", ""))
	var seat: int = int(action.get("seat", -1))
	match t:
		"play":
			return _do_play(st, seat, action.get("cards", []))
		"pass":
			return _do_pass(st, seat)
		"exchange_return":
			return _do_exchange_return(st, action)
		"next_round":
			return _do_next_round(st)
		_:
			return _fail(st, "unknown_action")


# ---------------------------------------------------------------- 内部流程

static func _do_play(st: Dictionary, seat: int, cards: Array) -> Dictionary:
	if st["phase"] != "play":
		return _fail(st, "not_playing")
	if seat != int(st["turn"]):
		return _fail(st, "not_your_turn")
	var hand: Array = st["hands"][seat]
	for c in cards:
		if not hand.has(c):
			return _fail(st, "card_not_in_hand")
	var combo: Dictionary = ComboGd.identify(cards, st["cfg"])
	if combo.is_empty():
		return _fail(st, "invalid_combo")
	# 禁止最后单张出王: 手中仅剩一张王时, 不能将其作为最后一张单出获胜
	if hand.size() == 1 and cards.size() == 1 and CardsGd.is_joker(cards[0]):
		return _fail(st, "joker_last_ban")
	if st["lead"].is_empty():
		if int(st["must_include"]) >= 0 and not cards.has(int(st["must_include"])):
			return _fail(st, "must_include_diamond3")
	else:
		if not ComboGd.beats(combo, st["lead"], st["revolution"]):
			return _fail(st, "cannot_beat")
	for c in cards:
		hand.erase(c)
	st["field"].append({"seat": seat, "combo": combo})
	st["passes"] = 0
	st["last_player"] = seat
	st["must_include"] = -1
	# 革命：四条触发（含王辅助），奇数次反转
	if bool(st["cfg"]["revolution"]) and int(combo["type"]) == ComboGd.Type.QUAD:
		st["quads"] = int(st["quads"]) + 1
		st["revolution"] = int(st["quads"]) % 2 == 1
	# 出完牌结算必须先于 8 切（最后一张恰好是 8 时同样算出完）
	if hand.is_empty():
		return _finish_player(st, seat)
	# 8 切: 打出的牌组中包含任意 8 → 清桌续领（基础规则，不可关闭）
	var has_8 := false
	for c in cards:
		if CardsGd.value(c) == 8:
			has_8 = true
			break
	if has_8 and not hand.is_empty():
		st["field"].clear()
		st["lead"] = {}
		st["turn"] = seat
		return _ok(st)
	st["lead"] = combo
	st["turn"] = _next_active(st, seat)
	return _ok(st)


static func _do_pass(st: Dictionary, seat: int) -> Dictionary:
	if st["phase"] != "play":
		return _fail(st, "not_playing")
	if seat != int(st["turn"]):
		return _fail(st, "not_your_turn")
	if st["lead"].is_empty():
		return _fail(st, "cannot_pass_on_lead")
	st["passes"] = int(st["passes"]) + 1
	if int(st["passes"]) >= _active_count(st) - 1:
		st["field"].clear()
		st["lead"] = {}
		st["passes"] = 0
		var leader := int(st["last_player"])
		if (st["finish_order"] as Array).has(leader):
			leader = _next_active(st, leader)  # 领出者已出完离场 → 顺延
		st["turn"] = leader
	else:
		st["turn"] = _next_active(st, seat)
	return _ok(st)


static func _do_next_round(st: Dictionary) -> Dictionary:
	if st["phase"] != "round_end":
		return _fail(st, "not_round_end")
	var next_round := int(st["round"]) + 1
	if next_round >= int(st["cfg"]["rounds"]):
		st["phase"] = "game_end"
		return _ok(st)
	st["round"] = next_round
	_deal_round(st, next_round)
	# 强制交换（上一局身份）：大贫民→大富豪 2 张，贫民→富豪 1 张
	# 强者返还等量牌（任意牌）给弱者，确保各 13 张
	var ids: Array = st["identities"]
	var beggar := _seat_with_identity(ids, 3)
	var millionaire := _seat_with_identity(ids, 0)
	var commoner := _seat_with_identity(ids, 2)
	var rich := _seat_with_identity(ids, 1)
	st["exchange"] = [
		_give(st, beggar, millionaire, 2),
		_give(st, commoner, rich, 1),
	]
	# 强者返还等量"任意牌"——由接收者自选(M3 换牌流程), 依次结算
	st["exchange_returns"] = [
		{"seat": millionaire, "to": beggar, "n": 2},
		{"seat": rich, "to": commoner, "n": 1},
	]
	st["revolution"] = false
	st["quads"] = 0
	st["finish_order"] = []
	st["field"] = []
	st["lead"] = {}
	st["passes"] = 0
	st["last_player"] = -1
	st["must_include"] = -1
	st["phase"] = "exchange"
	st["turn"] = millionaire
	return _ok(st)


## 接收者选定返还牌: 数量校验 + 归属校验, 全部返还完进入 play(乞丐先出)。
static func _do_exchange_return(st: Dictionary, action: Dictionary) -> Dictionary:
	if st["phase"] != "exchange":
		return _fail(st, "not_exchange")
	var pending: Array = st.get("exchange_returns", [])
	if pending.is_empty():
		return _fail(st, "not_exchange")
	var cur: Dictionary = pending[0]
	var seat := int(action.get("seat", -1))
	if seat != int(cur["seat"]):
		return _fail(st, "not_your_turn")
	var cards: Array = action.get("cards", [])
	if cards.size() != int(cur["n"]):
		return _fail(st, "wrong_card_count")
	var hand: Array = st["hands"][seat]
	for c in cards:
		if not hand.has(c):
			return _fail(st, "card_not_in_hand")
	for c in cards:
		hand.erase(c)
	for c in cards:
		st["hands"][int(cur["to"])].append(c)
	CardsGd.sort_cards(st["hands"][int(cur["to"])])
	st["exchange"].append({"from": seat, "to": int(cur["to"]),
			"cards": cards.duplicate(), "count": cards.size()})
	pending.pop_front()
	if pending.is_empty():
		st["phase"] = "play"
		st["turn"] = _seat_with_identity(st["identities"], 3)  # 乞丐先出
	else:
		st["turn"] = int(pending[0]["seat"])
	return _ok(st)


## 一名玩家出完：记录名次；第 3 名出完即局终，剩余者为乞丐。
static func _finish_player(st: Dictionary, seat: int) -> Dictionary:
	st["finish_order"].append(seat)
	if int(st["finish_order"].size()) >= SEATS - 1:
		for s in SEATS:
			if not st["finish_order"].has(s):
				st["finish_order"].append(s)
				break
		var order: Array = st["finish_order"]
		var ids := ScoringGd.identities(order.slice(0, 3), int(order[3]))
		# 一落千丈: 上局大富豪未保住第一 → 直接垫底为大贫民;
		# 其余三人按本局出完顺序获得 大富豪/富豪/贫民(含未出完者排最后)
		var prev: Array = st["identities"]
		if prev.size() == 4:
			var rich := prev.find(0)
			if rich >= 0 and int(ids[rich]) != 0:
				var others: Array = []
				for s in st["finish_order"]:
					if int(s) != rich:
						others.append(int(s))
				for s in SEATS:
					if s != rich and not others.has(s):
						others.append(int(s))
				var ranks := [0, 1, 2]
				for i in ranks.size():
					ids[int(others[i])] = ranks[i]
				ids[rich] = 3
		var deltas := [0, 0, 0, 0]
		for s in SEATS:
			deltas[s] = ScoringGd.round_delta(int(ids[s]))
			st["scores"][s] = int(st["scores"][s]) + deltas[s]
		st["identities"] = ids
		st["last_points"] = deltas
		st["phase"] = "round_end"
		st["turn"] = -1
		return _ok(st)
	st["turn"] = _next_active(st, seat)
	return _ok(st)


# ---------------------------------------------------------------- 内部工具

static func _empty_state(cfg: Dictionary, seed_v: int) -> Dictionary:
	return {
		"cfg": cfg,
		"seed": seed_v,
		"phase": "wait",
		"round": 0,
		"hands": [[], [], [], []],
		"dead": [],
		"scores": [0, 0, 0, 0],
		"turn": -1,
		"lead": {},
		"passes": 0,
		"last_player": -1,
		"field": [],
		"revolution": false,
		"quads": 0,
		"finish_order": [],
		"identities": [],
		"last_points": [],
		"must_include": -1,
		"exchange": [],
		"exchange_returns": [],
		"error": "",
	}


## 每局发牌独立定随机（seed+局号），可重放。
static func _deal_round(st: Dictionary, round_idx: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(st["seed"], ":", round_idx))
	var deck := CardsGd.full_deck(bool(st["cfg"]["with_joker"]))
	CardsGd.shuffle(deck, rng)
	var hands := [[], [], [], []]
	for seat in SEATS:
		var hand: Array = hands[seat]
		for i in HAND_SIZE:
			hand.append(deck[seat * HAND_SIZE + i])
		CardsGd.sort_cards(hand)
	st["hands"] = hands
	st["dead"] = deck.slice(SEATS * HAND_SIZE)


static func _seat_with_identity(ids: Array, identity: int) -> int:
	for s in ids.size():
		if int(ids[s]) == identity:
			return s
	return 0


static func _active_count(st: Dictionary) -> int:
	return SEATS - int(st["finish_order"].size())


static func _next_active(st: Dictionary, from_seat: int) -> int:
	for step in range(1, SEATS + 1):
		var s := (from_seat + step) % SEATS
		if not st["finish_order"].has(s):
			return s
	return -1


static func _give(st: Dictionary, from_seat: int, to_seat: int, count: int) -> Dictionary:
	var hand: Array = st["hands"][from_seat]
	CardsGd.sort_cards(hand)
	var cards: Array = hand.slice(hand.size() - count)
	for c in cards:
		hand.erase(c)
	for c in cards:
		st["hands"][to_seat].append(c)
	CardsGd.sort_cards(st["hands"][to_seat])
	return {"from": from_seat, "to": to_seat, "cards": cards, "count": count}


static func _ok(st: Dictionary) -> Dictionary:
	return {"ok": true, "error": "", "state": st}


static func _fail(st: Dictionary, code: String) -> Dictionary:
	st["error"] = code
	return {"ok": false, "error": code, "state": st}
