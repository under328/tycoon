## 格斗模式纯逻辑(回合制试炼): 共 5 回合 — 每回合先『二选一』抽 1 张牌,
## 再与怪物战斗。R1/R2/R4 小怪, R3 精英, R5 集齐五张牌后打 Boss。
## 左上 5 个装备槽(特殊牌不占槽): 抽到特殊牌立即生效并补抽一张普通牌,
## 保证 Boss 战时恰好 5 张装备。与渲染完全解耦, 可零依赖单测。
class_name FightMode
extends RefCounted

const CardsGd = preload("res://src/rules/cards.gd")

## 牌型层级(大→小)与加成(不满 5 张也可判型: 一对/三条/两对…)
const TIERS := {
	"straight_flush": {"name": "同花顺", "desc": "全属性+90%"},
	"quad": {"name": "四条", "desc": "物攻 ×2.0"},
	"flush": {"name": "同花", "desc": "主属性 ×2(花色决定方向)"},
	"full_house": {"name": "葫芦", "desc": "全属性+30% · 吸血 25%"},
	"straight": {"name": "顺子", "desc": "每 3 回合追加一次连击"},
	"trips": {"name": "三条", "desc": "物攻 ×1.55"},
	"two_pair": {"name": "两对", "desc": "护甲/魔抗 ×1.6"},
	"pair": {"name": "一对", "desc": "全属性 +25%"},
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
	{"id": 8, "key": "sp_eye", "name": "狂暴之眼", "icon": "👁",
		"desc": "连击上限 16, 连击伤害加成提升至 6%/层"},
	{"id": 9, "key": "sp_sand", "name": "时之沙漏", "icon": "⏳",
		"desc": "技能冷却缩短为 1 回合"},
	{"id": 10, "key": "sp_mirror", "name": "魔镜", "icon": "🪞",
		"desc": "反弹所受法术伤害的 40%"},
	{"id": 11, "key": "sp_giant", "name": "巨人腰带", "icon": "🥋",
		"desc": "生命上限永久 +30%"},
	{"id": 12, "key": "sp_fang", "name": "破甲獠牙", "icon": "🦷",
		"desc": "攻击与顺子无视一半护甲"},
	{"id": 13, "key": "sp_bell", "name": "昂扬战鼓", "icon": "🥁",
		"desc": "所有怒气获取提升 50%"},
	{"id": 14, "key": "sp_clover", "name": "四叶草", "icon": "🍀",
		"desc": "闪避率 +10%, 好运常伴"},
	{"id": 15, "key": "sp_phoenix", "name": "凤羽", "icon": "🪶",
		"desc": "回合开始生命低于 35% 时回复 12%"},
	{"id": 16, "key": "sp_ironwall", "name": "铁壁符", "icon": "🛡️",
		"desc": "防御时获得 10% 生命护盾并额外 +10 怒气"},
]
## 每回合附带奇物第三选项的概率(下调等待、上调惊喜: 0.22 → 0.30)
const SPECIAL_RATE := 0.30

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
	{"name": "冰封雪原", "mob": ["雪原狼", "霜牙雪狼"], "elite": "冰晶卫士",
			"boss": "极寒霜龙"},
	{"name": "幽暗墓地", "mob": ["骷髅兵", "腐骸骷髅"], "elite": "死灵法师",
			"boss": "亡灵君王"},
]

# ---------------------------------------------------------------- 运行状态
var phase := "draft"       # draft | battle | round_end | over
var round_num := 1         # 层内回合 1..5
var floor_num := 1         # 层数(每层 5 回合)
var run_won := false       # over: 是否击败 Boss
var group := 0             # 怪物主题组 0..2

var deck: Array = []       # 剩余普通牌(0..51 无重复)
var specials_left: Array = []  # 未出现过的特殊牌 id
var slots: Array = []      # 装备槽(普通牌, ≤5)
var specials: Array = []   # 已获特殊牌 id
var pair: Array = []       # 当前候选(2~3 个: 牌 id 或 100+sp_id)
var pairs_left := 1        # 本回合剩余候选组(主组 + 增援令额外组)
var locked := -1           # 锁环保留的候选(下回合重新出现)
var bonus_relic := -1      # 本轮二选一附带的奇物候选(100+sp_id, -1 = 无)
var comp := false          # 当前候选组是否为补抽(普通限定)

