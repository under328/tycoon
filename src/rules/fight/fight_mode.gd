## 格斗模式纯逻辑(回合制试炼): 共 5 回合 — 每回合先『二选一』抽 1 张牌,
## 再与怪物战斗。R1/R2/R4 小怪, R3 精英, R5 集齐五张牌后打 Boss。
## 左上 5 个装备槽(特殊牌不占槽): 抽到特殊牌立即生效并补抽一张普通牌,
## 保证 Boss 战时恰好 5 张装备。与渲染完全解耦, 可零依赖单测。
class_name FightMode
extends RefCounted

const CardsGd = preload("res://src/rules/cards.gd")

## 牌型层级(大→小)与加成(不满 5 张也可判型: 一对/三条/两对…)
const TIERS := {
	"straight_flush": {"name": "同花顺", "desc": "全属性+60%"},
	"quad": {"name": "四条", "desc": "物攻 ×1.8"},
	"flush": {"name": "同花", "desc": "主属性 ×2(花色决定方向)"},
	"full_house": {"name": "葫芦", "desc": "吸血 25%"},
	"straight": {"name": "顺子", "desc": "每 3 回合追加一次连击"},
	"trips": {"name": "三条", "desc": "物攻 ×1.4"},
	"two_pair": {"name": "两对", "desc": "护甲/魔抗 ×1.5"},
	"pair": {"name": "一对", "desc": "全属性 +15%"},
	"high": {"name": "高牌", "desc": "无加成"},
}
const TIER_RANK := ["straight_flush", "quad", "flush", "full_house",
		"straight", "trips", "two_pair", "pair", "high"]

## ── 特殊牌(奇物) 8 种: 候选中以 100+id 出现, 不占装备槽 ──
## 命名规则: key 供效果分支; UI 用 icon/name/desc 渲染紫框卡面
const SPECIALS := [
	{"id": 0, "key": "sp_extra", "name": "增援令", "icon": "🎯",
		"desc": "下回合起每回合额外多一组二选一"},
	{"id": 1, "key": "sp_lock", "name": "锁环", "icon": "🗝",
		"desc": "持有期间每轮未选中的候选牌下回合保留"},
	{"id": 2, "key": "sp_berserk", "name": "狂化面具", "icon": "😤",
		"desc": "生命/护甲减半, 攻击翻倍"},
	{"id": 3, "key": "sp_vamp", "name": "嗜血牙", "icon": "🩸",
		"desc": "攻击与技能附带 20% 吸血"},
	{"id": 4, "key": "sp_thorns", "name": "荆棘甲", "icon": "🌵",
		"desc": "反弹所受物理伤害的 30%"},
	{"id": 5, "key": "sp_first", "name": "先制符", "icon": "⚡",
		"desc": "每场战斗的首次攻击必定暴击"},
	{"id": 6, "key": "sp_shield", "name": "玉障", "icon": "🔮",
		"desc": "每场战斗开始获得 20% 生命护盾"},
	{"id": 7, "key": "sp_regen", "name": "泉涌珠", "icon": "💧",
		"desc": "每回合开始回复 5% 生命"},
]
## 候选抽到特殊牌的概率(普通牌用尽时回落普通)
const SPECIAL_RATE := 0.12

## ── 回合计划: 5 回合固定日程(数值 ±12% 随机) ──
const ROUND_PLAN := [
	{"kind": "mob", "hp": 55, "atk": 11},
	{"kind": "mob", "hp": 95, "atk": 16},
	{"kind": "elite", "hp": 165, "atk": 21},
	{"kind": "mob", "hp": 250, "atk": 28},
	{"kind": "boss", "hp": 480, "atk": 38},
]
const ROUNDS := 5
## 无尽层日程(6 回合起): [怪/精英/怪/精英/BOSS] 循环, 每轮 ×1.35
const ENDLESS_PLAN := [
	{"kind": "mob", "hp": 80, "atk": 14},
	{"kind": "elite", "hp": 170, "atk": 20},
	{"kind": "mob", "hp": 150, "atk": 18},
	{"kind": "elite", "hp": 250, "atk": 25},
	{"kind": "boss", "hp": 450, "atk": 36},
]

