## 设置面板截图: 打开主菜单后挂载设置页, 滚动到底部截帧 → builds/settings_capture.png
extends SceneTree

var frames := 0
var menu: Control = null


func _initialize() -> void:
	root.size = Vector2i(1280, 1050)
	var scn: GDScript = load("res://src/client/scenes/main_menu.gd")
	menu = scn.new()
	root.add_child(menu)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 40:
		menu._build_settings()
		menu._settings.open()
	elif frames >= 100 and frames <= 129 and menu._settings != null:
		# 持续滚动到底(容器重排会重置滚动位置)
		menu._settings._scroll.scroll_vertical = 10000
	elif frames == 130:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("builds/settings_capture.png")
		print("[cap] settings saved")
	elif frames == 140:
		quit(0)
	return false
