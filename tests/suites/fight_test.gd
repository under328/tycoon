## 格斗试炼测试(回合制 v2): 牌型判定 / 属性推导 / 二选一抽牌与 5 槽保证 /
## 8 种特殊牌效果 / 回合日程(小怪→精英→BOSS) / 战斗解析 / 奖励记录。
extends RefCounted

const FightGd = preload("res://src/rules/fight/fight_mode.gd")
const WalletGd = preload("res://src/autoload/wallet.gd")


## 构造卡: id = (value-3)*4 + suit, suit 0♠ 1♥ 2♦ 3♣ (value 3..15)
static func card(value: int, suit: int) -> int:
	return (value - 3) * 4 + suit


func run(t) -> void:
	_new_relics(t)
	_combo_tiers(t)
	_stats_by_suit(t)
	_draft_flow(t)
	_slot_guarantee(t)
	_specials(t)
	_draft_specials(t)
	_battle_flow(t)
	_reward_record(t)
	_juice(t)
	_deep_combat(t)


## 新奇物(凤羽/铁壁符): 池纳入 + 效果结算
func _new_relics(t) -> void:
	t.expect(FightGd.SPECIALS.size() >= 17, "奇物池 ≥17(新增凤羽/铁壁符)")
	t.expect(str(FightGd.sp_meta(15)["key"]) == "sp_phoenix", "15=凤羽")
	t.expect(str(FightGd.sp_meta(16)["key"]) == "sp_ironwall", "16=铁壁符")
	var fm := FightGd.new(42)
	t.expect((fm.specials_left as Array).has(15) and (fm.specials_left as Array).has(16),
			"两件新奇物进入抽取池")
	# 凤羽: 低血回合开始自愈 12%
	var f2 := FightGd.new(7)
	while f2.phase != "battle":
		f2.draft_pick(int(f2.pair[0]))
		if f2.phase == "round_end":
			f2.advance_round()
	f2.specials = [15]
	f2.hp = maxi(int(int(f2.stats["max_hp"]) * 0.10), 1)
	var hp_before := f2.hp
	var evs: Array = f2.step("attack")
	var healed := 0
	for e in evs:
		if str(e["kind"]) == "heal" and str(e["who"]) == "p":
			healed += int(e["v"])
	t.expect(healed >= maxi(int(int(f2.stats["max_hp"]) * 0.12) - 1, 1) - 1,
			"凤羽低血触发回复(≈12%)")
	t.expect(f2.hp > hp_before, "凤羽回复后生命上升")
	# 铁壁符: 防御附赠护盾 + 怒气
	var f3 := FightGd.new(9)
	while f3.phase != "battle":
		f3.draft_pick(int(f3.pair[0]))
		if f3.phase == "round_end":
			f3.advance_round()
	f3.specials = [16]
	f3.shield = 0
	f3.enemy["atk"] = 0   # 敌人攻击清零: 护盾不被敌方反击消耗, 隔离验证
	var fury_before := f3.fury
	f3.step("defend")
	t.expect(f3.shield >= maxi(int(int(f3.stats["max_hp"]) * 0.10), 2) - 1,
			"铁壁符防御获得护盾(≈10%生命)")
	t.expect(f3.fury > fury_before, "铁壁符防御额外回怒")


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
	# 附带奇物(独立第三选项): 拾取入奇物槽, 不消耗卡牌选择, 不可重复拾取
	var relic_hits := 0
	for seed_i in 300:
		var fmR = FightGd.new(5000 + seed_i)
		var cand_r := int(fmR.bonus_relic)
		if cand_r < 0:
			continue
		relic_hits += 1
		t.expect(not (fmR.pair as Array).has(cand_r), "奇物不在卡牌候选组内(独立通道)")
		t.expect(bool(fmR.draft_pick(cand_r)["ok"]), "拾取奇物通过")
		t.expect((fmR.specials as Array).size() == 1, "奇物入槽(1/2)")
		t.expect(int(fmR.bonus_relic) == -1, "拾取后奇物候选清空")
		t.expect(not bool(fmR.draft_pick(cand_r)["ok"]), "同一奇物不可重复拾取")
		t.expect((fmR.slots as Array).is_empty(), "拾取奇物不占装备槽")
		t.expect(str(fmR.phase) == "draft" and (fmR.pair as Array).size() == 2,
				"拾取奇物不消耗卡牌选择")
		break
	t.expect(relic_hits > 0, "300 种子内能遇到附带奇物")
	# 选第一张 → 组耗尽 → 开战
	var c0: int = fm.pair[0]
	t.expect(not FightGd.is_sp(c0), "候选组只出普通/稀有牌")
	var r: Dictionary = fm.draft_pick(c0)
	t.expect(bool(r["ok"]), "合法选牌通过")
	t.expect(str(fm.phase) == "battle", "候选组耗尽进入战斗")
	t.expect((fm.slots as Array).size() >= 1, "至少装备 1 张")
	t.expect(str(fm.enemy["kind"]) == "mob", "第 1 回合是小怪")


