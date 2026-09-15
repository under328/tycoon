## 联机格斗对战(1v1)纯规则: 两人从同一候选池各选 5 张牌 → 派生属性 →
## 回合制互殴。先手 = 牌型层级更强一方(平级则先座者)。
## 规则复用格斗试炼的属性推导/牌型判定(FightMode), 与网络/渲染完全解耦。
class_name FightPvp
extends RefCounted

const FightGd = preload("res://src/rules/fight/fight_mode.gd")

const CANDIDATE_N := 10   # 候选牌数(两人同池)
const PICK_N := 5         # 每人装备数
const TURN_SECONDS := 20  # 回合限时(超时服务器托管"攻击")
const PICK_SECONDS := 30  # 选牌限时


## 服务器掷候选池(确定性: 同 seed 同结果, 便于回放/测试)
static func roll_candidates(rng: RandomNumberGenerator) -> Array:
	var deck := []
	for i in 52:
		deck.append(i)
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
	return deck.slice(0, CANDIDATE_N)


static func new_state(candidates: Array, fighters: Array,
		names: Dictionary) -> Dictionary:
	return {
		"phase": "pick",                    # pick → battle → over
		"candidates": (candidates as Array).slice(0, CANDIDATE_N),
		"fighters": (fighters as Array).duplicate(),
		"names": names.duplicate(true),     # {seat: 名字} 仅格斗者
		"picks": {},                        # seat → [5 张]
		"hp": {}, "max_hp": {}, "stats": {}, "combo": {},
		"guard": {},                        # 防御姿态(受击后清除)
		"chilled": {},                      # 冰霜减速(下次出手 -20%)
		"skill_cd": {},
		"turn": -1,
		"round_no": 0,
		"winner": -1,
		"log": [],
	}


static func is_fighter(st: Dictionary, seat: int) -> bool:
	return (st["fighters"] as Array).has(seat)


static func foe_of(st: Dictionary, seat: int) -> int:
	var f: Array = st["fighters"]
	return int(f[0]) if int(f[1]) == seat else int(f[1])


## 选牌校验: 仅格斗者 / 未选过 / 恰好 5 张 / 全部在候选内且不重复。
static func apply_pick(st: Dictionary, seat: int, cards: Array) -> Dictionary:
	if str(st["phase"]) != "pick":
		return {"ok": false, "error": "not_pick"}
	if not is_fighter(st, seat):
		return {"ok": false, "error": "not_fighter"}
	if (st["picks"] as Dictionary).has(seat):
		return {"ok": false, "error": "already_picked"}
	if (cards as Array).size() != PICK_N:
		return {"ok": false, "error": "need_5"}
	var cands: Array = st["candidates"]
	var clean := []
	for c in cards:
		var id := int(c)
		if not cands.has(id) or clean.has(id):
			return {"ok": false, "error": "bad_cards"}
		clean.append(id)
	st["picks"][seat] = clean
	if (st["picks"] as Dictionary).size() >= 2:
		_begin_battle(st)
	return {"ok": true, "error": ""}


## 双方选毕 → 派生属性并定先手(牌型强者; 平级先座者)
static func _begin_battle(st: Dictionary) -> void:
	for seat in st["fighters"]:
		var hand: Array = st["picks"][seat]
		var combo: Dictionary = FightGd.evaluate_combo(hand)
		var stats: Dictionary = FightGd.derive_stats(hand, combo, 1)
		st["combo"][seat] = combo
		st["stats"][seat] = stats
		st["max_hp"][seat] = int(stats["max_hp"])
		st["hp"][seat] = int(stats["max_hp"])
		st["guard"][seat] = false
		st["chilled"][seat] = false
		st["skill_cd"][seat] = 0
	var fa: int = st["fighters"][0]
	var fb: int = st["fighters"][1]
	var ra: int = FightGd.TIER_RANK.find(str(st["combo"][fa]["tier"]))
	var rb: int = FightGd.TIER_RANK.find(str(st["combo"][fb]["tier"]))
	st["turn"] = fa if ra <= rb else fb
	st["phase"] = "battle"
	_log(st, "%s(%s) VS %s(%s) — %s 先攻!" % [
		st["names"][fa], str(st["combo"][fa]["name"]),
		st["names"][fb], str(st["combo"][fb]["name"]),
		st["names"][int(st["turn"])]])


