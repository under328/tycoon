## 格斗装备槽截图: 挂载 fight_panel, 装满 5 槽后截左上装备区
extends SceneTree

var frames := 0
var panel: Control = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	panel = (load("res://src/client/ui/fight_panel.gd") as GDScript).new()
	panel.daily = false
	root.add_child(panel)
	panel.size = root.size


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		# _ready 已自建 fm → 此时装填; 5 张不同花色展示边框内边距
		panel.fm.slots = [0, 8, 16, 24, 53]   # ♠3 ♠5 ♠7 ♠9 大王
		panel._refresh_slots()
	elif frames == 40:
		var img := root.get_viewport().get_texture().get_image()
		img.get_region(Rect2i(0, 0, 480, 300)).save_png("builds/fight_slots.png")
		print("[cap] fight_slots saved")
	elif frames == 50:
		quit(0)
	return false
