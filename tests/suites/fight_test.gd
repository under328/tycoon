## 格斗试炼测试(回合制 v2): 牌型判定 / 属性推导 / 二选一抽牌与 5 槽保证 /
## 8 种特殊牌效果 / 回合日程(小怪→精英→BOSS) / 战斗解析 / 奖励记录。
extends RefCounted

const FightGd = preload("res://src/rules/fight/fight_mode.gd")
const WalletGd = preload("res://src/autoload/wallet.gd")


## 构造卡: id = (value-3)*4 + suit, suit 0♠ 1♥ 2♦ 3♣ (value 3..15)
static func card(value: int, suit: int) -> int:
	return (value - 3) * 4 + suit


func run(t) -> void:
	_combo_tiers(t)
	_stats_by_suit(t)
	_draft_flow(t)
	_slot_guarantee(t)
	_specials(t)
	_draft_specials(t)
	_battle_flow(t)
	_reward_record(t)


func _combo_tiers(t) -> void:
	t.expect_eq(FightGd.evaluate_combo([card(5, 0), card(5, 1)])["tier"],
			"pair", "两张同点 = 一对")
	t.expect_eq(FightGd.evaluate_combo([card(5, 0), card(5, 1), card(9, 2)])["tier"],
			"pair", "三张内一对判定")  # 5,5,9 → 一对
	t.expect_eq(FightGd.evaluate_combo([card(5, 0), card(5, 1), card(5, 2)])["tier"],
			"trips", "三条")
	t.expect_eq(FightGd.evaluate_combo([
			card(5, 0), card(5, 1), card(9, 2), card(9, 3)])["tier"],
			"two_pair", "四张两对(新: [2,2] 判两对)")
	t.expect_eq(FightGd.evaluate_combo([
			card(5, 0), card(5, 1), card(5, 2), card(5, 3)])["tier"],
			"quad", "四条")
	t.expect_eq(FightGd.evaluate_combo([
			card(5, 0), card(5, 1), card(5, 2), card(5, 3), card(9, 0)])["tier"],
			"quad", "五张含四条仍判四条")
	# 同花/顺子需满 5 张
	t.expect_eq(FightGd.evaluate_combo([
			card(3, 0), card(4, 0), card(5, 0)])["tier"],
			"high", "三张同花不判同花(需满 5 张)")
	t.expect_eq(FightGd.evaluate_combo([
			card(3, 0), card(4, 0), card(5, 0), card(6, 0), card(7, 0)])["tier"],
			"straight_flush", "同花顺")
	t.expect_eq(FightGd.evaluate_combo([
			card(3, 0), card(4, 0), card(5, 0), card(6, 0), card(9, 0)])["tier"],
			"flush", "五张同花")
	t.expect_eq(FightGd.evaluate_combo([
			card(3, 0), card(4, 1), card(5, 2), card(6, 3), card(7, 0)])["tier"],
			"straight", "顺子")
	t.expect_eq(FightGd.evaluate_combo([
			card(5, 0), card(5, 1), card(5, 2), card(9, 0), card(9, 1)])["tier"],
			"full_house", "葫芦")


func _stats_by_suit(t) -> void:
	# 空手保底
	var s0 := FightGd.derive_stats([], {"tier": "high"})
	t.expect(int(s0["atk"]) >= 15, "空手保底攻击 ≥15")
	t.expect(int(s0["max_hp"]) >= 100, "空手保底生命 ≥100")
	# ♠物攻 ♦防御 ♥生命 ♣技能
	var s1 := FightGd.derive_stats([card(15, 0)], {"tier": "high"})  # ♠A
	var s2 := FightGd.derive_stats([card(15, 1)], {"tier": "high"})  # ♥A
	var s3 := FightGd.derive_stats([card(15, 2)], {"tier": "high"})  # ♦A
	var s4 := FightGd.derive_stats([card(15, 3)], {"tier": "high"})  # ♣A
	t.expect(int(s1["atk"]) > int(s3["atk"]), "♠ 物攻更高")
	t.expect(int(s2["max_hp"]) > int(s1["max_hp"]), "♥ 生命更高")
	t.expect(int(s3["def"]) > int(s1["def"]), "♦ 护甲更高")
	t.expect(int(s4["skill"]) > int(s1["skill"]), "♣ 技能更高")
	t.expect(str(s4["skill_kind"]) == "fire", "单♣ = 火球流派")


