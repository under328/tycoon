## 联机格斗对战纯规则 v4(回合制): 共 5 回合, 每回合双方各自『二选一』抽牌 →
## 玩家之间对战(无怪), 五回合打满后胜场多者赢。
## 抽牌与本地格斗试炼同源并满足联机语义:
## - 双方从同一副 52 张牌中各自独立抽取 — 一张牌被抽走即从牌库移除,
##   对方永远不会抽到同一张(稀有金框 200+ 编码在落牌时剥离);
## - 奇物池每人独立一份(8 种), 双方可以抽到相同奇物;
## - 候选组只出普通/稀有牌, 奇物以 22% 概率作为"第三选项"附带出现,
##   拾取只入奇物槽(上限 2), 不消耗卡牌选择;
## - 锁环(奇物1): 选牌后保留本组未选中的候选到下回合。
## 与网络/渲染完全解耦, 服务器权威, 可零依赖单测。
class_name FightPvp
extends RefCounted

const FightGd = preload("res://src/rules/fight/fight_mode.gd")
const CardsGd = preload("res://src/rules/cards.gd")

const ROUNDS := 5
const TURN_SECONDS := 20
const PICK_SECONDS := 30
const SPECIAL_RATE := 0.30    # 每回合附带奇物第三选项概率(与本地一致)
const RARE_RATE := 0.12       # 稀有普通牌(金框, 200+ 编码)


static func is_sp(cand: int) -> bool:
	return cand >= 100 and cand < 200


static func is_rare(cand: int) -> bool:
	return cand >= 200


static func card_of(cand: int) -> int:
	return cand - 200 if cand >= 200 else cand


static func sp_of(cand: int) -> int:
	return cand - 100


## 从共享牌库抽一张普通牌(每张牌全局只出现一次); 12% 金框稀有
static func _roll_card(st: Dictionary, rng: RandomNumberGenerator) -> int:
	var deck: Array = st["deck"]
	if deck.is_empty():   # 理论不会发生(52 张远大于 5 回合消耗)
		return rng.randi_range(0, 51)
	var card: int = deck.pop_at(rng.randi() % deck.size())
	return 200 + card if rng.randf() < RARE_RATE else card


static func new_state(fighters: Array, names: Dictionary) -> Dictionary:
	var per := {}
	for seat in fighters:
		per[seat] = {
			"slots": [], "specials": [],
			"specials_left": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
			"pair": [], "bonus_relic": -1, "pairs_left": 1,
			"locked": -1, "fury_carry": 0, "done": true,
			"round_pick": -1,   # 本回合最终装备的那张牌(先攻决胜用)
		}
	var deck := []
	for i in 52:
		deck.append(i)
	return {
		"phase": "draft",
		"round_num": 1,
		"fighters": (fighters as Array).duplicate(),
		"names": names.duplicate(true),
		"deck": deck,
		"per": per,
		"battle": {},
		"score": {},
		"round_winner": -1,
		"winner": -1,
		"log": [],
		"left": {},
	}


static func is_fighter(st: Dictionary, seat: int) -> bool:
	return (st["fighters"] as Array).has(seat)


## 玩家退出本场: 标记 + 对局日志(留下的人可见"AI 代管"提示)
static func mark_left(st: Dictionary, seat: int) -> void:
	if bool((st["left"] as Dictionary).get(seat, false)):
		return
	st["left"][seat] = true
	_log(st, TranslationServer.translate("%s 退出对局 — AI 代管接管")
			% str(st["names"].get(seat, "?")))


static func foe_of(st: Dictionary, seat: int) -> int:
	var f: Array = st["fighters"]
	return int(f[0]) if int(f[1]) == seat else int(f[1])


static func _log(st: Dictionary, text: String) -> void:
	(st["log"] as Array).append(text)
	while (st["log"] as Array).size() > 8:
		(st["log"] as Array).pop_front()


## ── 回合开启: 双方各自发独立候选组(共享一副牌), 重置回合状态 ──
static func open_round(st: Dictionary, rng: RandomNumberGenerator) -> void:
	st["phase"] = "draft"
	st["round_winner"] = -1
	for seat in st["fighters"]:
		var per: Dictionary = st["per"][seat]
		per["done"] = false
		per["pair"] = []
		per["bonus_relic"] = -1
		per["round_pick"] = -1
		per["pairs_left"] = 1 + (1 if (per["specials"] as Array).has(0) else 0)
	for seat in st["fighters"]:
		_deal_pair(st, int(seat), rng)
	_log(st, TranslationServer.translate("第 %d 回合 — 二选一编成") % int(st["round_num"]))


