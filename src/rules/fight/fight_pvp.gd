## 联机格斗对战纯规则 v2(回合制): 5 回合, 每回合『二选一』抽牌 → 玩家之间
## 对战(无怪)。先胜 3 回合者获胜。特殊牌(奇物)机制与本地格斗试炼同源
## (复用 FightMode 的属性推导/牌型判定/SPECIALS 目录)。
## 与网络/渲染完全解耦, 服务器权威, 可零依赖单测。
class_name FightPvp
extends RefCounted

const FightGd = preload("res://src/rules/fight/fight_mode.gd")
const CardsGd = preload("res://src/rules/cards.gd")

const ROUNDS := 5
const WIN_SCORE := 3          # 先胜 3 回合获胜(5 回合两日决胜)
const TURN_SECONDS := 20
const PICK_SECONDS := 30


static func is_sp(cand: int) -> bool:
	return cand >= 100


static func sp_of(cand: int) -> int:
	return cand - 100


## 候选抽取(服务器 rng): 25% 特殊牌(未耗尽时), 否则普通牌
static func roll_candidate(st: Dictionary, normal_only: bool,
		rng: RandomNumberGenerator) -> int:
	var left: Array = st["specials_left"]
	if not normal_only and not left.is_empty() and rng.randf() < 0.25:
		var sp: int = left.pop_at(rng.randi() % left.size())
		return 100 + sp
	var deck: Array = st["deck"]
	if deck.is_empty():
		return rng.randi_range(0, 51)
	return deck.pop_at(rng.randi() % deck.size())


static func new_state(fighters: Array, names: Dictionary) -> Dictionary:
	var per := {}
	for seat in fighters:
		per[seat] = {
			"slots": [], "specials": [], "pair": [], "pairs_left": 1,
			"comp": false, "locked": -1, "done": true,
			"pending_main": [], "need_comp": false,
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
		"specials_left": [0, 1, 2, 3, 4, 5, 6, 7],
		"per": per,
		"battle": {},
		"score": {},
		"round_winner": -1,
		"winner": -1,
		"log": [],
	}


static func is_fighter(st: Dictionary, seat: int) -> bool:
	return (st["fighters"] as Array).has(seat)


static func foe_of(st: Dictionary, seat: int) -> int:
	var f: Array = st["fighters"]
	return int(f[0]) if int(f[1]) == seat else int(f[1])


static func _log(st: Dictionary, text: String) -> void:
	(st["log"] as Array).append(text)
	while (st["log"] as Array).size() > 8:
		(st["log"] as Array).pop_front()


## ── 回合开启: 掷双方共同主候选组, 重置各格斗者回合状态 ──
static func open_round(st: Dictionary, rng: RandomNumberGenerator) -> void:
	st["phase"] = "draft"
	st["round_winner"] = -1
	var main := [roll_candidate(st, false, rng), roll_candidate(st, false, rng)]
	for seat in st["fighters"]:
		var per: Dictionary = st["per"][seat]
		per["done"] = false
		per["comp"] = false
		per["need_comp"] = false
		per["pair"] = []
		per["pending_main"] = main.duplicate()
		per["pairs_left"] = 1 + (1 if (per["specials"] as Array).has(0) else 0)
	for seat in st["fighters"]:
		_deal_pair(st, int(seat), rng)
	_log(st, "第 %d 回合 — 二选一编成" % int(st["round_num"]))


## 把该格斗者的下一候选组发到手上:
## 1 主组(合并锁环保留牌) → 2 特殊牌补抽(普通限定, 槽满跳过) → 3 增援令剩余组
static func _deal_pair(st: Dictionary, seat: int,
		rng: RandomNumberGenerator) -> void:
	var per: Dictionary = st["per"][seat]
	if not (per["pending_main"] as Array).is_empty():
		per["pair"] = (per["pending_main"] as Array).duplicate()
		per["pending_main"] = []
		per["comp"] = false
		if int(per["locked"]) >= 0:
			(per["pair"] as Array)[1] = int(per["locked"])
			per["locked"] = -1
		return
	if bool(per["need_comp"]) and (per["slots"] as Array).size() < 5:
		per["need_comp"] = false
		per["pair"] = [roll_candidate(st, true, rng),
				roll_candidate(st, true, rng)]
		per["comp"] = true
		return
	per["need_comp"] = false
	if int(per["pairs_left"]) > 0:
		per["pair"] = [roll_candidate(st, false, rng),
				roll_candidate(st, false, rng)]
		per["comp"] = false
		return
	per["pair"] = []
	per["done"] = true