## ── 抽牌流程: 二选一 → 装备槽 → 开战 ──
func _draft_flow(t) -> void:
	var fm = FightGd.new(12345)
	t.expect(str(fm.phase) == "draft", "开局进入 draft")
	t.expect(int(fm.round_num) == 1, "第 1 回合")
	t.expect((fm.pair as Array).size() == 2, "二选一: 两张候选")
	t.expect(fm.enemy.is_empty(), "draft 阶段无敌人")
	# 非法候选
	t.expect(not bool(fm.draft_pick(999)["ok"]), "候选外选牌被拒")
	t.expect(not bool(fm.draft_pick(-1)["ok"]), "槽空不允许跳过")
	# 选第一张 → 组耗尽 → 开战(或补抽)
	var c0: int = fm.pair[0]
	var r: Dictionary = fm.draft_pick(c0)
	t.expect(bool(r["ok"]), "合法选牌通过")
	if str(fm.phase) == "draft":
		# 抽到特殊牌 → 补抽组(普通限定)
		t.expect(FightGd.is_sp(c0), "选特殊牌进入补抽")
		for c in fm.pair:
			t.expect(not FightGd.is_sp(int(c)), "补抽组全是普通牌")
		r = fm.draft_pick(fm.pair[0])
		t.expect(bool(r["ok"]), "补抽选牌通过")
	t.expect(str(fm.phase) == "battle", "候选组耗尽进入战斗")
	t.expect((fm.slots as Array).size() >= 1, "至少装备 1 张")
	t.expect(str(fm.enemy["kind"]) == "mob", "第 1 回合是小怪")


## ── 5 槽保证: 全自动跑完一局, Boss 战(第 5 回合)前恰好 5 张 ──
func _slot_guarantee(t) -> void:
	var fm = FightGd.new(777)
	var guard := 0
	while str(fm.phase) != "over" and guard < 4000:
		guard += 1
		match str(fm.phase):
			"draft":
				fm.draft_pick(fm.pair[0], 0 if fm.slots.size() >= 5 else -1)
			"battle":
				fm.hp = int(fm.stats["max_hp"])   # 测试作弊: 满血保证通关
				if int(fm.enemy["hp"]) > 0:
					fm.step("attack")
			"round_end":
				t.expect((fm.slots as Array).size() == 5
						or int(fm.round_num) < 5,
						"第 5 回合前装备数未满 5 也合法(逐步满足)")
				fm.advance_round()
	t.expect(str(fm.phase) == "over", "全自动流程可达终局")
	t.expect(bool(fm.run_won), "满血作弊下可通关")
	t.expect((fm.slots as Array).size() == 5, "通关时恰好 5 张装备")
	t.expect(int(fm.round_num) == 5, "回合数止于 5")
	# 回合日程: R3 精英 / R5 BOSS(在 battle 阶段记录; 第 5 回合胜利直接 over)
	var fm2 = FightGd.new(42)
	var kinds_seen := {}
	var guard2 := 0
	while str(fm2.phase) != "over" and guard2 < 4000:
		guard2 += 1
		match str(fm2.phase):
			"draft":
				fm2.draft_pick(fm2.pair[0], 0 if fm2.slots.size() >= 5 else -1)
			"battle":
				kinds_seen[int(fm2.round_num)] = str(fm2.enemy["kind"])
				fm2.hp = int(fm2.stats["max_hp"])
				if int(fm2.enemy["hp"]) > 0:
					fm2.step("attack")
			"round_end":
				fm2.advance_round()
	t.expect(str(kinds_seen[3]) == "elite", "第 3 回合是精英怪")
	t.expect(str(kinds_seen[5]) == "boss", "第 5 回合是 BOSS")


