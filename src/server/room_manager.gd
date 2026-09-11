## 服务器核心逻辑（纯逻辑，无网络）。net_node.gd（服务器模式）把 RPC 翻译为这里的方法调用，
## 并把每个方法返回的 out 队列（{peer, event, data}）发给对应客户端。
## 单测直接驱动本类即可覆盖房间/对局/托管/重连全部行为。
class_name RoomManager
extends RefCounted

const MsgC = preload("res://src/protocol/msg.gd")
const RoomGd = preload("res://src/server/room.gd")
const ViewGd = preload("res://src/protocol/view.gd")
const StatsGd = preload("res://src/server/stats.gd")
const RulesConfigGd = preload("res://src/rules/rules_config.gd")
## AI 随机皮肤池
const SKINS := ["skin_aka", "skin_ao", "skin_kitsu", "skin_oiran", "skin_tengu", "skin_default"]

var default_settings: Dictionary = RulesConfigGd.defaults()

var rooms: Dictionary = {}       # code -> Room
var peer_room: Dictionary = {}   # peer -> code
var peer_client: Dictionary = {} # peer -> client_id（游客身份）
var peer_chat_ms: Dictionary = {}# peer -> 上次发言/表情时间（服务端限速）
var peer_skin: Dictionary = {}   # peer -> 皮肤 id
var soak_rooms := 0              # --soak 压测房间数
var soak_matches := 0            # 压测已完成对局数
var stats = null                 # StatsLib
var ai_delay_ms := 600
var phase_delay_ms := 2200
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()
	stats = StatsGd.new()


# ---------------------------------------------------------------- 连接与会话

func hello(peer: int, ver: int, token: String, client_id: String = "", skin_id: String = "") -> Array:
	var out := []
	if skin_id != "":
		peer_skin[peer] = skin_id
	if ver != MsgC.PROTOCOL_VERSION:
		out.append({"peer": peer, "event": "s_kicked",
				"data": {"reason": "version"}})
		return out
	if client_id != "":
		peer_client[peer] = client_id
	# 已在房间的 peer(如 quick_match 先于 hello 到达): 直接回报正确座位
	var known_code = peer_room.get(peer, "")
	if known_code != "":
		var known = rooms.get(known_code)
		if known != null:
			var s0: int = known.seat_of_peer(peer)
			if s0 >= 0:
				var sd: Dictionary = known.seats[s0]
				sd["online"] = true
				if known.match_ctl != null:
					known.match_ctl.seat_online[s0] = true
				out.append({"peer": peer, "event": "s_welcome",
						"data": {"seat": s0, "protocol_ok": true}})
				out.append({"peer": peer, "event": "s_room_state",
						"data": known.state_for(s0)})
				if known.match_ctl != null:
					out.append(_view_msg(known, s0))
				return out
	if token != "":
		var found: Dictionary = _room_by_token(token)
		if not found.is_empty():
			var room = found["room"]
			var seat: int = found["seat"]
			var seat_data: Dictionary = room.seats[seat]
			# 旧 peer 仍占用则顶替
			peer_room.erase(int(seat_data["peer"]))
			seat_data["peer"] = peer
			seat_data["online"] = true
			if skin_id != "":
				seat_data["skin_id"] = skin_id
			if room.match_ctl != null:
				room.match_ctl.seat_peer[seat] = peer
				room.match_ctl.seat_online[seat] = true
			peer_room[peer] = room.code
			out.append({"peer": peer, "event": "s_welcome",
					"data": {"seat": seat, "protocol_ok": true}})
			out.append({"peer": peer, "event": "s_room_state",
					"data": room.state_for(seat)})
			if room.match_ctl != null:
				out.append(_view_msg(room, seat))
			return out
	out.append({"peer": peer, "event": "s_welcome",
			"data": {"seat": -1, "protocol_ok": true}})
	return out


