## 主菜单多分辨率截图(入场动画结束后截帧): 输出 builds/menu_cap_*.png
## 用法: godot --path . --script tools/menu_capture.gd  (非 headless)
extends SceneTree

const PROFILES := [
	["pc", Vector2i(1280, 720), 1.0],
	["phone", Vector2i(1600, 720), 1.0],
	["compact", Vector2i(1248, 576), 1.25],
]

var step := 0
var frames := 0
var menu: Control = null


func _initialize() -> void:
	_next()


func _next() -> void:
	if step >= PROFILES.size():
		print("[cap] DONE")
		quit(0)
		return
	if menu != null:
		menu.queue_free()
		menu = null
	var p: Array = PROFILES[step]
	root.size = Vector2i(p[1])
	root.content_scale_factor = float(p[2])
	var scn: GDScript = load("res://src/client/scenes/main_menu.gd")
	menu = scn.new()
	root.add_child(menu)
	frames = 0


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 90:  # ~1.5s: 入场动画(≤1.6s)基本完成
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("builds/menu_cap_%s.png" % str(PROFILES[step][0]))
		print("[cap] %s saved" % str(PROFILES[step][0]))
		step += 1
		_next()
	return false
