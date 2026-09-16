## 大厅页截图: 入口页 @ 1280x720 与 1280x800(expand 高视口) 各一帧
## (--script 模式须运行时 load, const preload 早于 autoload 注册会编译失败)
extends SceneTree

var step := 0
var frames := 0
var lobby: Control = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 1 and step == 0:
		lobby = (load("res://src/client/scenes/lobby.tscn") as PackedScene).instantiate()
		root.add_child(lobby)
	if frames == 100:
		var img := root.get_viewport().get_texture().get_image()
		if step == 0:
			img.save_png("builds/lobby_720.png")
			print("[cap] lobby_720 saved")
			# 切高视口(expand: 逻辑高 800)
			lobby.queue_free()
			root.size = Vector2i(1280, 800)
			step = 1
			frames = 0
		else:
			lobby = (load("res://src/client/scenes/lobby.tscn") as PackedScene).instantiate()
			root.add_child(lobby)
			step = 2
	elif frames == 100 and step == 2:
		pass
	elif frames == 200 and step == 2:
		var img2 := root.get_viewport().get_texture().get_image()
		img2.save_png("builds/lobby_800.png")
		print("[cap] lobby_800 saved")
		quit(0)
	return false