func peer_gone(peer: int) -> Array:
	var out := []
	var code = peer_room.get(peer, "")
	peer_client.erase(peer)
	peer_chat_ms.erase(peer)
	if code == "":
		return out
	peer_room.erase(peer)
	var room = rooms.get(code)
	if room == null:
		return out
	var seat: int = room.seat_of_peer(peer)
	if seat < 0:
		return out
	if room.match_ctl != null:
		# 对局中：座位保留 30s 宽限（v1: 到对局结束），AI 立即接管
		room.seats[seat]["online"] = false
		room.match_ctl.seat_online[seat] = false
	else:
		room.remove_seat(seat)
		if room.is_empty():
			rooms.erase(code)
		else:
			_bcast_room_state(out, room)
	return out


# ---------------------------------------------------------------- 房间操作

func quick_match(peer: int, name: String, rules: Dictionary, client_id: String = "", skin_id: String = "") -> Array:
	var out := []
	if client_id != "":
		peer_client[peer] = client_id
	if skin_id != "":
		peer_skin[peer] = skin_id
	for code in rooms:
		var room = rooms[code]
		if room.match_ctl == null and room.first_free_seat() >= 0:
			return join_room(peer, name, code, client_id, skin_id)
	return create_room(peer, name, rules, client_id, skin_id)


func create_room(peer: int, name: String, rules: Dictionary, client_id: String = "", skin_id: String = "") -> Array:
	var out := []
	if _in_live_match(peer):
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": "in_game", "msg": "对局进行中"}})
		return out
	if client_id != "":
		peer_client[peer] = client_id
	if skin_id != "":
		peer_skin[peer] = skin_id
	_leave_room(peer, out)
	var cfg := default_settings.duplicate()
	for k in cfg.keys():
		if rules.has(k):
			cfg[k] = rules[k]
	var room = RoomGd.new(_gen_code(), cfg, _rng)
	rooms[room.code] = room
	room.sit(peer, name, client_id, skin_id)
	peer_room[peer] = room.code
	out.append({"peer": peer, "event": "s_room_state",
			"data": room.state_for(room.seat_of_peer(peer))})
	return out


func join_room(peer: int, name: String, code: String, client_id: String = "", skin_id: String = "") -> Array:
	var out := []
	if _in_live_match(peer):
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": "in_game", "msg": "对局进行中"}})
		return out
	if client_id != "":
		peer_client[peer] = client_id
	if skin_id != "":
		peer_skin[peer] = skin_id
	var room = rooms.get(code)
	if room == null:
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": "no_room", "msg": "房间不存在"}})
		return out
	if room.match_ctl != null:
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": "in_game", "msg": "对局进行中"}})
		return out
	_leave_room(peer, out)
	var seat: int = room.sit(peer, name, client_id, skin_id)
	if seat < 0:
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": "full", "msg": "房间已满"}})
		return out
	peer_room[peer] = room.code
	out.append({"peer": peer, "event": "s_room_state",
			"data": room.state_for(seat)})
	_bcast_room_state(out, room)
	return out


func leave(peer: int) -> Array:
	var out := []
	_leave_room(peer, out)
	return out


## 快捷表情：广播给房内所有在线人类（大厅和对局中都可发）。限速 500ms。
func emoji(peer: int, id: int, now_ms: int = -1) -> Array:
	var out := []
	if not _chat_ok(peer, now_ms):
		return out
	var room = _room_of(peer)
	if room == null:
		return out
	var seat: int = room.seat_of_peer(peer)
	if seat < 0:
		return out
	_bcast_event(out, room, "s_emoji", {"seat": seat, "id": clampi(id, 0, 7)})
	return out


## 房主修改规则设置（仅对局未开始时）。
func set_settings(peer: int, rules: Dictionary) -> Array:
	var out := []
	var room = _room_of(peer)
	if room == null or room.match_ctl != null:
		return out
	if int(room.host_seat) != _seat_of(room, peer):
		return out
	var cfg := default_settings.duplicate()
	for k in cfg.keys():
		if rules.has(k):
			cfg[k] = rules[k]
	room.settings = RulesConfigGd.normalize(cfg)
	_bcast_room_state(out, room)
	return out


## 房内文本聊天（限长 80 字，广播给全房在线人类）。限速 500ms。
func chat(peer: int, text: String, now_ms: int = -1) -> Array:
	var out := []
	if not _chat_ok(peer, now_ms):
		return out
	var room = _room_of(peer)
	if room == null:
		return out
	var seat: int = room.seat_of_peer(peer)
	if seat < 0:
		return out
	text = text.strip_edges().substr(0, 80)
	if text == "":
		return out
	_bcast_event(out, room, "s_chat", {"seat": seat, "text": text})
	return out


