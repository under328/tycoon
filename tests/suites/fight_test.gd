## 格斗试炼测试: 牌型判定全层级 / 属性推导与花色语义 / 战斗解析 / 奖励记录。
extends RefCounted

const FightGd = preload("res://src/rules/fight/fight_mode.gd")
const WalletGd = preload("res://src/autoload/wallet.gd")

## 构造卡: id = (value-3)*4 + suit, suit 0♠ 1♥ 2♦ 3♣ (value 3..15)
static func card(value: int, suit: int) -> int:
	return (value - 3) * 4 + suit


func run(t) -> void:
	_combo_tiers(t)
	_stats_by_suit(t)
	_battle_flow(t)
	_reward_record(t)


## 牌型: 9 层级逐级验证(♠♥♦♣)
func _combo_tiers(t) -> void:
	var sf := [0, 4, 8, 12, 16]          # ♠ 3-4-5-6-7 同花顺
	t.expect_eq(str(FightGd.evaluate_combo(sf)["tier"]), "straight_flush", "同花顺")
	var quad := [card(5, 0), card(5, 1), card(5, 2), card(5, 3), card(9, 0)]
	t.expect_eq(str(FightGd.evaluate_combo(quad)["tier"]), "quad", "四条")
	var flush := [card(4, 0), card(7, 0), card(10, 0), card(13, 0), card(9, 0)]
	t.expect_eq(str(FightGd.evaluate_combo(flush)["tier"]), "flush", "同花(4♠)")
	var fh := [card(6, 0), card(6, 1), card(6, 2), card(10, 0), card(10, 1)]
	t.expect_eq(str(FightGd.evaluate_combo(fh)["tier"]), "full_house", "葫芦")
	var straight := [card(4, 0), card(5, 1), card(6, 2), card(7, 3), card(8, 0)]
	t.expect_eq(str(FightGd.evaluate_combo(straight)["tier"]), "straight", "顺子")
	var trips := [card(9, 0), card(9, 1), card(9, 2), card(4, 0), card(13, 1)]
	t.expect_eq(str(FightGd.evaluate_combo(trips)["tier"]), "trips", "三条")
	var two := [card(9, 0), card(9, 1), card(4, 2), card(4, 3), card(13, 0)]
	t.expect_eq(str(FightGd.evaluate_combo(two)["tier"]), "two_pair", "两对")
	var pair := [card(9, 0), card(9, 2), card(4, 1), card(6, 3), card(13, 0)]
	t.expect_eq(str(FightGd.evaluate_combo(pair)["tier"]), "pair", "一对")
	var high := [card(9, 0), card(4, 1), card(6, 2), card(8, 3), card(13, 0)]
	t.expect_eq(str(FightGd.evaluate_combo(high)["tier"]), "high", "高牌")
	# 层级排序完整且互斥
	var ranks: Array = FightGd.TIER_RANK
	t.expect_eq(ranks.size(), 9, "9 个牌型层级")
	t.expect_eq(ranks[0], "straight_flush", "同花顺最大")


## 花色语义: ♠→物攻 ♦→护甲魔抗 ♥→生命 ♣→技能; 两对→防 1.5×
func _stats_by_suit(t) -> void:
	var spades := [card(10, 0), card(11, 0), card(12, 0), card(8, 1), card(8, 2)]
	# ♠10+11+12=33 → atk 33*6=198; 一对(8) → 全属性 ×1.15
	var c := FightGd.evaluate_combo(spades)
	var st: Dictionary = FightGd.derive_stats(spades, c, 1)
	t.expect_eq(int(st["atk"]), int(198 * 1.15), "♠合计 → 物攻×一对加成")
	t.expect(float(st["crit_rate"]) > 0.10, "♠ 张数提升暴击率")
	var diamonds := [card(10, 2), card(11, 2), card(12, 2), card(8, 0), card(8, 1)]
	var c2 := FightGd.evaluate_combo(diamonds)
	var st2: Dictionary = FightGd.derive_stats(diamonds, c2, 1)
	t.expect(int(st2["def"]) > int(st["def"]), "♦合计 → 护甲")
	var hearts := [card(10, 1), card(11, 1), card(12, 1), card(8, 0), card(8, 2)]
	var c3 := FightGd.evaluate_combo(hearts)
	var st3: Dictionary = FightGd.derive_stats(hearts, c3, 1)
	t.expect(int(st3["max_hp"]) > int(st["max_hp"]), "♥合计 → 生命上限")
	var clubs := [card(10, 3), card(11, 3), card(12, 3), card(8, 0), card(8, 1)]
	var c4 := FightGd.evaluate_combo(clubs)
	var st4: Dictionary = FightGd.derive_stats(clubs, c4, 1)
	t.expect(int(st4["skill"]) > int(st["skill"]), "♣合计 → 技能强度")


## 战斗: 攻击掉血 / 击杀小怪 → Boss / 玩家死亡 / 层推进
func _battle_flow(t) -> void:
	var f = FightGd.new(42)
	var cands: Array = f.draw_candidates(8)
	t.expect_eq(cands.size(), 8, "候选 8 张")
	f.equip(cands.slice(0, 5))
	t.expect((f.hand as Array).size() == 5, "装备 5 张")
	var hp0: int = f.hp
	f.spawn_enemy(false)
	var ehp0: int = int(f.enemy["hp"])
	var evs: Array = f.step("attack")
	t.expect(evs.size() >= 1, "攻击产生事件")
	t.expect(int(f.enemy["hp"]) < ehp0, "攻击造成伤害")
	# 打死小怪 → 推进到 Boss
	f.enemy["hp"] = 1
	var evs2: Array = f.step("attack")
	t.expect(int(f.enemy["hp"]) == 0, "小怪被击破")
	var die_seen := false
	for e in evs2:
		if str(e["kind"]) == "die":
			die_seen = true
	t.expect(die_seen, "击破事件")
	t.expect(f.encounter_cleared(), "本场清理完成")
	f.advance_stage()
	f.spawn_enemy(true)
	t.expect(bool(f.enemy["is_boss"]), "Boss 登场")
	t.expect(int(f.enemy["max_hp"]) > ehp0, "Boss 比小怪硬")
	# 玩家死亡: 怪物一击必杀(先保证Boss不会被顺手打死)
	f.enemy["hp"] = 99999
	f.enemy["max_hp"] = 99999
	f.hp = 1
	f.enemy["atk"] = 9999
	f.step("attack")
	t.expect(f.player_dead(), "玩家死亡判定")
	# 层推进: 下一层候选重抽, 层数+1
	var nf: Array = f.next_floor()
	t.expect_eq(int(f.floor_num), 2, "层推进 +1")
	t.expect_eq(nf.size(), 8, "新层候选 8 张")


## 奖励: 层数越高钻石越多 + 最高纪录持久语义
func _reward_record(t) -> void:
	var w = WalletGd.new()
	w.save_path = "user://test_fight_wallet.cfg"
	var r1: Dictionary = w.grant_fight_reward(1)
	var r3: Dictionary = w.grant_fight_reward(3)
	t.expect(int(r3["diamonds"]) > int(r1["diamonds"]), "层数越高钻石越多")
	t.expect_eq(int(r3["best"]), 3, "最高纪录=3")
	t.expect_eq(int(w.fight_best), 3, "钱包记录最高层")
	var r5: Dictionary = w.grant_fight_reward(5)
	t.expect(bool(r5["new_record"]), "破纪录标记")
	t.expect_eq(int(w.fight_best), 5, "纪录更新为 5")
	w.queue_free()
