## 格斗模式纯逻辑(无尽试炼): 抽牌 / 牌型判定 / 属性推导 / 敌人生成 / 回合解析。
## 与渲染完全解耦 — 桌面 UI(fight_panel) 只读状态与调 step(), 可零依赖单测。
class_name FightMode
extends RefCounted

const CardsGd = preload("res://src/rules/cards.gd")

## 牌型层级(大→小)与加成
const TIERS := {
	"straight_flush": {"name": "同花顺", "desc": "全属性+60%, 必定先攻"},
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

var floor_num := 1        # 当前层(无尽)
var hp := 0               # 当前生命
var hand: Array = []      # 已装备 5 张牌(id 0..51)
var combo := {}           # 牌型判定结果
var stats := {}           # 派生属性
var enemy := {}           # 当前敌人 {name, glyph, hp, max_hp, atk, is_boss}
var rng := RandomNumberGenerator.new()
var _skill_cd := 0        # 技能冷却(回合)
var _round_no := 0        # 本场战斗回合数
var log_lines: Array = [] # 战斗播报(最近若干条)


func _init(seed_v: int = -1) -> void:
	if seed_v < 0:
		seed_v = int(Time.get_unix_time_from_system() * 1000.0) % 1000000007
	rng.seed = seed_v


## ── 抽牌: 每关从 8 张候选中选 5 张 ──
func draw_candidates(n: int = 8) -> Array:
	var deck := []
	for i in 52:
		deck.append(i)
	deck.shuffle()
	return deck.slice(0, mini(n, deck.size()))


func equip(cards: Array) -> void:
	hand = (cards as Array).slice(0, 5)
	combo = evaluate_combo(hand)
	stats = derive_stats(hand, combo, floor_num)
	_apply_blessings(stats)
	hp = int(stats["max_hp"])
	_skill_cd = 0
	_round_no = 0
	_log("第 %d 层: 属性就绪 — HP %d / 物攻 %d / 护甲 %d / 技能 %d (%s)" % [
		floor_num, hp, int(stats["atk"]), int(stats["def"]),
		int(stats["skill"]), str(combo["name"])])


## 获得祝福: 记录并立即叠加到当前属性(生命祝福同时回补差值)
func add_blessing(id: String) -> void:
	blessings.append(id)
	_apply_blessings(stats)
	if id == "b_hp":
		hp = mini(hp + int(int(stats["max_hp"]) * 0.3), int(stats["max_hp"]))
	if id == "b_regen":
		pass  # 回合开始时生效
	_log("获得祝福: %s" % str(BLESSINGS.filter(
			func(b: Dictionary) -> bool: return str(b["id"]) == id)[0]["name"]))


## 祝福叠加到属性(乘区/加区)
func _apply_blessings(st: Dictionary) -> void:
	var n := {}
	for b in blessings:
		n[b] = int(n.get(b, 0)) + 1
	st["atk"] = int(int(st["atk"]) * (1.0 + 0.25 * int(n.get("b_atk", 0))))
	st["def"] = int(int(st["def"]) * (1.0 + 0.30 * int(n.get("b_def", 0))))
	st["mres"] = int(int(st["mres"]) * (1.0 + 0.30 * int(n.get("b_def", 0))))
	st["max_hp"] = int(int(st["max_hp"]) * (1.0 + 0.30 * int(n.get("b_hp", 0))))
	st["crit_rate"] = float(st["crit_rate"]) + 0.12 * int(n.get("b_crit", 0))
	st["crit_dmg"] = float(st["crit_dmg"]) + 0.5 * int(n.get("b_cdmg", 0))
	st["vamp"] = float(st.get("vamp", 0.0)) + 0.15 * int(n.get("b_vamp", 0))
	st["skill"] = int(int(st["skill"]) * (1.0 + 0.40 * int(n.get("b_skill", 0))))
	st["skill_cd_fast"] = n.get("b_skill", 0) > 0
	st["regen"] = n.get("b_regen", 0) > 0


## 通关三选一: 随机抽 3 个不同祝福
func roll_blessings() -> Array:
	var pool: Array = BLESSINGS.duplicate()
	pool.shuffle()
	return pool.slice(0, 3)


## ── 牌型判定: 标准 5 张扑克(不含王) ──
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
	var flush: bool = uniq_suits(suits) == 1
	var straight: bool = uniq.size() == 5 \
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
	elif shape == [1, 2, 2]:
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


## ── 属性推导: ♠物攻/♦护甲魔抗/♥生命/♣技能 + 牌型加成 + 层数成长 ──
static func derive_stats(cards: Array, combo: Dictionary, floor_num: int) -> Dictionary:
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
			3:
				club += v
	var spade_cnt := _suit_count(cards, 0)
	var tier := str(combo["tier"])
	var grow := 1.0 + 0.15 * (floor_num - 1)   # 玩家随层数成长
	var atk := spade * 6
	var def := dia * 3
	var mres := dia * 2
	var skill := club * 10
	var max_hp := 100 + heart * 25
	match tier:
		"straight_flush":
			atk *= 1.6
			def *= 1.6
			mres *= 1.6
			max_hp *= 1.6
			skill *= 1.6
		"quad":
			atk *= 1.8
		"flush":
			if spade_cnt >= 3:
				atk *= 2.0
			elif _suit_count(cards, 1) >= 3:
				max_hp *= 1.8
			elif _suit_count(cards, 2) >= 3:
				def *= 2.0
				mres *= 2.0
			else:
				skill *= 2.0
		"full_house":
			pass  # 吸血在结算时按 tier 生效
		"trips":
			atk *= 1.4
		"two_pair":
			def *= 1.5
			mres *= 1.5
		"pair":
			atk *= 1.15
			def *= 1.15
			mres *= 1.15
			max_hp *= 1.15
			skill *= 1.15
	var club_cnt := _suit_count(cards, 3)
	return {
		"atk": int(atk * grow), "def": int(def * grow),
		"mres": int(mres * grow), "skill": int(skill * grow),
		"max_hp": int(max_hp * grow),
		"crit_rate": 0.10 + 0.05 * spade_cnt,          # ♠ 张数 → 暴击率
		"crit_dmg": 1.5 + 0.1 * spade_cnt,             # ♠ 张数 → 爆伤
		"vamp": 0.25 if tier == "full_house" else 0.0, # 葫芦吸血
		"combo_tier": tier,
		"straight": tier == "straight",                # 顺子: 每 3 回合连击
		"club_cnt": club_cnt,
		# ♣ 张数决定技能流派: 1=火球(纯伤) 2=冰霜(伤害+减速) ≥3=圣光(伤害+回血)
		"skill_kind": "fire" if club_cnt <= 1 else ("frost" if club_cnt == 2 else "light"),
	}


static func _suit_count(cards: Array, suit: int) -> int:
	var n := 0
	for c in cards:
		if CardsGd.suit(int(c)) == suit:
			n += 1
	return n


## ── 敌人生成: 每层 小怪 → Boss, 层数越深越强 ──
const MOB_NAMES := [["绿史莱姆", "🟢"], ["洞穴蝙蝠", "🦇"],
		["骷髅兵", "☠️"], ["毒蜘蛛", "🕷️"]]
const BOSS_NAMES := [["史莱姆之王", "👑"], ["蝙蝠伯爵", "🧛"],
		["骸骨将军", "💀"], ["深渊蜘蛛后", "🕸️"], ["炎魔领主", "👹"],
		["远古龙王", "🐉"]]

func spawn_enemy(is_boss: bool) -> void:
	var scale := pow(1.25, floor_num - 1)
	var base_hp := (70.0 if is_boss else 42.0) * scale
	var base_atk := (16.0 if is_boss else 10.0) * scale
	var elite := not is_boss and floor_num % 3 == 0   # 每 3 层小怪为精英
	if elite:
		base_hp *= 1.6
		base_atk *= 1.35
	if is_boss:
		base_hp *= 1.5
		base_atk *= 1.2
	var pool: Array = BOSS_NAMES if is_boss else MOB_NAMES
	var pick: Array = pool[rng.randi() % pool.size()]
	var affix := ""
	if elite:
		affix = ["rage", "iron", "vamp"][rng.randi() % 3]
	elif is_boss and floor_num >= 4:
		affix = ["rage", "iron", "vamp"][rng.randi() % 3]
	var name_txt := str(pick[0])
	if affix != "":
		name_txt = "「%s」%s" % [AFFIX_NAMES[affix], name_txt]
	if elite:
		name_txt = "精英·" + name_txt
	enemy = {
		"name": name_txt, "glyph": str(pick[1]), "is_boss": is_boss,
		"elite": elite, "affix": affix,
		"hp": int(base_hp), "max_hp": int(base_hp),
		"atk": int(base_atk),
		"intent": "attack",
		"magic": is_boss and rng.randf() < 0.5,   # Boss 半数带法术攻击(打魔抗)
	}
	choose_intent()
	_round_num = 0
	_log("%s出现! HP %d / 攻击 %d" % [name_txt, enemy["hp"], enemy["atk"]])


## 怪物意图: 事先定好下一手, 玩家可据此选择攻/防
func choose_intent() -> void:
	var r := rng.randf()
	if r < 0.3:
		enemy["intent"] = "heavy"
	elif r < 0.45 and bool(enemy.get("magic", false)):
		enemy["intent"] = "spell"
	else:
		enemy["intent"] = "attack"


## 每层推进: 小怪 → Boss
func next_encounter() -> String:
	spawn_enemy(_stage == "boss")
	return _stage


## 祝福目录(通关后三选一, 可叠加): apply 在属性推导后叠加
const BLESSINGS := [
	{"id": "b_atk", "name": "攻击祝福", "desc": "物攻 +25%"},
	{"id": "b_def", "name": "铁壁祝福", "desc": "护甲/魔抗 +30%"},
	{"id": "b_hp", "name": "生命祝福", "desc": "生命上限 +30%"},
	{"id": "b_crit", "name": "精准祝福", "desc": "暴击率 +12%"},
	{"id": "b_cdmg", "name": "重伤祝福", "desc": "暴击伤害 +50%"},
	{"id": "b_vamp", "name": "嗜血祝福", "desc": "吸血 +15%"},
	{"id": "b_skill", "name": "灵韵祝福", "desc": "技能伤害 +40%, 冷却 -1"},
	{"id": "b_regen", "name": "恢复祝福", "desc": "每回合开始回复 4% 生命"},
]
const AFFIX_NAMES := {"rage": "狂暴", "iron": "铁壁", "vamp": "嗜血"}

var _stage := "mob"        # mob → boss → clear(进下一层)
var blessings: Array = []  # 已获祝福 id(可叠加)
var _round_num := 0        # 当前战斗回合(狂暴词缀用)


## 进入新层: 返回候选牌(8 张), 由 UI 选 5 张后 equip()
func next_floor() -> Array:
	floor_num += 1
	_stage = "mob"
	return draw_candidates(8)


## ── 战斗回合: action ∈ {"attack","skill","defend"} ──
## 返回事件列表供 UI 播放: {who:"p"/"e", kind:"dmg"/"heal"/"miss"/"crit"/"defend", v:int}
func step(action: String) -> Array:
	var evs: Array = []
	if _stage == "boss" and enemy.is_empty():
		return evs
	_round_no += 1
	_round_num = _round_no
	if _skill_cd > 0:
		_skill_cd -= 1
	# 恢复祝福: 回合开始回血
	if bool(stats.get("regen", false)) and hp < int(stats["max_hp"]):
		var rg := maxi(int(int(stats["max_hp"]) * 0.04), 2)
		hp = mini(hp + rg, int(stats["max_hp"]))
		evs.append({"who": "p", "kind": "heal", "v": rg})
	# 玩家行动
	match action:
		"attack":
			var crit: bool = rng.randf() < float(stats["crit_rate"])
			var dmg := int(float(stats["atk"]) * rng.randf_range(0.9, 1.1))
			if crit:
				dmg = int(dmg * float(stats["crit_dmg"]))
			dmg = maxi(dmg - 2, 1)
			if str(enemy.get("affix", "")) == "iron":
				dmg = maxi(int(dmg * 0.75), 1)
			enemy["hp"] = int(enemy["hp"]) - dmg
			evs.append({"who": "p", "kind": "crit" if crit else "dmg", "v": dmg})
			_vamp_heal(evs, dmg)
		"skill":
			var dmg := int(float(stats["skill"]) * rng.randf_range(0.9, 1.2))
			dmg = maxi(dmg - 1, 1)
			if str(enemy.get("affix", "")) == "iron":
				dmg = maxi(int(dmg * 0.75), 1)
			enemy["hp"] = int(enemy["hp"]) - dmg
			var kind_name := str(stats.get("skill_kind", "fire"))
			match kind_name:
				"frost":  # 冰霜: 附带减速(敌下一手伤害 -20%)
					enemy["chilled"] = true
					evs.append({"who": "e", "kind": "chilled", "v": 0})
				"light":  # 圣光: 附带回血(技能值的 30%)
					var hl := maxi(int(dmg * 0.3), 1)
					hp = mini(hp + hl, int(stats["max_hp"]))
					evs.append({"who": "p", "kind": "heal", "v": hl})
			evs.append({"who": "p", "kind": "skill", "v": dmg,
					"skill_kind": kind_name})
			_skill_cd = 1 if bool(stats.get("skill_cd_fast", false)) else 2
		"defend":
			var heal := maxi(int(stats["max_hp"]) / 25, 3)
			hp = mini(hp + heal, int(stats["max_hp"]))
			evs.append({"who": "p", "kind": "defend", "v": heal})
	# 顺子: 每 3 回合追加一次普攻
	if action != "defend" and bool(stats.get("straight", false)) \
			and _round_no % 3 == 0 and int(enemy["hp"]) > 0:
		var dmg2 := maxi(int(float(stats["atk"]) * 0.7), 1)
		enemy["hp"] = int(enemy["hp"]) - dmg2
		evs.append({"who": "p", "kind": "dmg", "v": dmg2})
		_vamp_heal(evs, dmg2)
	# 敌人亡 → 本场胜利
	if int(enemy["hp"]) <= 0:
		enemy["hp"] = 0
		evs.append({"who": "e", "kind": "die", "v": 0})
		return evs
	# 敌人按意图行动(意图上一回合末已公示); 狂暴词缀每回合 +12% 攻
	var intent := str(enemy.get("intent", "attack"))
	var heavy: bool = intent == "heavy"
	var spell: bool = intent == "spell"
	var rage_mul: float = 1.0 + 0.12 * _round_no 			if str(enemy.get("affix", "")) == "rage" else 1.0
	var edmg := int(float(enemy["atk"]) * rage_mul
			* (1.6 if heavy else (1.1 if spell else 1.0))
			* rng.randf_range(0.9, 1.1))
	if spell:
		edmg = maxi(edmg - int(float(stats["mres"]) * 0.6), 1)  # 法术打魔抗
	else:
		edmg = maxi(edmg - _player_mit(), 1)                     # 物理打护甲
	if action == "defend":
		edmg = int(edmg * 0.4)
	if bool(enemy.get("chilled", false)):
		edmg = maxi(int(edmg * 0.8), 1)
		enemy["chilled"] = false
	edmg = maxi(edmg, 1)
	hp -= edmg
	evs.append({"who": "e", "kind": "spell" if spell else ("heavy" if heavy else "dmg"),
			"v": edmg})
	# 嗜血词缀: 按造成的伤害回血
	if str(enemy.get("affix", "")) == "vamp":
		enemy["hp"] = mini(int(enemy["hp"]) + int(edmg * 0.3), int(enemy["max_hp"]))
	# 选定下一手意图并公示
	choose_intent()
	# 连击: 顺子玩家死亡判定后不再追击 ✓(顺序已保证)
	return evs


func _vamp_heal(evs: Array, dmg: int) -> void:
	if float(stats.get("vamp", 0.0)) > 0.0:
		var heal := int(dmg * float(stats["vamp"]))
		if heal > 0:
			hp = mini(hp + heal, int(stats["max_hp"]))
			evs.append({"who": "p", "kind": "heal", "v": heal})


func _player_mit() -> int:
	# 减伤公式: DEF/(DEF+60) 比例减免 → 取整为固定减免值
	var def := float(stats["def"])
	return int(def * 60.0 / (def + 60.0))


## 战斗阶段推进: 当前敌人死亡 → boss?层通关 : 打 boss
func encounter_cleared() -> bool:
	return enemy.is_empty() or int(enemy["hp"]) <= 0


func player_dead() -> bool:
	return hp <= 0


## 敌人全清 → 进入下一层的准备(层数+1 在 UI 确认后调 next_floor)
func stage_label() -> String:
	return "Boss战" if _stage == "boss" else "小怪战"


func advance_stage() -> void:
	if _stage == "mob":
		_stage = "boss"
	elif _stage == "boss":
		_stage = "clear"


func all_stages_cleared() -> bool:
	return _stage == "clear"


func log_line(text: String) -> void:
	log_lines.append(text)
	while log_lines.size() > 6:
		log_lines.pop_front()


func _log(text: String) -> void:
	log_line(text)
