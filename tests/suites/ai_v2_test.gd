## AI 策略 v2 行为测试: 一手清盘即出 / 领出保王(出牌价值) / 跟牌省王再省牌数。
extends RefCounted

const BotPlayerGd = preload("res://src/rules/ai/bot_player.gd")
const CardsGd = preload("res://src/rules/cards.gd")


func run(t) -> void:
	_lead_joker_aversion(t)
	_rush_lead(t)
	_rush_follow_must_beat(t)
	_follow_save_jokers_then_len(t)


## id: value = 3 + id/4 (3=0..3, 5=8..11, 6=12..15, 7=16..19, A14=44..47); 王=52,53
func _st(hand: Array, lead: Dictionary) -> Dictionary:
	return {"phase": "play", "cfg": {}, "lead": lead, "revolution": false,
			"must_include": -1, "hands": [hand, [], [], []]}


func _values(action: Dictionary) -> Array:
	var out := []
	for c in action["cards"]:
		out.append(CardsGd.value(int(c)))
	return out


## 领出: 同为对子时, 天然对(出牌价值2)优先于含王对(价值-2), 同分取更弱者
func _lead_joker_aversion(t) -> void:
	var st := _st([0, 1, 16, 17, 52, 53], {})
	var act := BotPlayerGd.decide(st, 0)
	t.expect_eq(str(act["t"]), "play", "领出: 有牌可出")
	t.expect(_values(act) == [3, 3], "领出选最弱天然对(3), 不舍王 got=%s" % str(_values(act)))


## 领出: 两张手牌成对 → 一手清盘立即出(不再挑挑拣拣)
func _rush_lead(t) -> void:
	var st := _st([8, 9], {})
	var act := BotPlayerGd.decide(st, 0)
	t.expect_eq(int(act["cards"].size()), 2, "清盘: 两张全出")


## 跟牌: 压过场牌且同时清盘 → 立即出
func _rush_follow_must_beat(t) -> void:
	var lead := {"type": 0, "key": 7.0, "len": 1, "cards": [16]}
	var st := _st([44], lead)  # 单A 压单7, 一张清盘
	var act := BotPlayerGd.decide(st, 0)
	t.expect_eq(_values(act), [14], "跟牌清盘: 出A制胜")
	# 反例: 压不过时不得非法清盘(唯一一张是♥3 键3, 压不了 7 → 只能过)
	var st2 := _st([1], lead)
	t.expect_eq(str(BotPlayerGd.decide(st2, 0)["t"]), "pass",
			"跟牌压不过: 不产生非法动作")


## 跟牌: 同键距同王数 → 出小对留四条(多张组合留给领出轮)
func _follow_save_jokers_then_len(t) -> void:
	var lead := {"type": 1, "key": 5.0, "len": 2, "cards": [8, 9]}
	# 6666 + 单张8: 四条与 66 同距同王数, 但四条不能一次清盘(还有单8)
	var st := _st([12, 13, 14, 15, 20], lead)
	var act := BotPlayerGd.decide(st, 0)
	t.expect_eq(str(act["t"]), "play", "跟牌: 有压必压")
	t.expect_eq(int(act["cards"].size()), 2, "同距同王数 → 出对留四条 got=%d"
			% int(act["cards"].size()))
	t.expect(_jokers(act) == 0, "天然对 0 王")
	# 王数优先: 天然对 6 (0王) 优先于 王+6 对(1王)
	var st2 := _st([12, 13, 52], lead)  # 66 + 王
	var act2 := BotPlayerGd.decide(st2, 0)
	t.expect_eq(_jokers(act2), 0, "同距 → 0 王天然对优先")


func _jokers(action: Dictionary) -> int:
	var n := 0
	for c in action["cards"]:
		if CardsGd.is_joker(int(c)):
			n += 1
	return n