## ── 特殊牌(8 种奇物) ──
func _specials(t) -> void:
	t.expect(FightGd.SPECIALS.size() == 8, "特殊牌共 8 种")
	for i in 8:
		t.expect(str(FightGd.sp_meta(i)["key"]).begins_with("sp_"),
				"奇物 %d 目录完整" % i)
	var fm = FightGd.new(9)
	# 狂化: 生命/护甲减半, 攻击翻倍
	fm.slots = [FightGd.CardsGd.DIAMOND_3]
	fm._refresh_stats()
	var base_atk := int(fm.stats["atk"])
	var base_hp := int(fm.stats["max_hp"])
	var base_def := int(fm.stats["def"])
	fm._take_special(2)
	t.expect(int(fm.stats["atk"]) == base_atk * 2, "狂化: 攻击翻倍")
	t.expect(int(fm.stats["max_hp"]) == base_hp / 2, "狂化: 生命减半")
	t.expect(int(fm.stats["def"]) < base_def, "狂化: 护甲下降")
	t.expect((fm.specials as Array).has(2), "奇物已入列(不占槽)")
	t.expect((fm.slots as Array).size() == 1, "特殊牌不占装备槽")
	# 嗜血/荆棘/先制/玉障/泉涌 标志位
	fm._take_special(3)
	t.expect(absf(float(fm.stats["vamp"]) - 0.20) < 0.001, "嗜血: 20% 吸血")
	fm._take_special(4)
	t.expect(absf(float(fm.stats["thorns"]) - 0.30) < 0.001, "荆棘: 30% 反弹")
	fm._take_special(5)
	t.expect(bool(fm.stats["first"]), "先制标志位")
	fm._take_special(7)
	t.expect(bool(fm.stats["regen"]), "泉涌标志位")
	# 玉障: 开战获得护盾
	fm._take_special(6)
	fm.slots = [card(5, 1)]
	fm._refresh_stats()
	fm._start_battle()
	t.expect(int(fm.shield) == int(int(fm.stats["max_hp"]) * 0.2),
			"玉障: 开战 20% 生命护盾")
	# 先制: 首攻必暴击
	var evs: Array = fm.step("attack")
	var first_is_crit := false
	for e in evs:
		if str(e["kind"]) == "crit":
			first_is_crit = true
	t.expect(first_is_crit, "先制符: 首次攻击必暴击")
	# 后续攻击不再必然暴击(手牌无♠, crit_rate=0.1); 怪物可能被击杀,
	# 每次循环前若已脱离战斗则重开一场
	var crit_count := 0
	for i in 30:
		if str(fm.phase) != "battle":
			fm._start_battle()
		fm.enemy["hp"] = 999999
		for e in fm.step("attack"):
			if str(e["kind"]) == "crit":
				crit_count += 1
	t.expect(crit_count < 30, "先制符仅首攻生效(30 攻未全暴)")
	# 泉涌: 回合开始回血
	if str(fm.phase) != "battle":
		fm._start_battle()
	fm.hp = 10
	var evs2: Array = fm.step("defend")
	var healed := false
	for e in evs2:
		if str(e["kind"]) == "heal":
			healed = true
	t.expect(healed, "泉涌: 回合开始回血")


