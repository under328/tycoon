## 牌型识别与比较测试（v2: 仅 单张/对子/三条/四条, ♠3 单出最强, 无顺子/階段）。
## 牌 id 备查: 0..3=3(♠♥♦♣) 4..7=4 … 32..35=J 36..39=Q 40..43=K 44..47=A 48..51=2 52/53=王
extends RefCounted

const ComboGd = preload("res://src/rules/combo.gd")

var cfg: Dictionary = {}


func run(t) -> void:
	# --- 单张 ---
	t.expect_eq(ComboGd.identify([0], cfg)["key"], 16.5, "♠3 key=16.5")
	t.expect_eq(ComboGd.identify([1], cfg)["key"], 3, "单3♥ key=3")
	t.expect_eq(ComboGd.identify([52], cfg)["key"], 16, "JOKER 单张 key=16")
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

	# --- 顺子/階段: v2 已废除, 一律非法 ---
	t.expect(ComboGd.identify([0, 5, 10], cfg).is_empty(), "345 顺子非法")
	t.expect(ComboGd.identify([0, 4, 8, 12], cfg).is_empty(), "3456 连顺非法")
	t.expect(ComboGd.identify([32, 37, 42], cfg).is_empty(), "J Q K 顺子非法")
	t.expect(ComboGd.identify([0, 4, 52], cfg).is_empty(), "3 4 +王 不能补成顺子")
	t.expect(ComboGd.identify([0, 9, 52], cfg).is_empty(), "3 6 +王 不能补成顺子")
	# 王补位优先解释为同点数组合（规格 §4）
	var jj := ComboGd.identify([0, 52, 53], cfg)
	t.expect_eq(jj["type"], ComboGd.Type.TRIPLE, "3♠+两王 优先成三条3")
	t.expect_eq(jj["key"], 3, "三条3 key=3")
	t.expect(ComboGd.identify([44, 48, 52], cfg).is_empty(), "A2+王 端点越界(超过2)非法")

	# --- ♠3 特判 ---
	t.expect(ComboGd.identify([0], cfg)["key"] > ComboGd.identify([52], cfg)["key"], "♠3 单张压王")
	t.expect(ComboGd.identify([0, 1], cfg)["key"] == 3, "♠3 成对后按 3 计")

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
	t.expect(not ComboGd.beats({"type": 1, "key": 15, "len": 2}, {"type": 1, "key": 3, "len": 3}, false),
			"长度不同 互不压")
	t.expect(ComboGd.beats({"type": 3, "key": 8, "len": 4}, {"type": 3, "key": 3, "len": 4}, false),
			"四条8 压 四条3")
	t.expect(ComboGd.beats({"type": 3, "key": 3, "len": 4}, {"type": 0, "key": 15, "len": 1}, false),
			"四条3 炸弹压 单张2")
	t.expect(ComboGd.beats({"type": 3, "key": 3, "len": 4}, {"type": 2, "key": 13, "len": 3}, true),
			"四条3 炸弹压 三条K(革命)")
	t.expect(not ComboGd.beats({"type": 0, "key": 15, "len": 1}, {"type": 3, "key": 3, "len": 4}, false),
			"单张2 不压 四条3")
	t.expect(ComboGd.beats({"type": 0, "key": 16, "len": 1}, {"type": 0, "key": 3, "len": 1}, true),
			"革命: 王 仍压 3(王不参与反转)")
	t.expect(ComboGd.beats({"type": 0, "key": 3, "len": 1}, {"type": 0, "key": 15, "len": 1}, true),
			"革命: 单3 压 单2(2最小)")
	t.expect(ComboGd.beats({"type": 0, "key": 16.5, "len": 1}, {"type": 0, "key": 16, "len": 1}, true),
			"革命: ♠3 仍压 王(例外)")
	t.expect(ComboGd.beats({"type": 0, "key": 16.5, "len": 1}, {"type": 0, "key": 3, "len": 1}, true),
			"革命: ♠3 仍压 3")
	t.expect(not ComboGd.beats({"type": 0, "key": 3, "len": 1}, {"type": 0, "key": 16.5, "len": 1}, true),
			"革命: 3 不压 ♠3")
	t.expect(ComboGd.beats({"type": 3, "key": 3, "len": 4}, {"type": 3, "key": 8, "len": 4}, true),
			"革命: 四条3 压 四条8")
