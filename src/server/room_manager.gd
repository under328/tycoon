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
const SKINS := ["skin_aka", "skin_ao", "skin_kitsu", "skin_oiran", "skin_tengu", "skin_default", "skin_dball", "skin_ninja", "skin_rx"]
## 房间总数上限: 空房不会自动销毁(等待房主回房), 防异常客户端刷爆内存
const MAX_ROOMS := 200

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
## 身份簿: client_id → 最近一次上报的昵称(持久化 user://identity.json)。
## 重装后游客 id 由设备稳定 ID 派生而不变 → 凭它免备份码找回昵称。
var identity_book: Dictionary = {}

const IDENTITY_PATH := "user://identity.json"


func _init() -> void:
	_rng.randomize()
	stats = StatsGd.new()
	var f := FileAccess.open(IDENTITY_PATH, FileAccess.READ)
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			identity_book = parsed


# ---------------------------------------------------------------- 连接与会话

func hello(peer: int, ver: int, token: String, client_id: String = "",
		skin_id: String = "", card_id: String = "", nick: String = "") -> Array:
	var out := []
	# 有人回到房间而对局已结束(game_end) → 立即收尾该局:
	# 否则重入者会收到上局 game_end 视图, 看到"上局结算界面"而非新局。
	for code in rooms.keys():
		var r0 = rooms[code]
		if r0.match_ctl != null 				and str(r0.match_ctl.state.get("phase", "")) == "game_end":
			r0.end_match()
			_bcast_room_state(out, r0)
	if skin_id != "":
		peer_skin[peer] = skin_id
	if ver != MsgC.PROTOCOL_VERSION:
		# 版本不一致: 带上双方协议版本, 客户端能给出明确指引(常见于一方未更新)
		out.append({"peer": peer, "event": "s_kicked",
				"data": {"reason": "version", "server_ver": MsgC.PROTOCOL_VERSION,
						"client_ver": int(ver)}})
		return out
	if client_id != "":
		peer_client[peer] = client_id
		# 身份簿: 实名上报即记录; 默认昵称(重装后)则回执找回
		var saved_nick := str(identity_book.get(client_id, ""))
		if nick != "" and nick != "玩家":
			if saved_nick != nick:
				identity_book[client_id] = nick
				_save_identity_book()
		elif (nick == "" or nick == "玩家") and saved_nick != "" \
				and saved_nick != "玩家":
			out.append({"peer": peer, "event": "s_identity",
					"data": {"nickname": saved_nick}})
	# 已在房间的 peer(如 quick_match 先于 hello 到达): 直接回报正确座位
	var known_code = peer_room.get(peer, "")
	if known_code != "":
		var known = rooms.get(known_code)
		if known != null:
			var s0: int = known.seat_of_peer(peer)
			if s0 >= 0:
				var sd: Dictionary = known.seats[s0]
				sd["online"] = true
				sd["offline_ms"] = 0
				if card_id != "":
					sd["card_id"] = card_id
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
			seat_data["offline_ms"] = 0
			if skin_id != "":
				seat_data["skin_id"] = skin_id
			if card_id != "":
				seat_data["card_id"] = card_id
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
		# 房间内断线: 保留座位 30s 宽限(token 重连自动归位),
		# 避免 WiFi 抖动/手机息屏就把玩家直接移出房间
		room.seats[seat]["online"] = false
		room.seats[seat]["offline_ms"] = int(Time.get_ticks_msec())
		_bcast_room_state(out, room)
	return out


# ---------------------------------------------------------------- 房间操作

func quick_match(peer: int, name: String, rules: Dictionary, client_id: String = "",
		skin_id: String = "", card_id: String = "") -> Array:
	var out := []
	if client_id != "":
		peer_client[peer] = client_id
	if skin_id != "":
		peer_skin[peer] = skin_id
	for code in rooms:
		var room = rooms[code]
		if room.match_ctl == null and room.first_free_seat() >= 0:
			return join_room(peer, name, code, client_id, skin_id)
	return create_room(peer, name, rules, client_id, skin_id, card_id)


func create_room(peer: int, name: String, rules: Dictionary, client_id: String = "",
		skin_id: String = "", card_id: String = "") -> Array:
	var out := []
	if _in_live_match(peer):
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": "in_game", "msg": "你所在的对局尚未结束"}})
		return out
	if rooms.size() >= MAX_ROOMS:
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": "room_limit", "msg": "服务器房间已满, 请稍后再试"}})
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
	room.sit(peer, name, client_id, skin_id, card_id)
	peer_room[peer] = room.code
	out.append({"peer": peer, "event": "s_room_state",
			"data": room.state_for(room.seat_of_peer(peer))})
	return out