var hp := 0
var hits := 0              # 连击数(连续进攻; 防御清零)
var cleared := 0          # 本层已通关回合数
var total_cleared := 0    # 全程累计通关回合数(跨层累加, 结算奖励依据)
var total_bosses := 0     # 全程累计击破 BOSS 数(跨层累加)
var cleared_ever := false # 本次试炼是否击破过 BOSS(中途阵亡仍算有战果)
var last_rank := ""        # 上回合评级 S/A/B
var _combo_crit_next := false   # 连击 5 层里程碑: 下一击必暴
var _round_dmg_taken := 0       # 本场战斗受到的伤害(评级用)
var hard := false               # 每日挑战: 怪物 HP/攻击 +25%, 玩家伤害 -20%
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
var _burn_turns := 0       # 灼烧剩余回合(烈焰吐息)
var _burn_dmg := 0         # 灼烧每回合伤害
var _player_frozen := false # 冰冻: 下次攻击伤害减半(极寒冰封)
var _guarding := false      # 格挡中(防御: 本回合受击减免 80%)
var _enemy_burn_turns := 0  # 敌方点燃剩余跳数(烈焰技能)
var _enemy_burn_dmg := 0    # 敌方点燃每跳伤害

## BOSS 专属必杀技(按主题组): 蓄力回合承伤+50%, 回合末释放
const BOSS_SPECIALS := [
	{"name": "藤蔓缠绕", "desc": "重击并吸取生命"},
	{"name": "暗影尖啸", "desc": "无视护甲魔抗的重击"},
	{"name": "烈焰吐息", "desc": "重击并施加灼烧"},
	{"name": "极寒冰封", "desc": "冰冻玩家, 下次攻击伤害减半"},
	{"name": "亡者召唤", "desc": "重击并回复自身生命"},
]


func _init(seed_v: int = -1) -> void:
	if seed_v < 0:
		seed_v = int(Time.get_unix_time_from_system() * 1000.0) % 1000000007
	rng.seed = seed_v
	deck = []
	for i in 52:
		deck.append(i)
	_shuffle(deck)
	specials_left = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
	group = rng.randi() % GROUPS.size()
	hp = 100
	_refresh_stats()
	_open_round()
	_log(tr("第 1 层 — %s 地下城") % str(GROUPS[group]["name"]))


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


## 抽一个候选普通牌。奇物不进候选组 — 经 bonus_relic 第三选项独立出现
func _roll_candidate() -> int:
	if deck.is_empty():  # 理论不会发生(52 张远大于消耗)
		return rng.randi_range(0, 51)
	var card: int = deck.pop_at(rng.randi() % deck.size())
	if rng.randf() < 0.12:   # 稀有普通牌(金框)
		return 200 + card
	return card


## 开启本回合候选组
func _open_pair() -> void:
	comp = false
	var cands := [_roll_candidate()]
	if locked >= 0:
		# 锁环保留值跨层幸存而牌库每层重置 → 可能与新 roll 撞出
		# 两份同一牌。撞车则重抽(最多 8 次; 重抽后同牌不可能再现 —
		# 单副牌每张只 pop 一次)。
		if cands[0] == locked:
			for _attempt in 8:
				cands[0] = _roll_candidate()
				if cands[0] != locked:
					break
		cands.append(locked)   # 锁环: 上轮未选中的牌保留出现
		locked = -1
	else:
		cands.append(_roll_candidate())
	pair = cands
	# 附带奇物: 每回合 12% 概率出现一个(池内扣除, 装备后不再出现);
	# 与装备牌分离 — 选奇物不消耗卡牌选择, 选卡牌也仍可再拿奇物
	bonus_relic = -1
	if specials.size() < 2 and not specials_left.is_empty() \
			and rng.randf() < SPECIAL_RATE:
		bonus_relic = 100 + specials_left.pop_at(rng.randi() % specials_left.size())


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
		pair = [_roll_candidate(), _roll_candidate()]
		comp = true
		return
	_start_battle()


