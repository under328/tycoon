## 设置面板截图: 打开主菜单后挂载设置页截帧 → builds/settings_capture.png
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
	if frames == 40:
		menu._build_settings()
		menu._settings.open()
	elif frames == 130:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("builds/settings_capture.png")
		print("[cap] settings saved")
	elif frames == 140:
		quit(0)
	return false
