## 规则式 AI（托管 / 本地模式 / fuzz 测试共用）。
## 策略 v2: 一手清盘立即出; 领出按出牌价值(牌数−2×王数)保王;
## 跟牌出"最小能压的", 同距省王再省牌数。
class_name BotPlayer
extends RefCounted

const CardsGd = preload("res://src/rules/cards.gd")
const ComboGd = preload("res://src/rules/combo.gd")
const GameStateGd = preload("res://src/rules/game_state.gd")


## 为座位 seat 决定下一步动作（返回可传入 GameState.apply 的 action）。
static func decide(st: Dictionary, seat: int) -> Dictionary:
	match str(st["phase"]):
		"exchange":
			return _decide_exchange_return(st, seat)
		"play":
			return _decide_play(st, seat)
	return {"t": "pass", "seat": seat}


## 换牌返还: 返还最弱 n 张(强者留强, 策略最优)。
static func _decide_exchange_return(st: Dictionary, seat: int) -> Dictionary:
	for e in st.get("exchange_returns", []):
		if int(e["seat"]) == seat:
			var hand: Array = st["hands"][seat].duplicate()
			CardsGd.sort_cards(hand)
			return {"t": "exchange_return", "seat": seat,
					"cards": hand.slice(0, int(e["n"]))}
	return {"t": "pass", "seat": seat}


static func _decide_play(st: Dictionary, seat: int) -> Dictionary:
	var hand: Array = st["hands"][seat]
	var lead: Dictionary = st["lead"]
	var combos := all_combos(hand, st["cfg"],
			hand.size() == 1 and CardsGd.is_joker(hand[0]) and not lead.is_empty())
	var must_include := int(st["must_include"])
	# 一手清盘 = 直接获胜, 立即打出(受 must_include 约束; 跟牌时还须压过场牌)
	for combo in combos:
		if must_include >= 0 and not combo["cards"].has(must_include):
			continue
		if int(combo["len"]) != hand.size():
			continue
		if lead.is_empty() or ComboGd.beats(combo, lead, st["revolution"]):
			return {"t": "play", "seat": seat, "cards": combo["cards"]}
	if lead.is_empty():
		var best := {}
		for combo in combos:
			if must_include >= 0 and not combo["cards"].has(must_include):
				continue
			if best.is_empty() or _prefer_lead(combo, best, bool(st["revolution"])):
				best = combo
		if best.is_empty():
			return {"t": "pass", "seat": seat}
		return {"t": "play", "seat": seat, "cards": best["cards"]}
	var beat := {}
	var lead_eff := ComboGd.eff_key(float(lead["key"]), st["revolution"])
	var beat_d := INF
	var beat_jokers := 99
	var beat_len := 99
	for combo in combos:
		if not ComboGd.beats(combo, lead, st["revolution"]):
			continue
		var d: float = absf(ComboGd.eff_key(float(combo["key"]), st["revolution"]) - lead_eff)
		var jc := _joker_count(combo)
		if beat.is_empty() or d < beat_d or (d == beat_d and (jc < beat_jokers
				or (jc == beat_jokers and int(combo["len"]) < beat_len))):
			beat = combo
			beat_d = d
			beat_jokers = jc
			beat_len = int(combo["len"])
	if beat.is_empty():
		return {"t": "pass", "seat": seat}
	return {"t": "play", "seat": seat, "cards": beat["cards"]}


static func _prefer_lead(a: Dictionary, b: Dictionary, revolution: bool) -> bool:
	# 出牌价值 = 牌数 - 2×王数(王是跟牌压制的战略资源, 领出尽量不舍王);
	# 同分取当前点序下更弱者(反转时 key 大者更弱)
	var sa := int(a["len"]) - 2 * _joker_count(a)
	var sb := int(b["len"]) - 2 * _joker_count(b)
	if sa != sb:
		return sa > sb
	return ComboGd.eff_key(float(a["key"]), revolution) \
			< ComboGd.eff_key(float(b["key"]), revolution)


static func _joker_count(combo: Dictionary) -> int:
	var n := 0
	for c in combo["cards"]:
		if CardsGd.is_joker(c):
			n += 1
	return n


## 从"可见视图"决策（客户端提示 / E2E 自动打牌用）：只需本人手牌。
static func decide_from_view(view: Dictionary) -> Dictionary:
	var seat := int(view["my_seat"])
	var st := {
		"phase": view["phase"],
		"cfg": view["rules"],
		"lead": view["lead"],
		"revolution": view["revolution"],
		"must_include": view["must_include"],
		"hands": [[], [], [], []],
	}
	st["hands"][seat] = view["hand"]
	return decide(st, seat)


## 枚举手牌全部合法组合（v2: 单张/对子/三条/四条, 含王补位）。
## ban_last_joker: 仅剩一张王且跟牌时禁止单出(领出放行, 见 game_state 规则)。
static func all_combos(hand: Array, cfg: Dictionary, ban_last_joker := true) -> Array:
	var out := []
	var by_val := {}
	var jokers := []
	for c in hand:
		if CardsGd.is_joker(c):
			jokers.append(c)
		else:
			var v := CardsGd.value(c)
			if not by_val.has(v):
				by_val[v] = []
			by_val[v].append(c)
	for c in hand:
		if ban_last_joker:
			continue
		var combo := ComboGd.identify([c], cfg)
		if not combo.is_empty():
			out.append(combo)
	# 同点组合（纯自然 + 王补位）
	for v in by_val:
		var group: Array = by_val[v]
		for k in range(2, mini(4, group.size()) + 1):
			var combo := ComboGd.identify(group.slice(0, k), cfg)
			if not combo.is_empty():
				out.append(combo)
		for n in range(group.size() + 1, mini(4, group.size() + jokers.size()) + 1):
			var cards := group.duplicate()
			for j in n - group.size():
				cards.append(jokers[j])
			var combo2 := ComboGd.identify(cards, cfg)
			if not combo2.is_empty():
				out.append(combo2)
	return out
