## 牌型识别与比较。契约见 docs/规则规格.md §4。
## v2: 仅 单张/对子/三条/四条（革命）；♠3 单出时为最强单张；无顺子/階段。
class_name Combo
extends RefCounted

const CardsGd = preload("res://src/rules/cards.gd")

enum Type { SINGLE, PAIR, TRIPLE, QUAD }

const TYPE_NAMES := ["单张", "对子", "三条", "四条"]

## ♠3 单出时的 key: 比 JOKER(16) 大但比 4(4) 小
const SPADE3_KEY := 16.5


## 识别一组牌；非法返回 {}。
## 仅四种牌型: 单张 / 对子 / 三条 / 四条（含王补位）。
static func identify(cards: Array, cfg: Dictionary) -> Dictionary:
	var n := cards.size()
	if n == 0 or n > 4:
		return {}
	if n == 1:
		var card: int = cards[0]
		if CardsGd.is_joker(card):
			return _mk(Type.SINGLE, CardsGd.JOKER_VALUE, 1, cards)
		if card == 0:
			return _mk(Type.SINGLE, SPADE3_KEY, 1, cards)
		return _mk(Type.SINGLE, CardsGd.value(card), 1, cards)
	var naturals := []
	var joker_count := 0
	for c in cards:
		if CardsGd.is_joker(c):
			joker_count += 1
		else:
			naturals.append(c)
	if naturals.is_empty():
		return {}  # 王+王不可组对
	# 同点数（对/三/四条），王补位优先
	var val_count := {}
	for c in naturals:
		var v := CardsGd.value(c)
		val_count[v] = int(val_count.get(v, 0)) + 1
	if val_count.size() == 1 and n <= 4:
		var v: int = val_count.keys()[0]
		var t := Type.PAIR
		if n == 3:
			t = Type.TRIPLE
		elif n == 4:
			t = Type.QUAD
		return _mk(t, v, n, cards)
	# 混合不同点数 → 非法（v2 无顺子/階段）
	return {}


## next 能否压制 prev。
## - 四条(炸弹)可压制任何非四条组合; 四条之间按点序比较(革命时同样反转)。
## - 其他情况必须同牌型、同长度。
## - 革命仅反转 3..2 的自然牌点序(3 最强, 2 最弱); 王(16)与 ♠3(16.5) 保持最大。
static func beats(next: Dictionary, prev: Dictionary, revolution: bool) -> bool:
	if next.is_empty() or prev.is_empty():
		return false
	var nt := int(next["type"])
	var pt := int(prev["type"])
	if nt == Type.QUAD:
		return pt != Type.QUAD 				or eff_key(float(next["key"]), revolution) > eff_key(float(prev["key"]), revolution)
	if pt == Type.QUAD:
		return false
	if nt != pt or int(next["len"]) != int(prev["len"]):
		return false
	return eff_key(float(next["key"]), revolution) > eff_key(float(prev["key"]), revolution)


## 革命时的有效点数: 仅反转 3..2 的自然牌(3→15 … 2→3); 王(16)/♠3(16.5) 不变。
static func eff_key(key: float, revolution: bool) -> float:
	if revolution and key < 16.0:
		return 18.0 - key
	return key


static func _mk(t: int, key: float, len: int, cards: Array) -> Dictionary:
	return {"type": t, "key": key, "len": len, "cards": cards.duplicate()}
