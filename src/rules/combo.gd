## 牌型识别与比较。契约见 docs/规则规格.md §2/§4。
## 组合表示：{ "type": Type, "key": int(压制用端点), "len": int, "cards": Array }
class_name Combo
extends RefCounted

const CardsGd = preload("res://src/rules/cards.gd")

enum Type { SINGLE, PAIR, TRIPLE, QUAD, SEQ, STAIRS }

const TYPE_NAMES := ["单张", "对子", "三条", "四条", "顺子", "階段"]


## 识别一组牌；非法返回 {}。
static func identify(cards: Array, cfg: Dictionary) -> Dictionary:
	var n := cards.size()
	if n == 0:
		return {}
	if n == 1:
		return _mk(Type.SINGLE, CardsGd.value(cards[0]), 1, cards)
	var naturals := []
	var joker_count := 0
	for c in cards:
		if CardsGd.is_joker(c):
			joker_count += 1
		else:
			naturals.append(c)
	if naturals.is_empty():
		return {}  # 王+王不可组对（规格 §4）
	# 同点数（对/三/四条），王补位
	var val_count := {}
	for c in naturals:
		var v := CardsGd.value(c)
		val_count[v] = int(val_count.get(v, 0)) + 1
	if val_count.size() == 1:
		if n > 4:
			return {}
		var v: int = val_count.keys()[0]
		var t := Type.PAIR
		if n == 3:
			t = Type.TRIPLE
		elif n == 4:
			t = Type.QUAD
		return _mk(t, v, n, cards)
	# 顺序组合：自然牌必须互不相同
	for v in val_count:
		if int(val_count[v]) > 1:
			return {}
	if n < 3:
		return {}
	# 窗口锚定在最小自然牌，王补洞/向上延伸；端点不得超过 2(15)
	var sorted_vals := val_count.keys()
	sorted_vals.sort()
	var top: int = int(sorted_vals[0]) + n - 1
	if top > CardsGd.MAX_VALUE:
		return {}
	if int(sorted_vals[sorted_vals.size() - 1]) > top:
		return {}
	# 階段：自然牌同花色（王视作任意花色）
	var suits := {}
	for c in naturals:
		suits[CardsGd.suit(c)] = true
	if suits.size() == 1 and cfg.get("stairs", true):
		return _mk(Type.STAIRS, top, n, cards)
	return _mk(Type.SEQ, top, n, cards)


## next 能否压制 prev（revolution 时点序反转）。
static func beats(next: Dictionary, prev: Dictionary, revolution: bool) -> bool:
	if next.is_empty() or prev.is_empty():
		return false
	if int(next["type"]) != int(prev["type"]) or int(next["len"]) != int(prev["len"]):
		return false
	if revolution:
		return int(next["key"]) < int(prev["key"])
	return int(next["key"]) > int(prev["key"])


static func type_name(combo: Dictionary) -> String:
	if combo.is_empty():
		return "—"
	return TYPE_NAMES[int(combo["type"])]


static func describe(combo: Dictionary) -> String:
	if combo.is_empty():
		return "自由出牌"
	return "%s %s" % [type_name(combo), CardsGd.labels(_key_cards(combo))]


## 用于展示的组合代表牌：顺子显示端点，其余显示点数代表。
static func _key_cards(combo: Dictionary) -> Array:
	return [int(combo["key"])]


static func _mk(t: int, key: int, len: int, cards: Array) -> Dictionary:
	return {"type": t, "key": key, "len": len, "cards": cards.duplicate()}