## 发该格斗者的下一候选组: 组耗尽 → done。
## 每组 = 两张普通牌(独立抽取) + 可能附带的奇物第三选项
static func _deal_pair(st: Dictionary, seat: int,
		rng: RandomNumberGenerator) -> void:
	var per: Dictionary = st["per"][seat]
	per["bonus_relic"] = -1
	if int(per["pairs_left"]) <= 0:
		per["pair"] = []
		per["done"] = true
		return
	var pair := [_roll_card(st, rng), _roll_card(st, rng)]
	if int(per["locked"]) >= 0:
		# 锁环保留值与新 roll 撞车 → 重抽(最多 8 次; 牌库每张只 pop 一次)
		for _attempt in 8:
			if int(pair[1]) != int(per["locked"]):
				break
			pair[1] = _roll_card(st, rng)
		pair[1] = int(per["locked"])
		per["locked"] = -1
	per["pair"] = pair
	# 附带奇物(每人独立池, 双方可抽到相同奇物; 装备 2 个后不再出现)
	if (per["specials"] as Array).size() < 2 \
			and not (per["specials_left"] as Array).is_empty() \
			and rng.randf() < SPECIAL_RATE:
		var pool: Array = per["specials_left"]
		per["bonus_relic"] = 100 + int(pool.pop_at(rng.randi() % pool.size()))


static func _take_special(st: Dictionary, seat: int, sp_id: int) -> void:
	var per: Dictionary = st["per"][seat]
	(per["specials"] as Array).append(sp_id)
	var meta: Dictionary = FightGd.sp_meta(sp_id)
	_log(st, TranslationServer.translate("%s 获得奇物【%s】") % [st["names"][seat], str(meta["name"])])


## 派生该格斗者当前属性(含奇物修正)
static func derive_fighter(per: Dictionary) -> Dictionary:
	var slots: Array = per["slots"]
	var combo: Dictionary = FightGd.evaluate_combo(slots)
	var stats: Dictionary = FightGd.derive_stats(slots, combo)
	var sps: Array = per["specials"]
	if sps.has(2):   # 狂化
		stats["max_hp"] = int(int(stats["max_hp"]) * 0.5)
		stats["def"] = int(int(stats["def"]) * 0.5)
		stats["mres"] = int(int(stats["mres"]) * 0.5)
		stats["atk"] = int(int(stats["atk"]) * 2.0)
	if sps.has(11):  # 巨人腰带
		stats["max_hp"] = int(int(stats["max_hp"]) * 1.3)
	stats["vamp"] = float(stats.get("vamp", 0.0)) + (0.20 if sps.has(3) else 0.0)
	stats["thorns"] = 0.30 if sps.has(4) else 0.0
	stats["mirror"] = 0.40 if sps.has(10) else 0.0   # 魔镜: 反弹法术 40%
	stats["pierce"] = 0.5 if sps.has(12) else 0.0    # 破甲獠牙: 无视 50% 护甲
	stats["fury_mul"] = 1.5 if sps.has(13) else 1.0  # 昂扬战鼓: 怒气 +50%
	stats["first"] = sps.has(5)
	stats["regen"] = sps.has(7)
	stats["evade"] = 0.06 + (0.04 if str(stats.get("skill_kind", "fire")) == "frost"
			else 0.0) + (0.10 if sps.has(14) else 0.0)   # 四叶草: 闪避 +10%
	return stats