## 怪物主题组(引擎只存组号与名字, 形象由 UI 按组号+类别绘制;
## 同组两只小怪为同族换色变体)
const GROUPS := [
	{"name": "翡翠森林", "mob": ["毒蘑菇", "巨毒蘑菇"], "elite": "古树妖",
			"boss": "森林巨鹿"},
	{"name": "回声洞穴", "mob": ["洞穴蝙蝠", "血翼蝠王"], "elite": "岩石傀儡",
			"boss": "深渊魔王"},
	{"name": "熔火之心", "mob": ["熔岩史莱姆", "熔岩大史莱姆"], "elite": "炎魔卫士",
			"boss": "熔岩龙王"},
]

# ---------------------------------------------------------------- 运行状态
var phase := "draft"       # draft | battle | round_end | over
var round_num := 1         # 1..5
var run_won := false       # over: 是否击败 Boss
var group := 0             # 怪物主题组 0..2

var deck: Array = []       # 剩余普通牌(0..51 无重复)
var specials_left: Array = []  # 未出现过的特殊牌 id
var slots: Array = []      # 装备槽(普通牌, ≤5)
var specials: Array = []   # 已获特殊牌 id
var pair: Array = []       # 当前候选(2~3 个: 牌 id 或 100+sp_id)
var pairs_left := 1        # 本回合剩余候选组(主组 + 增援令额外组)
var locked := -1           # 锁环保留的候选(下回合重新出现)
var comp := false          # 当前候选组是否为补抽(普通限定)

var hp := 0
var hits := 0              # 连击数(连续进攻; 防御清零)
var cleared := 0          # 已通关回合数(奖励/最佳依据)
var last_rank := ""        # 上回合评级 S/A/B
var _combo_crit_next := false   # 连击 5 层里程碑: 下一击必暴
var _round_dmg_taken := 0       # 本场战斗受到的伤害(评级用)
var fury := 0              # 怒气 0-100(满则可释放奥义大招)
var rare_count := 0        # 已装备稀有卡数(每张 +8% 生命上限)
var stats := {}            # 派生属性(含特殊牌修正)
var combo := {}            # 当前装备牌型
var enemy := {}            # {name, kind, group, hp, max_hp, atk, intent}
var shield := 0            # 玉障护盾(每场战斗重置)

var log_lines: Array = []
var rng := RandomNumberGenerator.new()

var _skill_cd := 0
var _battle_round := 0     # 本场战斗回合数(先制符/顺子用)
var _first_used := false   # 先制符本场是否已消耗


func _init(seed_v: int = -1) -> void:
	if seed_v < 0:
		seed_v = int(Time.get_unix_time_from_system() * 1000.0) % 1000000007
	rng.seed = seed_v
	deck = []
	for i in 52:
		deck.append(i)
	_shuffle(deck)
	specials_left = [0, 1, 2, 3, 4, 5, 6, 7]
	group = rng.randi() % GROUPS.size()
	hp = 100
	_refresh_stats()
	_open_round()
	_log(tr("第 1 回合 — %s 地下城") % str(GROUPS[group]["name"]))


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = a[i]
		a[i] = a[j]
		a[j] = tmp


# ---------------------------------------------------------------- 抽牌阶段

static func is_sp(cand: int) -> bool:
	return cand >= 100 and cand < 200


## 稀有普通牌(金框): 装备后永久 +8% 生命上限
static func is_rare(cand: int) -> bool:
	return cand >= 200


static func card_of(cand: int) -> int:
	return cand - 200 if cand >= 200 else cand


static func sp_of(cand: int) -> int:
	return cand - 100


static func sp_meta(sp_id: int) -> Dictionary:
	return SPECIALS[clampi(sp_id, 0, SPECIALS.size() - 1)]


## 抽一个候选: 25% 特殊牌(未耗尽时), 否则普通牌
func _roll_candidate(normal_only: bool) -> int:
	if not normal_only and not specials_left.is_empty() \
			and rng.randf() < SPECIAL_RATE:
		var sp: int = specials_left.pop_at(rng.randi() % specials_left.size())
		return 100 + sp
	if deck.is_empty():  # 理论不会发生(52 张远大于消耗)
		return rng.randi_range(0, 51)
	var card: int = deck.pop_at(rng.randi() % deck.size())
	if rng.randf() < 0.12:   # 稀有普通牌(金框)
		return 200 + card
	return card


