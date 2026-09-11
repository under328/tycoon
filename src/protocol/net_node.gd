## 统一网络节点：服务器与客户端共用同一份脚本，保证 RPC 配置两端对称。
## 挂载路径必须两端一致：/root/Main/Net。
## 服务器模式：把 RPC 翻译为 RoomManager 纯逻辑调用并回发 out 队列。
## 客户端模式：连接/版本握手/session_token 自动重连/信号分发（UI 无关）。
extends Node

signal connected_ok
signal connection_failed
signal server_disconnected
signal welcomed(seat: int)
signal rejoined
signal room_state(state: Dictionary)
signal view_changed(view: Dictionary)
signal game_event(event: String, data: Dictionary)
signal errored(code: String, msg: String)
signal kicked_off(reason: String)
signal stats_updated(entry: Dictionary)

const MsgC = preload("res://src/protocol/msg.gd")
const ManagerGd = preload("res://src/server/room_manager.gd")
const BotPlayerGd = preload("res://src/rules/ai/bot_player.gd")

var is_server := false

# --- 服务器侧 ---
var manager = null
var _health := TCPServer.new()
var _health_peers: Array = []
var _log_accum := 0.0

# --- 客户端侧 ---
var latest_view: Dictionary = {}
var last_room_state: Dictionary = {}
var my_seat := -1
var in_room := false
var autoplay := false          # E2E：轮到自己自动出牌
var address := "127.0.0.1"
var port := 24565
var auto_reconnect := true     # 掉线后凭 token 自动重连
var _session_token := ""
var _want_connection := false
var _retry_timer := 0.0
var _autoplay_armed := false
var _had_view := false
var _welcomed := false
var _pending_ops: Array = []   # 握手完成前缓存的房间操作


func setup(p_is_server: bool) -> void:
	is_server = p_is_server


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_conn_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if is_server:
		# AppMode autoload 在 E2E SceneTree 环境不存在 → 兼容取默认值
		var am := get_node_or_null("/root/AppMode")
		var port_v := 24565
		var ai_ms := 600
		var phase_ms := 2200
		if am != null:
			port_v = int(am.port)
			ai_ms = int(am.ai_delay_ms)
			phase_ms = int(am.phase_delay_ms)
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_server(port_v, 64)
		if err != OK:
			push_error("服务器启动失败 port=%d err=%d" % [port_v, err])
			return
		multiplayer.multiplayer_peer = peer
		manager = ManagerGd.new()
		manager.ai_delay_ms = ai_ms
		manager.phase_delay_ms = phase_ms
		# 健康检查: HTTP GET http://<host>:%d/ → JSON 状态（运维探活用）
		if _health.listen(port_v + 1) == OK:
			print("[server] 健康检查端口 http=%d" % (port_v + 1))
		print("[server] Tycoon 服务器已启动 端口=%d ai_delay=%dms phase_delay=%dms" % [
			port_v, ai_ms, phase_ms])


func _process(delta: float) -> void:
	if is_server:
		if manager != null:
			_flush(manager.tick(Time.get_ticks_msec()))
		_poll_health(delta)
	else:
		_client_process(delta)


func _poll_health(delta: float) -> void:
	_log_accum += delta
	if _log_accum >= 60.0:
		_log_accum = 0.0
		print("[server] rooms=%d players=%d uptime=%ds" % [
			manager.rooms.size(), manager.peer_room.size(),
			int(Time.get_ticks_msec() / 1000.0)])
	if _health.is_listening():
		while _health.is_connection_available():
			var s: StreamPeerTCP = _health.take_connection()
			var body := "{\"status\":\"ok\",\"rooms\":%d,\"players\":%d,\"uptime\":%d}" % [
				manager.rooms.size(), manager.peer_room.size(),
				int(Time.get_ticks_msec() / 1000.0)]
			var resp := "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [
				body.to_utf8_buffer().size(), body]
			s.put_data(resp.to_utf8_buffer())
			_health_peers.append({"s": s, "t": 0.3})
	var keep: Array = []
	for e in _health_peers:
		e["t"] -= delta
		if e["t"] > 0.0:
			keep.append(e)
		else:
			(e["s"] as StreamPeerTCP).disconnect_from_host()
	_health_peers = keep


func _on_peer_disconnected(peer: int) -> void:
	if is_server and manager != null:
		_flush(manager.peer_gone(peer))


# ================================================================ C → S

@rpc("any_peer", "call_remote", "reliable")
func c_hello(ver: int, token: String, client_id: String) -> void:
	if not is_server:
		return
	_flush(manager.hello(multiplayer.get_remote_sender_id(), ver, str(token), str(client_id)))


@rpc("any_peer", "call_remote", "reliable")
func c_room_quick(data: Dictionary) -> void:
	if not is_server:
		return
	_flush(manager.quick_match(_sender(), str(data.get("name", "玩家")),
			data.get("rules", {}), str(data.get("client_id", ""))))


@rpc("any_peer", "call_remote", "reliable")
func c_room_create(data: Dictionary) -> void:
	if not is_server:
		return
	_flush(manager.create_room(_sender(), str(data.get("name", "玩家")),
			data.get("rules", {}), str(data.get("client_id", ""))))