## 选牌/跳过。cand=-1 跳过本组(仅槽满)。slot= 槽满替换槽位。
## 返回 {ok, error}; 双方完成后自动进入战斗。
static func draft_pick(st: Dictionary, seat: int, cand: int, slot: int,
		rng: RandomNumberGenerator) -> Dictionary:
	if str(st["phase"]) != "draft":
		return {"ok": false, "error": "not_draft"}
	if not is_fighter(st, seat):
		return {"ok": false, "error": "not_fighter"}
	var per: Dictionary = st["per"][seat]
	if bool(per["done"]):
		return {"ok": false, "error": "already_done"}
	# 奇物第三选项: 只入奇物槽(上限 2), 不消耗卡牌选择 — 候选组原样保留
	if cand >= 100 and cand == int(per["bonus_relic"]):
		if (per["specials"] as Array).size() >= 2:
			return {"ok": false, "error": "relic_full"}
		_take_special(st, seat, sp_of(cand))
		per["bonus_relic"] = -1   # 立即清空: 不可重复拾取
		return {"ok": true, "error": ""}
	if cand != -1 and not (per["pair"] as Array).has(cand):
		return {"ok": false, "error": "bad_candidate"}
	var slots: Array = per["slots"]
	if cand == -1:
		if slots.size() < 5:
			return {"ok": false, "error": "cannot_skip"}
	elif cand >= 0:
		if slots.size() >= 5:
			if slot < 0 or slot >= 5:
				return {"ok": false, "error": "need_slot"}
			slots[slot] = card_of(cand)
		else:
			slots.append(card_of(cand))
		per["round_pick"] = card_of(cand)   # 记录本回合装备的牌(先攻决胜)
		_log_pick(st, seat, cand)
		if is_rare(cand):
			# 稀有金框: 装备 + 怒气携带 +20(开战时转入)
			per["fury_carry"] = mini(int(per["fury_carry"]) + 20, 100)
			_log(st, TranslationServer.translate("%s 装备稀有牌! (怒气 +20)") % st["names"][seat])
	# 锁环(奇物1): 保留本组未选中的候选到下回合
	if cand >= 0 and (per["specials"] as Array).has(1) \
			and not is_sp(cand) and (per["pair"] as Array).size() >= 2:
		for c in per["pair"]:
			if int(c) != cand:
				per["locked"] = int(c)
	# 本组解析完 → 下一组或完成
	per["pairs_left"] = int(per["pairs_left"]) - 1
	per["pair"] = []
	_deal_pair(st, seat, rng)
	if bool(per["done"]):
		var all_done := true
		for s in st["fighters"]:
			if not bool((st["per"][s] as Dictionary)["done"]):
				all_done = false
		if all_done:
			_begin_round_battle(st)
	return {"ok": true, "error": ""}


static func _log_pick(st: Dictionary, seat: int, cand: int) -> void:
	_log(st, TranslationServer.translate("%s 装备 %s(%d/5)") % [st["names"][seat],
			CardsGd.label(card_of(cand)),
			(st["per"][seat]["slots"] as Array).size()])


## ── 本回合对战(新鲜生命, 按当前编成派生) ──
static func _begin_round_battle(st: Dictionary) -> void:
	st["phase"] = "battle"
	var b := {
		"hp": {}, "max_hp": {}, "shield": {}, "stats": {}, "combo": {},
		"guard": {}, "chilled": {}, "skill_cd": {}, "first_used": {},
		"fury": {}, "streak": {}, "enraged": {}, "burn_turns": {},
		"turn": -1, "battle_round": 0,
	}
	for seat in st["fighters"]:
		var per: Dictionary = st["per"][seat]
		var stats: Dictionary = derive_fighter(per)
		var combo: Dictionary = FightGd.evaluate_combo(per["slots"])
		b["stats"][seat] = stats
		b["combo"][seat] = combo
		b["max_hp"][seat] = int(stats["max_hp"])
		b["hp"][seat] = int(stats["max_hp"])
		b["shield"][seat] = int(int(stats["max_hp"]) * 0.2) \
				if (per["specials"] as Array).has(6) else 0
		b["guard"][seat] = false
		b["chilled"][seat] = false
		b["skill_cd"][seat] = 0
		b["first_used"][seat] = false
		b["streak"][seat] = 0
		b["enraged"][seat] = false
		b["burn_turns"][seat] = 0
		# 闪避率: 基础 6% + 冰霜技能流 +4% + 四叶草 +10%(在 derive_fighter 汇总)
		# 稀有牌积攒的怒气带入本场, 用后清零
		b["fury"][seat] = mini(int(per["fury_carry"]), 100)
		per["fury_carry"] = 0
	# 先攻规则(任务反馈): 本回合双方各自装备的牌, 点数大者先攻 —
	# 点数相同按黑红梅方(♠>♥>♣>♦)决胜; 共享牌库同牌唯一, 不存在全同。
	# 旧规则(整套牌型等级, 平局偏向 1 号位=左边)仅作缺牌兜底。
	var fa: int = st["fighters"][0]
	var fb: int = st["fighters"][1]
	var pa: int = int((st["per"][fa] as Dictionary).get("round_pick", -1))
	var pb: int = int((st["per"][fb] as Dictionary).get("round_pick", -1))
	if pa >= 0 and pb >= 0:
		var va := CardsGd.value(pa)
		var vb := CardsGd.value(pb)
		if va != vb:
			b["turn"] = fa if va > vb else fb
		else:
			b["turn"] = fa if _suit_rank(pa) < _suit_rank(pb) else fb
	else:
		var ra: int = FightGd.TIER_RANK.find(str(b["combo"][fa]["tier"]))
		var rb: int = FightGd.TIER_RANK.find(str(b["combo"][fb]["tier"]))
		b["turn"] = fa if ra <= rb else fb
	st["battle"] = b
	_log(st, TranslationServer.translate("对战开始 — %s 先攻") % st["names"][int(b["turn"])])


