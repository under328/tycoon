## 帮助页布局探针: 普通/肉鸽/格斗三页在 720(桌面) 与 576(手机矮屏) 两档截图。
## 用法: godot --path . --script tools/help_layout_probe.gd
extends SceneTree

var f := 0
var pages := ["res://src/client/ui/normal_help.gd", "res://src/client/ui/rogue_help.gd",
		"res://src/client/ui/fight_help.gd"]
var pi := 0
var cur: Control = null
var phase := 0   # 0=等720渲染 1=等576渲染


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_factor = 1.0


func _process(_d: float) -> bool:
	f += 1
	match f:
		5:
			cur = (load(pages[pi]) as GDScript).new()
			root.add_child(cur)
			cur.size = root.size
		45:
			root.get_viewport().get_texture().get_image() \
					.save_png("builds/help_p%d_720.png" % pi)
			cur.queue_free()
		50:
			root.size = Vector2i(1280, 576)   # 手机横屏逻辑高(sq 档)
		55:
			cur = (load(pages[pi]) as GDScript).new()
			root.add_child(cur)
			cur.size = root.size
		95:
			root.get_viewport().get_texture().get_image() \
					.save_png("builds/help_p%d_576.png" % pi)
			cur.queue_free()
			root.size = Vector2i(1280, 720)
			pi += 1
			if pi < pages.size():
				f = 4   # 下一页从头来
			else:
				print("[help-probe] saved 6 shots")
				quit(0)
	return false
