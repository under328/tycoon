## 联机修复探针: ① c_room_settings RPC 通路(选格斗模式真正下发服务器);
## ② 服务器按 mode=fight 开局(下发 s_fight_state 而非普通对局视图);
## ③ 身份簿昵称找回(重装后 client_id 不变 → s_identity 回执)。
## 用法: godot --headless --path . --script tools/online_fix_probe.gd
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")

var net = null
var server = null
var f := 0
var stage := 0
var settings_ok := false
var fight_started := false
var identity_ok := false
var _identity_check_done := false


func _initialize() -> void:
	pass


func _setup() -> void:
	var main := Node.new()
	main.name = "Main"
	root.add_child(main)
	server = NetNodeGd.start_embedded(main, 24731)
	if server == null:
		print("[probe-net] FAIL: 内嵌服务器启动失败")
		quit(1)
		return
	server.manager.ai_delay_ms = 50
	server.manager.phase_delay_ms = 200
	# 预置身份簿: 该 client_id 上次昵称(模拟重装前记录)
	server.manager.identity_book["dprobe0000000000"] = "老玩家"
	net = NetNodeGd.new()
	net.name = "Net"
	net.setup(false)
	main.add_child(net)
	net.connected_ok.connect(func() -> void:
		print("[probe-net] connected, hello 已发"))
	net.errored.connect(func(code: String, msg: String) -> void:
		print("[probe-net] error: %s %s" % [code, msg]))
	net.room_state.connect(func(state: Dictionary) -> void:
		var mode := str((state.get("settings", {}) as Dictionary).get("mode", "?"))
		print("[probe-net] room_state mode=%s" % mode)
		if stage == 1 and mode == "fight":
			settings_ok = true
			stage = 2
			print("[probe-net] set_settings RPC 通路 OK → 开始游戏")
			net.start_game())
	net.fight_state.connect(func(_v: Dictionary) -> void:
		if stage == 2 and not fight_started:
			fight_started = true
			print("[probe-net] 格斗对局视图已下发(s_fight_state) OK"))


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		_setup()
		return false
	match f:
		4:
			# 模拟"重装后": 默认昵称 + 设备派生且与身份簿一致的游客 id
			var gs := root.get_node_or_null("/root/GameSettings")
			if gs != null:
				gs.nickname = "玩家"
				gs.client_id = "dprobe0000000000"
		5:
			net.connect_to("127.0.0.1", 24731)
		70:
			# hello 已通(昵称=玩家 + 预置 client_id → 应收到 s_identity 找回)
			if not _identity_check_done:
				_identity_check_done = true
				var gs := root.get_node_or_null("/root/GameSettings")
				var nick: String = str(gs.nickname) if gs != null else "?"
				if nick == "老玩家":
					identity_ok = true
					print("[probe-net] 身份簿昵称找回 OK(玩家→老玩家)")
				else:
					print("[probe-net] 身份簿找回未生效, 当前昵称=%s" % nick)
				stage = 1
				net.create_room({})   # 先建普通房间
		130:
			# 房间内把模式改为格斗(修复前该 RPC 静默失效)
			print("[probe-net] 发送 set_settings(mode=fight)")
			net.set_settings({"mode": "fight"})
		400:
			print("[probe-net] 结果 settings_ok=%s fight_started=%s identity_ok=%s" % [
					str(settings_ok), str(fight_started), str(identity_ok)])
			if settings_ok and fight_started and identity_ok:
				print("[probe-net] ALL PASS")
				quit(0)
			else:
				print("[probe-net] FAIL")
				quit(1)
	return false