@rpc("any_peer", "call_remote", "reliable")
func c_room_join(data: Dictionary) -> void:
	if not is_server:
		return
	_flush(manager.join_room(_sender(), str(data.get("name", "玩家")),
			str(data.get("code", "")), str(data.get("client_id", ""))))


@rpc("any_peer", "call_remote", "reliable")
func c_room_settings(data: Dictionary) -> void:
	if not is_server:
		return
	_flush(manager.set_settings(_sender(), data.get("rules", {})))


@rpc("any_peer", "call_remote", "reliable")
func c_emoji(data: Dictionary) -> void:
	if not is_server:
		return
	_flush(manager.emoji(_sender(), int(data.get("id", 0))))


@rpc("any_peer", "call_remote", "reliable")
func c_chat(data: Dictionary) -> void:
	if not is_server:
		return
	_flush(manager.chat(_sender(), str(data.get("text", ""))))


@rpc("any_peer", "call_remote", "reliable")
func c_stats(_data: Dictionary) -> void:
	if not is_server:
		return
	_flush(manager.stats_get(_sender()))


@rpc("any_peer", "call_remote", "reliable")
func c_room_leave(_data: Dictionary) -> void:
	if not is_server:
		return
	_flush(manager.leave(_sender()))


@rpc("any_peer", "call_remote", "reliable")
func c_room_kick(data: Dictionary) -> void:
	if not is_server:
		return
	_flush(manager.kick(_sender(), int(data.get("seat", -1))))


@rpc("any_peer", "call_remote", "reliable")
func c_bot_fill(_data: Dictionary) -> void:
	if not is_server:
		return
	_flush(manager.fill_bots(_sender()))


@rpc("any_peer", "call_remote", "reliable")
func c_room_start(_data: Dictionary) -> void:
	if not is_server:
		return
	_flush(manager.start(_sender()))


@rpc("any_peer", "call_remote", "reliable")
func c_game_play(data: Dictionary) -> void:
	if not is_server:
		return
	_flush(manager.play(_sender(), data.get("cards", [])))


@rpc("any_peer", "call_remote", "reliable")
func c_game_pass(_data: Dictionary) -> void:
	if not is_server:
		return
	_flush(manager.pass_turn(_sender()))


# ================================================================ S → C

@rpc("authority", "call_remote", "reliable")
func s_welcome(data: Dictionary) -> void:
	my_seat = int(data.get("seat", -1))
	if my_seat >= 0:
		in_room = true
		if _had_view:
			rejoined.emit()
	_welcomed = true
	welcomed.emit(my_seat)
	_flush_pending()


@rpc("authority", "call_remote", "reliable")
func s_room_state(data: Dictionary) -> void:
	if is_server:
		return
	in_room = true
	if data.has("session_token"):
		_session_token = str(data["session_token"])
	if int(data.get("my_seat", -1)) >= 0:
		my_seat = int(data["my_seat"])
	last_room_state = data.duplicate(true)
	room_state.emit(data)


@rpc("authority", "call_remote", "reliable")
func s_game_view(data: Dictionary) -> void:
	if is_server:
		return
	var view: Dictionary = data.get("view", {})
	latest_view = view
	my_seat = int(view.get("my_seat", my_seat))
	_had_view = true
	_autoplay_armed = true  # 每个新 view 重新武装一次自动出牌
	if data.has("turn_seat"):
		game_event.emit("turn", {"seat": int(data["turn_seat"])})
	view_changed.emit(view)


@rpc("authority", "call_remote", "reliable")
func s_game_played(data: Dictionary) -> void:
	if is_server:
		return
	game_event.emit("played", data)


@rpc("authority", "call_remote", "reliable")
func s_game_cleared(data: Dictionary) -> void:
	if is_server:
		return
	game_event.emit("cleared", data)


@rpc("authority", "call_remote", "reliable")
func s_revolution(data: Dictionary) -> void:
	if is_server:
		return
	game_event.emit("revolution", data)


@rpc("authority", "call_remote", "reliable")
func s_round_end(data: Dictionary) -> void:
	if is_server:
		return
	game_event.emit("round_end", data)


@rpc("authority", "call_remote", "reliable")
func s_exchange(data: Dictionary) -> void:
	if is_server:
		return
	game_event.emit("exchange", data)


@rpc("authority", "call_remote", "reliable")
func s_game_end(data: Dictionary) -> void:
	if is_server:
		return
	game_event.emit("game_end", data)


@rpc("authority", "call_remote", "reliable")
func s_kicked(data: Dictionary) -> void:
	if is_server:
		return
	var reason: String = str(data.get("reason", ""))
	if reason == "version":
		auto_reconnect = false
		_want_connection = false
	in_room = false
	kicked_off.emit(reason)


@rpc("authority", "call_remote", "reliable")
func s_emoji(data: Dictionary) -> void:
	if is_server:
		return
	game_event.emit("emoji", data)


@rpc("authority", "call_remote", "reliable")
func s_chat(data: Dictionary) -> void:
	if is_server:
		return
	game_event.emit("chat", data)