## 选牌/跳过。cand = 候选值(-1 = 跳过本组, 仅槽满可用);
## slot = 槽满替换时的槽位下标(0..4, -1 = 追加)。
## 返回 {ok, error}; 状态错误时 UI 以 phase/pair 重渲染即可。
func draft_pick(cand: int, slot: int = -1) -> Dictionary:
	if phase != "draft":
		return {"ok": false, "error": "not_draft"}
	# 奇物候选: 装备到奇物槽(最多 2 个; 已装备的不会再次抽到 — 出池即扣)
	if cand == bonus_relic and cand >= 100:
		if specials.size() >= 2:
			return {"ok": false, "error": "relic_full"}
		_take_special(sp_of(cand))
		bonus_relic = -1   # 立即清空: 不可重复拾取, UI 同步撤下第三选项
		_log(tr("装入奇物槽: %s(%d/2)") % [str(sp_meta(sp_of(cand))["name"]), specials.size()])
		return {"ok": true, "error": ""}
	if cand != -1 and not (pair as Array).has(cand):
		return {"ok": false, "error": "bad_candidate"}
	if cand == -1:
		# 跳过仅允许在"槽满后的替换/跳过"场景(增援令额外组才有意义)
		if slots.size() < 5:
			return {"ok": false, "error": "cannot_skip"}
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
	if specials.has(11):  # 巨人腰带: 生命上限 +30%
		stats["max_hp"] = int(int(stats["max_hp"]) * 1.3)
	stats["vamp"] = float(stats.get("vamp", 0.0)) + (0.20 if specials.has(3) else 0.0)
	stats["thorns"] = 0.30 if specials.has(4) else 0.0
	stats["mirror"] = 0.40 if specials.has(10) else 0.0   # 魔镜: 反弹法术 40%
	stats["pierce"] = 0.5 if specials.has(12) else 0.0    # 破甲獠牙: 无视 50% 护甲
	stats["fury_mul"] = 1.5 if specials.has(13) else 1.0  # 昂扬战鼓: 怒气 +50%
	stats["first"] = specials.has(5)
	stats["regen"] = specials.has(7)
	stats["evade"] = 0.10 if specials.has(14) else 0.0    # 四叶草: 闪避 +10%
	var new_max := int(stats["max_hp"])
	if old_max > 0:
		hp = clampi(hp + maxi(new_max - old_max, 0), 1, new_max)
	else:
		hp = new_max
	hp = mini(hp, new_max)
	if hard:   # 每日挑战: 玩家伤害 -20% (普攻/技能/奥义/反击/顺子全走 atk/skill)
		stats["atk"] = maxi(int(int(stats["atk"]) * 0.8), 1)
		stats["skill"] = maxi(int(int(stats["skill"]) * 0.8), 1)


## 怒气获取统一入口(昂扬战鼓 ×1.5)
func _fury_gain(base: int) -> int:
	return int(base * float(stats.get("fury_mul", 1.0)))


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
	_burn_turns = 0
	_burn_dmg = 0
	_player_frozen = false
	_guarding = false
	_enemy_burn_turns = 0
	_enemy_burn_dmg = 0
	var plan: Dictionary
	if round_num <= ROUNDS:
		plan = ROUND_PLAN[clampi(round_num - 1, 0, ROUNDS - 1)]
	else:
		# 无尽层: 5 回合循环 [怪/精英/怪/精英/BOSS], 每轮 ×1.35
		var idx := (round_num - 1) % ROUNDS
		var cycle := floor_num - 1
		var scale := pow(1.40, cycle)
		var base: Dictionary = ENDLESS_PLAN[idx]
		plan = {"kind": str(base["kind"]),
			"hp": int(int(base["hp"]) * scale),
			"atk": int(int(base["atk"]) * scale)}
	var kind := str(plan["kind"])
	var v := rng.randf_range(0.88, 1.12)
	var hard_mult := 1.25 if hard else 1.0
	var e_hp := int(int(plan["hp"]) * hard_mult * v)
	var e_atk := int(int(plan["atk"]) * hard_mult * rng.randf_range(0.88, 1.12))
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