## 开启本回合候选组
func _open_pair() -> void:
	comp = false
	var cands := [_roll_candidate(false)]
	if locked >= 0:
		cands.append(locked)   # 锁环: 上轮未选中的牌保留出现
		locked = -1
	else:
		cands.append(_roll_candidate(false))
	pair = cands


## 回合开启: 计算候选组数(增援令 +1)并进入 draft
func _open_round() -> void:
	phase = "draft"
	pairs_left = 1 + (1 if specials.has(0) else 0)   # 增援令: 下回合起 +1 组
	_open_pair()


## 候选组解析完一组的公共收尾: 还有组则开下一组, 否则进入战斗
func _after_pair_resolved() -> void:
	pairs_left -= 1
	if pairs_left > 0:
		_open_pair()
		return
	if slots.is_empty():
		# 保底: 首回合把两组全跳过(理论不可能, 槽空不允许跳过) — 防御
		pair = [_roll_candidate(true), _roll_candidate(true)]
		comp = true
		return
	_start_battle()


## 选牌/跳过。cand = 候选值(-1 = 跳过本组, 仅槽满可用);
## slot = 槽满替换时的槽位下标(0..4, -1 = 追加)。
## 返回 {ok, error}; 状态错误时 UI 以 phase/pair 重渲染即可。
func draft_pick(cand: int, slot: int = -1) -> Dictionary:
	if phase != "draft":
		return {"ok": false, "error": "not_draft"}
	if cand != -1 and not (pair as Array).has(cand):
		return {"ok": false, "error": "bad_candidate"}
	if cand == -1:
		# 跳过仅允许在"槽满后的替换/跳过"场景(增援令额外组才有意义)
		if slots.size() < 5:
			return {"ok": false, "error": "cannot_skip"}
		_after_pair_resolved()
		return {"ok": true, "error": ""}
	if is_sp(cand):
		_take_special(sp_of(cand))
		# 未选中的候选: 持有锁环时保留
		if specials.has(1):
			for c in pair:
				if int(c) != cand:
					locked = int(c)
		if slots.size() < 5:
			# 补抽一组普通牌 — 保证 Boss 战前集齐 5 张装备
			_log(tr("奇物【%s】生效 — 补抽一张普通牌") % str(sp_meta(sp_of(cand))["name"]))
			pair = [_roll_candidate(true), _roll_candidate(true)]
			comp = true
			return {"ok": true, "error": ""}
		else:
			_after_pair_resolved()
			return {"ok": true, "error": ""}
	# 普通牌(稀有牌剥离金框标记后入槽)
	if slots.size() >= 5:
		if slot < 0 or slot >= 5:
			return {"ok": false, "error": "need_slot"}   # 等待 UI 选槽/跳过
		slots[slot] = card_of(cand)
		_log(tr("替换装备: 槽位 %d → %s") % [slot + 1, CardsGd.label(cand)])
	else:
		slots.append(card_of(cand))
		_log(tr("装备 %s(%d/5)") % [CardsGd.label(cand), slots.size()])
	if is_rare(cand):
		rare_count += 1
		fury = mini(fury + 20, 100)
		_log(tr("稀有卡! 生命上限永久 +8%"))
	_refresh_stats()
	# 锁环: 记录本组未选中的候选(补抽组不触发, 仅主组)
	if specials.has(1) and not comp:
		for c in pair:
			if int(c) != cand:
				locked = int(c)
	_after_pair_resolved()
	return {"ok": true, "error": ""}


func _take_special(sp_id: int) -> void:
	specials.append(sp_id)
	var meta: Dictionary = sp_meta(sp_id)
	_log(tr("获得奇物【%s】%s") % [str(meta["name"]), str(meta["desc"])])
	_refresh_stats()


## 装备变化后重算属性(含特殊牌修正); 生命上限增量直接补进当前生命
func _refresh_stats() -> void:
	var old_max := int(stats.get("max_hp", 0))
	combo = evaluate_combo(slots)
	stats = derive_stats(slots, combo)
	if specials.has(2):   # 狂化面具
		stats["max_hp"] = int(int(stats["max_hp"]) * 0.5)
		stats["def"] = int(int(stats["def"]) * 0.5)
		stats["mres"] = int(int(stats["mres"]) * 0.5)
		stats["atk"] = int(int(stats["atk"]) * 2.0)
	stats["vamp"] = float(stats.get("vamp", 0.0)) + (0.20 if specials.has(3) else 0.0)
	stats["thorns"] = 0.30 if specials.has(4) else 0.0
	stats["first"] = specials.has(5)
	stats["regen"] = specials.has(7)
	var new_max := int(stats["max_hp"])
	if old_max > 0:
		hp = clampi(hp + maxi(new_max - old_max, 0), 1, new_max)
	else:
		hp = new_max
	hp = mini(hp, new_max)


