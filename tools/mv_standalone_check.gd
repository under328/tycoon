## MonsterView 独立绘制体检: group 0..4 各挂一个, 截图对比
extends SceneTree

var frames := 0
var views: Array = []


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var MVS = load("res://src/client/ui/monster_view.gd")
	for g in 5:
		var mv: Control = MVS.new()
		mv.group = g
		mv.kind = "mob"
		mv.position = Vector2(60 + g * 240, 200)
		mv.size = Vector2(200, 200)
		root.add_child(mv)
		views.append(mv)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 20:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("builds/mv_standalone.png")
		print("[cap] saved; sizes=")
		for v in views:
			print("  group=", v.group, " size=", v.size)
	elif frames == 30:
		quit(0)
	return false