## BOSS 必杀技: 蓄力回合玩家承伤+50%, 回合末按主题组释放特色技能
func _cast_boss_special(evs: Array) -> void:
	var skill_name := str(BOSS_SPECIALS[group]["name"])
	var base := float(enemy["atk"])
	var dmg := 0
	match group:
		0:  # 森林巨鹿 · 藤蔓缠绕: 重击 + 吸取生命
			dmg = maxi(int(base * 1.5), 1)
			_damage_player(dmg)
			var hl := maxi(int(int(enemy["max_hp"]) * 0.08), 1)
			enemy["hp"] = mini(int(enemy["hp"]) + hl, int(enemy["max_hp"]))
			evs.append({"who": "e", "kind": "special", "v": dmg, "skill": skill_name,
					"heal": hl})
		1:  # 深渊魔王 · 暗影尖啸: 无视护甲魔抗
			dmg = maxi(int(base * 1.8 * rng.randf_range(0.9, 1.1)), 1)
			_damage_player(dmg)
			evs.append({"who": "e", "kind": "special", "v": dmg, "skill": skill_name})
		2:  # 熔岩龙王 · 烈焰吐息: 重击 + 灼烧 2 回合
			dmg = maxi(int(base * 1.2), 1)
			_damage_player(dmg)
			_burn_turns = 2
			_burn_dmg = maxi(int(base * 0.35), 1)
			evs.append({"who": "e", "kind": "special", "v": dmg, "skill": skill_name,
					"burn": _burn_dmg})
		3:  # 极寒霜龙 · 极寒冰封: 冰冻玩家(下次攻击伤害减半)
			dmg = maxi(int(base * 0.8), 1)
			_damage_player(dmg)
			_player_frozen = true
			evs.append({"who": "e", "kind": "special", "v": dmg, "skill": skill_name,
					"frozen": true})
		4:  # 亡灵君王 · 亡者召唤: 攻击 + 回复自身 15%
			dmg = maxi(int(base * 1.1), 1)
			_damage_player(dmg)
			var hl2 := maxi(int(int(enemy["max_hp"]) * 0.15), 1)
			enemy["hp"] = mini(int(enemy["hp"]) + hl2, int(enemy["max_hp"]))
			evs.append({"who": "e", "kind": "special", "v": dmg, "skill": skill_name,
					"heal": hl2})
	_round_dmg_taken += dmg
	_log(tr("%s 释放必杀技「%s」!") % [str(enemy["name"]), skill_name])


