## 联机房间界面截图: 真实链路(内嵌服开房→房间视图→补2AI)后,
## 依次切换 普通/肉鸽/格斗 三种模式各截一张, 验证规则设置联动显隐。
## 用法: godot --path . --script tools/room_capture.gd (1280x720)
extends SceneTree

var main: Node = null
var f := 0
var fills := 0
var st := 0        # 0等待房间 1补AI 2存normal+切rogue 3存rogue+切fight 4存fight
var st_f := 0
var names := ["normal", "rogue", "fight"]


func _initialize() -> void:
	root.size = Vector2i(1248, 576)   # 手机横屏逻辑视口


func _process(_delta: float) -> bool:
	f += 1
	st_f += 1
	match st:
		0:
			if f == 10:
				main = (load("res://src/client/main.tscn") as PackedScene).instantiate()
				root.add_child(main)
			elif f == 26:
				root.content_scale_factor = 1.25   # 模拟手机触屏缩放(逻辑视口 1024x576)
				var probe := UDPServer.new()
				if probe.listen(24565) != OK:
					for c in root.get_children():
						if c.name == "GameSettings":
							c.host_port = 24695
				probe.stop()
			elif f == 32:
				main._start_online()
			elif f == 40:
				main._start_host()
				st = 1
				st_f = 0
		1:
			if main != null and main.lobby != null \
					and str(main.lobby._view) == "room" and f > 140:
				if fills < 2 and not bool(main.lobby.fill_btn.disabled):
					main.lobby.fill_btn.pressed.emit()
					fills += 1
					st_f = 0
				elif fills >= 2 and st_f > 40:
					st = 2
					st_f = 0
		2:
			if st_f == 1:
				_save(0)
			elif st_f == 5:
				_switch(1)
			elif st_f > 45:
				st = 3
				st_f = 0
		3:
			if st_f == 1:
				_save(1)
			elif st_f == 5:
				_switch(2)
			elif st_f > 45:
				st = 4
				st_f = 0
		4:
			if st_f == 1:
				_save(2)
			elif st_f > 5:
				print("[cap] all saved")
				quit(0)
	return false


func _switch(idx: int) -> void:
	var lobby = main.lobby
	lobby.mode_option.select(idx)
	lobby.mode_option.item_selected.emit(idx)


func _save(idx: int) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("builds/room_%s.png" % names[idx])
	print("[cap] room_%s saved" % names[idx])