static func _take_special(st: Dictionary, seat: int, sp_id: int) -> void:
	var per: Dictionary = st["per"][seat]
	(per["specials"] as Array).append(sp_id)
	var meta: Dictionary = FightGd.sp_meta(sp_id)
	_log(st, "%s 获得奇物【%s】" % [st["names"][seat], str(meta["name"])])


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
	stats["vamp"] = float(stats.get("vamp", 0.0)) + (0.20 if sps.has(3) else 0.0)
	stats["thorns"] = 0.30 if sps.has(4) else 0.0
	stats["first"] = sps.has(5)
	stats["regen"] = sps.has(7)
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
	if cand != -1 and not (per["pair"] as Array).has(cand):
		return {"ok": false, "error": "bad_candidate"}
	var slots: Array = per["slots"]
	if cand == -1:
		if slots.size() < 5:
			return {"ok": false, "error": "cannot_skip"}
	elif is_sp(cand):
		_take_special(st, seat, sp_of(cand))
		if (per["specials"] as Array).has(1) and not bool(per["comp"]):
			for c in per["pair"]:
				if int(c) != cand:
					per["locked"] = int(c)
	else:
		if slots.size() >= 5:
			if slot < 0 or slot >= 5:
				return {"ok": false, "error": "need_slot"}
			slots[slot] = cand
		else:
			slots.append(cand)
	# 本组解析完 → 下一组或完成
	if not bool(per["done"]):
		if is_sp(cand):
			per["need_comp"] = true
		if not bool(per["comp"]):   # 补抽组不消耗组数
			per["pairs_left"] = int(per["pairs_left"]) - 1
		per["pair"] = []
		_deal_pair(st, seat, rng)
	_log_pick(st, seat, cand)
	if bool(per["done"]):
		var all_done := true
		for s in st["fighters"]:
			if not bool((st["per"][s] as Dictionary)["done"]):
				all_done = false
		if all_done:
			_begin_round_battle(st, rng)
	return {"ok": true, "error": ""}


static func _log_pick(st: Dictionary, seat: int, cand: int) -> void:
	if cand < 0 or is_sp(cand):
		return
	_log(st, "%s 装备 %s(%d/5)" % [st["names"][seat], CardsGd.label(cand),
			(st["per"][seat]["slots"] as Array).size()])


