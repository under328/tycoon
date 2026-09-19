## 怪物图鉴截图: 5 主题 × 小怪/精英/BOSS 全 15 形象排布出图
extends SceneTree

var frames := 0
var views: Array = []


func _initialize() -> void:
	root.size = Vector2i(1330, 900)
	var MVS = load("res://src/client/ui/monster_view.gd")
	var bg := ColorRect.new()
	bg.color = Color("232335")
	root.add_child(bg)
	bg.size = Vector2(1330, 900)
	var kinds := ["mob", "elite", "boss"]
	for g in 5:
		for k in 3:
			var mv: Control = MVS.new()
			mv.group = g
			mv.kind = kinds[k]
			mv.position = Vector2(60 + g * 250, 40 + k * 220)
			root.add_child(mv)
			mv.size = Vector2(200, 200)   # 入树后再定尺寸(窗口基础高 720 内)
			views.append(mv)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 15:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("builds/monster_roster.png")
		print("[cap] monster_roster saved")
	elif frames == 25:
		quit(0)
	return false
