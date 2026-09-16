## 成就·战绩弹窗截图: 主菜单 → 挂载 profile_panel → 截帧(含页签切换)
extends SceneTree

var frames := 0
var menu: Control = null
var pp: Control = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var scn: GDScript = load("res://src/client/scenes/main_menu.gd")
	menu = scn.new()
	root.add_child(menu)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 40:
		pp = (load("res://src/client/ui/profile_panel.gd") as GDScript).new()
		menu._mount_page(pp)
	elif frames == 130:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("builds/profile_ach.png")
		print("[cap] profile_ach saved")
	elif frames == 140:
		pp._set_tab("stats")
	elif frames == 200:
		var img2 := root.get_viewport().get_texture().get_image()
		img2.save_png("builds/profile_stats.png")
		print("[cap] profile_stats saved")
	elif frames == 210:
		quit(0)
	return false