## 聊天/表情共用限速：同一玩家 500ms 内只处理一条。
func _chat_ok(peer: int, now_ms: int) -> bool:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	var last = int(peer_chat_ms.get(peer, -100000))
	if now_ms - last < 500:
		return false
	peer_chat_ms[peer] = now_ms
	return true


## 查询自己的战绩。
func stats_get(peer: int) -> Array:
	var cid: String = str(peer_client.get(peer, ""))
	return [{"peer": peer, "event": "s_stats", "data": {"your": stats.get_entry(cid)}}]


func kick(host_peer: int, target_seat: int) -> Array:
	var out := []
	var room = _room_of(host_peer)
	if room == null or int(room.host_seat) != _seat_of(room, host_peer):
		return out
	var seat_data = room.seats[target_seat]
	if seat_data == null or bool(seat_data["bot"]):
		return out
	var target_peer := int(seat_data["peer"])
	peer_room.erase(target_peer)
	room.remove_seat(target_seat)
	out.append({"peer": target_peer, "event": "s_kicked", "data": {"reason": "host"}})
	_bcast_room_state(out, room)
	return out


func fill_bots(peer: int) -> Array:
	var out := []
	var room = _room_of(peer)
	if room == null or room.match_ctl != null:
		return out
	if int(room.host_seat) != _seat_of(room, peer):
		return out
	while room.first_free_seat() >= 0:
		room.sit_bot(SKINS[randi() % SKINS.size()])
	_bcast_room_state(out, room)
	return out


func start(peer: int, now_ms: int = -1) -> Array:
	var out := []
	var room = _room_of(peer)
	if room == null or room.match_ctl != null:
		return out
	if int(room.host_seat) != _seat_of(room, peer):
		return out
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	var r: Dictionary = room.start(now_ms, ai_delay_ms, phase_delay_ms)
	if not bool(r["ok"]):
		return out
	_bcast_views(out, room)
	return out


# ---------------------------------------------------------------- 对局动作

func play(peer: int, cards: Array, now_ms: int = -1) -> Array:
	return _game_action(peer, {"t": "play", "seat": -1, "cards": cards}, now_ms)


func pass_turn(peer: int, now_ms: int = -1) -> Array:
	return _game_action(peer, {"t": "pass", "seat": -1}, now_ms)


func exchange_return(peer: int, cards: Array, now_ms: int = -1) -> Array:
	return _game_action(peer, {"t": "exchange_return", "seat": -1, "cards": cards}, now_ms)


func _game_action(peer: int, action: Dictionary, now_ms: int) -> Array:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	var out := []
	var room = _room_of(peer)
	if room == null or room.match_ctl == null:
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": "no_match", "msg": "没有进行中的对局"}})
		return out
	var seat: int = room.seat_of_peer(peer)
	var ctl = room.match_ctl
	action["seat"] = seat
	var r: Dictionary = ctl.human_apply(action, now_ms)
	if not bool(r["changed"]):
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": str(r.get("error", "invalid")), "msg": "非法操作"}})
		return out
	_after_state_change(out, room, r)
	return out


# ---------------------------------------------------------------- 时钟驱动

func tick(now_ms: int) -> Array:
	var out := []
	for code in rooms.keys():
		var room = rooms[code]
		if room.match_ctl == null:
			continue
		var ctl = room.match_ctl
		var r: Dictionary = ctl.tick(now_ms)
		if bool(r["changed"]):
			_after_state_change(out, room, r)
		if ctl.game_finished(now_ms):
			room.end_match()
			if room.soak:
				soak_matches += 1
				room.start(now_ms, ai_delay_ms, phase_delay_ms)  # 压测: 无缝续局
			else:
				_bcast_room_state(out, room)
	return out


## 状态变化后：广播事件 + 给每个在线人类发私有 view（含 game_turn）。
func _after_state_change(out: Array, room, r: Dictionary) -> void:
	for e in r.get("events", []):
		if str(e["event"]) == "s_game_end":
			_record_stats(room, e["data"])
		_bcast_event(out, room, e["event"], e["data"])
	_bcast_views(out, room)


