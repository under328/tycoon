## 联机房间界面截图: 真实链路(内嵌服开房→房间视图→补2AI)后截全屏
## 用法: godot --path . --script tools/room_capture.gd -- <宽>x<高> (缺省 1280x720)
extends SceneTree

var main: Node = null
var f := 0
var fills := 0
var saved := false
var w := 1280
var h := 720


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.contains("x"):
			var parts := a.split("x")
			w = int(parts[0])
			h = int(parts[1])
	root.size = Vector2i(w, h)
	# 端口占用探测延迟到树激活后(_initialize 期 autoload 尚未入树)


func _process(_delta: float) -> bool:
	f += 1
	if f == 10:
		main = (load("res://src/client/main.tscn") as PackedScene).instantiate()
		root.add_child(main)
	elif f == 25:
		var probe := UDPServer.new()
		if probe.listen(24565) != OK:
			for c in root.get_children():
				if c.name == "GameSettings":
					c.host_port = 24695   # 24565 被占 → 换测试端口
		probe.stop()
	elif f == 30:
		main._start_online()
	elif f == 40:
		main._start_host()
	elif f > 120 and main != null and main.lobby != null \
			and str(main.lobby._view) == "room" \
			and str(main.lobby._last_room_code) != "":
		# 房间就绪: 补 2 个 AI 让座位有真实占用
		if fills < 2 and not bool(main.lobby.fill_btn.disabled):
			main.lobby.fill_btn.pressed.emit()
			fills += 1
			return false
		if not saved and fills >= 2:
			saved = true
			var img := root.get_viewport().get_texture().get_image()
			img.save_png("builds/room_view_%dx%d.png" % [w, h])
			print("[cap] room_view_%dx%d saved" % [w, h])
		elif saved and f > 160:
			quit(0)
	return false