func _choose_intent() -> void:
	var r := rng.randf()
	var kind := str(enemy.get("kind", "mob"))
	if kind == "mob":
		enemy["intent"] = "heavy" if r < 0.3 else "attack"
		return
	if kind == "boss" and r < 0.20:
		# BOSS 蓄力必杀: 意图公示技能名, 蓄力回合承伤+50%
		enemy["intent"] = "charge"
		enemy["special"] = str(BOSS_SPECIALS[group]["name"])
		return
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
	# 灼烧: 回合开始受伤(烈焰吐息)
	if _burn_turns > 0:
		_burn_turns -= 1
		_damage_player(_burn_dmg)
		evs.append({"who": "p", "kind": "burn", "v": _burn_dmg})
		if player_dead():
			return evs
	# 凤羽: 回合开始生命 <35% 时回复 12%(绝境续命)
	if specials.has(15) and hp > 0 			and hp < int(int(stats["max_hp"]) * 0.35):
		var ph := maxi(int(int(stats["max_hp"]) * 0.12), 2)
		hp = mini(hp + ph, int(stats["max_hp"]))
		evs.append({"who": "p", "kind": "heal", "v": ph})
	# 泉涌: 回合开始回血
	if bool(stats.get("regen", false)) and hp < int(stats["max_hp"]):
		var rg := maxi(int(int(stats["max_hp"]) * 0.05), 2)
		hp = mini(hp + rg, int(stats["max_hp"]))
		evs.append({"who": "p", "kind": "heal", "v": rg})
	match action:
		"attack":
			hits = mini(hits + 1, _hits_cap())
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
			var rate := 0.06 if specials.has(8) else 0.04   # 狂暴之眼: 6%/层
			dmg = int(dmg * (1.0 + rate * mini(maxi(hits - 1, 0), _hits_cap() - 1)))
			if float(stats.get("pierce", 0.0)) > 0.0:
				dmg = int(dmg * 1.2)   # 破甲獠牙: 怪物无护甲 → 折算 +20% 伤害
			dmg = maxi(dmg - 2, 1)
			if _player_frozen:
				dmg = maxi(int(dmg * 0.5), 1)   # 冰冻: 伤害减半后解除
				_player_frozen = false
				evs.append({"who": "p", "kind": "chilled", "v": 0})
			if str(enemy.get("intent", "")) == "charge":
				dmg = int(dmg * 1.5)   # 蓄力回合: 承伤 +50%
			enemy["hp"] = int(enemy["hp"]) - dmg
			fury = mini(fury + _fury_gain(12), 100)
			evs.append({"who": "p", "kind": "crit" if crit else "dmg", "v": dmg})
			if hits == 5:
				_combo_crit_next = true   # 里程碑: 下一击必暴
				evs.append({"who": "p", "kind": "milestone", "v": 5})
			if hits == 8:
				fury = mini(fury + _fury_gain(30), 100)
				evs.append({"who": "p", "kind": "milestone", "v": 8})
			if hits >= 2:
				evs.append({"who": "p", "kind": "combo", "v": hits})
			_vamp_heal(evs, dmg)
		"skill":
			# 技能差异化(基础 16+club×4 已高于普攻 15+spade×4):
			# 烈焰=高伤+点燃两跳; 冰霜=中伤+冻结敌方输出; 圣光=低伤+高回复+怒气
			var kind_name := str(stats.get("skill_kind", "fire"))
			var mul := 1.5 if kind_name == "fire" \
					else (1.0 if kind_name == "frost" else 0.8)
			var dmg := maxi(int(float(stats["skill"]) * mul
					* rng.randf_range(0.9, 1.2)), 1)
			if str(enemy.get("intent", "")) == "charge":
				dmg = int(dmg * 1.5)   # 蓄力回合: 承伤 +50%
			enemy["hp"] = int(enemy["hp"]) - dmg
			match kind_name:
				"frost":
					enemy["chilled"] = true
					evs.append({"who": "e", "kind": "chilled", "v": 0})
					fury = mini(fury + _fury_gain(5), 100)
				"light":
					var hl := maxi(int(dmg * 0.4), 1)
					hp = mini(hp + hl, int(stats["max_hp"]))
					evs.append({"who": "p", "kind": "heal", "v": hl})
					fury = mini(fury + _fury_gain(10), 100)
				"fire":
					# 点燃: 敌方回合开始灼烧, 共 2 跳
					_enemy_burn_turns = 2
					_enemy_burn_dmg = maxi(int(float(stats["skill"]) * 0.22), 1)
					evs.append({"who": "e", "kind": "ignite", "v": _enemy_burn_dmg})
			evs.append({"who": "p", "kind": "skill", "v": dmg,
					"skill_kind": kind_name})
			_vamp_heal(evs, dmg)
			hits = mini(hits + 1, _hits_cap())
			fury = mini(fury + _fury_gain(8), 100)
			if hits >= 2:
				evs.append({"who": "p", "kind": "combo", "v": hits})
			_skill_cd = 1 if specials.has(9) else 2
		"defend":
			hits = 0   # 防御打断连击(攻与守的取舍)
			_guarding = true   # 格挡: 本回合受击减免 80%
			var heal := maxi(int(stats["max_hp"]) / 25, 3)
			hp = mini(hp + heal, int(stats["max_hp"]))
			if specials.has(16):   # 铁壁符: 护盾 + 怒气
				shield += maxi(int(int(stats["max_hp"]) * 0.10), 2)
				fury = mini(fury + _fury_gain(10), 100)
			evs.append({"who": "p", "kind": "defend", "v": heal})
		"ult":
			# 奥义: 2.5 倍攻击必中 + 回复 20% 生命, 怒气清零
			var udmg := maxi(int(float(stats["atk"]) * 2.5), 1)
			enemy["hp"] = int(enemy["hp"]) - udmg
			fury = 0
			hits = mini(hits + 1, _hits_cap())
			var uhl := maxi(int(int(stats["max_hp"]) * 0.2), 1)
			hp = mini(hp + uhl, int(stats["max_hp"]))
			evs.append({"who": "p", "kind": "ult", "v": udmg})
			evs.append({"who": "p", "kind": "heal", "v": uhl})
			_vamp_heal(evs, udmg)
	# 顺子: 每 3 回合追加一次普攻
	if action != "defend" and action != "ult" and bool(stats.get("straight", false)) \
			and _battle_round % 3 == 0 and int(enemy["hp"]) > 0:
		var dmg2 := maxi(int(float(stats["atk"]) * 0.7), 1)
		if str(enemy.get("intent", "")) == "charge":
			dmg2 = int(dmg2 * 1.5)   # 蓄力回合: 承伤 +50%
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
	# 蓄力回合: 不进行普通攻击(玩家伤害处放大 +50%), 回合末释放组别必杀技
	if str(enemy.get("intent", "attack")) == "charge":
		_cast_boss_special(evs)
		_choose_intent()
		return evs
	# 敌方点燃(烈焰技能): 敌方回合开始灼烧
	if _enemy_burn_turns > 0:
		_enemy_burn_turns -= 1
		enemy["hp"] = int(enemy["hp"]) - _enemy_burn_dmg
		evs.append({"who": "e", "kind": "burn_e", "v": _enemy_burn_dmg})
		if int(enemy["hp"]) <= 0:
			enemy["hp"] = 0
			evs.append({"who": "e", "kind": "die", "v": 0})
			_win_round()
			return evs
	# 不确定性事件: 12% 概率场上突发状况(好运/坏运都有)
	_roll_uncertainty(evs)
	# 怪物按意图行动(踉跄事件的当回合不出手)
	if not bool(enemy.get("slipped", false)):
		_enemy_act(action, str(enemy.get("intent", "attack")), evs)
	enemy.erase("slipped")
	_guarding = false
	_choose_intent()
	return evs