## 终局：写入战绩并在事件里附带各人类玩家的最新统计。
func _record_stats(room, data: Dictionary) -> void:
	var scores: Array = data.get("scores", [])
	var best := -999999
	for s in 4:
		best = maxi(best, int(scores[s]))
	var entries := []
	for s in 4:
		var seat_data = room.seats[s]
		if seat_data == null or bool(seat_data["bot"]):
			continue
		var cid := str(seat_data.get("client_id", ""))
		entries.append({
			"client_id": cid, "name": str(seat_data["name"]),
			"total": int(scores[s]), "win": int(scores[s]) == best,
		})
	stats.record(entries)
	# 记录后再截图，game_end payload 反映本场结果
	var stats_map := {}
	for s in 4:
		var seat_data2 = room.seats[s]
		if seat_data2 == null or bool(seat_data2["bot"]):
			continue
		var cid2 := str(seat_data2.get("client_id", ""))
		if cid2 != "":
			stats_map[s] = stats.get_entry(cid2)
	data["stats"] = stats_map


func _bcast_views(out: Array, room) -> void:
	if room.match_ctl == null:
		return
	var ctl = room.match_ctl
	for s in 4:
		if _human_online(room, s):
			out.append(_view_msg(room, s))


func _view_msg(room, seat: int) -> Dictionary:
	var ctl = room.match_ctl
	var view := ViewGd.build(ctl.state, seat)
	var data := {"view": view}
	if str(ctl.state["phase"]) == "play":
		data["turn_seat"] = int(ctl.state["turn"])
	return {"peer": int(room.seats[seat]["peer"]), "event": "s_game_view", "data": data}


func _bcast_event(out: Array, room, event: String, data: Dictionary) -> void:
	for s in 4:
		if _human_online(room, s):
			out.append({"peer": int(room.seats[s]["peer"]), "event": event, "data": data})


func _bcast_room_state(out: Array, room) -> void:
	for s in 4:
		var seat_data = room.seats[s]
		if seat_data != null and not bool(seat_data["bot"]) and bool(seat_data["online"]):
			out.append({"peer": int(seat_data["peer"]), "event": "s_room_state",
					"data": room.state_for(s)})


# ---------------------------------------------------------------- 内部工具

## 该 peer 是否正坐在有进行中对局的房间里(防误操作毁局)
func _in_live_match(peer: int) -> bool:
	var room = _room_of(peer)
	return room != null and room.match_ctl != null


func _leave_room(peer: int, out: Array) -> void:
	var code = peer_room.get(peer, "")
	if code == "":
		return
	peer_room.erase(peer)
	var room = rooms.get(code)
	if room == null:
		return
	room.remove_seat(room.seat_of_peer(peer))
	if room.is_empty():
		rooms.erase(code)
	else:
		_bcast_room_state(out, room)


func _room_of(peer: int):
	var code = peer_room.get(peer, "")
	if code == "":
		return null
	return rooms.get(code)


func _seat_of(room, peer: int) -> int:
	return room.seat_of_peer(peer)


## --soak: 创建 N 个全机器人压测房间(对局结束自动续局)
func start_soak(n: int) -> void:
	soak_rooms = n
	for i in n:
		var room = RoomGd.new(_gen_code(), default_settings.duplicate(), _rng)
		room.soak = true
		rooms[room.code] = room
		room.start(Time.get_ticks_msec(), ai_delay_ms, phase_delay_ms)
	print("[server] soak 压测启动: %d 个机器人房间" % n)


func _human_online(room, seat: int) -> bool:
	var seat_data = room.seats[seat]
	return seat_data != null and not bool(seat_data["bot"]) \
			and bool(seat_data["online"]) and int(seat_data["peer"]) >= 0


func _room_by_token(token: String) -> Dictionary:
	for code in rooms:
		var room = rooms[code]
		for s in 4:
			var seat_data = room.seats[s]
			if seat_data != null and str(seat_data["token"]) == token \
					and not bool(seat_data["bot"]):
				return {"room": room, "seat": s}
	return {}


func _gen_code() -> String:
	while true:
		var code := "%06d" % _rng.randi_range(0, 999999)
		if not rooms.has(code):
			return code
	return ""
