## 格斗对战控制器 v2(回合制): 包着 FightPvp 状态机, 负责计时(AI 选牌/行动、
## 超时托管、回合过场)。接口与 MatchController 对齐(kind/tick/game_finished),
## RoomManager 按 kind == "fight" 分流广播(s_fight_state)。纯逻辑可单测。
class_name FightMatch
extends RefCounted

const FightPvpGd = preload("res://src/rules/fight/fight_pvp.gd")
const FightGd = preload("res://src/rules/fight/fight_mode.gd")

var kind := "fight"
var state: Dictionary
var seat_peer: Array = []      # 长度4: 座位 → peer id(AI 为 -1)
var seat_online: Array = []    # 长度4: 座位 → 人类是否在线(观战者也计)
var ai_delay_ms := 600
var phase_delay_ms := 2600     # round_end/over 展示时长

var _rng := RandomNumberGenerator.new()
var _deadline_ms := 0          # 当前阶段人类限时(选牌/行动)
var _next_ai_ms := 0           # AI 下次行动时间
var _phase_until_ms := 0


func _init(seed_v: int, fighters: Array, names: Dictionary, peers: Array,
		online: Array, p_ai_delay_ms: int, p_phase_delay_ms: int,
		now_ms: int) -> void:
	_rng.seed = seed_v
	state = FightPvpGd.new_state(fighters, names)
	seat_peer = peers.duplicate()
	seat_online = online.duplicate()
	ai_delay_ms = p_ai_delay_ms
	phase_delay_ms = p_phase_delay_ms
	FightPvpGd.open_round(state, _rng)
	_arm(now_ms)


## 该座位当前是否由 AI 代管(AI 座位或离线人类)。
func is_bot_seat(seat: int) -> bool:
	if seat < 0 or seat >= 4:
		return false
	if int(seat_peer[seat]) < 0:
		return true
	return not bool(seat_online[seat])


## 人类玩家动作(座位由 RoomManager 填好)；返回 {changed, error, events}。
func human_pick(seat: int, cand: int, slot: int, now_ms: int) -> Dictionary:
	var r: Dictionary = FightPvpGd.draft_pick(state, seat, cand, slot, _rng)
	if not bool(r["ok"]):
		return {"changed": false, "error": str(r["error"])}
	_arm(now_ms)
	return {"changed": true, "events": []}


func human_act(seat: int, action: String, now_ms: int) -> Dictionary:
	var r: Dictionary = FightPvpGd.apply_action(state, seat, action, _rng)
	if not bool(r["ok"]):
		return {"changed": false, "error": str(r["error"])}
	_arm(now_ms)
	return {"changed": true, "events": r["events"]}


## 驱动一步: AI 选牌/行动 + 人类超时托管 + 回合过场。返回 {changed, events}。
func tick(now_ms: int) -> Dictionary:
	match str(state["phase"]):
		"draft":
			if now_ms >= _next_ai_ms:
				for seat in state["fighters"]:
					var per: Dictionary = state["per"][seat]
					if not bool(per["done"]) and is_bot_seat(int(seat)):
						_auto_pick(int(seat))
						_arm(now_ms)
						return {"changed": true, "events": []}
			if now_ms >= _deadline_ms:
				for seat in state["fighters"]:
					var per: Dictionary = state["per"][seat]
					if not bool(per["done"]) and not is_bot_seat(int(seat)):
						_auto_pick(int(seat))   # 超时托管: 能拿就拿
						_arm(now_ms)
						return {"changed": true, "events": []}
		"battle":
			var t := int(state["battle"]["turn"])
			if now_ms >= _next_ai_ms and is_bot_seat(t):
				var evs := _auto_act(t)
				_arm(now_ms)
				return {"changed": true, "events": evs}
			if now_ms >= _deadline_ms and not is_bot_seat(t):
				var evs2: Array = FightPvpGd.apply_action(
						state, t, "attack", _rng)["events"]
				_arm(now_ms)
				return {"changed": true, "events": evs2}
		"round_end":
			if now_ms >= _phase_until_ms:
				FightPvpGd.advance_round(state, _rng)
				_arm(now_ms)
				return {"changed": true, "events": []}
	return {"changed": false, "events": []}


## 对局结束且展示完毕(由 RoomManager 收尾)。
func game_finished(now_ms: int) -> bool:
	return str(state["phase"]) == "over" and now_ms >= _phase_until_ms


func view_for(seat: int) -> Dictionary:
	return FightPvpGd.view(state, seat)


## AI/超时托管选牌: 先拾取奇物第三选项(不消耗卡牌选择);
## 再选使牌型更强的普通牌, 满槽替换最弱槽位; 无从选则跳过
func _auto_pick(seat: int) -> void:
	var per: Dictionary = state["per"][seat]
	if int(per["bonus_relic"]) >= 0 \
			and (per["specials"] as Array).size() < 2:
		FightPvpGd.draft_pick(state, int(seat), int(per["bonus_relic"]), -1, _rng)
		return
	var pair: Array = per["pair"]
	if (pair as Array).is_empty():
		FightPvpGd.draft_pick(state, int(seat), -1, -1, _rng)
		return
	var best: int = -1
	var best_rank := -1
	var best_slot := 0
	for c in pair:
		var slots: Array = (per["slots"] as Array).duplicate()
		var slot := 0
		var card_v: int = FightPvpGd.card_of(int(c))
		if slots.size() >= 5:
			slot = _weakest_slot(slots)
			slots[slot] = card_v
		else:
			slots.append(card_v)
		var rk: int = FightGd.TIER_RANK.find(
				str(FightGd.evaluate_combo(slots)["tier"]))
		if rk > best_rank:
			best_rank = rk
			best = int(c)
			best_slot = slot
	if best >= 0:
		FightPvpGd.draft_pick(state, int(seat), best, best_slot, _rng)
	else:
		FightPvpGd.draft_pick(state, int(seat), -1, -1, _rng)


static func _weakest_slot(slots: Array) -> int:
	var best := 0
	var best_v := 99
	for i in slots.size():
		var v: int = FightPvpGd.card_of(int(slots[i]))
		if v < best_v:
			best_v = v
			best = i
	return best


## AI 行动启发式: 技能好了一般放; 残血三成概率防御; 否则普攻
func _auto_act(seat: int) -> Array:
	var act := "attack"
	if int(state["battle"]["fury"][seat]) >= 100:
		act = "ult"   # 怒气满优先奥义
	var hp := int(state["battle"]["hp"][seat])
	var mh := maxi(int(state["battle"]["max_hp"][seat]), 1)
	if int(state["battle"]["skill_cd"][seat]) <= 0 and _rng.randf() < 0.65:
		act = "skill"
	elif float(hp) / float(mh) < 0.3 and _rng.randf() < 0.4:
		act = "defend"
	return FightPvpGd.apply_action(state, int(seat), act, _rng)["events"]


func _arm(now_ms: int) -> void:
	match str(state["phase"]):
		"draft":
			_next_ai_ms = now_ms + ai_delay_ms
			_deadline_ms = now_ms + FightPvpGd.PICK_SECONDS * 1000
		"battle":
			_next_ai_ms = now_ms + ai_delay_ms
			_deadline_ms = now_ms + FightPvpGd.TURN_SECONDS * 1000
		"round_end":
			_phase_until_ms = now_ms + phase_delay_ms
		"over":
			_phase_until_ms = now_ms + phase_delay_ms