## 连击上限(狂暴之眼 16 / 常规 11)
func _hits_cap() -> int:
	return 16 if specials.has(8) else 11


## 不确定性事件池: 敌人踉跄 / 怒气涌动 / 星辰祝福 / 灵感风暴
func _roll_uncertainty(evs: Array) -> void:
	if rng.randf() >= 0.12:
		return
	match rng.randi() % 4:
		0:
			enemy["slipped"] = true
			evs.append({"who": "e", "kind": "slip", "v": 0})
			_log(tr("意外! %s 踉跄了一下, 本回合无法出手!") % str(enemy["name"]))
		1:
			var gain := _fury_gain(20)
			fury = mini(fury + gain, 100)
			evs.append({"who": "p", "kind": "surge", "v": gain})
			_log(tr("战意涌动! 怒气 +%d") % gain)
		2:
			var hl := maxi(int(int(stats["max_hp"]) * 0.08), 2)
			hp = mini(hp + hl, int(stats["max_hp"]))
			evs.append({"who": "p", "kind": "heal", "v": hl})
			_log(tr("星辰祝福! 回复 %d 生命") % hl)
		3:
			_combo_crit_next = true
			evs.append({"who": "p", "kind": "storm", "v": 0})
			_log(tr("灵感风暴! 下一击必定暴击!"))


## 敌方回合行动: 出手 / 被四叶草闪避 / 命中(格挡减 80%) / 法术被魔镜反弹
func _enemy_act(action: String, intent: String, evs: Array) -> void:
	var heavy: bool = intent == "heavy"
	var spell: bool = intent == "spell"
	# 四叶草闪避: 物理攻击可被玩家躲开(法术必中)
	if not spell and rng.randf() < float(stats.get("evade", 0.0)):
		evs.append({"who": "p", "kind": "evade", "v": 0})
		_log(tr("好险! 你闪开了 %s 的攻击!") % str(enemy["name"]))
		return
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
		fury = mini(fury + _fury_gain(25), 100)
		evs.append({"who": "p", "kind": "parry", "v": counter})
		if int(enemy["hp"]) <= 0:
			enemy["hp"] = 0
			evs.append({"who": "e", "kind": "die", "v": 0})
			_win_round()
		return
	if _guarding:
		edmg = int(edmg * 0.2)   # 格挡: 减免 80% 伤害
	if bool(enemy.get("chilled", false)):
		edmg = maxi(int(edmg * 0.8), 1)
		enemy["chilled"] = false
	edmg = maxi(edmg, 1)
	_round_dmg_taken += edmg
	_damage_player(edmg)
	fury = mini(fury + _fury_gain(8), 100)
	evs.append({"who": "e", "kind": "spell" if spell else ("heavy" if heavy else "dmg"),
			"v": edmg})
	# 魔镜: 反弹法术伤害 40%
	if spell and float(stats.get("mirror", 0.0)) > 0.0 \
			and int(enemy["hp"]) > 0:
		var back := maxi(int(edmg * float(stats["mirror"])), 1)
		enemy["hp"] = int(enemy["hp"]) - back
		evs.append({"who": "e", "kind": "thorns", "v": back})
		if int(enemy["hp"]) <= 0:
			enemy["hp"] = 0
			evs.append({"who": "e", "kind": "die", "v": 0})
			_win_round()
			return
	# 荆棘: 反弹物理伤害 30%
	if not spell and float(stats.get("thorns", 0.0)) > 0.0 \
			and int(enemy["hp"]) > 0:
		var back2 := maxi(int(edmg * float(stats["thorns"])), 1)
		enemy["hp"] = int(enemy["hp"]) - back2
		evs.append({"who": "e", "kind": "thorns", "v": back2})
		if int(enemy["hp"]) <= 0:
			enemy["hp"] = 0
			evs.append({"who": "e", "kind": "die", "v": 0})
			_win_round()


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
	total_cleared += 1
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
		total_bosses += 1
		cleared_ever = true
		_log(tr("BOSS 击破! 可继续下一层!"))
	else:
		_log(tr("%s 被击破! 回复 %d 生命") % [str(enemy["name"]), heal])


