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

## 肉鸽模式『命运卡』目录: 每局开始随机抽一张生效(单局有效)。
## 引擎读取 st["cfg"]["rogue_mod"]; 目录同时供牌桌揭示 UI 与帮助图鉴使用。
const ROGUE_MODS := [
	{"id": "joker_x2", "name": "王者归来", "glyph": "王", "cat": "发牌",
		"desc": "本局牌堆多 2 张王(共 4 张), 压制与反转更疯狂"},
	{"id": "revolution_start", "name": "天生革命", "glyph": "革", "cat": "规则",
		"desc": "本局从开局起就处于革命状态, 大小颠倒"},
	{"id": "short_hands", "name": "缩地成寸", "glyph": "缩", "cat": "发牌",
		"desc": "本局每人只发 10 张牌, 节奏更快"},
	{"id": "chaos_exchange", "name": "混沌换牌", "glyph": "混", "cat": "规则",
		"desc": "本局换牌张数随机(1~3 张), 强弱易位更难预料"},
	{"id": "joker_rage", "name": "龙王之怒", "glyph": "怒", "cat": "触发",
		"desc": "本局任何人打出王, 革命状态立即翻转"},
	{"id": "double_stakes", "name": "双倍赌局", "glyph": "×2", "cat": "结算",
		"desc": "本局身份积分变动 ×2, 大起大落"},
	{"id": "joker_ban", "name": "无王之地", "glyph": "禁", "cat": "发牌",
		"desc": "本局牌堆不含王, 全凭真本事"},
	{"id": "no_exchange", "name": "免战之约", "glyph": "免", "cat": "规则",
		"desc": "本局跳过换牌阶段, 开局直接亮牌开打"},
	{"id": "score_negate", "name": "福祸反转", "glyph": "反", "cat": "结算",
		"desc": "本局身份积分正负反转, 垫底反而得分"},
	{"id": "eight_gift", "name": "八喜临门", "glyph": "喜", "cat": "触发",
		"desc": "本局打出 8 切时, 立即从死牌堆摸 1 张"},
]


## 按局号定随机抽一张命运卡(可重放: seed+局号), 写入 cfg 与状态快照
static func _roll_rogue(st: Dictionary, round_idx: int) -> String:
	if not bool(st["cfg"].get("rogue", false)):
		return ""
	# 固定剧本锁(首局预置 rogue_mod 时上锁): 每局都生效同一张
	var lock := str(st["cfg"].get("rogue_mod_lock", ""))
	if lock != "":
		st["cfg"]["rogue_mod"] = lock
		return lock
	# 首局允许调用方指定命运卡(cfg 预置 rogue_mod): 固定剧本/测试用
	if round_idx == 0 and str(st["cfg"].get("rogue_mod", "")) != "":
		return _rogue_mod_id(st)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(st["seed"], ":rogue:", round_idx))
	var mod: Dictionary = ROGUE_MODS[rng.randi() % ROGUE_MODS.size()]
	st["cfg"]["rogue_mod"] = str(mod["id"])
	return str(mod["id"])


static func _rogue_mod_id(st: Dictionary) -> String:
	return str(st["cfg"].get("rogue_mod", ""))

## 错误码 → 玩家可读的中文提示
const ERROR_MSG := {
	"not_playing": "当前不在出牌阶段",
	"not_your_turn": "还没轮到你出牌",
	"card_not_in_hand": "手牌中不存在所选的牌",
	"invalid_combo": "不是有效的牌型组合",
	"joker_last_ban": "最后一张是王，不能单出获胜",
	"must_include_diamond3": "首手必须包含 ♦3",
	"cannot_beat": "压不过上家的牌",
	"cannot_pass_on_lead": "你是领出者，必须出牌",
	"not_round_end": "当前不在回合结束阶段",
	"not_exchange": "当前不在换牌阶段",
	"wrong_card_count": "返还牌数不正确",
	"unknown_action": "未知操作",
}