func join_room(peer: int, name: String, code: String, client_id: String = "",
		skin_id: String = "", card_id: String = "") -> Array:
	var out := []
	if _in_live_match(peer):
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": "in_game", "msg": "你所在的对局尚未结束"}})
		return out
	if client_id != "":
		peer_client[peer] = client_id
	if client_id == "":
		client_id = str(peer_client.get(peer, ""))   # join 载荷缺 id 时用 hello 登记的
	if skin_id != "":
		peer_skin[peer] = skin_id
	var room = rooms.get(code)
	if room == null:
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": "no_room", "msg": "房间不存在"}})
		return out
	# 同一玩家(client_id)的离线座位直接归位 — 否则"退出→重进"会开出第二个
	# 座位(旧的显示 离线·AI 代管), 同人出现两次。对局中的座位也归位:
	# 主动退出后重进拿回自己的座位, 而不是被 in_game 拒之门外。
	var reseat: int = room.seat_of_client(client_id)
	if reseat >= 0 and not bool(room.seats[reseat]["online"]):
		if peer_room.has(peer) and str(peer_room[peer]) != room.code:
			_leave_room(peer, out)   # 从别的房间正确退出后再归位本房
		var sd: Dictionary = room.seats[reseat]
		peer_room.erase(int(sd["peer"]))   # 旧 peer 仍占用则顶替
		sd["peer"] = peer
		sd["online"] = true
		sd["offline_ms"] = 0
		if name != "":
			sd["name"] = name
		if skin_id != "":
			sd["skin_id"] = skin_id
		if card_id != "":
			sd["card_id"] = card_id
		if room.match_ctl != null:
			room.match_ctl.seat_peer[reseat] = peer
			room.match_ctl.seat_online[reseat] = true
		peer_room[peer] = room.code
		out.append({"peer": peer, "event": "s_room_state",
				"data": room.state_for(reseat)})
		# 已退出本场者只归位到房间页, 不补发对局视图(否则会被重新拉回
		# 牌桌/竞技场, 且其操作全被 left 拒绝 → 卡在游戏界面进不了房间)
		if room.match_ctl != null and not room.match_ctl.has_left(reseat):
			out.append(_view_msg(room, reseat))
		_bcast_room_state(out, room)
		return out
	if room.match_ctl != null:
		# 对局进行中: 普通/肉鸽允许朋友接管一个 AI 座位加入共享对局
		# (命运卡由当前天选者代选, 其余与同桌完全同步); 格斗对战座位固定, 拒绝。
		if str(room.settings.get("mode", "")) != "fight":
			var bot_seat := -1
			for s in 4:
				var sd0 = room.seats[s]
				if sd0 != null and bool(sd0["bot"]):
					bot_seat = s
					break
			if bot_seat >= 0:
				if peer_room.has(peer) and str(peer_room[peer]) != room.code:
					_leave_room(peer, out)
				var token: String = room.claim_bot_seat(bot_seat, peer, name,
						client_id, skin_id, card_id)
				room.match_ctl.seat_peer[bot_seat] = peer
				room.match_ctl.seat_online[bot_seat] = true
				if room.match_ctl.state.has("names") 						and (room.match_ctl.state["names"] as Array).size() == 4:
					room.match_ctl.state["names"][bot_seat] = name
				room.match_ctl.state["names"] = room.match_ctl.state["names"]
				peer_room[peer] = room.code
				var rs: Dictionary = room.state_for(bot_seat)
				rs["session_token"] = token
				out.append({"peer": peer, "event": "s_room_state", "data": rs})
				out.append(_view_msg(room, bot_seat))   # 立即进入共享对局
				_bcast_room_state(out, room)
				return out
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": "in_game",
						"msg": "该房间对局进行中, 对局结束后可加入"}})
		return out
	_leave_room(peer, out)
	var seat: int = room.sit(peer, name, client_id, skin_id, card_id)
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