# ---------------------------------------------------------------- 战斗阶段

## 进入本场战斗: 按回合计划生成怪物 + 玉障护盾
func _start_battle() -> void:
	phase = "battle"
	_skill_cd = 0
	_battle_round = 0
	_first_used = false
	hits = 0
	_round_dmg_taken = 0
	last_rank = ""
	var plan: Dictionary
	if round_num <= ROUNDS:
		plan = ROUND_PLAN[clampi(round_num - 1, 0, ROUNDS - 1)]
	else:
		# 无尽层: 5 回合循环 [怪/精英/怪/精英/BOSS], 每轮 ×1.35
		var idx := (round_num - 1) % ROUNDS
		var cycle := int((round_num - 1) / ROUNDS)
		var scale := pow(1.45, cycle)
		var base: Dictionary = ENDLESS_PLAN[idx]
		plan = {"kind": str(base["kind"]),
			"hp": int(int(base["hp"]) * scale),
			"atk": int(int(base["atk"]) * scale)}
	var kind := str(plan["kind"])
	var v := rng.randf_range(0.88, 1.12)
	var e_hp := int(int(plan["hp"]) * v)
	var e_atk := int(int(plan["atk"]) * rng.randf_range(0.88, 1.12))
	var g: Dictionary = GROUPS[group]
	var name_txt: String = ""
	var variant := 0
	match kind:
		"mob":
			var mobs: Array = g["mob"]
			var mi := rng.randi() % mobs.size()
			name_txt = str(mobs[mi])
			variant = mi   # 同族换色变体(UI 按 variant 调色)
		"elite":
			name_txt = str(g["elite"])
		"boss":
			name_txt = str(g["boss"])
	enemy = {
		"name": name_txt, "kind": kind, "group": group, "variant": variant,
		"hp": e_hp, "max_hp": e_hp, "atk": e_atk, "intent": "attack",
	}
	_choose_intent()
	# 玉障: 每场战斗开始 20% 生命护盾
	shield = int(int(stats["max_hp"]) * 0.2) if specials.has(6) else 0
	var kind_name: String = str({"mob": tr("小怪"),
			"elite": tr("精英怪"), "boss": "BOSS"}[kind])
	_log(tr("第 %d 回合 %s: %s 出现! HP %d / 攻击 %d") % [
		round_num, kind_name, name_txt, e_hp, e_atk])


func _choose_intent() -> void:
	var r := rng.randf()
	var kind := str(enemy.get("kind", "mob"))
	if kind == "mob":
		enemy["intent"] = "heavy" if r < 0.3 else "attack"
	else:
		if r < 0.3:
			enemy["intent"] = "heavy"
		elif r < 0.55:
			enemy["intent"] = "spell"
		else:
			enemy["intent"] = "attack"


