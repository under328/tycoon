## 规则式 AI（托管 / 本地模式 / fuzz 测试共用）。
## 策略 v1：跟牌出"最小能压的"；领出优先出牌数多的组合 shed 牌，同数取最小 key。
class_name BotPlayer
extends RefCounted

const CardsGd = preload("res://src/rules/cards.gd")
const ComboGd = preload("res://src/rules/combo.gd")
const GameStateGd = preload("res://src/rules/game_state.gd")


## 为座位 seat 决定下一步动作（返回可传入 GameState.apply 的 action）。
static func decide(st: Dictionary, seat: int) -> Dictionary:
	match str(st["phase"]):
		"exchange":
			return {"t": "exchange_done", "seat": seat}
		"play":
			return _decide_play(st, seat)
	return {"t": "pass", "seat": seat}


static func _decide_play(st: Dictionary, seat: int) -> Dictionary:
	var hand: Array = st["hands"][seat]
	var lead: Dictionary = st["lead"]
	var combos := all_combos(hand, st["cfg"])
	var must_include := int(st["must_include"])
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
	var lead_key := int(lead["key"])
	for combo in combos:
		if ComboGd.beats(combo, lead, st["revolution"]):
			if beat.is_empty() or _closer(combo, beat, lead_key):
				beat = combo
	if beat.is_empty():
		return {"t": "pass", "seat": seat}
	return {"t": "play", "seat": seat, "cards": beat["cards"]}


static func _prefer_lead(a: Dictionary, b: Dictionary, revolution: bool) -> bool:
	# 牌数多者优先（先跑为敬）；同数取当前点序下更弱者（反转时 key 大者更弱）
	if int(a["len"]) != int(b["len"]):
		return int(a["len"]) > int(b["len"])
	if revolution:
		return int(a["key"]) > int(b["key"])
	return int(a["key"]) < int(b["key"])


## 跟牌选"离 lead 最近的能压牌"（最不容易被压的弱牌）；同距少用王。
static func _closer(a: Dictionary, b: Dictionary, lead_key: int) -> bool:
	var da: int = absi(int(a["key"]) - lead_key)
	var db: int = absi(int(b["key"]) - lead_key)
	if da != db:
		return da < db
	return _joker_count(a) < _joker_count(b)


static func _joker_count(combo: Dictionary) -> int:
	var n := 0
	for c in combo["cards"]:
		if CardsGd.is_joker(c):
			n += 1
	return n


## 枚举手牌全部合法组合（含王补位；顺子窗口锚定最小自然牌向上延伸，与规则一致）。
static func all_combos(hand: Array, cfg: Dictionary) -> Array:
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
	# 单张
	for c in hand:
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
	# 顺子 / 階段：枚举窗口（锚定最小自然牌 → 窗口内自然牌 + 王补齐）
	for length in range(3, 14):
		for start in range(3, CardsGd.MAX_VALUE - length + 2):
			var cards := []
			var natural_count := 0
			for v in range(start, start + length):
				if by_val.has(v):
					cards.append(by_val[v][0])
					natural_count += 1
			var need_jokers := length - natural_count
			if need_jokers == 0 or need_jokers > jokers.size():
				continue
			for j in need_jokers:
				cards.append(jokers[j])
			var combo3 := ComboGd.identify(cards, cfg)
			if not combo3.is_empty():
				out.append(combo3)
	return out