## 局域网发现: 对外可见的房间概览(压测房间不公开;
## 有空位且未开局才标 open — 客户端只把 open 房间列为可点)
func discovery_snapshot() -> Array:
	var out: Array = []
	for code in rooms:
		var room = rooms[code]
		if room.soak:
			continue
		var players := 0
		for s in room.seats:
			if s != null:
				players += 1
		if players >= 4:
			continue
		out.append({
			"code": code,
			"players": players,
			"cap": 4,
			"open": room.match_ctl == null,
		})
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
	# 表情包贴纸(id 100..107)原样透传; 普通表情仍限 0..7
	var eid := id
	if id >= 100:
		eid = 100 + clampi(id - 100, 0, 7)
	else:
		eid = clampi(id, 0, 7)
	_bcast_event(out, room, "s_emoji", {"seat": seat, "id": eid})
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


## 转让房主: 仅房主可操作; 目标须为房内真人座位且非自己; 对局进行中不可转让
func transfer_host(host_peer: int, target_seat: int) -> Array:
	var out := []
	var room = _room_of(host_peer)
	if room == null or int(room.host_seat) != _seat_of(room, host_peer):
		return out
	if room.match_ctl != null or target_seat < 0 \
			or target_seat >= (room.seats as Array).size():
		return out
	var seat_data = room.seats[target_seat]
	if seat_data == null or bool(seat_data["bot"]) \
			or target_seat == _seat_of(room, host_peer):
		return out
	room.host_seat = target_seat
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


## 肉鸽 draft: 任意玩家选一张命运卡(先到先得)
func rogue_pick(peer: int, idx: int) -> Array:
	var out := []
	var room = _room_of(peer)
	if room == null or room.match_ctl == null:
		return out
	if str(room.match_ctl.state.get("phase", "")) != "draft":
		return out
	var seat: int = room.seat_of_peer(peer)
	var r: Dictionary = room.match_ctl.human_apply(
			{"t": "rogue_pick", "idx": idx, "seat": seat}, Time.get_ticks_msec())
	if not bool(r["changed"]):
		# 非天选者的迟到选择: 明确回执, 避免该客户端卡在等待
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": str(r.get("error", "invalid")),
						"msg": "本轮命运卡不由你选择"}})
		return out
	_after_state_change(out, room, r)
	return out


## 格斗对战: 选牌(候选/槽位/跳过由 data 携带; 仅格斗者座位合法)
func fight_pick(peer: int, data: Dictionary) -> Array:
	var out := _fight_action(peer, "pick", data)
	return out


## 格斗对战: 回合行动 attack/skill/defend(仅当前回合格斗者合法)
func fight_act(peer: int, action: String) -> Array:
	return _fight_action(peer, "act", action)


func _fight_action(peer: int, kind: String, payload) -> Array:
	var out := []
	var room = _room_of(peer)
	if room == null or room.match_ctl == null \
			or str(room.match_ctl.kind) != "fight":
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": "no_match", "msg": "没有进行中的格斗对局"}})
		return out
	var seat: int = room.seat_of_peer(peer)
	if room.match_ctl.has_left(seat):
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": "left_match", "msg": "已退出本场对局"}})
		return out
	var r: Dictionary
	if kind == "pick":
		var data: Dictionary = payload
		r = room.match_ctl.human_pick(seat, int(data.get("cand", -1)),
				int(data.get("slot", -1)), Time.get_ticks_msec())
	else:
		r = room.match_ctl.human_act(seat, str(payload), Time.get_ticks_msec())
	if not bool(r["changed"]):
		# 过期操作(客户端视图落后于服务器状态): 除错误外补发该座位当前视图,
		# 否则客户端会拿旧 pair/旧回合无限重试, 永远无法重新同步(死锁)
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": str(r.get("error", "invalid")), "msg": "非法操作"}})
		if seat >= 0 and room.match_ctl.state["per"].has(seat):
			out.append({"peer": peer, "event": "s_fight_state",
					"data": {"view": room.match_ctl.view_for(seat), "events": []}})
		return out
	_bcast_fight(out, room, r.get("events", []))
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
	if ctl.has_left(seat):
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": "left_match", "msg": "已退出本场对局"}})
		return out
	action["seat"] = seat
	var r: Dictionary = ctl.human_apply(action, now_ms)
	if not bool(r["changed"]):
		out.append({"peer": peer, "event": "s_error",
				"data": {"code": str(r.get("error", "invalid")), "msg": "非法操作"}})
		return out
	_after_state_change(out, room, r)
	return out


