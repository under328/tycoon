## 格斗对战控制器：包着 FightPvp 状态机，负责计时(AI 选牌/行动、超时托管)。
## 接口与 MatchController 对齐(kind/tick/game_finished)，RoomManager 按
## kind == "fight" 分流广播(s_fight_state 代替 s_game_view)。纯逻辑可单测。
class_name FightMatch
extends RefCounted

const FightPvpGd = preload("res://src/rules/fight/fight_pvp.gd")

var kind := "fight"
var state: Dictionary
var seat_peer: Array = []      # 长度4: 座位 → peer id(AI 为 -1)
var seat_online: Array = []    # 长度4: 座位 → 人类是否在线(观战者也计)
var ai_delay_ms := 600
var phase_delay_ms := 2600     # over 展示时长(之后收尾回房)

var _rng := RandomNumberGenerator.new()
var _deadline_ms := 0          # 当前阶段人类限时(选牌/行动)
var _next_ai_ms := 0           # AI 下次行动时间
var _over_until_ms := 0


func _init(seed_v: int, candidates: Array, fighters: Array,
		names: Dictionary, peers: Array, online: Array,
		p_ai_delay_ms: int, p_phase_delay_ms: int, now_ms: int) -> void:
	_rng.seed = seed_v
	state = FightPvpGd.new_state(candidates, fighters, names)
	seat_peer = peers.duplicate()
	seat_online = online.duplicate()
	ai_delay_ms = p_ai_delay_ms
	phase_delay_ms = p_phase_delay_ms
	_arm(now_ms)


## 该座位当前是否由 AI 代管(AI 座位或离线人类)。
func is_bot_seat(seat: int) -> bool:
	if seat < 0 or seat >= 4:
		return false
	if int(seat_peer[seat]) < 0:
		return true
	return not bool(seat_online[seat])


## 人类玩家动作(座位由 RoomManager 填好)；返回 {changed, error}。
func human_pick(seat: int, cards: Array, now_ms: int) -> Dictionary:
	var r: Dictionary = FightPvpGd.apply_pick(state, seat, cards)
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


## 驱动一步: AI 选牌/行动 + 人类超时托管。返回 {changed, events}。
func tick(now_ms: int) -> Dictionary:
	match str(state["phase"]):
		"pick":
			for seat in state["fighters"]:
				if not (state["picks"] as Dictionary).has(seat) \
						and is_bot_seat(seat) and now_ms >= _next_ai_ms:
					_auto_pick(seat)
					_arm(now_ms)
					return {"changed": true, "events": []}
			# 人类超时: 托管随机选满 5 张
			for seat in state["fighters"]:
				if not (state["picks"] as Dictionary).has(seat) \
						and not is_bot_seat(seat) and now_ms >= _deadline_ms:
					_auto_pick(seat)
					_arm(now_ms)
					return {"changed": true, "events": []}
		"battle":
			var t := int(state["turn"])
			if now_ms >= _next_ai_ms and is_bot_seat(t):
				var evs := _auto_act(t)
				_arm(now_ms)
				return {"changed": true, "events": evs}
			if now_ms >= _deadline_ms and not is_bot_seat(t):
				var evs2: Array = FightPvpGd.apply_action(
						state, t, "attack", _rng)["events"]
				_arm(now_ms)
				return {"changed": true, "events": evs2}
	return {"changed": false, "events": []}


## 对局结束且展示完毕(由 RoomManager 收尾)。
func game_finished(now_ms: int) -> bool:
	return str(state["phase"]) == "over" and now_ms >= _over_until_ms


func view_for(seat: int) -> Dictionary:
	return FightPvpGd.view(state, seat)


## AI 选牌: 随机 5 张(同池随机, 不读对手)
func _auto_pick(seat: int) -> void:
	var pool: Array = (state["candidates"] as Array).duplicate()
	pool.shuffle()
	FightPvpGd.apply_pick(state, seat, pool.slice(0, FightPvpGd.PICK_N))


## AI 行动启发式: 技能好了一般放; 残血三成概率防御; 否则普攻
func _auto_act(seat: int) -> Array:
	var act := "attack"
	var hp := int(state["hp"][seat])
	var mh := maxi(int(state["max_hp"][seat]), 1)
	if int(state["skill_cd"][seat]) <= 0 and _rng.randf() < 0.65:
		act = "skill"
	elif float(hp) / float(mh) < 0.3 and _rng.randf() < 0.4:
		act = "defend"
	return FightPvpGd.apply_action(state, seat, act, _rng)["events"]


func _arm(now_ms: int) -> void:
	match str(state["phase"]):
		"pick":
			_next_ai_ms = now_ms + ai_delay_ms
			_deadline_ms = now_ms + FightPvpGd.PICK_SECONDS * 1000
		"battle":
			_next_ai_ms = now_ms + ai_delay_ms
			_deadline_ms = now_ms + FightPvpGd.TURN_SECONDS * 1000
		"over":
			_over_until_ms = now_ms + phase_delay_ms