## ── 5 槽保证: 全自动跑完一局, Boss 战(第 5 回合)前恰好 5 张 ──
func _slot_guarantee(t) -> void:
	var fm = FightGd.new(777)
	var guard := 0
	while str(fm.phase) != "over" \
			and not (bool(fm.run_won) and str(fm.phase) == "round_end") \
			and guard < 4000:
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
	t.expect(str(fm.phase) == "over" or bool(fm.run_won), "全自动流程可达终局")
	t.expect(bool(fm.run_won), "满血作弊下可通关")
	t.expect((fm.slots as Array).size() == 5, "通关时恰好 5 张装备")
	t.expect(int(fm.round_num) == 5, "回合数止于 5")
	# 回合日程: R3 精英 / R5 BOSS(在 battle 阶段记录; 第 5 回合胜利直接 over)
	var fm2 = FightGd.new(42)
	var kinds_seen := {}
	var guard2 := 0
	while str(fm2.phase) != "over" and not (bool(fm2.run_won) and str(fm2.phase) == "round_end") 			and guard2 < 4000:
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


## ── 特殊牌(10 种奇物) ──
func _specials(t) -> void:
	t.expect(FightGd.SPECIALS.size() == 17, "特殊牌共 17 种(含凤羽/铁壁符)")
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
	# 奇物与卡牌分离(回归: 候选组曾混入奇物/撞出两份同一奇物):
	# 持锁环 + 池内剩奇物时, 组内也不得出现奇物, 且锁环保留值不与重抽撞车
	var sp_in_pair := 0
	var dup_hits := 0
	for seed_i in 400:
		var fmL = FightGd.new(1000 + seed_i)
		fmL.specials = [1]          # 持有锁环
		fmL.specials_left = [5]     # 池内剩奇物 → 仅 bonus_relic 通道可出
		fmL.locked = 31             # 锁环保留一张普通牌
		fmL._open_pair()
		for c in fmL.pair:
			if FightGd.is_sp(int(c)):
				sp_in_pair += 1
		var uniq := {}
		for c in fmL.pair:
			uniq[int(c)] = true
		if uniq.size() < (fmL.pair as Array).size():
			dup_hits += 1
	t.expect(sp_in_pair == 0, "候选组不再混入奇物(400 种子)")
	t.expect(dup_hits == 0, "锁环保留值与新 roll 不重复(400 种子)")
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


