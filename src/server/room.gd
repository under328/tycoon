## 一个房间：成员/座位/令牌/设置 + 关联的对局控制器。纯逻辑（无网络）。
## 座位数据: { "peer": int(-1=空位或AI), "name": String, "token": String,
##             "bot": bool, "online": bool }
class_name Room
extends RefCounted

const GameStateGd = preload("res://src/rules/game_state.gd")
const MatchCtlGd = preload("res://src/server/match_controller.gd")
const FightMatchGd = preload("res://src/server/fight_match.gd")
const FightPvpGd = preload("res://src/rules/fight/fight_pvp.gd")

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


## 按 client_id 找同一玩家的座位(退出后重进归位用); 无匹配返回 -1。
## 只匹配真人座位 — 断线宽限/AI 代管的离线座都能据此找回。
func seat_of_client(client_id: String) -> int:
	if client_id == "":
		return -1
	for s in SEATS:
		var seat = seats[s]
		if seat != null and not bool(seat["bot"]) \
				and str(seat.get("client_id", "")) == client_id:
			return s
	return -1


func first_free_seat() -> int:
	for s in SEATS:
		if seats[s] == null:
			return s
	return -1


## 返回加入者的座位；满员返回 -1。
func sit(peer: int, name: String, client_id: String = "", skin_id: String = "skin_default",
		card_id: String = "") -> int:
	var s := first_free_seat()
	if s < 0:
		return -1
	seats[s] = {
		"peer": peer, "name": _clean_name(name), "token": _gen_token(),
		"bot": false, "online": true, "client_id": client_id, "skin_id": skin_id,
		"card_id": card_id, "offline_ms": 0,
	}
	return s


func sit_bot(skin_id: String = "skin_default") -> int:
	var s := first_free_seat()
	if s < 0:
		return -1
	seats[s] = {"peer": -1, "name": "AI·%d" % (s + 1), "token": "",
			"bot": true, "online": true, "client_id": "", "skin_id": skin_id}
	return s


## 对局进行中让朋友接管一个 AI 座位(共享对局中途加入):
## 座位从 AI 转为真人(生成会话 token 供断线重连), 返回新 token。
func claim_bot_seat(seat: int, peer: int, name: String, client_id: String,
		skin_id: String = "skin_default", card_id: String = "") -> String:
	if seat < 0 or seat >= SEATS or seats[seat] == null or not bool(seats[seat]["bot"]):
		return ""
	seats[seat] = {
		"peer": peer, "name": _clean_name(name), "token": _gen_token(),
		"bot": false, "online": true, "client_id": client_id, "skin_id": skin_id,
		"card_id": card_id, "offline_ms": 0,
	}
	return str(seats[seat]["token"])


## 昵称兜底: 旧版客户端可能上报空名 — 座位卡/对局视图不落空
func _clean_name(name: String) -> String:
	var nm := name.strip_edges()
	return nm if nm != "" else "玩家"


func _gen_token() -> String:
	var chars := "abcdefghijklmnopqrstuvwxyz0123456789"
	var out := ""
	for i in 24:
		out += chars[token_rng.randi_range(0, chars.length() - 1)]
	return out


## 移除成员（离开/被踢）。对局中普通退房保留座位(离线·AI 代管,
## 重进归位); final=true(应用退出等彻底离开)则对局中座位也置空 —
## 其他玩家不再看到其"离线"座位挂到对局结束(任务反馈)。
## 断线(WiFi 抖动/杀进程)不经此路, 走 peer_gone 的离线宽限保留重连归位。
func remove_seat(seat: int, final: bool = false) -> void:
	if seat < 0:
		return
	if match_ctl != null and not final:
		if seats[seat] != null:
			seats[seat]["online"] = false
		return
	if seat >= SEATS or seats[seat] == null:
		return
	seats[seat] = null
	if match_ctl != null and "seat_online" in match_ctl:
		match_ctl.seat_online[seat] = false   # AI 立即接管
	if seat == host_seat:
		for s in SEATS:
			var seat2 = seats[s]
			if seat2 != null and not bool(seat2["bot"]):
				host_seat = s
				break


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
				"card_id": str(seat_data.get("card_id", "")),
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
	if str(settings.get("mode", "normal")) == "fight":
		return _start_fight(now_ms, ai_delay_ms, phase_delay_ms)
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
	var nms: Array = ["", "", "", ""]
	for s2 in SEATS:
		if seats[s2] != null:
			nms[s2] = str(seats[s2]["name"])
	st["names"] = nms   # 视图等待提示用(view.names)
	match_ctl = MatchCtlGd.new(st, peers, online, ai_delay_ms, phase_delay_ms, now_ms)
	return {"ok": true, "match_ctl": match_ctl}


## 格斗对战开局: 前 2 个座位为格斗者(1 人开局时 2 号位补 AI),
## 3/4 号位玩家自动成为观战者。
func _start_fight(now_ms: int, ai_delay_ms: int, phase_delay_ms: int) -> Dictionary:
	if seats[0] == null and seats[1] == null:
		return {"ok": false}
	if seats[1] == null:
		sit_bot(BOT_SKINS[token_rng.randi_range(0, BOT_SKINS.size() - 1)])
	var fighters := [0, 1]
	var names := {}
	var peers := []
	var online := []
	for s in SEATS:
		var seat_data = seats[s]
		if seat_data == null:      # 3/4 号位空位(观战席无人)
			peers.append(-1)
			online.append(false)
			continue
		if s < 2:
			names[s] = str(seat_data["name"])
		peers.append(int(seat_data["peer"]) if not bool(seat_data["bot"]) else -1)
		online.append(bool(seat_data["online"]) and not bool(seat_data["bot"]))
	var seed_v := token_rng.randi_range(1, 1000000000)
	match_ctl = FightMatchGd.new(seed_v, fighters, names, peers, online,
			ai_delay_ms, phase_delay_ms, now_ms)
	return {"ok": true, "match_ctl": match_ctl}


func end_match() -> void:
	match_ctl = null
	# 清掉对局中掉线未归的人类座位（AI 空位留给下一局补满）
	for s in SEATS:
		var seat_data = seats[s]
		if seat_data != null and not bool(seat_data["bot"]) and not bool(seat_data["online"]):
			seats[s] = null
