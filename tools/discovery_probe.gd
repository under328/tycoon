## 开房可发现探针(问题#13): 主机本机开房后, "搜索附近主机"应能搜到本机房间。
## 用法: godot --headless --path . --script tools/discovery_probe.gd
extends SceneTree

var f := 0
var main: Node = null
var scanned := 0
var ok := false


func _initialize() -> void:
	pass


func _process(_d: float) -> bool:
	f += 1
	match f:
		5:
			main = (load("res://src/client/main.tscn") as PackedScene).instantiate()
			root.add_child(main)
		20:
			main._start_online()          # 进入联机大厅
		25:
			# 模拟点击【本机开房】: 内嵌服务器 + 自动建房
			main.lobby.host_requested.emit()
		200:
			if main.net == null or not main.net.in_room:
				print("[probe-disc] 尚未进房(_ROOM_WAIT)")
				f = 199
				return false
			print("[probe-disc] 已开房 room=%s → 开始扫描" % str(main.net.last_room_state.get("room_code", "?")))
		210:
			main.lobby._scan_tick()   # 用户点【搜索附近主机】
			scanned += 1
			if scanned < 10:
				f = 209   # 每 5 帧扫一次(回包异步)
				return false
			# 房间页: 发现应答含本机房间 → 状态栏播报"可被发现"
			if main.lobby._disc_announced:
				var txt: String = str(main.lobby.status_label.text)
				print("[probe-disc] 房间页状态: %s" % txt)
				ok = "可被" in txt
		230:
			if ok:
				print("[probe-disc] ALL PASS — 开房后可搜索到本机房间(标·本机房间, 不可点入)")
				quit(0)
			else:
				print("[probe-disc] FAIL — 未搜到本机房间")
				quit(1)
	return false