## 先攻决胜花色序: 黑红梅方(♠>♥>♣>♦)。牌编码 0♠ 1♥ 2♦ 3♣ → 序 [0,1,3,2]
static func _suit_rank(card: int) -> int:
	return [0, 1, 3, 2][CardsGd.suit(card)]


## 行动: attack/skill/defend/ult。返回 {ok, error, events}。
static func apply_action(st: Dictionary, seat: int, action: String,
		rng: RandomNumberGenerator) -> Dictionary:
	var b: Dictionary = st.get("battle", {})
	if str(st["phase"]) != "battle":
		return {"ok": false, "error": "not_battle", "events": []}
	if not is_fighter(st, seat):
		return {"ok": false, "error": "not_fighter", "events": []}
	if int(b["turn"]) != seat:
		return {"ok": false, "error": "not_turn", "events": []}
	if not action in ["attack", "skill", "defend", "ult"]:
		return {"ok": false, "error": "bad_action", "events": []}
	if action == "skill" and int(b["skill_cd"][seat]) > 0:
		return {"ok": false, "error": "skill_cd", "events": []}
	if action == "ult" and int(b["fury"][seat]) < 100:
		return {"ok": false, "error": "no_fury", "events": []}
	var foe := foe_of(st, seat)
	var evs: Array = []
	# 点燃(烈焰技能): 行动者回合开始先吃灼烧伤害
	if int(b.get("burn_turns", {}).get(seat, 0)) > 0:
		b["burn_turns"][seat] = int(b["burn_turns"][seat]) - 1
		var bd := maxi(int(int(b["max_hp"][seat]) * 0.04), 1)
		b["hp"][seat] = int(b["hp"][seat]) - bd
		evs.append(_ev(seat, seat, "burn", bd))
		if int(b["hp"][seat]) <= 0:
			b["hp"][seat] = 0
			_end_round(st, foe)
			return {"ok": true, "error": "", "events": evs}
	# 凤羽: 行动回合开始生命 <35% 时回复 12%(绝境续命)
	if (st["per"][seat]["specials"] as Array).has(15) 			and int(b["hp"][seat]) > 0 			and int(b["hp"][seat]) < int(int(b["max_hp"][seat]) * 0.35):
		var ph := maxi(int(int(b["max_hp"][seat]) * 0.12), 2)
		b["hp"][seat] = mini(int(b["hp"][seat]) + ph, int(b["max_hp"][seat]))
		evs.append(_ev(seat, seat, "heal", ph))
	b["battle_round"] = int(b["battle_round"]) + 1
	evs.append_array(_resolve(st, seat, foe, action, rng))
	if action != "ult":
		# 基础积攒(昂扬战鼓 ×1.5)
		var fmul: float = float(b["stats"][seat].get("fury_mul", 1.0))
		b["fury"][seat] = mini(int(b["fury"][seat]) + int(4 * fmul), 100)
	# 战场风向(不确定性): 8% 概率随机一方士气大涨 +15 怒气
	if rng.randf() < 0.08:
		var lucky: int = [seat, foe][rng.randi() % 2]
		var lmul: float = float(b["stats"][lucky].get("fury_mul", 1.0))
		var gain := int(15 * lmul)
		b["fury"][lucky] = mini(int(b["fury"][lucky]) + gain, 100)
		evs.append(_ev(lucky, lucky, "surge", gain))
	# 击倒对方 → 胜; 荆棘反杀自己 → 对方胜(都不再轮转)
	if int(b["hp"][foe]) <= 0:
		b["fury"][seat] = mini(int(b["fury"][seat]) + 30, 100)   # 击倒奖励
		_end_round(st, seat)
	elif int(b["hp"][seat]) <= 0:
		b["hp"][seat] = 0
		_end_round(st, foe)
	else:
		b["turn"] = foe   # 行动后轮转到对方
	return {"ok": true, "error": "", "events": evs}


