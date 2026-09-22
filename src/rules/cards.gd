## 牌的编码与工具（纯逻辑，无场景依赖）。
## id 0..51 = 标准牌：点数 = 3 + id/4，花色 = id%4（0♠ 1♥ 2♦ 3♣）
## id 52/53 = 小王 / 大王
class_name Cards
extends RefCounted

const JOKER_VALUE := 16
const DIAMOND_3 := 2  # ♦3，首局首出标记牌
const MAX_VALUE := 15

const SUIT_NAMES := ["♠", "♥", "♦", "♣"]


static func value(card: int) -> int:
	if card >= 52:
		return JOKER_VALUE
	return 3 + floori(card / 4.0)


static func suit(card: int) -> int:
	return card % 4


static func is_joker(card: int) -> bool:
	return card >= 52


static func rank_label(card: int) -> String:
	if is_joker(card):
		return "王"
	var v := value(card)
	match v:
		11:
			return "J"
		12:
			return "Q"
		13:
			return "K"
		14:
			return "A"
		15:
			return "2"
		_:
			return str(v)


## 点数值(3..16) → 显示名: 3..10 数字, 11=J, 12=Q, 13=K, 14=A, 15=2, 16=王
## (rank_label 接收的是牌 id; 记牌器等按"点数"统计处须用本函数)
static func rank_value_label(v: int) -> String:
	match v:
		11:
			return "J"
		12:
			return "Q"
		13:
			return "K"
		14:
			return "A"
		15:
			return "2"
		16:
			return "王"
	return str(v)


static func label(card: int) -> String:
	if is_joker(card):
		# 52/53 基础王, 54/55 = 『王者归来』扩展王: 偶数小王 / 奇数大王
		return "小王" if card % 2 == 0 else "大王"
	return "%s%s" % [rank_label(card), SUIT_NAMES[suit(card)]]


static func is_red(card: int) -> bool:
	return not is_joker(card) and (suit(card) == 1 or suit(card) == 2)


static func full_deck(with_joker: bool) -> Array:
	var deck := []
	for i in 52:
		deck.append(i)
	if with_joker:
		deck.append(52)
		deck.append(53)
	return deck


static func shuffle(cards: Array, rng: RandomNumberGenerator) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = cards[i]
		cards[i] = cards[j]
		cards[j] = tmp


static func sort_cards(cards: Array) -> void:
	cards.sort()
