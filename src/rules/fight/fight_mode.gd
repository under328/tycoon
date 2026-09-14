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
	hp = int(stats["max_hp"])
	_skill_cd = 0
	_round_no = 0
	_log("第 %d 层: 属性就绪 — HP %d / 物攻 %d / 护甲 %d / 技能 %d (%s)" % [
		floor_num, hp, int(stats["atk"]), int(stats["def"]),
		int(stats["skill"]), str(combo["name"])])


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
	return {
		"atk": int(atk * grow), "def": int(def * grow),
		"mres": int(mres * grow), "skill": int(skill * grow),
		"max_hp": int(max_hp * grow),
		"crit_rate": 0.10 + 0.05 * spade_cnt,          # ♠ 张数 → 暴击率
		"crit_dmg": 1.5 + 0.1 * spade_cnt,             # ♠ 张数 → 爆伤
		"vamp": 0.25 if tier == "full_house" else 0.0, # 葫芦吸血
		"combo_tier": tier,
		"straight": tier == "straight",                # 顺子: 每 3 回合连击
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
	if is_boss:
		base_hp *= 1.5
		base_atk *= 1.2
	var pool: Array = BOSS_NAMES if is_boss else MOB_NAMES
	var pick: Array = pool[rng.randi() % pool.size()]
	enemy = {
		"name": str(pick[0]) + ("" if is_boss else ""),
		"glyph": str(pick[1]), "is_boss": is_boss,
		"hp": int(base_hp), "max_hp": int(base_hp),
		"atk": int(base_atk),
	}
	_round_no = 0
	_log("%s出现! HP %d / 攻击 %d" % [enemy["name"], enemy["hp"], enemy["atk"]])


## 每层推进: 小怪 → Boss
func next_encounter() -> String:
	spawn_enemy(_stage == "boss")
	return _stage


var _stage := "mob"   # mob → boss → clear(进下一层)


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
	if _skill_cd > 0:
		_skill_cd -= 1
	# 玩家行动
	match action:
		"attack":
			var crit: bool = rng.randf() < float(stats["crit_rate"])
			var dmg := int(float(stats["atk"]) * rng.randf_range(0.9, 1.1))
			if crit:
				dmg = int(dmg * float(stats["crit_dmg"]))
			dmg = maxi(dmg - 2, 1)
			enemy["hp"] = int(enemy["hp"]) - dmg
			evs.append({"who": "p", "kind": "crit" if crit else "dmg", "v": dmg})
			_vamp_heal(evs, dmg)
		"skill":
			var dmg := int(float(stats["skill"]) * rng.randf_range(0.9, 1.2))
			dmg = maxi(dmg - 1, 1)
			enemy["hp"] = int(enemy["hp"]) - dmg
			evs.append({"who": "p", "kind": "skill", "v": dmg})
			_skill_cd = 2
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
	# 敌人行动(玩家防御 → 减伤 60%)
	var heavy: bool = rng.randf() < 0.25
	var edmg := int(float(enemy["atk"]) * (1.6 if heavy else 1.0)
			* rng.randf_range(0.9, 1.1))
	if action == "defend":
		edmg = int(edmg * 0.4)
	edmg = maxi(edmg - _player_mit(), 1)
	hp -= edmg
	evs.append({"who": "e", "kind": "heavy" if heavy else "dmg", "v": edmg})
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