## round_end 展示完毕后由 UI 调用 → 下一回合
## 进入下一层: 全状态重置
func start_next_floor() -> void:
	floor_num += 1
	round_num = 1
	cleared = 0
	run_won = false
	slots.clear()
	specials.clear()
	specials_left = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
	deck.clear()
	for i in 52:
		deck.append(i)
	_shuffle(deck)
	hits = 0
	fury = 0
	rare_count = 0
	combo = {}
	shield = 0
	last_rank = ""
	_skill_cd = 0
	_battle_round = 0
	_first_used = false
	_guarding = false
	_enemy_burn_turns = 0
	_enemy_burn_dmg = 0
	_refresh_stats()
	hp = int(stats["max_hp"])
	group = (group + 1 + rng.randi() % (GROUPS.size() - 1)) % GROUPS.size()
	enemy = {}
	log_lines.clear()
	_open_round()
	_log(tr("第 %d 层开始 — %s 地下城") % [floor_num, str(GROUPS[group]["name"])])


func advance_round() -> void:
	if phase != "round_end":
		return
	if round_num >= ROUNDS:
		return   # R5 通关: 引擎停在 round_end 等 UI 调 start_next_floor
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
	var spade_cnt := _suit_count(cards, 0)
	var heart_cnt := _suit_count(cards, 1)
	var dia_cnt := _suit_count(cards, 2)
	var club_cnt := _suit_count(cards, 3)
	# 单张小加成: 每张牌按点数提供少量属性(点数 3..15 → 力量 1..13)
	var rank_sum := 0
	for c in cards:
		rank_sum += maxi(CardsGd.value(int(c)) - 2, 0)
	var atk := 15 + spade_cnt * 4 + int(rank_sum * 0.6)
	var def := 4 + dia_cnt * 3 + int(rank_sum * 0.4)
	var mres := 3 + dia_cnt * 3 + int(rank_sum * 0.4)
	# 技能基础(16+club×4)高于普攻(15+spade×4): 修复"技能伤害比普攻还低"的失衡;
	# 威力靠技能种类倍率与特效区分(烈焰高伤点燃 / 冰霜冻结 / 圣光回复)
	var skill := 16 + club_cnt * 4 + int(rank_sum * 0.55)
	var max_hp := 100 + heart_cnt * 5 + int(rank_sum * 3)
	var tier := str(combo["tier"])
	match tier:
		"straight_flush":
			atk = int(atk * 1.9)
			def = int(def * 1.9)
			mres = int(mres * 1.9)
			max_hp = int(max_hp * 1.9)
			skill = int(skill * 1.9)
		"quad":
			atk = int(atk * 2.0)
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
		"full_house":
			atk = int(atk * 1.3)
			def = int(def * 1.3)
			mres = int(mres * 1.3)
			max_hp = int(max_hp * 1.3)
			skill = int(skill * 1.3)
		"trips":
			atk = int(atk * 1.55)
		"two_pair":
			def = int(def * 1.6)
			mres = int(mres * 1.6)
		"pair":
			atk = int(atk * 1.25)
			def = int(def * 1.25)
			mres = int(mres * 1.25)
			max_hp = int(max_hp * 1.25)
			skill = int(skill * 1.25)
	# 集满五张 = 变身: 全属性 +5%(变身演出由 UI 播放)
	if cards.size() >= 5:
		atk = int(atk * 1.05)
		def = int(def * 1.05)
		mres = int(mres * 1.05)
		skill = int(skill * 1.05)
		max_hp = int(max_hp * 1.05)
	return {
		"atk": atk, "def": def, "mres": mres, "skill": skill,
		"max_hp": max_hp,
		"transformed": cards.size() >= 5,
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