## 战斗回合: action ∈ {"attack","skill","defend"}
## 返回事件列表供 UI 播放: {who:"p"/"e", kind:"dmg"/"crit"/..., v:int}
func step(action: String) -> Array:
	var evs: Array = []
	if phase != "battle":
		return evs
	if action == "ult" and fury < 100:
		return evs   # 怒气未满, 奥义不可用
	_battle_round += 1
	if _skill_cd > 0:
		_skill_cd -= 1
	# 泉涌: 回合开始回血
	if bool(stats.get("regen", false)) and hp < int(stats["max_hp"]):
		var rg := maxi(int(int(stats["max_hp"]) * 0.05), 2)
		hp = mini(hp + rg, int(stats["max_hp"]))
		evs.append({"who": "p", "kind": "heal", "v": rg})
	match action:
		"attack":
			hits = mini(hits + 1, 11)
			var crit: bool = rng.randf() < float(stats["crit_rate"])
			if _combo_crit_next:
				crit = true   # 连击 5 层里程碑: 本击必暴
				_combo_crit_next = false
			if bool(stats.get("first", false)) and not _first_used:
				crit = true
				_first_used = true
			var dmg := int(float(stats["atk"]) * rng.randf_range(0.9, 1.1))
			if crit:
				dmg = int(dmg * float(stats["crit_dmg"]))
			dmg = int(dmg * (1.0 + 0.04 * mini(maxi(hits - 1, 0), 10)))   # 连击伤害加成
			dmg = maxi(dmg - 2, 1)
			enemy["hp"] = int(enemy["hp"]) - dmg
			fury = mini(fury + 12, 100)
			evs.append({"who": "p", "kind": "crit" if crit else "dmg", "v": dmg})
			if hits == 5:
				_combo_crit_next = true   # 里程碑: 下一击必暴
				evs.append({"who": "p", "kind": "milestone", "v": 5})
			if hits == 8:
				fury = mini(fury + 30, 100)
				evs.append({"who": "p", "kind": "milestone", "v": 8})
			if hits >= 2:
				evs.append({"who": "p", "kind": "combo", "v": hits})
			_vamp_heal(evs, dmg)
		"skill":
			var dmg := maxi(int(float(stats["skill"]) * rng.randf_range(0.9, 1.2)), 1)
			enemy["hp"] = int(enemy["hp"]) - dmg
			var kind_name := str(stats.get("skill_kind", "fire"))
			match kind_name:
				"frost":
					enemy["chilled"] = true
					evs.append({"who": "e", "kind": "chilled", "v": 0})
				"light":
					var hl := maxi(int(dmg * 0.3), 1)
					hp = mini(hp + hl, int(stats["max_hp"]))
					evs.append({"who": "p", "kind": "heal", "v": hl})
			evs.append({"who": "p", "kind": "skill", "v": dmg,
					"skill_kind": kind_name})
			_vamp_heal(evs, dmg)
			hits = mini(hits + 1, 11)
			fury = mini(fury + 8, 100)
			if hits >= 2:
				evs.append({"who": "p", "kind": "combo", "v": hits})
			_skill_cd = 2
		"defend":
			hits = 0   # 防御打断连击(攻与守的取舍)
			var heal := maxi(int(stats["max_hp"]) / 25, 3)
			hp = mini(hp + heal, int(stats["max_hp"]))
			evs.append({"who": "p", "kind": "defend", "v": heal})
		"ult":
			# 奥义: 2.5 倍攻击必中 + 回复 20% 生命, 怒气清零
			var udmg := maxi(int(float(stats["atk"]) * 2.5), 1)
			enemy["hp"] = int(enemy["hp"]) - udmg
			fury = 0
			hits = mini(hits + 1, 11)
			var uhl := maxi(int(int(stats["max_hp"]) * 0.2), 1)
			hp = mini(hp + uhl, int(stats["max_hp"]))
			evs.append({"who": "p", "kind": "ult", "v": udmg})
			evs.append({"who": "p", "kind": "heal", "v": uhl})
			_vamp_heal(evs, udmg)
	# 顺子: 每 3 回合追加一次普攻
	if action != "defend" and action != "ult" and bool(stats.get("straight", false)) \
			and _battle_round % 3 == 0 and int(enemy["hp"]) > 0:
		var dmg2 := maxi(int(float(stats["atk"]) * 0.7), 1)
		enemy["hp"] = int(enemy["hp"]) - dmg2
		evs.append({"who": "p", "kind": "dmg", "v": dmg2})
		_vamp_heal(evs, dmg2)
	# BOSS 狂暴: 血量跌破 30% 一次性触发, 攻击 +40%
	if str(enemy.get("kind", "")) == "boss" and not bool(enemy.get("enraged", false)) \
			and int(enemy["hp"]) > 0 \
			and int(enemy["hp"]) <= int(int(enemy["max_hp"]) * 0.3):
		enemy["enraged"] = true
		enemy["atk"] = int(int(enemy["atk"]) * 1.4)
		evs.append({"who": "e", "kind": "enrage", "v": 0})
		_log(tr("狂暴! 攻击大幅提升!"))
	# 怪物亡 → 回合胜利
	if int(enemy["hp"]) <= 0:
		enemy["hp"] = 0
		evs.append({"who": "e", "kind": "die", "v": 0})
		_win_round()
		return evs
	# 蓄力回合: 敌人不攻击且承伤 +50%, 下回合释放强化重击
	if str(enemy.get("intent", "attack")) == "charge":
		evs.append({"who": "e", "kind": "charging", "v": 0})
		return evs
	# 怪物按意图行动
	var intent := str(enemy.get("intent", "attack"))
	var heavy: bool = intent == "heavy"
	var spell: bool = intent == "spell"
	var edmg := int(float(enemy["atk"]) * (1.6 if heavy else (1.1 if spell else 1.0))
			* rng.randf_range(0.9, 1.1))
	if spell:
		edmg = maxi(int(edmg * 60.0 / (60.0 + float(stats["mres"]))), 1)
	else:
		edmg = maxi(int(edmg * 80.0 / (80.0 + float(stats["def"]))), 1)
	if action == "defend" and intent == "heavy":
		# 完美格挡: 零伤害 + 反击, 重读意图的奖励
		var counter := maxi(int(float(stats["atk"]) * 1.0), 1)
		enemy["hp"] = int(enemy["hp"]) - counter
		fury = mini(fury + 25, 100)
		evs.append({"who": "p", "kind": "parry", "v": counter})
		_choose_intent()
		if int(enemy["hp"]) <= 0:
			enemy["hp"] = 0
			evs.append({"who": "e", "kind": "die", "v": 0})
			_win_round()
		return evs
	if action == "defend":
		edmg = int(edmg * 0.4)
	if bool(enemy.get("chilled", false)):
		edmg = maxi(int(edmg * 0.8), 1)
		enemy["chilled"] = false
	edmg = maxi(edmg, 1)
	_round_dmg_taken += edmg
	_damage_player(edmg)
	fury = mini(fury + 8, 100)
	evs.append({"who": "e", "kind": "spell" if spell else ("heavy" if heavy else "dmg"),
			"v": edmg})
	# 荆棘: 反弹物理伤害 30%
	if not spell and float(stats.get("thorns", 0.0)) > 0.0 \
			and int(enemy["hp"]) > 0:
		var back := maxi(int(edmg * float(stats["thorns"])), 1)
		enemy["hp"] = int(enemy["hp"]) - back
		evs.append({"who": "e", "kind": "thorns", "v": back})
		if int(enemy["hp"]) <= 0:
			enemy["hp"] = 0
			evs.append({"who": "e", "kind": "die", "v": 0})
			_win_round()
			return evs
	_choose_intent()
	return evs