## ── 本回合对战(新鲜生命, 按当前编成派生) ──
static func _begin_round_battle(st: Dictionary, rng: RandomNumberGenerator) -> void:
	st["phase"] = "battle"
	var b := {
		"hp": {}, "max_hp": {}, "shield": {}, "stats": {}, "combo": {},
		"guard": {}, "chilled": {}, "skill_cd": {}, "first_used": {},
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
	var fa: int = st["fighters"][0]
	var fb: int = st["fighters"][1]
	var ra: int = FightGd.TIER_RANK.find(str(b["combo"][fa]["tier"]))
	var rb: int = FightGd.TIER_RANK.find(str(b["combo"][fb]["tier"]))
	b["turn"] = fa if ra <= rb else fb
	st["battle"] = b
	_log(st, "对战开始 — %s 先攻" % st["names"][int(b["turn"])])


## 行动: attack/skill/defend。返回 {ok, error, events}。
static func apply_action(st: Dictionary, seat: int, action: String,
		rng: RandomNumberGenerator) -> Dictionary:
	var b: Dictionary = st.get("battle", {})
	if str(st["phase"]) != "battle":
		return {"ok": false, "error": "not_battle", "events": []}
	if not is_fighter(st, seat):
		return {"ok": false, "error": "not_fighter", "events": []}
	if int(b["turn"]) != seat:
		return {"ok": false, "error": "not_turn", "events": []}
	if not action in ["attack", "skill", "defend"]:
		return {"ok": false, "error": "bad_action", "events": []}
	if action == "skill" and int(b["skill_cd"][seat]) > 0:
		return {"ok": false, "error": "skill_cd", "events": []}
	b["battle_round"] = int(b["battle_round"]) + 1
	var foe := foe_of(st, seat)
	var evs := _resolve(st, seat, foe, action, rng)
	if int(b["hp"][foe]) > 0:
		b["turn"] = foe   # 行动后轮转到对方(击杀则回合直接结束)
	if int(b["hp"][foe]) <= 0:
		_end_round(st, seat)
	return {"ok": true, "error": "", "events": evs}


static func _resolve(st: Dictionary, actor: int, foe: int, action: String,
		rng: RandomNumberGenerator) -> Array:
	var evs: Array = []
	var b: Dictionary = st["battle"]
	var a: Dictionary = b["stats"][actor]
	var f: Dictionary = b["stats"][foe]
	if action != "skill" and int(b["skill_cd"][actor]) > 0:
		b["skill_cd"][actor] = int(b["skill_cd"][actor]) - 1
	# 泉涌
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
			var crit: bool = rng.randf() < float(a["crit_rate"])
			if bool(a.get("first", false)) and not bool(b["first_used"][actor]):
				crit = true
				b["first_used"][actor] = true
			var dmg := int(float(a["atk"]) * rng.randf_range(0.9, 1.1))
			if crit:
				dmg = int(dmg * float(a["crit_dmg"]))
			dmg = _hit(b, actor, foe, dmg, _mitigate(int(f["def"])), guard_on)
			evs.append(_ev(actor, foe, "crit" if crit else "dmg", dmg))
			_vamp(b, actor, dmg, evs)
		"skill":
			var dmg := maxi(int(float(a["skill"]) * rng.randf_range(0.9, 1.2)), 1)
			var kind := str(a.get("skill_kind", "fire"))
			match kind:
				"frost":
					dmg = int(dmg * 0.85)
				"light":
					dmg = int(dmg * 0.75)
			dmg = _hit(b, actor, foe, dmg, _mitigate(int(f["mres"])), guard_on)
			match kind:
				"frost":
					b["chilled"][foe] = true
					evs.append(_ev(actor, foe, "chill", 0))
				"light":
					var hl := maxi(int(dmg * 0.3), 1)
					b["hp"][actor] = mini(int(b["hp"][actor]) + hl,
							int(b["max_hp"][actor]))
					evs.append(_ev(actor, actor, "heal", hl))
			evs.append(_ev(actor, foe, "skill", dmg))
			_vamp(b, actor, dmg, evs)
			b["skill_cd"][actor] = 2
		"defend":
			b["guard"][actor] = true
			var heal := maxi(int(b["max_hp"][actor]) / 25, 3)
			b["hp"][actor] = mini(int(b["hp"][actor]) + heal,
					int(b["max_hp"][actor]))
			evs.append(_ev(actor, actor, "defend", heal))
	# 顺子追击
	if action != "defend" and bool(a.get("straight", false)) \
			and int(b["battle_round"]) % 3 == 0 and int(b["hp"][foe]) > 0:
		var d2 := _hit(b, actor, foe, int(float(a["atk"]) * 0.7),
				_mitigate(int(f["def"])), false)
		evs.append(_ev(actor, foe, "dmg", d2))
		_vamp(b, actor, d2, evs)
	# 荆棘: 反弹物理伤害
	if action != "defend" and float(f.get("thorns", 0.0)) > 0.0 \
			and int(b["hp"][actor]) > 0 and evs.size() > 0:
		var taken := 0
		for e in evs:
			if int(e["target"]) == actor and str(e["kind"]) in ["dmg", "crit", "skill"]:
				taken += int(e["v"])
		if taken > 0:
			var back := maxi(int(taken * float(f["thorns"])), 1)
			b["hp"][actor] = int(b["hp"][actor]) - back
			evs.append(_ev(foe, actor, "thorns", back))
	if int(b["hp"][actor]) <= 0 and int(b["hp"][foe]) > 0:
		b["hp"][actor] = 0
	return evs


## 落伤: 护盾 → 冰冻 → 格挡 → 固定减免, 下限 1
## 百分比减伤系数: def 越高减免越多但永不完全免疫
static func _mitigate(def: int) -> float:
	return 80.0 / (80.0 + float(def))


static func _hit(b: Dictionary, actor: int, foe: int, dmg: int,
		mit_mul: float, guard_on: bool) -> int:
	if bool(b["chilled"][actor]):
		dmg = int(dmg * 0.8)
		b["chilled"][actor] = false
	if guard_on:
		dmg = int(dmg * 0.5)
	dmg = maxi(int(dmg * mit_mul), 1)
	# 玉障护盾优先吸收
	var sh: int = int(b["shield"][foe])
	if sh > 0:
		var absorbed: int = mini(sh, dmg)
		b["shield"][foe] = sh - absorbed
		dmg -= absorbed
	b["hp"][foe] = int(b["hp"][foe]) - dmg
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


## 回合结束: 胜者 +1 分; 先胜 3 分者终局
static func _end_round(st: Dictionary, winner: int) -> void:
	var b: Dictionary = st["battle"]
	b["hp"][winner] = maxi(int(b["hp"][winner]), 1)
	st["phase"] = "round_end"
	st["round_winner"] = winner
	st["score"][winner] = int(st["score"].get(winner, 0)) + 1
	_log(st, "%s 拿下第 %d 回合! (比分 %d:%d)" % [
		st["names"][winner], int(st["round_num"]),
		int(st["score"].get(st["fighters"][0], 0)),
		int(st["score"].get(st["fighters"][1], 0))])
	if int(st["score"][winner]) >= WIN_SCORE:
		st["phase"] = "over"
		st["winner"] = winner
		_log(st, "★ %s 赢得整场格斗对战!" % st["names"][winner])


## round_end 展示完毕 → 下一回合(比分未达标时)
static func advance_round(st: Dictionary, rng: RandomNumberGenerator) -> bool:
	if str(st["phase"]) != "round_end":
		return false
	if int(st["round_num"]) >= ROUNDS:
		# 五回合打满: 按比分(平分加赛已由先胜3规则避免; 极端平局判先手方)
		var fa: int = st["fighters"][0]
		var fb: int = st["fighters"][1]
		var sa: int = int(st["score"].get(fa, 0))
		var sb: int = int(st["score"].get(fb, 0))
		st["phase"] = "over"
		st["winner"] = fa if sa >= sb else fb
		return true
	st["round_num"] = int(st["round_num"]) + 1
	open_round(st, rng)
	return true


## ── 按座位裁剪视图 ──
static func view(st: Dictionary, my_seat: int) -> Dictionary:
	var fighters: Array = st["fighters"]
	var v := {
		"phase": st["phase"],
		"my_seat": my_seat,
		"fighters": (fighters as Array).duplicate(),
		"spectator": not (fighters as Array).has(my_seat),
		"names": (st["names"] as Dictionary).duplicate(true),
		"round_num": int(st["round_num"]),
		"rounds_total": ROUNDS,
		"win_score": WIN_SCORE,
		"score": (st["score"] as Dictionary).duplicate(),
		"round_winner": int(st["round_winner"]),
		"winner": int(st["winner"]),
		"log": (st["log"] as Array).duplicate(),
		"turn": int(st["battle"].get("turn", -1)) if str(st["phase"]) == "battle" else -1,
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
			"comp": bool(mine["comp"]),
			"done": bool(mine["done"]),
			"pairs_left": int(mine["pairs_left"]),
		}
	for seat in fighters:
		var per: Dictionary = st["per"][seat]
		v["per"][seat] = {
			"slots_count": (per["slots"] as Array).size(),
			"specials_count": (per["specials"] as Array).size(),
			"done": bool(per["done"]),
		}
	if str(st["phase"]) in ["battle", "round_end", "over"]:
		var b: Dictionary = st["battle"]
		v["hp"] = (b["hp"] as Dictionary).duplicate()
		v["max_hp"] = (b["max_hp"] as Dictionary).duplicate()
		v["shield"] = (b["shield"] as Dictionary).duplicate()
		v["skill_cd"] = (b["skill_cd"] as Dictionary).duplicate()
		v["my_turn"] = int(b["turn"]) == my_seat and str(st["phase"]) == "battle"
		v["hands"] = {}
		v["combo"] = {}
		v["skill_kind"] = {}
		v["stats_brief"] = {}
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
	else:
		v["my_turn"] = false
		# draft 阶段不泄露对手候选; 展示双方编成进度即可
	return v