## 退出本场对局(人留在房间): 座位转 AI 代管; 全员退出 → 立即收尾。
## 返回房间页的玩家收到 room_state(座位仍在, 可等下一局)。
func game_leave(peer: int) -> Array:
	var out := []
	var room = _room_of(peer)
	if room == null or room.match_ctl == null:
		return out
	var seat: int = room.seat_of_peer(peer)
	if seat < 0:
		return out
	room.match_ctl.leave(seat)
	# 对局内系统提示: 留在牌桌的玩家从聊天栏看到"XX 退出了对局(AI 代管)"
	var seat_data = room.seats[seat]
	var nm: String = str(seat_data["name"]) if seat_data != null else ""
	_bcast_event(out, room, "s_chat", {"seat": seat,
			"text": TranslationServer.translate("退出了对局（AI 代管）")
					+ (" · " + nm if nm != "" else "")})
	if room.match_ctl.all_humans_left():
		room.end_match()
	_bcast_room_state(out, room)
	return out


## 格斗: 退出本场(留在房间); 双方都退出 → 立即收尾。
func fight_leave(peer: int) -> Array:
	var out := []
	var room = _room_of(peer)
	if room == null or room.match_ctl == null \
			or str(room.match_ctl.kind) != "fight":
		return out
	var seat: int = room.seat_of_peer(peer)
	if seat < 0:
		return out
	room.match_ctl.leave(seat)
	if room.match_ctl.all_humans_left():
		room.end_match()
	_bcast_room_state(out, room)
	return out


# ---------------------------------------------------------------- 时钟驱动

func tick(now_ms: int) -> Array:
	var out := []
	# 大厅离线宽限扫描: 断线未归超过 30s 的座位移除(对局中由 match_ctl 处理)
	for code in rooms.keys():
		var room0 = rooms[code]
		if room0.match_ctl == null:
			var changed := false
			for s in room0.seats.size():
				var sd = room0.seats[s]
				if sd != null and not bool(sd["online"]) \
						and int(sd.get("offline_ms", 0)) > 0 \
						and now_ms - int(sd["offline_ms"]) > 30000:
					room0.remove_seat(s)
					changed = true
			if changed:
				if room0.is_empty():
					rooms.erase(code)
				else:
					_bcast_room_state(out, room0)
	for code in rooms.keys():
		var room = rooms[code]
		if room.match_ctl == null:
			continue
		var ctl = room.match_ctl
		if str(ctl.get("kind")) == "fight":
			_tick_fight(out, room, now_ms)
			continue
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


## 格斗房间时钟: AI/超时驱动 + 结束收尾
func _tick_fight(out: Array, room, now_ms: int) -> void:
	var ctl = room.match_ctl
	var r: Dictionary = ctl.tick(now_ms)
	if bool(r["changed"]):
		_bcast_fight(out, room, r.get("events", []))
	if ctl.game_finished(now_ms):
		room.end_match()
		_bcast_room_state(out, room)


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
		# 已退出本场(left)的座位不再收对局视图 — 防止客户端被重新拉回牌桌
		if _human_online(room, s) and not ctl.has_left(s):
			out.append(_view_msg(room, s))


func _view_msg(room, seat: int) -> Dictionary:
	var ctl = room.match_ctl
	if str(ctl.get("kind")) == "fight":
		return {"peer": int(room.seats[seat]["peer"]), "event": "s_fight_state",
				"data": {"view": ctl.view_for(seat), "events": []}}
	var view := ViewGd.build(ctl.state, seat)
	var data := {"view": view}
	if str(ctl.state["phase"]) == "play":
		data["turn_seat"] = int(ctl.state["turn"])
	return {"peer": int(room.seats[seat]["peer"]), "event": "s_game_view", "data": data}


## 格斗对战广播: 全房在线人类(格斗者+观战者)都收到按座位裁剪的战斗视图。
## 已退出本场(left)的座位不再广播 — 否则其客户端会被重新拉回竞技场。
func _bcast_fight(out: Array, room, events: Array) -> void:
	for s in 4:
		if _human_online(room, s) and not room.match_ctl.has_left(s):
			out.append({"peer": int(room.seats[s]["peer"]), "event": "s_fight_state",
					"data": {"view": room.match_ctl.view_for(s),
							"events": events}})


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


## net_node 路由用: peer → 所在房间(不在任何房间返回 null)。
func room_of_peer(peer: int):
	return _room_of(peer)


func _seat_of(room, peer: int) -> int:
	return room.seat_of_peer(peer)


func _save_identity_book() -> void:
	var f := FileAccess.open(IDENTITY_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(identity_book))


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
