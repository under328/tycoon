## 牌型识别与比较测试（对应 docs/规则规格.md §4）。
## 牌 id 备查: 0..3=3(♠♥♦♣) 4..7=4 … 32..35=J 36..39=Q 40..43=K 44..47=A 48..51=2 52/53=王
extends RefCounted

const ComboGd = preload("res://src/rules/combo.gd")

var cfg: Dictionary = {"stairs": true}


func run(t) -> void:
	# --- 单张 ---
	t.expect_eq(ComboGd.identify([0], cfg)["key"], 3.5, "♠3 key=3.5")
	t.expect_eq(ComboGd.identify([1], cfg)["key"], 3, "单3♥ key=3")
	t.expect_eq(ComboGd.identify([52], cfg)["key"], 3.25, "JOKER 单张")
	t.expect_eq(ComboGd.identify([53], cfg)["type"], ComboGd.Type.SINGLE, "单大王")

	# --- 对子 ---
	t.expect_eq(ComboGd.identify([0, 1], cfg)["type"], ComboGd.Type.PAIR, "3♠3♥ 成对")
	t.expect_eq(ComboGd.identify([0, 1], cfg)["key"], 3, "对3 key=3")
	t.expect_eq(ComboGd.identify([2, 53], cfg)["type"], ComboGd.Type.PAIR, "♦3+王 成对")
	t.expect_eq(ComboGd.identify([2, 53], cfg)["key"], 3, "♦3+王 对 key=3")
	t.expect(ComboGd.identify([0, 4], cfg).is_empty(), "3♠4♠ 不是对")
	t.expect(ComboGd.identify([52, 53], cfg).is_empty(), "王+王 不可成对")

	# --- 三条 / 四条 ---
	t.expect_eq(ComboGd.identify([0, 1, 2], cfg)["type"], ComboGd.Type.TRIPLE, "三条3")
	t.expect_eq(ComboGd.identify([0, 1, 52], cfg)["type"], ComboGd.Type.TRIPLE, "3+3+王 三条")
	t.expect_eq(ComboGd.identify([0, 1, 2, 3], cfg)["type"], ComboGd.Type.QUAD, "四条3")
	t.expect_eq(ComboGd.identify([0, 1, 2, 53], cfg)["type"], ComboGd.Type.QUAD, "3+3+3+王 四条")
	t.expect_eq(ComboGd.identify([48, 49, 50, 51], cfg)["key"], 15, "四条2 key=15")
	t.expect(ComboGd.identify([0, 1, 2, 3, 4], cfg).is_empty(), "五张同点非法")

	# --- 顺子 ---
	var s := ComboGd.identify([0, 5, 10], cfg)  # 3♠ 4♥ 5♠
	t.expect_eq(s["key"], 5, "345 端点 5")
	t.expect_eq(s["len"], 3, "345 长度 3")
	var s4 := ComboGd.identify([0, 4, 8, 12], cfg)  # 3♠4♠5♠6♠
	t.expect_eq(s4["len"], 4, "3456 长度 4")
	t.expect_eq(ComboGd.identify([32, 37, 42], cfg)["key"], 13, "J♠Q♥K♦ → 端点 K")
	t.expect_eq(ComboGd.identify([36, 40, 45], cfg)["key"], 14, "Q♠K♦A♥ → 端点 A")
	t.expect(ComboGd.identify([36, 45, 50], cfg).is_empty(), "Q,A,2 跳过K 非顺子")
	t.expect(ComboGd.identify([0, 8], cfg).is_empty(), "两张不成顺")
	t.expect(ComboGd.identify([0, 8, 12], cfg).is_empty(), "3♠5♠6♠ 缺口无王不可补")
	t.expect_eq(ComboGd.identify([0, 9, 52], cfg)["key"], 5, "3♠5♥+王 → 345 端点5")
	# 王补位优先解释为同点数组合（规格 §4）
	var jj := ComboGd.identify([0, 52, 53], cfg)
	t.expect_eq(jj["type"], ComboGd.Type.TRIPLE, "3♠+两王 优先成三条3")
	t.expect_eq(jj["key"], 3, "三条3 key=3")
	t.expect(ComboGd.identify([44, 48, 52], cfg).is_empty(), "A2+王 端点越界(超过2)非法")

	# --- 階段（同花顺）---
	var stair := ComboGd.identify([0, 4, 8], cfg)  # 3♠4♠5♠
	var off := ComboGd.identify([0, 4, 8], {"stairs": false})
	var with_joker := ComboGd.identify([0, 4, 52], cfg)  # 3♠4♠+王

	# --- 比较与革命 ---
	t.expect(ComboGd.beats({"type": 1, "key": 5, "len": 2}, {"type": 1, "key": 3, "len": 2}, false),
			"对5 压 对3")
	t.expect(not ComboGd.beats({"type": 1, "key": 3, "len": 2}, {"type": 1, "key": 5, "len": 2}, false),
			"对3 不压 对5")
	t.expect(ComboGd.beats({"type": 1, "key": 3, "len": 2}, {"type": 1, "key": 15, "len": 2}, true),
			"革命: 对3 压 对2")
	t.expect(not ComboGd.beats({"type": 1, "key": 15, "len": 2}, {"type": 1, "key": 3, "len": 2}, true),
			"革命: 对2 不压 对3")
	t.expect(not ComboGd.beats({"type": 0, "key": 16, "len": 1}, {"type": 1, "key": 3, "len": 2}, false),
			"牌型不同 互不压")
	t.expect(not ComboGd.beats({"type": 4, "key": 8, "len": 4}, {"type": 4, "key": 6, "len": 3}, false),
			"顺子长度不同 互不压")
	t.expect(not ComboGd.beats({"type": 5, "key": 8, "len": 3}, {"type": 4, "key": 8, "len": 3}, false),
			"階段与顺子 互不压")