## 玩家受伤: 先扣玉障护盾再扣生命
func _damage_player(v: int) -> void:
	if shield > 0:
		var absorbed := mini(shield, v)
		shield -= absorbed
		v -= absorbed
	hp -= v


func _vamp_heal(evs: Array, dmg: int) -> void:
	if float(stats.get("vamp", 0.0)) > 0.0:
		var heal := int(dmg * float(stats["vamp"]))
		if heal > 0:
			hp = mini(hp + heal, int(stats["max_hp"]))
			evs.append({"who": "p", "kind": "heal", "v": heal})


## 本回合胜利: 回 25% 生命, 下一回合(或通关)
func _win_round() -> void:
	phase = "round_end"
	cleared += 1
	fury = mini(fury + 30, 100)
	var heal := int(int(stats["max_hp"]) * 0.25)
	hp = mini(hp + heal, int(stats["max_hp"]))
	# 评级: 本场未受伤 = S, 受伤 ≤25% = A, 其余 B(评级奖励怒气)
	if _round_dmg_taken == 0:
		last_rank = "S"
		fury = mini(fury + 20, 100)
	elif _round_dmg_taken <= int(int(stats["max_hp"]) * 0.25):
		last_rank = "A"
		fury = mini(fury + 10, 100)
	else:
		last_rank = "B"
	if round_num >= ROUNDS:
		run_won = true
		_log(tr("BOSS 击破! 可继续无尽挑战!"))
	else:
		_log(tr("%s 被击破! 回复 %d 生命") % [str(enemy["name"]), heal])


## round_end 展示完毕后由 UI 调用 → 下一回合
func advance_round() -> void:
	if phase != "round_end":
		return
	round_num += 1
	_open_round()
	_log(tr("第 %d 回合开始") % round_num)


func player_dead() -> bool:
	return hp <= 0


## 复活币: 原地复活(60% 生命), 战斗继续
func revive() -> void:
	hp = maxi(int(int(stats["max_hp"]) * 0.6), 1)
	shield = 0
	_log(tr("复活币发光 — 你重新站了起来!"))


