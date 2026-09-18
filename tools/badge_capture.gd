## 首页资产面板截图: 已签状态(签到钮隐藏, 成就·战绩吸收其宽)截帧
extends SceneTree

var frames := 0
var menu: Control = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		var w = root.get_node("/root/Wallet")
		w.sign_day = w._today()   # 强制今日已签 → 签到钮隐藏
		var scn: GDScript = load("res://src/client/scenes/main_menu.gd")
		menu = scn.new()
		root.add_child(menu)
	elif frames == 90:
		var img := root.get_viewport().get_texture().get_image()
		img.get_region(Rect2i(1000, 20, 270, 110)).save_png("builds/badge_signed.png")
		print("[cap] badge_signed saved")
	elif frames == 100:
		quit(0)
	return false