## 行动: attack / skill / defend。返回 {ok, error, events}。
## events: {who:行动方座位, target:受方座位, kind:dmg/crit/skill/heal/defend/chill, v:int}
static func apply_action(st: Dictionary, seat: int, action: String,
		rng: RandomNumberGenerator) -> Dictionary:
	if str(st["phase"]) != "battle":
		return {"ok": false, "error": "not_battle", "events": []}
	if not is_fighter(st, seat):
		return {"ok": false, "error": "not_fighter", "events": []}
	if int(st["turn"]) != seat:
		return {"ok": false, "error": "not_turn", "events": []}
	if not action in ["attack", "skill", "defend"]:
		return {"ok": false, "error": "bad_action", "events": []}
	if action == "skill" and int(st["skill_cd"][seat]) > 0:
		return {"ok": false, "error": "skill_cd", "events": []}
	var foe := foe_of(st, seat)
	var evs := _resolve(st, seat, foe, action, rng)
	_log_action(st, seat, foe, action, evs)
	if int(st["hp"][foe]) <= 0:
		st["hp"][foe] = 0
		st["phase"] = "over"
		st["winner"] = seat
		_log(st, "★ %s 击倒 %s — 获胜!" % [st["names"][seat], st["names"][foe]])
	else:
		st["turn"] = foe
		st["round_no"] = int(st["round_no"]) + 1
	return {"ok": true, "error": "", "events": evs}


## 一回合结算: 行动方出手 → 顺子追击 → (受方存活时)轮转到受方
static func _resolve(st: Dictionary, actor: int, foe: int, action: String,
		rng: RandomNumberGenerator) -> Array:
	var evs: Array = []
	var a: Dictionary = st["stats"][actor]
	var f: Dictionary = st["stats"][foe]
	# 行动方技能冷却流动(出手时 -1, 用技能后置 2)
	if action != "skill" and int(st["skill_cd"][actor]) > 0:
		st["skill_cd"][actor] = int(st["skill_cd"][actor]) - 1
	var guard_on: bool = bool(st["guard"][foe])   # 上回合防御 → 减伤
	st["guard"][foe] = false
	match action:
		"attack":
			var dmg := int(float(a["atk"]) * rng.randf_range(0.9, 1.1))
			var crit: bool = rng.randf() < float(a["crit_rate"])
			if crit:
				dmg = int(dmg * float(a["crit_dmg"]))
			dmg = _hit(st, actor, foe, dmg, _mitigate(int(f["def"])), guard_on)
			evs.append(_ev(actor, foe, "crit" if crit else "dmg", dmg))
			_vamp(st, actor, dmg, evs)
		"skill":
			var dmg := int(float(a["skill"]) * rng.randf_range(0.9, 1.2))
			var kind := str(a.get("skill_kind", "fire"))
			match kind:
				"frost":
					dmg = int(dmg * 0.85)
				"light":
					dmg = int(dmg * 0.75)
			dmg = _hit(st, actor, foe, dmg, int(int(f["mres"]) * 0.6), guard_on)
			match kind:
				"frost":
					st["chilled"][foe] = true
					evs.append(_ev(actor, foe, "chill", 0))
				"light":
					var hl := maxi(int(dmg * 0.3), 1)
					st["hp"][actor] = mini(int(st["hp"][actor]) + hl,
							int(st["max_hp"][actor]))
					evs.append(_ev(actor, actor, "heal", hl))
			evs.append(_ev(actor, foe, "skill", dmg))
			_vamp(st, actor, dmg, evs)
			st["skill_cd"][actor] = 2
		"defend":
			st["guard"][actor] = true
			var heal := maxi(int(st["max_hp"][actor]) / 25, 3)
			st["hp"][actor] = mini(int(st["hp"][actor]) + heal,
					int(st["max_hp"][actor]))
			evs.append(_ev(actor, actor, "defend", heal))
	# 顺子: 每 3 回合追加一次 70% 物攻(追击不打防御中的既减半量, 保持简洁)
	if action != "defend" and bool(a.get("straight", false)) \
			and int(st["round_no"]) % 3 == 2 and int(st["hp"][foe]) > 0:
		var d2 := _hit(st, actor, foe,
				int(float(a["atk"]) * 0.7), _mitigate(int(f["def"])), false)
		evs.append(_ev(actor, foe, "dmg", d2))
		_vamp(st, actor, d2, evs)
	return evs


## 落伤: 冰霜减速(出手方) → 防御减半 → 下限 1, 扣血
static func _hit(st: Dictionary, actor: int, foe: int, dmg: int,
		flat_reduce: int, guard_on: bool) -> int:
	if bool(st["chilled"][actor]):
		dmg = int(dmg * 0.8)
		st["chilled"][actor] = false
	if guard_on:
		dmg = int(dmg * 0.5)
	dmg = maxi(dmg - flat_reduce, 1)
	st["hp"][foe] = int(st["hp"][foe]) - dmg
	return dmg