static func _resolve(st: Dictionary, actor: int, foe: int, action: String,
			rng: RandomNumberGenerator) -> Array:
	var evs: Array = []
	var b: Dictionary = st["battle"]
	var a: Dictionary = b["stats"][actor]
	var f: Dictionary = b["stats"][foe]
	# 狂暴(每人每回合一次): 生命 < 25% 时攻击永久 +25% — 劣势翻盘机制
	for s in [actor, foe]:
		if not bool(b["enraged"][s]) 				and int(b["hp"][s]) < int(int(b["max_hp"][s]) * 0.25):
			b["enraged"][s] = true
			b["stats"][s]["atk"] = int(int(b["stats"][s]["atk"]) * 1.25)
			evs.append(_ev(s, s, "enrage", 0))
	if action != "skill" and int(b["skill_cd"][actor]) > 0:
		b["skill_cd"][actor] = int(b["skill_cd"][actor]) - 1
	# 泉涌回血(受击积怒气统一放命中结算后)
	if bool(a.get("regen", false)):
		var hp_now: int = int(b["hp"][actor])
		var mh: int = int(b["max_hp"][actor])
		if hp_now < mh:
			var rg := maxi(int(mh * 0.05), 2)
			b["hp"][actor] = mini(hp_now + rg, mh)
			evs.append(_ev(actor, actor, "heal", rg))
	var guard_on: bool = bool(b["guard"][foe])
	b["guard"][foe] = false
	match action:
		"attack":
			# 闪避: 攻击可被躲开(技能必中) — 目标侧移, 无伤害, 连击不断但不涨
			if rng.randf() < float(f.get("evade", 0.0)):
				b["fury"][foe] = mini(int(b["fury"][foe]) + 6, 100)
				evs.append(_ev(actor, foe, "evade", 0))
				b["fury"][actor] = mini(int(b["fury"][actor])
						+ int(4 * float(a.get("fury_mul", 1.0))), 100)
				return evs
			var crit: bool = rng.randf() < float(a["crit_rate"])
			if bool(a.get("first", false)) and not bool(b["first_used"][actor]):
				crit = true
				b["first_used"][actor] = true
			var dmg := int(float(a["atk"]) * rng.randf_range(0.9, 1.1))
			if crit:
				dmg = int(dmg * float(a["crit_dmg"]))
			# 破甲獠牙: 无视一半护甲
			var atk_def: int = int(int(f["def"]) * 0.5) 					if float(a.get("pierce", 0.0)) > 0.0 else int(f["def"])
			# 连击: 连续进攻每层 +4% 伤害(封顶 10 层), 防御重置
			var streak: int = int(b["streak"][actor])
			dmg = int(dmg * (1.0 + 0.04 * mini(streak, 10)))
			b["streak"][actor] = mini(streak + 1, 99)
			dmg = _hit(b, actor, foe, dmg, _mitigate(atk_def), guard_on)
			evs.append(_ev(actor, foe, "crit" if crit else "dmg", dmg))
			if int(b["streak"][actor]) >= 3:
				evs.append(_ev(actor, actor, "comboup",
						int(b["streak"][actor])))
			_vamp(b, actor, dmg, evs)
			b["fury"][actor] = mini(int(b["fury"][actor])
					+ int(12 * float(a.get("fury_mul", 1.0))), 100)
		"skill":
			# 技能差异化(与本地试炼同源): 烈焰高伤+点燃 / 冰霜冻结 / 圣光回复
			var kind := str(a.get("skill_kind", "fire"))
			var mul := 1.5 if kind == "fire" 					else (1.0 if kind == "frost" else 0.8)
			var dmg := maxi(int(float(a["skill"]) * mul * rng.randf_range(0.9, 1.2)), 1)
			dmg = int(dmg * (1.0 + 0.04 * mini(int(b["streak"][actor]), 10)))
			b["streak"][actor] = mini(int(b["streak"][actor]) + 1, 99)
			var sk_mit: float = _mitigate(int(f["mres"])) if kind != "fire" 					else _mitigate(int(int(f["mres"]) * 0.5))   # 烈焰无视一半魔抗
			dmg = _hit(b, actor, foe, dmg, sk_mit, guard_on)
			match kind:
				"frost":
					b["chilled"][foe] = true
					evs.append(_ev(actor, foe, "chill", 0))
					var fmul2: float = float(a.get("fury_mul", 1.0))
					b["fury"][actor] = mini(int(b["fury"][actor]) + int(5 * fmul2), 100)
				"light":
					var hl := maxi(int(dmg * 0.4), 1)
					b["hp"][actor] = mini(int(b["hp"][actor]) + hl,
							int(b["max_hp"][actor]))
					evs.append(_ev(actor, actor, "heal", hl))
					var fmul3: float = float(a.get("fury_mul", 1.0))
					b["fury"][actor] = mini(int(b["fury"][actor]) + int(10 * fmul3), 100)
				"fire":
					# 点燃: 对方回合开始灼烧 2 跳(每跳 4% 生命)
					b["burn_turns"][foe] = 2
			evs.append(_ev(actor, foe, "skill", dmg))
			if int(b["streak"][actor]) >= 3:
				evs.append(_ev(actor, actor, "comboup",
						int(b["streak"][actor])))
			_vamp(b, actor, dmg, evs)
			b["skill_cd"][actor] = 2
			var fmul4: float = float(a.get("fury_mul", 1.0))
			b["fury"][actor] = mini(int(b["fury"][actor]) + int(8 * fmul4), 100)
		"defend":
			b["streak"][actor] = 0   # 防御重置连击(攻守取舍)
			b["guard"][actor] = true   # 格挡: 下一次受击减免 80%
			var heal := maxi(int(b["max_hp"][actor]) / 25, 3)
			b["hp"][actor] = mini(int(b["hp"][actor]) + heal,
					int(b["max_hp"][actor]))
			if (st["per"][actor]["specials"] as Array).has(16):   # 铁壁符
				b["shield"][actor] = int(b["shield"][actor]) 						+ maxi(int(int(b["max_hp"][actor]) * 0.10), 2)
				b["fury"][actor] = mini(int(b["fury"][actor]) 						+ int(10 * float(a.get("fury_mul", 1.0))), 100)
			evs.append(_ev(actor, actor, "defend", heal))
		"ult":
			# 奥义: 2.2 倍攻击必中(无视减伤) + 回复 15% 生命, 怒气清零
			var dmg := maxi(int(float(a["atk"]) * 2.2), 1)
			dmg = _hit(b, actor, foe, dmg, 1.0, false)
			b["streak"][actor] = 0
			b["fury"][actor] = 0
			var uhl := maxi(int(int(b["max_hp"][actor]) * 0.15), 1)
			b["hp"][actor] = mini(int(b["hp"][actor]) + uhl,
					int(b["max_hp"][actor]))
			evs.append(_ev(actor, actor, "heal", uhl))
			evs.append(_ev(actor, foe, "ult", dmg))
	# 顺子追击(破甲獠牙同样生效)
	if action != "defend" and bool(a.get("straight", false)) 			and int(b["battle_round"]) % 3 == 0 and int(b["hp"][foe]) > 0:
		var st_def: int = int(int(f["def"]) * 0.5) 				if float(a.get("pierce", 0.0)) > 0.0 else int(f["def"])
		var d2 := _hit(b, actor, foe, int(float(a["atk"]) * 0.7),
				_mitigate(st_def), false)
		evs.append(_ev(actor, foe, "dmg", d2))
		_vamp(b, actor, d2, evs)
	# 荆棘: 反弹物理伤害 / 魔镜: 反弹法术伤害
	if action != "defend" and int(b["hp"][actor]) > 0 and evs.size() > 0:
		var taken_phys := 0
		var taken_spell := 0
		for e in evs:
			if int(e["target"]) == actor and str(e["kind"]) in ["dmg", "crit", "skill"]:
				if str(e["kind"]) == "skill":
					taken_spell += int(e["v"])
				else:
					taken_phys += int(e["v"])
		var back_total := 0
		if taken_phys > 0 and float(f.get("thorns", 0.0)) > 0.0:
			back_total += maxi(int(taken_phys * float(f["thorns"])), 1)
		if taken_spell > 0 and float(f.get("mirror", 0.0)) > 0.0:
			back_total += maxi(int(taken_spell * float(f["mirror"])), 1)
		if back_total > 0 and int(b["hp"][actor]) > 0:
			b["hp"][actor] = int(b["hp"][actor]) - back_total
			evs.append(_ev(foe, actor, "thorns", back_total))
	if int(b["hp"][actor]) <= 0 and int(b["hp"][foe]) > 0:
		b["hp"][actor] = 0
	return evs


