## 联机帮助弹窗截图: 主菜单打开帮助页 → 截帧 → builds/help_capture.png
extends SceneTree

var frames := 0
var menu: Control = null
var help: Control = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var scn: GDScript = load("res://src/client/scenes/main_menu.gd")
	menu = scn.new()
	root.add_child(menu)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 40 and help == null:
		help = (load("res://src/client/ui/lobby_help.gd") as GDScript).new()
		menu.add_child(help)
	if frames == 130:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("builds/help_capture.png")
		print("[cap] help saved")
	elif frames == 140:
		quit(0)
	return false