## 物理减伤(与格斗试炼同式): DEF/(DEF+60) 折算固定减免
static func _mitigate(def: int) -> int:
	return int(float(def) * 60.0 / (float(def) + 60.0))


## 葫芦吸血: 按造成伤害回 25%
static func _vamp(st: Dictionary, actor: int, dmg: int, evs: Array) -> void:
	var a: Dictionary = st["stats"][actor]
	if float(a.get("vamp", 0.0)) > 0.0:
		var heal := int(dmg * float(a["vamp"]))
		if heal > 0:
			st["hp"][actor] = mini(int(st["hp"][actor]) + heal,
					int(st["max_hp"][actor]))
			evs.append(_ev(actor, actor, "heal", heal))


static func _ev(who: int, target: int, kind: String, v: int) -> Dictionary:
	return {"who": who, "target": target, "kind": kind, "v": v}


static func _log(st: Dictionary, text: String) -> void:
	(st["log"] as Array).append(text)
	while (st["log"] as Array).size() > 8:
		(st["log"] as Array).pop_front()


static func _log_action(st: Dictionary, actor: int, foe: int,
		action: String, evs: Array) -> void:
	var an: String = str(st["names"][actor])
	var fn: String = str(st["names"][foe])
	match action:
		"attack":
			var dmg := 0
			var crit := false
			for e in evs:
				if str(e["kind"]) in ["dmg", "crit"]:
					dmg = int(e["v"])
					crit = str(e["kind"]) == "crit"
			_log(st, "%s 攻击 %s — %s%d 伤害" % [an, fn,
					"暴击! " if crit else "", dmg])
		"skill":
			var dmg := 0
			for e in evs:
				if str(e["kind"]) == "skill":
					dmg = int(e["v"])
			var kind := str((st["stats"][actor] as Dictionary)
					.get("skill_kind", "fire"))
			var nm: String = str({"fire": "火球", "frost": "冰霜",
					"light": "圣光"}.get(kind, "技能"))
			_log(st, "%s 释放【%s】— %s 受到 %d 伤害" % [an, nm, fn, dmg])
		"defend":
			_log(st, "%s 摆出防御姿态" % an)


## 按座位裁剪视图(观战者与格斗者同屏信息, 仅 my_pick/操作权不同)。
## 防作弊: pick 阶段不出现已选的具体牌; battle 起装备公开(同池可知)。
static func view(st: Dictionary, my_seat: int) -> Dictionary:
	var fighters: Array = st["fighters"]
	var picks: Dictionary = st["picks"]
	var v := {
		"phase": st["phase"],
		"my_seat": my_seat,
		"fighters": (fighters as Array).duplicate(),
		"spectator": not (fighters as Array).has(my_seat),
		"names": (st["names"] as Dictionary).duplicate(true),
		"picks_done": {},
		"turn": int(st["turn"]),
		"round_no": int(st["round_no"]),
		"winner": int(st["winner"]),
		"log": (st["log"] as Array).duplicate(),
		"my_turn": int(st["turn"]) == my_seat and str(st["phase"]) == "battle",
		"turn_seconds": TURN_SECONDS,
		"pick_seconds": PICK_SECONDS,
		"hp": (st["hp"] as Dictionary).duplicate(),
		"max_hp": (st["max_hp"] as Dictionary).duplicate(),
		"combo": {},
	}
	for seat in fighters:
		v["picks_done"][seat] = picks.has(seat)
	if str(st["phase"]) == "pick":
		v["candidates"] = (st["candidates"] as Array).duplicate()
		v["my_pick"] = (picks.get(my_seat, []) as Array).duplicate()
		v["skill_cd"] = {}
	else:
		v["hands"] = (picks as Dictionary).duplicate(true)  # 战斗阶段公开装备
		v["skill_cd"] = (st["skill_cd"] as Dictionary).duplicate()
		v["skill_kind"] = {}
		v["stats_brief"] = {}
		for seat in fighters:
			var s: Dictionary = st["stats"][seat]
			v["skill_kind"][seat] = str(s.get("skill_kind", "fire"))
			v["stats_brief"][seat] = {
				"atk": int(s["atk"]), "def": int(s["def"]),
				"mres": int(s["mres"]), "skill": int(s["skill"]),
			}
			var c: Dictionary = st["combo"][seat]
			v["combo"][seat] = {"name": str(c["name"]),
					"desc": str(c["desc"]), "tier": str(c["tier"])}
	return v