## 落伤: 冰冻 → 格挡 → 固定减免, 下限 1
## 百分比减伤系数: def 越高减免越多但永不完全免疫
static func _mitigate(def: int) -> float:
	return 80.0 / (80.0 + float(def))


static func _hit(b: Dictionary, actor: int, foe: int, dmg: int,
		mit_mul: float, guard_on: bool) -> int:
	if bool(b["chilled"][actor]):
		dmg = int(dmg * 0.8)
		b["chilled"][actor] = false
	if guard_on:
		dmg = int(dmg * 0.2)   # 格挡: 减免 80% 伤害
	dmg = maxi(int(dmg * mit_mul), 1)
	# 玉障护盾优先吸收
	var sh: int = int(b["shield"][foe])
	if sh > 0:
		var absorbed: int = mini(sh, dmg)
		b["shield"][foe] = sh - absorbed
		dmg -= absorbed
	b["hp"][foe] = int(b["hp"][foe]) - dmg
	b["fury"][foe] = mini(int(b["fury"][foe]) + 8, 100)   # 受击积怒气
	return dmg


static func _vamp(b: Dictionary, actor: int, dmg: int, evs: Array) -> void:
	var a: Dictionary = b["stats"][actor]
	if float(a.get("vamp", 0.0)) > 0.0:
		var heal := int(dmg * float(a["vamp"]))
		if heal > 0:
			b["hp"][actor] = mini(int(b["hp"][actor]) + heal,
					int(b["max_hp"][actor]))
			evs.append(_ev(actor, actor, "heal", heal))