## 开新一场对局。seed_v<0 时随机。第 1 局直接进入 play：
## 持 ♦3 者先出且首手必含 ♦3；♦3 为死牌时随机首出、无限制。
static func new_match(cfg: Dictionary, seed_v: int = -1) -> Dictionary:
	cfg = RulesConfigGd.normalize(cfg)
	if seed_v < 0:
		seed_v = int(Time.get_unix_time_from_system() * 1000.0) % 1000000007
	var st := _empty_state(cfg, seed_v)
	if _rogue_mod_id(st) != "":
		st["cfg"]["rogue_mod_lock"] = _rogue_mod_id(st)  # 固定剧本: 每局同卡
	_deal_round(st, 0)
	if _rogue_mod_id(st) == "revolution_start":
		st["revolution"] = true
		st["quads"] = 1
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
	# 禁止最后单张出王(跟牌时): 手中仅剩一张王不能作为最后一张跟出获胜。
	# 领出时放行 — 否则"只剩单王+轮到领出"无任何合法动作, 对局死锁。
	if hand.size() == 1 and cards.size() == 1 and CardsGd.is_joker(cards[0]) 			and not st["lead"].is_empty():
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
	# 出完者的最后一手同样立 lead: 其余玩家须先压过/Pass, 全部 Pass
	# 才清桌并由出完者下一位领出(不得直接"接风"跳过对手)
	st["lead"] = combo
	# 革命：四条触发（含王辅助），奇数次反转
	if bool(st["cfg"]["revolution"]) and int(combo["type"]) == ComboGd.Type.QUAD:
		st["quads"] = int(st["quads"]) + 1
		st["revolution"] = int(st["quads"]) % 2 == 1
	# 命运卡『龙王之怒』: 出王即翻转革命
	if _rogue_mod_id(st) == "joker_rage":
		for c in cards:
			if CardsGd.is_joker(c):
				st["revolution"] = not st["revolution"]
				break
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
		# 命运卡『八喜临门』: 8 切时从死牌堆摸 1 张(手牌+1, 可见可打)
		if _rogue_mod_id(st) == "eight_gift" and not (st["dead"] as Array).is_empty():
			var gr := RandomNumberGenerator.new()
			gr.seed = hash(str(st["seed"], ":8gift:", int(st["round"]),
					st["field"].size()))
			var pick: int = (st["dead"] as Array)[gr.randi() % (st["dead"] as Array).size()]
			(st["dead"] as Array).erase(pick)
			hand.append(pick)
			CardsGd.sort_cards(hand)
			st["gift_drawn"] = gr.randi()  # 状态戳: 客户端可感知手牌变化
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
	var mod := _roll_rogue(st, next_round)
	_deal_round(st, next_round)
	# 强制交换（上一局身份）：大贫民→大富豪 2 张，贫民→富豪 1 张
	# 『混沌换牌』: 张数随机 1~3(按局定随机, 可重放)
	var n_rich := 2
	var n_common := 1
	if mod == "chaos_exchange":
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(st["seed"], ":ce:", next_round))
		n_rich = rng.randi_range(1, 3)
		n_common = rng.randi_range(1, 3)
	var ids: Array = st["identities"]
	var beggar := _seat_with_identity(ids, 3)
	var millionaire := _seat_with_identity(ids, 0)
	var commoner := _seat_with_identity(ids, 2)
	var rich := _seat_with_identity(ids, 1)
	if mod == "no_exchange":
		# 『免战之约』: 跳过换牌阶段, 直接开打(乞丐先出), 各自手牌不变
		st["exchange"] = []
		st["exchange_returns"] = []
		st["phase"] = "play"
		st["turn"] = beggar
		st["revolution"] = mod == "revolution_start"
		st["quads"] = 1 if mod == "revolution_start" else 0
		st["finish_order"] = []
		st["field"] = []
		st["lead"] = {}
		st["passes"] = 0
		st["last_player"] = -1
		st["must_include"] = -1
		return _ok(st)
	st["exchange"] = [
		_give(st, beggar, millionaire, n_rich),
		_give(st, commoner, rich, n_common),
	]
	# 强者返还等量"任意牌"——由接收者自选(M3 换牌流程), 依次结算
	st["exchange_returns"] = [
		{"seat": millionaire, "to": beggar, "n": n_rich},
		{"seat": rich, "to": commoner, "n": n_common},
	]
	st["revolution"] = mod == "revolution_start"
	st["quads"] = 1 if mod == "revolution_start" else 0
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
		var mult := 1
		match _rogue_mod_id(st):
			"double_stakes":
				mult = 2
			"score_negate":
				mult = -1
		for s in SEATS:
			deltas[s] = ScoringGd.round_delta(int(ids[s])) * mult
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
	# 命运卡在本局发牌前抽取(影响牌堆/手牌数)
	var mod := _roll_rogue(st, round_idx)
	# 『无王之地』: 牌堆不含王(优先于房间带王配置)
	var deck := CardsGd.full_deck(
			bool(st["cfg"]["with_joker"]) and mod != "joker_ban")
	if mod == "joker_x2":
		deck.append(54)  # 扩展王: is_joker 以 id>=52 判定, 无需特判
		deck.append(55)
	CardsGd.shuffle(deck, rng)
	var hand_n := HAND_SIZE - (3 if mod == "short_hands" else 0)
	var hands := [[], [], [], []]
	for seat in SEATS:
		var hand: Array = hands[seat]
		for i in hand_n:
			hand.append(deck[seat * hand_n + i])
		CardsGd.sort_cards(hand)
	st["hands"] = hands
	st["dead"] = deck.slice(SEATS * hand_n)


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


## 错误码 → 玩家可读中文
static func error_msg(code: String) -> String:
	return ERROR_MSG.get(code, code)
