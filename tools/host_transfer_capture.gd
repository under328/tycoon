## 转让房主 E2E 截图: 双进程 —
##   host: godot --path . --script tools/host_transfer_capture.gd -- host
##   join: godot --path . --script tools/host_transfer_capture.gd -- join
## 流程: 房主建房并发布房间码 → 乙加入 → 房主视角可见乙座位的 👑 →
##       点击 👑 弹确认框 → 确认 → 广播后 host_seat 变为乙 → XFER_OK。
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")

var main: Node = null
var net = null
var last_room_state := {}
var role := "host"
var f := 0
var st := 0
var st_f := 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	for a in OS.get_cmdline_user_args():
		role = a


func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("builds/%s.png" % name)
	print("[cap] %s saved" % name)


func _process(_delta: float) -> bool:
	f += 1
	st_f += 1
	if role == "host":
		return _host_flow()
	return _join_flow()


func _host_flow() -> bool:
	match st:
		0:
			if f == 10:
				main = (load("res://src/client/main.tscn") as PackedScene).instantiate()
				root.add_child(main)
			elif f == 30:
				main._start_online()
			elif f == 40:
				# 固定测试端口(与 join 侧一致; 避免与常驻服务器端口冲突)
				for c in root.get_children():
					if c.name == "GameSettings":
						c.host_port = 24695
				main._start_host()
			elif f == 50:
				net = main.lobby.net
				net.room_state.connect(func(s: Dictionary) -> void:
					last_room_state = s)
				st = 1
				st_f = 0
		1:
			if main.lobby != null and str(main.lobby._view) == "room" \
					and str(main.lobby._last_room_code) != "":
				var cf := FileAccess.open("user://transfer_code.txt", FileAccess.WRITE)
				cf.store_string(str(main.lobby._last_room_code))
				cf.close()
				print("[xfer] 房间码已发布: ", main.lobby._last_room_code)
				st = 2
				st_f = 0
		2:
			if st_f > 900:
				print("[xfer] FAIL 等待乙加入超时")
				quit(1)
				return true
			var humans := 0
			for p in last_room_state.get("players", []):
				if not bool(p.get("empty", true)) and not bool(p.get("is_bot", false)):
					humans += 1
			if humans >= 2 and st_f > 10:
				print("[xfer] 乙已加入, 乙座位转让按钮 visible=",
						str(main.lobby._transfer_btns[1].visible))
				_shot("xfer_host_view")
				# 点击乙座位的转让按钮 → 弹确认框
				main.lobby._transfer_btns[1].pressed.emit()
				st = 3
				st_f = 0
		3:
			if st_f == 25:
				_shot("xfer_confirm")
				var ok_btn := _find_btn(main.lobby._xfer_overlay, "确认转让")
				if ok_btn == null:
					print("[xfer] FAIL 确认弹窗缺少确认按钮")
					quit(1)
					return true
				ok_btn.pressed.emit()
				print("[xfer] 已确认转让")
			elif st_f > 45:
				st = 4
				st_f = 0
		4:
			if int(last_room_state.get("host_seat", -1)) == 1:
				_shot("xfer_done")
				print("[xfer] XFER_OK —— 房主已转让给乙(host_seat=1)")
				quit(0)
			elif st_f > 200:
				print("[xfer] FAIL 转让后 host_seat 未变更: ",
						str(last_room_state.get("host_seat", "?")))
				quit(1)
	return false


func _join_flow() -> bool:
	match st:
		0:
			if f == 10:
				var holder := Node.new()
				holder.name = "Main"
				root.add_child(holder)
				net = NetNodeGd.new()
				net.name = "Net"
				net.setup(false)
				holder.add_child(net)
				net.autoplay = true
				st = 1
				st_f = 0
		1:
			var cf := FileAccess.open("user://transfer_code.txt", FileAccess.READ)
			if cf == null:
				if f > 900:
					print("[xfer:join] FAIL 房间码文件超时")
					quit(1)
				return false
			var code := cf.get_as_text().strip_edges()
			cf.close()
			if code == "":
				return false
			print("[xfer:join] 连接主机后加入房间 ", code)
			net.connected_ok.connect(func() -> void:
				print("[xfer:join] 已连接, 发送加入请求")
				net.join_room(code))
			net.connect_to("127.0.0.1", 24695)
			st = 2
			st_f = 0
		2:
			if st_f > 900:
				print("[xfer:join] join 在线保持结束")
				quit(0)
	return false


func _find_btn(node: Node, text: String) -> Button:
	for c in node.get_children():
		if c is Button and str(c.text).contains(text):
			return c
		var r := _find_btn(c, text)
		if r != null:
			return r
	return null
