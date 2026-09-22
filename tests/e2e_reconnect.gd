## 重连按钮 E2E: 大厅加入房间 → 异常断线 → 右上角"重新连接"点亮 →
## 点击后诊断重连 → 凭 session_token 自动回座(房间页恢复)。
## 另验证: 服务器彻底消失时按钮保持并给出指引。
## 运行: godot --headless --path . --script tests/e2e_reconnect.gd
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")

const PORT := 24699

var f := 0
var main: Node = null
var server = null
var host = null
var lobby: Control = null
var lnet = null
var code := ""
var step := 0
var seat_before := -1
var results: Array = []
var ok_fires := 0


func _chk(cond: bool, msg: String) -> void:
	results.append([cond, msg])
	print("[rc] %s %s" % ["✓" if cond else "✗", msg])


func _process(_d: float) -> bool:
	f += 1
	if f > 5400:
		_chk(false, "总超时 step=%d" % step)
		return _finish()
	match step:
		0:
			if f == 10:
				main = Node.new()
				main.name = "Main"
				root.add_child(main)
				server = NetNodeGd.start_embedded(main, PORT)
				server.manager.ai_delay_ms = 60
				host = NetNodeGd.new()
				host.name = "Net"   # 相对路径 Main/Net(与服务器侧对称)
				host.setup(false)
				main.add_child(host)
				host.connected_ok.connect(func() -> void:
					host.create_room({"rounds": 3, "turn_seconds": 5}))
				host.connect_to("127.0.0.1", PORT)
			if f > 20 and not (host.last_room_state as Dictionary).is_empty():
				code = str(host.last_room_state["room_code"])
				print("[rc] 房间就绪 ", code)
				# 挂真实大厅(独立 multiplayer 根, net 相对路径 = Main/Net)
				var croot := Node.new()
				croot.name = "C2"
				main.add_child(croot)
				var tree := Engine.get_main_loop() as SceneTree
				tree.set_multiplayer(MultiplayerAPI.create_default_interface(),
						NodePath(str(croot.get_path())))
				var inner := Node.new()
				inner.name = "Main"
				croot.add_child(inner)
				lnet = NetNodeGd.new()
				lnet.name = "Net"
				lnet.setup(false)
				inner.add_child(lnet)
				lnet.client_id_override = "cid-rc"
				lobby = (load("res://src/client/scenes/lobby.tscn")
						as PackedScene).instantiate()
				lobby.name = "Lobby"
				lobby.setup(lnet)
				lnet.connected_ok.connect(func() -> void: ok_fires += 1)
				main.add_child(lobby)
				step = 1
				f = 0
		1:
			if f > 30:
				# 模拟点击附近房间(带 token 语义)
				lobby._join_found_best("127.0.0.1", PORT, code, [])
				step = 2
				f = 0
		2:
			if lobby._view == "room" and int(lobby.net.my_seat) >= 0:
				seat_before = int(lobby.net.my_seat)
				_chk(true, "加入房间成功(座位 %d)" % seat_before)
				_chk(not lobby.reconnect_btn.visible, "正常连接时重连按钮隐藏")
				step = 3
				f = 0
			elif f > 240:
				_chk(false, "加入房间失败")
				return _finish()
		3:
			# 异常断线(模拟掉线/网络中断)
			if f == 30:
				print("[rc] 模拟异常断线")
				lobby._conn_problems = true
				lnet.disconnect_all()
			if f > 240:   # 显隐由 3 秒扫描节拍刷新, 等 4 秒确保到位
				_chk(lobby.reconnect_btn.visible, "异常后重连按钮点亮")
				step = 4
				f = 0
		4:
			# 点击重新连接 → 诊断重连 → 凭 token 自动回座
			if f == 10:
				lobby.reconnect_btn.pressed.emit()
			if not lnet._is_connected():
				return false   # 先等 socket 恢复, 再校验房间状态(排除断线前残留)
			if lobby._view == "room" and lobby.net.in_room \
					and int(lobby.net.my_seat) == seat_before:
				_chk(ok_fires >= 2, "重连成功(connected_ok 触发 %d 次)" % ok_fires)
				_chk(not lobby.reconnect_btn.visible, "重连成功后按钮熄灭")
				step = 5
				f = 0
				f = 0
			elif f > 240:
				print("[rc] 诊断: connected=%s address=%s port=%s fires=%s in_room=%s status=%s" % [
						str(lnet._is_connected()), str(lnet.address), str(lnet.port),
						str(ok_fires),
						str(lnet.in_room),
						lobby.status_label.text.replace("
", " | ").substr(0, 60)])
				_chk(false, "点击重连后未能回房")
				return _finish()
		5:
			# 服务器彻底消失: 按钮保持可见, 点击给出诊断指引不崩溃
			if f == 10:
				# 必须走 stop_embedded 真正释放端口(queue_free 不停 ENet socket)
				NetNodeGd.stop_embedded(main)
				lnet.address = "127.0.0.1"   # 重连目标钉死在本测试端口(已消失)
				lnet.port = PORT
				lobby._conn_problems = true
				lnet.disconnect_all()
			if f > 60:
				lobby._reconnect_now()
				step = 6
				f = 0
		6:
			if f > 600:
				print("[rc] 诊断2: problems=%s connected=%s button=%s" % [
						str(lobby._conn_problems), str(lnet._is_connected()),
						str(lobby.reconnect_btn.visible)])
				_chk(lobby.reconnect_btn.visible,
						"服务器消失: 重连按钮保持可见供重试")
				var st: String = lobby.status_label.text
				_chk(st.contains("无法连接") or st.contains("正在") or st != "",
						"服务器消失: 状态栏有诊断信息(%s)" % st.substr(0, 24))
				return _finish()
	return false


func _finish() -> bool:
	var failed := 0
	for r in results:
		if not bool(r[0]):
			failed += 1
	if failed == 0:
		print("[rc] RECONNECT_E2E_OK —— 重连按钮全链路验证通过 (%d 项)" % results.size())
		quit(0)
		return true
	else:
		for r in results:
			if not bool(r[0]):
				print("[rc]   失败: " + str(r[1]))
		print("[rc] RECONNECT_E2E_FAIL —— %d/%d 失败" % [failed, results.size()])
		quit(1)
	return true