@rpc("authority", "call_remote", "reliable")
func s_stats(data: Dictionary) -> void:
	if is_server:
		return
	stats_updated.emit(data.get("your", {}))


@rpc("authority", "call_remote", "reliable")
func s_error(data: Dictionary) -> void:
	if is_server:
		return
	errored.emit(str(data.get("code", "")), str(data.get("msg", "")))


# ================================================================ 客户端 API

func connect_to(p_address: String, p_port: int) -> bool:
	if is_server:
		return false
	address = p_address
	port = p_port
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		errored.emit("connect_fail", "无法创建连接")
		return false
	multiplayer.multiplayer_peer = peer
	_want_connection = true
	return true


## E2E 用：模拟断网（保留 token，自动重连）
func drop_connection() -> void:
	if is_server:
		return
	var peer = multiplayer.multiplayer_peer
	if peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		peer.close()


func leave_room() -> void:
	if _is_connected():
		_c_send("c_room_leave", {})
	_session_token = ""
	in_room = false
	my_seat = -1
	latest_view = {}


func disconnect_all() -> void:
	_want_connection = false
	auto_reconnect = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null


func quick_match(rules: Dictionary = {}) -> void:
	_c_send("c_room_quick", {"name": _name(), "rules": rules})


func create_room(rules: Dictionary = {}) -> void:
	_c_send("c_room_create", {"name": _name(), "rules": rules})


func join_room(code: String) -> void:
	_c_send("c_room_join", {"name": _name(), "code": code})


func fill_bots() -> void:
	_c_send("c_bot_fill", {})


func start_game() -> void:
	_c_send("c_room_start", {})


func play(cards: Array) -> void:
	_c_send("c_game_play", {"cards": cards})


func pass_turn() -> void:
	_c_send("c_game_pass", {})


## 房主：修改房间规则（对局未开始时）
func set_settings(rules: Dictionary) -> void:
	_c_send("c_room_settings", {"rules": rules})


## 快捷表情（房间内）
func send_emoji(id: int) -> void:
	_c_send("c_emoji", {"id": id})


## 房内文本聊天
func send_chat(text: String) -> void:
	_c_send("c_chat", {"text": text})


## 请求自己的战绩
func request_stats() -> void:
	_c_send("c_stats", {})


# ================================================================ 内部

func _client_process(delta: float) -> void:
	if _want_connection and not _is_connected():
		_retry_timer -= delta
		if _retry_timer <= 0.0:
			_retry_timer = 2.0
			connect_to(address, port)
	if autoplay:
		_autoplay_tick()


func _is_connected() -> bool:
	var peer = multiplayer.multiplayer_peer
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _on_connected() -> void:
	connected_ok.emit()
	_retry_timer = 0.0
	_c_send("c_hello", {})


func _on_conn_failed() -> void:
	if not auto_reconnect:
		connection_failed.emit()


func _on_server_disconnected() -> void:
	latest_view = {}
	_welcomed = false
	if auto_reconnect and _want_connection:
		_retry_timer = 2.0
	server_disconnected.emit()


func _c_send(event: String, data: Dictionary) -> void:
	if not _is_connected():
		errored.emit("not_connected", "未连接服务器")
		return
	if event == "c_hello":
		rpc_id(1, "c_hello", MsgC.PROTOCOL_VERSION, _session_token, _client_id(), _client_skin())
		return
	# 握手(welcome)完成前, 房间操作排队——服务器必须先知道座位归属
	if not _welcomed:
		_pending_ops.append([event, data])
		if _pending_ops.size() > 20:
			_pending_ops.pop_front()
		return
	rpc_id(1, event, data)


func _flush_pending() -> void:
	for op in _pending_ops:
		rpc_id(1, op[0], op[1])
	_pending_ops.clear()


## 查询某座位当前皮肤（联机），无数据返回空串
func skin_of_seat(seat: int) -> String:
	if last_room_state.is_empty():
		return ""
	for p in last_room_state.get("players", []):
		if int(p.get("seat", -1)) == seat:
			return str(p.get("skin_id", "skin_default"))
	return ""


func _client_skin() -> String:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		return str(gs.equipped_skin)
	return "skin_default"


func _client_id() -> String:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		return str(gs.client_id)
	return "e2e-client"


func _name() -> String:
	# 兼容无 autoload 的 E2E 环境
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		return str(gs.nickname)
	return "玩家"


func _flush(out: Array) -> void:
	if manager == null:
		return
	for m in out:
		var peer: int = m["peer"]
		if multiplayer.get_peers().has(peer):
			rpc_id(peer, m["event"], m["data"])


func _sender() -> int:
	return multiplayer.get_remote_sender_id()


func _autoplay_tick() -> void:
	if not _autoplay_armed or latest_view.is_empty() or my_seat < 0:
		return
	if str(latest_view["phase"]) != "play":
		return
	if int(latest_view["turn"]) != my_seat:
		return
	_autoplay_armed = false
	var action := BotPlayerGd.decide_from_view(latest_view)
	if str(action.get("t")) == "play":
		play(action.get("cards", []))
	else:
		pass_turn()
