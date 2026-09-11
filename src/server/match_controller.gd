## 对局控制器：包着规则引擎状态机，负责计时（AI 节奏/回合超时/阶段过渡），
## 并把状态变化翻译成对外事件。纯逻辑，由 RoomManager.tick 驱动。
class_name MatchController
extends RefCounted

const GameStateGd = preload("res://src/rules/game_state.gd")
const BotPlayerGd = preload("res://src/rules/ai/bot_player.gd")
const ComboGd = preload("res://src/rules/combo.gd")
const CardsGd = preload("res://src/rules/cards.gd")

var state: Dictionary
var seat_peer: Array = []      # 座位 → peer id（AI 为 -1）
var seat_online: Array = []    # 座位 → 人类是否在线
var ai_delay_ms := 600
var phase_delay_ms := 2200

var _turn_deadline_ms := 0
var _next_act_ms := 0
var _phase_until_ms := 0


func _init(game_state: Dictionary, peers: Array, online: Array,
		p_ai_delay_ms: int, p_phase_delay_ms: int, now_ms: int) -> void:
	state = game_state
	seat_peer = peers.duplicate()
	seat_online = online.duplicate()
	ai_delay_ms = p_ai_delay_ms
	phase_delay_ms = p_phase_delay_ms
	_arm(now_ms)


## 该座位当前是否由 AI 代管（空位 AI 或离线人类）。
func is_bot_seat(seat: int) -> bool:
	if seat < 0 or seat >= 4:
		return false
	if int(seat_peer[seat]) < 0:
		return true
	return not bool(seat_online[seat])


## 驱动一步。返回 {changed: bool, events: Array}。
## events 元素: {event: String, data: Dictionary}
func tick(now_ms: int) -> Dictionary:
	if state.is_empty():
		return {"changed": false, "events": []}
	match str(state["phase"]):
		"play":
			if is_bot_seat(int(state["turn"])):
				if now_ms >= _next_act_ms:
					return _step(BotPlayerGd.decide(state, int(state["turn"])), now_ms)
			elif now_ms >= _turn_deadline_ms:
				# 人类超时 → 托管决策（跟牌 Pass / 领出最小牌）
				return _step(BotPlayerGd.decide(state, int(state["turn"])), now_ms)
		"exchange":
			if now_ms >= _phase_until_ms:
				return _step({"t": "exchange_done", "seat": int(state["turn"])}, now_ms)
		"round_end":
			if now_ms >= _phase_until_ms:
				return _step({"t": "next_round"}, now_ms)
	return {"changed": false, "events": []}


## 对局结束且展示完毕（由 RoomManager 调用收尾）。
func game_finished(now_ms: int) -> bool:
	return not state.is_empty() and str(state["phase"]) == "game_end" \
			and now_ms >= _phase_until_ms


## 人类玩家的动作（seat 已由 RoomManager 填好）；返回 {changed, error, events}。
func human_apply(action: Dictionary, now_ms: int) -> Dictionary:
	return _step(action, now_ms)


func _step(action: Dictionary, now_ms: int) -> Dictionary:
	var prev_phase: String = str(state["phase"])
	var prev_rev: bool = bool(state["revolution"])
	var seat: int = int(action.get("seat", int(state["turn"])))
	var r := GameStateGd.apply(state, action)
	if not bool(r["ok"]):
		return {"changed": false, "error": str(r["error"]), "events": []}
	state = r["state"]
	var events := []
	var t: String = str(action.get("t", ""))
	if t == "play":
		var combo := ComboGd.identify(action.get("cards", []), state["cfg"])
		var cleared: bool = (state["field"] as Array).is_empty() \
				and (state["lead"] as Dictionary).is_empty()
		var is_eight_cut := cleared and bool(state["cfg"]["eight_cut"])
		if is_eight_cut:
			is_eight_cut = false
			for c in combo.get("cards", []):
				if CardsGd.value(int(c)) == 8:
					is_eight_cut = true
					break
		events.append({"event": "s_game_played", "data": {
			"seat": seat, "combo": combo, "eight_cut": is_eight_cut,
			"remain": (state["hands"][seat] as Array).size(),
		}})
	elif t == "pass":
		if (state["field"] as Array).is_empty() and (state["lead"] as Dictionary).is_empty():
			events.append({"event": "s_game_cleared", "data": {
				"seat": int(state["last_player"])}})
	if bool(state["revolution"]) != prev_rev:
		events.append({"event": "s_revolution", "data": {"on": bool(state["revolution"])}})
	var new_phase: String = str(state["phase"])
	if new_phase != prev_phase:
		match new_phase:
			"round_end":
				events.append({"event": "s_round_end", "data": {
					"identities": state["identities"],
					"last_points": state["last_points"],
					"scores": state["scores"],
				}})
			"exchange":
				events.append({"event": "s_exchange", "data": {"picks": state["exchange"]}})
			"game_end":
				events.append({"event": "s_game_end", "data": {"scores": state["scores"]}})
	_arm(now_ms)
	return {"changed": true, "events": events}


func _arm(now_ms: int) -> void:
	match str(state["phase"]):
		"play":
			_next_act_ms = now_ms + ai_delay_ms
			_turn_deadline_ms = now_ms + int(state["cfg"]["turn_seconds"]) * 1000
		"exchange":
			_phase_until_ms = now_ms + phase_delay_ms
		"round_end":
			_phase_until_ms = now_ms + phase_delay_ms
		"game_end":
			_phase_until_ms = now_ms + phase_delay_ms