static func _ev(who: int, target: int, kind: String, v: int) -> Dictionary:
	return {"who": who, "target": target, "kind": kind, "v": v}


## 回合结束: 胜者 +1 分; 不设提前终结 — 五回合打满后按胜场数定胜负
static func _end_round(st: Dictionary, winner: int) -> void:
	var b: Dictionary = st["battle"]
	b["hp"][winner] = maxi(int(b["hp"][winner]), 1)
	st["phase"] = "round_end"
	st["round_winner"] = winner
	st["score"][winner] = int(st["score"].get(winner, 0)) + 1
	_log(st, TranslationServer.translate("%s 拿下第 %d 回合! (比分 %d:%d)") % [
		st["names"][winner], int(st["round_num"]),
		int(st["score"].get(st["fighters"][0], 0)),
		int(st["score"].get(st["fighters"][1], 0))])


## round_end 展示完毕 → 下一回合(比分未达标时)
static func advance_round(st: Dictionary, rng: RandomNumberGenerator) -> bool:
	if str(st["phase"]) != "round_end":
		return false
	if int(st["round_num"]) >= ROUNDS:
		# 五回合打满: 胜场多者赢(每回合必有胜者, 5 局不会平; 极端兜底判先手方)
		var fa: int = st["fighters"][0]
		var fb: int = st["fighters"][1]
		var sa: int = int(st["score"].get(fa, 0))
		var sb: int = int(st["score"].get(fb, 0))
		st["phase"] = "over"
		st["winner"] = fa if sa >= sb else fb
		_log(st, TranslationServer.translate("★ %s 赢得整场格斗对战! (比分 %d:%d)") % [
			st["names"][int(st["winner"])], maxi(sa, sb), mini(sa, sb)])
		return true
	st["round_num"] = int(st["round_num"]) + 1
	open_round(st, rng)
	return true