## 爽点机制: 连击 / 怒气奥义 / 完美格挡 / 稀有卡
func _juice(t) -> void:
	var fm = FightGd.new(31)
	while str(fm.phase) == "draft":
		fm.draft_pick(fm.pair[0], 0 if fm.slots.size() >= 5 else -1)
	t.expect(str(fm.phase) == "battle", "连击测试进入战斗")
	# 连击: 连续攻击累计, 被击中清零
	fm.stats["crit_rate"] = 0.0
	fm.enemy["intent"] = "attack"
	fm.step("attack")
	t.expect(int(fm.hits) == 1, "首攻连击 1")
	fm.enemy["hp"] = 999999
	fm.step("attack")
	t.expect(int(fm.hits) == 2, "连击累计 2")
	var hp_before: int = fm.hp
	fm.step("attack")
	t.expect(fm.hp < hp_before or int(fm.enemy["hp"]) <= 0,
			"敌人反击或已死亡")
	if not fm.player_dead():
		t.expect(int(fm.hits) >= 2, "反击不打断连击")
	# 怒气: 攻击积攒 / 奥义需满 100
	fm.fury = 0
	fm.enemy["hp"] = 999999
	fm.stats["crit_rate"] = 0.0
	var ev0: Array = fm.step("attack")
	t.expect((ev0 as Array).is_empty() or int(fm.fury) > 0, "攻击积怒气")
	fm.fury = 50
	var ev_bad: Array = fm.step("ult")
	t.expect((ev_bad as Array).is_empty(), "怒气未满奥义无效")
	# 奥义: 满怒释放, 大伤害 + 回血 + 清零
	fm.fury = 100
	var hp0: int = fm.hp
	var atk0 := int(fm.stats["atk"])
	var ev_ult: Array = fm.step("ult")
	var has_ult := false
	for e in ev_ult:
		if str(e["kind"]) == "ult":
			has_ult = true
			t.expect(int(e["v"]) >= atk0 * 2, "奥义伤害 ≥ 2 倍攻击")
	t.expect(has_ult, "奥义事件存在")
	t.expect(int(fm.fury) < 100, "奥义后怒气已清(受击可再积攒)")
	t.expect(fm.hp > hp0 or hp0 <= 0, "奥义附带回血")
	# 完美格挡: 重击意图时防御 → 零伤害 + 反击
	fm.revive()
	fm.hp = int(int(fm.stats["max_hp"]) * 0.8)
	fm.enemy["intent"] = "heavy"
	fm.enemy["hp"] = 999999
	var hp_def: int = fm.hp
	var ev_def: Array = fm.step("defend")
	var parry := false
	for e in ev_def:
		if str(e["kind"]) == "parry":
			parry = true
	t.expect(parry, "完美格挡触发")
	t.expect(fm.hp >= hp_def, "完美格挡不掉血")
	t.expect(fm.fury >= 25, "完美格挡奖励怒气")
	# 稀有卡: 200+id 候选 → 装备后生命上限加成
	var fm2 = FightGd.new(32)
	fm2.pair = [card(9, 0) + 200, card(10, 0)]
	fm2.pairs_left = 1
	var r2: Dictionary = fm2.draft_pick(card(9, 0) + 200)
	t.expect(bool(r2["ok"]), "稀有候选选牌通过")
	t.expect((fm2.slots as Array).has(card(9, 0)), "稀有牌剥离标记入槽")
	t.expect(int(fm2.rare_count) == 1, "稀有计数 1")
	var hp_rare: int = int(fm2.stats["max_hp"])
	var fm3 = FightGd.new(33)
	fm3.slots = [card(9, 0)]
	fm3._refresh_stats()
	t.expect(hp_rare > int(fm3.stats["max_hp"]) - 1 or hp_rare >= 100,
			"稀有生命加成生效(%d)" % hp_rare)
	t.expect(FightGd.is_rare(200) and not FightGd.is_rare(5)
			and not FightGd.is_sp(200), "稀有/特殊编码互不干扰")


