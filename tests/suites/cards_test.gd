## 牌编码测试。
extends RefCounted

const CardsGd = preload("res://src/rules/cards.gd")


func run(t) -> void:
	# 点数: 3 + id/4
	t.expect_eq(CardsGd.value(0), 3, "id0 → 3")
	t.expect_eq(CardsGd.value(3), 3, "id3 → 3")
	t.expect_eq(CardsGd.value(4), 4, "id4 → 4")
	t.expect_eq(CardsGd.value(16), 7, "id16 → 7")
	t.expect_eq(CardsGd.value(44), 14, "id44 → A")
	t.expect_eq(CardsGd.value(48), 15, "id48 → 2")
	t.expect_eq(CardsGd.value(51), 15, "id51 → 2")
	t.expect_eq(CardsGd.value(52), 16, "小王 → 16")
	t.expect_eq(CardsGd.value(53), 16, "大王 → 16")

	# 花色与标签
	t.expect_eq(CardsGd.suit(2), 2, "id2 花色 ♦")
	t.expect_eq(CardsGd.label(2), "3♦", "id2 = 3♦")
	t.expect_eq(CardsGd.label(0), "3♠", "id0 = 3♠")
	t.expect_eq(CardsGd.label(5), "4♥", "id5 = 4♥")
	t.expect_eq(CardsGd.label(48), "2♠", "id48 = 2♠")
	t.expect_eq(CardsGd.label(44), "A♠", "id44 = A♠")
	t.expect_eq(CardsGd.label(52), "小王", "id52")
	t.expect_eq(CardsGd.label(53), "大王", "id53")
	t.expect(CardsGd.is_red(5), "♥ 为红色")
	t.expect(CardsGd.is_red(10), "♦ 为红色")
	t.expect(not CardsGd.is_red(0), "♠ 非红色")
	t.expect(CardsGd.is_joker(52), "52 是王")
	t.expect(not CardsGd.is_joker(51), "51 不是王")

	# 牌堆
	var deck := CardsGd.full_deck(true)
	t.expect_eq(deck.size(), 54, "带王 54 张")
	deck = CardsGd.full_deck(false)
	t.expect_eq(deck.size(), 52, "无王 52 张")
	var seen := {}
	for c in deck:
		t.expect(not seen.has(c), "牌堆无重复 id=%d" % c)
		seen[c] = true

	# 洗牌确定性
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var a := CardsGd.full_deck(true)
	CardsGd.shuffle(a, rng)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	var b := CardsGd.full_deck(true)
	CardsGd.shuffle(b, rng2)
	t.expect_eq(a, b, "同种子洗牌结果一致")
	t.expect_eq(a.size(), 54, "洗牌不丢牌")