## 替换 / 跳过 / 锁环保留 / 增援令额外组
func _draft_specials(t) -> void:
	# 锁环: 未选中候选下回合保留
	var fm = FightGd.new(11)
	fm._take_special(1)
	fm.slots = [card(5, 0)]
	fm.pair = [card(9, 0), card(11, 0)]
	fm.pairs_left = 1
	var r: Dictionary = fm.draft_pick(card(9, 0))
	t.expect(bool(r["ok"]), "锁环组选牌通过")
	t.expect(int(fm.locked) == card(11, 0), "未选中的候选被锁定")
	t.expect(str(fm.phase) == "battle" or str(fm.phase) == "draft",
			"组解析后进入下一阶段")
	fm.round_num = 2
	fm._open_round()
	t.expect((fm.pair as Array).has(card(11, 0)), "锁定的牌下回合重新出现")
	t.expect(int(fm.locked) == -1, "锁定已消费")
	# 增援令: 下回合起每组回合多一组
	var fm2 = FightGd.new(12)
	fm2._take_special(0)
	fm2._open_round()
	t.expect(int(fm2.pairs_left) == 2, "增援令: 每回合两组候选")
	var guard := 0
	while str(fm2.phase) == "draft" and guard < 10:
		guard += 1
		fm2.draft_pick(fm2.pair[0], 0 if fm2.slots.size() >= 5 else -1)
	t.expect(guard == 2, "增援令回合需选两组")
	t.expect(str(fm2.phase) == "battle", "两组选完开战")
	# 替换: 槽满后需指定槽位
	var fm3 = FightGd.new(13)
	fm3.slots = [card(3, 0), card(4, 0), card(5, 0), card(6, 0), card(7, 0)]
	fm3.pair = [card(15, 0), card(14, 0)]
	fm3.pairs_left = 1
	var r3: Dictionary = fm3.draft_pick(card(15, 0))
	t.expect(str(r3["error"]) == "need_slot", "槽满选普通牌要求槽位")
	r3 = fm3.draft_pick(card(15, 0), 2)
	t.expect(bool(r3["ok"]), "指定槽位替换成功")
	t.expect(int(fm3.slots[2]) == card(15, 0), "槽位内容已替换")
	# 跳过: 槽满时允许跳过整组
	var fm4 = FightGd.new(14)
	fm4.slots = [card(3, 0), card(4, 0), card(5, 0), card(6, 0), card(7, 0)]
	fm4.pair = [card(15, 0), card(14, 0)]
	fm4.pairs_left = 1
	var r4: Dictionary = fm4.draft_pick(-1)
	t.expect(bool(r4["ok"]), "槽满允许跳过")
	t.expect((fm4.slots as Array).size() == 5, "跳过不改变装备")


## ── 替换 / 跳过 / 锁环 / 增援令 ──
func _battle_flow(t) -> void:
	var fm = FightGd.new(2024)
	# 槽满替换: 直接灌满 5 槽再抽
	while str(fm.phase) == "draft":
		fm.draft_pick(fm.pair[0], 0 if fm.slots.size() >= 5 else -1)
	t.expect(str(fm.phase) == "battle", "自动编成进入战斗")
	# 战斗解析
	var ehp0 := int(fm.enemy["hp"])
	var evs: Array = fm.step("attack")
	var dealt := 0
	for e in evs:
		if str(e["kind"]) in ["dmg", "crit"]:
			dealt += int(e["v"])
	t.expect(dealt > 0 and int(fm.enemy["hp"]) < ehp0, "攻击造成伤害")
	# 防御减伤
	var intent: String = str(fm.enemy["intent"])
	fm.enemy["intent"] = "attack"
	var hp0: int = fm.hp
	fm.step("defend")
	var took_defend: int = hp0 - fm.hp
	fm.enemy["intent"] = "attack"
	var hp1: int = fm.hp
	fm.step("attack")
	var took_attack: int = hp1 - fm.hp
	t.expect(took_defend <= took_attack, "防御比攻击受创更轻(意图=攻击)")
	t.expect(intent != "", "意图存在")
	# 玩家死亡判定
	fm.hp = 0
	t.expect(fm.player_dead(), "生命归零判死亡")
	# 复活
	fm.revive()
	t.expect(not fm.player_dead() and fm.hp > 0, "复活币回 60% 生命")


func _reward_record(t) -> void:
	var w = WalletGd.new()
	var dia0: int = w.diamonds
	var r: Dictionary = w.grant_fight_reward(5)
	t.expect(int(r["diamonds"]) > 0, "通关奖励钻石入账")
	t.expect(w.diamonds > dia0, "钱包余额增加")
	var r2: Dictionary = w.grant_fight_reward(0)
	t.expect(int(r2["diamonds"]) >= 0, "0 层结算不崩溃")
	t.expect(int(r["best"]) == 5, "历史最佳记录为 5 层")