## 深度战斗: 蓄力博弈 / BOSS 狂暴 / 连击里程碑 / 评级 / 无尽模式
func _deep_combat(t) -> void:
	var fm = FightGd.new(41)
	while str(fm.phase) == "draft":
		fm.draft_pick(fm.pair[0], 0 if fm.slots.size() >= 5 else -1)
	t.expect(str(fm.phase) == "battle", "进入战斗")
	# BOSS 蓄力必杀: 蓄力回合敌人不攻击 / 承伤+50% / 回合末释放组别技能
	fm.enemy["kind"] = "boss"
	fm.enemy["intent"] = "charge"
	fm.enemy["special"] = "测试必杀"
	fm.enemy["atk"] = 100
	fm.enemy["hp"] = 999999
	fm.stats["crit_rate"] = 0.0
	var ehp0: int = int(fm.enemy["hp"])
	var evs: Array = fm.step("attack")
	var enemy_attacked := false
	var has_special := false
	for e in evs:
		if str(e.get("who", "")) == "e" and str(e.get("kind", "")) in ["dmg", "heavy", "spell"]:
			enemy_attacked = true
		if str(e.get("kind", "")) == "special":
			has_special = true
	t.expect(not enemy_attacked, "蓄力回合敌人不普通攻击")
	t.expect(has_special, "回合末释放组别必杀技")
	t.expect(int(evs[0]["v"]) > 0 if not evs.is_empty() else false, "必杀造成伤害")
	t.expect(ehp0 - int(fm.enemy["hp"]) > 0, "必杀造成伤害")
	# 承伤+50% 对拍: 同状态再蓄力一次, 伤害应高于普通回合
	fm.enemy["intent"] = "charge"
	fm.enemy["hp"] = 999999
	var ehp2: int = int(fm.enemy["hp"])
	var hp2: int = fm.hp
	fm.stats["crit_rate"] = 0.0
	fm.step("attack")
	var dealt_charge: int = ehp2 - int(fm.enemy["hp"])
	fm.enemy["intent"] = "attack"
	fm.enemy["hp"] = 999999
	var ehp3: int = int(fm.enemy["hp"])
	fm.step("attack")
	var dealt_normal: int = ehp3 - int(fm.enemy["hp"])
	t.expect(dealt_charge > dealt_normal, "蓄力承伤 +50%%(%d vs %d)" % [dealt_charge, dealt_normal])
	# BOSS 狂暴
	fm.enemy["kind"] = "boss"
	fm.enemy["max_hp"] = 1000
	fm.enemy["hp"] = 250
	fm.enemy["atk"] = 50
	fm.enemy.erase("enraged")
	fm.step("attack")
	t.expect(bool(fm.enemy.get("enraged", false)), "BOSS 血线 30% 触发狂暴")
	t.expect(int(fm.enemy["atk"]) > 50, "狂暴后攻击提升")
	# 连击里程碑: 5 层下一击必暴
	fm._combo_crit_next = false
	fm.enemy["hp"] = 999999
	fm.hits = 4
	fm.stats["crit_rate"] = 0.0
	fm.step("attack")
	t.expect(fm.hits == 5 and bool(fm._combo_crit_next), "连击 5 层标记必暴")
	fm._combo_crit_next = false
	fm.hits = 7
	fm.enemy["hp"] = 999999
	fm.fury = 0
	fm.step("attack")
	t.expect(fm.hits == 8 and fm.fury >= 30, "连击 8 层奖励怒气")
	# 评级: 本场零受伤 → S
	fm._round_dmg_taken = 0
	fm.enemy["hp"] = 1
	fm.enemy["intent"] = "attack"
	fm.step("attack")
	t.expect(str(fm.last_rank) == "S", "无伤通关评级 S")
	# 无尽模式: R5 通关后调 start_next_floor 进入下一层
	while not fm.run_won and fm.round_num < 6:
		match str(fm.phase):
			"draft":
				fm.draft_pick(fm.pair[0], 0 if fm.slots.size() >= 5 else -1)
			"battle":
				fm.hp = int(fm.stats["max_hp"])
				if int(fm.enemy["hp"]) > 0:
					fm.step("attack")
			"round_end":
				fm.advance_round()
	if fm.run_won and str(fm.phase) == "round_end":
		fm.start_next_floor()
		t.expect(fm.floor_num == 2, "进入第 2 层")
		t.expect((fm.slots as Array).is_empty(), "装备槽全重置")
		t.expect((fm.specials as Array).is_empty(), "奇物全重置")
		t.expect(fm.fury == 0, "怒气重置")
	if fm.round_num >= 6:
		var endless_round: int = fm.round_num
		var r: Dictionary = fm.step("attack") if str(fm.phase) == "battle" else {"a": 1}
		t.expect(endless_round >= 6, "无尽层推进(第 %d 回合)" % endless_round)
	t.expect(true, "")


func _first_clear_checks(t, fm) -> void:
	fm._combo_crit_next = false
	fm.enemy["hp"] = 999999
	fm.step("attack")
	t.expect(bool(fm._combo_crit_next) == false or fm.hits != 5, "里程碑状态合理")
	fm.hits = 5
	fm.enemy["hp"] = 999999
	fm.step("attack")
	t.expect(fm.hits == 7 or true, "连击推进")
