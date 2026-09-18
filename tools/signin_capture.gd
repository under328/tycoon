## 每日签到弹窗截图: 主菜单 → 强制可签到 → 打开签到弹窗 → 截帧
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
		var w = root.get_node("/root/Wallet")
		w.sign_day = ""   # 强制今日可签到
		menu._show_signin(Button.new())
	elif frames == 130:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("builds/signin.png")
		print("[cap] signin saved")
	elif frames == 140:
		quit(0)
	return false
