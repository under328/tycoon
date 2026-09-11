## 一个房间：成员/座位/令牌/设置 + 关联的对局控制器。纯逻辑（无网络）。
## 座位数据: { "peer": int(-1=空位或AI), "name": String, "token": String,
##             "bot": bool, "online": bool }
class_name Room
extends RefCounted

const GameStateGd = preload("res://src/rules/game_state.gd")
const MatchCtlGd = preload("res://src/server/match_controller.gd")

const SEATS := 4
## AI 随机皮肤池
const BOT_SKINS := ["skin_aka", "skin_ao", "skin_kitsu", "skin_oiran", "skin_tengu", "skin_default"]

var code := ""
var host_seat := 0
var settings: Dictionary = {}
var seats: Array = []          # 长度4, 空位为 null
var match_ctl = null           # MatchController 或 null
var soak := false              # 压测房间: 对局结束自动续局
var token_rng: RandomNumberGenerator

func _init(p_code: String, p_settings: Dictionary, rng: RandomNumberGenerator) -> void:
	code = p_code
	settings = p_settings
	token_rng = rng
	for i in SEATS:
		seats.append(null)


func is_empty() -> bool:
	for s in seats:
		if s != null and not bool(s["bot"]):
			return false
	return true


func seat_of_peer(peer: int) -> int:
	for s in SEATS:
		var seat = seats[s]
		if seat != null and int(seat["peer"]) == peer:
			return s
	return -1


func first_free_seat() -> int:
	for s in SEATS:
		if seats[s] == null:
			return s
	return -1


## 返回加入者的座位；满员返回 -1。
func sit(peer: int, name: String, client_id: String = "", skin_id: String = "skin_default") -> int:
	var s := first_free_seat()
	if s < 0:
		return -1
	seats[s] = {
		"peer": peer, "name": name, "token": _gen_token(),
		"bot": false, "online": true, "client_id": client_id, "skin_id": skin_id,
	}
	return s


func sit_bot(skin_id: String = "skin_default") -> int:
	var s := first_free_seat()
	if s < 0:
		return -1
	seats[s] = {"peer": -1, "name": "AI·%d" % (s + 1), "token": "",
			"bot": true, "online": true, "client_id": "", "skin_id": skin_id}
	return s


func _gen_token() -> String:
	var chars := "abcdefghijklmnopqrstuvwxyz0123456789"
	var out := ""
	for i in 24:
		out += chars[token_rng.randi_range(0, chars.length() - 1)]
	return out


## 移除成员（离开/被踢）。对局中不掉座位，只标记离线交给 AI。
func remove_seat(seat: int) -> void:
	if seat < 0:
		return
	if match_ctl != null:
		seats[seat]["online"] = false
	else:
		seats[seat] = null
		if seat == host_seat:
			for s in SEATS:
				var seat2 = seats[s]
				if seat2 != null and not bool(seat2["bot"]):
					host_seat = s
					break


func peer_token(peer: int) -> String:
	var s := seat_of_peer(peer)
	if s >= 0:
		return str(seats[s]["token"])
	return ""


## room_state payload（token 只发给归属者）。
func state_for(seat: int) -> Dictionary:
	var players := []
	for s in SEATS:
		var seat_data = seats[s]
		if seat_data == null:
			players.append({"seat": s, "empty": true})
		else:
			players.append({
				"seat": s, "empty": false, "name": str(seat_data["name"]),
				"is_bot": bool(seat_data["bot"]), "online": bool(seat_data["online"]),
				"skin_id": str(seat_data.get("skin_id", "skin_default")),
			})
	var out := {
		"room_code": code, "host_seat": host_seat, "players": players,
		"settings": settings.duplicate(), "my_seat": seat,
	}
	if seat >= 0 and seats[seat] != null:
		out["session_token"] = str(seats[seat]["token"])
	return out


## 开新对局：空位补 AI。返回 {ok, match_ctl}
func start(now_ms: int, ai_delay_ms: int, phase_delay_ms: int) -> Dictionary:
	if match_ctl != null:
		return {"ok": false}
	for s in SEATS:
		if seats[s] == null:
			sit_bot(BOT_SKINS[token_rng.randi_range(0, BOT_SKINS.size() - 1)])
	var peers := []
	var online := []
	for s in SEATS:
		var seat = seats[s]
		peers.append(int(seat["peer"]) if not bool(seat["bot"]) else -1)
		online.append(bool(seat["online"]) and not bool(seat["bot"]))
	var st := GameStateGd.new_match(settings, -1)
	match_ctl = MatchCtlGd.new(st, peers, online, ai_delay_ms, phase_delay_ms, now_ms)
	return {"ok": true, "match_ctl": match_ctl}


func end_match() -> void:
	match_ctl = null
	# 清掉对局中掉线未归的人类座位（AI 空位留给下一局补满）
	for s in SEATS:
		var seat_data = seats[s]
		if seat_data != null and not bool(seat_data["bot"]) and not bool(seat_data["online"]):
			seats[s] = null