func skill_cd() -> int:
	return _skill_cd


func _log(text: String) -> void:
	log_lines.append(text)
	while log_lines.size() > 8:
		log_lines.pop_front()


# ---------------------------------------------------------------- 属性推导

## ── 牌型判定: 不满 5 张也可判(一对/三条/两对[2,2]); 同花/顺子需满 5 张 ──
static func evaluate_combo(cards: Array) -> Dictionary:
	var values: Array = []
	var suits: Array = []
	for c in cards:
		values.append(CardsGd.value(int(c)))
		suits.append(CardsGd.suit(int(c)))
	values.sort()
	var uniq := {}
	for v in values:
		uniq[v] = true
	var counts := {}
	for v in values:
		counts[v] = int(counts.get(v, 0)) + 1
	var shape := counts.values()
	shape.sort()
	var flush: bool = cards.size() >= 5 and uniq_suits(suits) == 1
	var straight: bool = cards.size() >= 5 and uniq.size() == 5 \
			and int(values[4]) - int(values[0]) == 4
	var tier := "high"
	if flush and straight:
		tier = "straight_flush"
	elif 4 in shape:
		tier = "quad"
	elif flush:
		tier = "flush"
	elif shape == [2, 3]:
		tier = "full_house"
	elif straight:
		tier = "straight"
	elif 3 in shape:
		tier = "trips"
	elif shape == [2, 2]:
		tier = "two_pair"
	elif 2 in shape:
		tier = "pair"
	return {"tier": tier, "name": str(TIERS[tier]["name"]),
			"desc": str(TIERS[tier]["desc"])}


static func uniq_suits(suits: Array) -> int:
	var set := {}
	for x in suits:
		set[x] = true
	return set.size()


## ── 属性推导: ♠物攻/♦护甲魔抗/♥生命/♣技能 + 牌型加成。
## 空手保底: 攻击 15 / 生命 100(防止纯♦♣开局毫无输出)。
static func derive_stats(cards: Array, combo: Dictionary) -> Dictionary:
	var spade := 0
	var heart := 0
	var dia := 0
	var club := 0
	for c in cards:
		var v := CardsGd.value(int(c))
		match CardsGd.suit(int(c)):
			0: spade += v
			1: heart += v
			2: dia += v
			3: club += v
	var spade_cnt := _suit_count(cards, 0)
	var tier := str(combo["tier"])
	var atk := 15 + spade * 6
	var def := 5 + dia * 3
	var mres := 3 + dia * 2
	var skill := club * 6
	var max_hp := 100 + heart * 12
	match tier:
		"straight_flush":
			atk = int(atk * 1.6)
			def = int(def * 1.6)
			mres = int(mres * 1.6)
			max_hp = int(max_hp * 1.6)
			skill = int(skill * 1.6)
		"quad":
			atk = int(atk * 1.8)
		"flush":
			if spade_cnt >= 3:
				atk = int(atk * 2.0)
			elif _suit_count(cards, 1) >= 3:
				max_hp = int(max_hp * 1.8)
			elif _suit_count(cards, 2) >= 3:
				def = int(def * 2.0)
				mres = int(mres * 2.0)
			else:
				skill = int(skill * 2.0)
		"trips":
			atk = int(atk * 1.4)
		"two_pair":
			def = int(def * 1.5)
			mres = int(mres * 1.5)
		"pair":
			atk = int(atk * 1.15)
			def = int(def * 1.15)
			mres = int(mres * 1.15)
			max_hp = int(max_hp * 1.15)
			skill = int(skill * 1.15)
	var club_cnt := _suit_count(cards, 3)
	return {
		"atk": atk, "def": def, "mres": mres, "skill": skill,
		"max_hp": max_hp,
		"crit_rate": 0.10 + 0.05 * spade_cnt,
		"crit_dmg": 1.5 + 0.1 * spade_cnt,
		"vamp": 0.25 if tier == "full_house" else 0.0,
		"combo_tier": tier,
		"straight": tier == "straight",
		"club_cnt": club_cnt,
		"skill_kind": "fire" if club_cnt <= 1 else ("frost" if club_cnt == 2 else "light"),
	}


static func _suit_count(cards: Array, suit: int) -> int:
	var n := 0
	for c in cards:
		if CardsGd.suit(int(c)) == suit:
			n += 1
	return n
