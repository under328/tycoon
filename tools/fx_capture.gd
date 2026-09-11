## 特效截图工具: 逐个播放 fx_overlay 各类型并截帧到 builds/。
## 用法: godot --path . --script tools/fx_capture.gd  (非 headless, 需渲染)
extends SceneTree

const TYPES := ["revolution", "anti_revolution", "eight_cut", "fall", "exchange"]

var frame := 0
var idx := -1
var fx: Control = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	_next()


func _next() -> void:
	idx += 1
	if idx >= TYPES.size():
		quit()
		return
	fx = load("res://src/client/ui/fx_overlay.gd").create(TYPES[idx])
	root.add_child(fx)
	frame = 0


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 20 or frame == 55:
		var img := root.get_texture().get_image()
		img.save_png("res://builds/fx_%s_%d.png" % [TYPES[idx], 1 if frame == 20 else 2])
	if frame >= 110:
		if fx != null:
			fx.queue_free()
			fx = null
		_next()
	return false
