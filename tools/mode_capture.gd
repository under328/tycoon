## 模式选择弹窗截图: 主菜单 → 打开本地游戏模式选择 → 截帧
extends SceneTree

var frames := 0
var menu: Control = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var scn: GDScript = load("res://src/client/scenes/main_menu.gd")
	menu = scn.new()
	root.add_child(menu)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 50:
		menu._show_mode_select()
	elif frames == 130:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("builds/mode_select.png")
		print("[cap] mode_select saved")
	elif frames == 140:
		quit(0)
	return false