## ── 按座位裁剪视图 ──
static func view(st: Dictionary, my_seat: int) -> Dictionary:
	var fighters: Array = st["fighters"]
	var phase := str(st["phase"])
	var v := {
		"phase": phase,
		"my_seat": my_seat,
		"fighters": (fighters as Array).duplicate(),
		"spectator": not (fighters as Array).has(my_seat),
		"names": (st["names"] as Dictionary).duplicate(true),
		"round_num": int(st["round_num"]),
		"rounds_total": ROUNDS,
		"score": (st["score"] as Dictionary).duplicate(),
		"round_winner": int(st["round_winner"]),
		"winner": int(st["winner"]),
		"log": (st["log"] as Array).duplicate(),
		"left": (st["left"] as Dictionary).duplicate(),
		"turn": int(st["battle"].get("turn", -1)) if phase == "battle" else -1,
		"turn_seconds": TURN_SECONDS,
		"pick_seconds": PICK_SECONDS,
		"my": {},
		"per": {},
	}
	# 自己的候选/编成(私密)
	if (st["per"] as Dictionary).has(my_seat):
		var mine: Dictionary = st["per"][my_seat]
		v["my"] = {
			"slots": (mine["slots"] as Array).duplicate(),
			"specials": (mine["specials"] as Array).duplicate(),
			"pair": (mine["pair"] as Array).duplicate(),
			"bonus_relic": int(mine["bonus_relic"]),
			"done": bool(mine["done"]),
			"pairs_left": int(mine["pairs_left"]),
		}
	for seat in fighters:
		var per: Dictionary = st["per"][seat]
		# 变身: 集满 5 张装备(光环只在编成/对战阶段显示, 过场与终局隐藏)。
		# 对手的具体奇物/装备只在开战后披露 — 编成阶段只给数量。
		var info := {
			"slots_count": (per["slots"] as Array).size(),
			"specials_count": (per["specials"] as Array).size(),
			"done": bool(per["done"]),
			"transformed": (per["slots"] as Array).size() >= 5 \
					and phase in ["draft", "battle"],
			"relics": [],
		}
		if phase in ["battle", "round_end", "over"] or int(seat) == my_seat:
			info["relics"] = (per["specials"] as Array).duplicate()
		v["per"][seat] = info
	if phase in ["battle", "round_end", "over"]:
		var b: Dictionary = st["battle"]
		v["hp"] = (b["hp"] as Dictionary).duplicate()
		v["max_hp"] = (b["max_hp"] as Dictionary).duplicate()
		v["shield"] = (b["shield"] as Dictionary).duplicate()
		v["fury"] = (b["fury"] as Dictionary).duplicate()
		v["skill_cd"] = (b["skill_cd"] as Dictionary).duplicate()
		v["streak"] = (b["streak"] as Dictionary).duplicate()
		v["my_turn"] = int(b["turn"]) == my_seat and phase == "battle"
		v["hands"] = {}
		v["combo"] = {}
		v["skill_kind"] = {}
		v["stats_brief"] = {}
		v["suit"] = {}
		for seat in fighters:
			var per: Dictionary = st["per"][seat]
			v["hands"][seat] = (per["slots"] as Array).duplicate()
			var combo: Dictionary = b["combo"][seat]
			v["combo"][seat] = {"name": str(combo["name"]),
					"desc": str(combo["desc"]), "tier": str(combo["tier"])}
			var s: Dictionary = b["stats"][seat]
			v["skill_kind"][seat] = str(s.get("skill_kind", "fire"))
			v["stats_brief"][seat] = {"atk": int(s["atk"]), "def": int(s["def"]),
					"mres": int(s["mres"]), "skill": int(s["skill"])}
			# 主花色(变身光环颜色)
			var cnt := [0, 0, 0, 0]
			var best := 0
			for c in per["slots"]:
				var su := CardsGd.suit(int(c))
				cnt[su] += 1
				if cnt[su] > cnt[best]:
					best = su
			v["suit"][seat] = best
	else:
		v["my_turn"] = false
		# draft 阶段不泄露对手候选; 展示双方编成进度即可
	return v
