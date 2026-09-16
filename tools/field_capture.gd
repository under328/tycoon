## 出牌区验证: 本地局运行中采样 出牌条目数/模拟行数, 超容量时截图对比。
## 用法: godot --path . --script tools/field_capture.gd -- profile=pc|phone
extends SceneTree

var f := 0
var main = null
var profile := "pc"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("profile="):
			profile = a.split("=")[1]
	if profile == "phone":
		root.size = Vector2i(1248, 576)
		root.content_scale_factor = 1.25
	else:
		root.size = Vector2i(1280, 720)
	main = (load("res://src/client/main.tscn") as PackedScene).instantiate()
	root.add_child(main)


func _process(_d: float) -> bool:
	f += 1
	if f == 10:
		main._launch_new_local(false)
	if f > 200 and f % 120 == 0 and main.table != null:
		var t = main.table
		if str(t._current_view().get("phase", "")) == "play":
			var n: int = t.field_box.get_child_count()
			var box_w: float = t.field_box.size.x
			# 模拟折行: 从末尾往前沿 x 累计
			var x := 0.0
			var lines := 1
			var kids: Array = t.field_box.get_children()
			kids.reverse()
			for c in kids:
				var cw: float = c.get_meta("w", c.size.x)
				if x > 0.0 and x + cw > box_w:
					lines += 1
					x = 0.0
				x += cw + 16.0
			print("[field] f=%d hands=%d lines=%d box_w=%.0f" % [f, n, lines, box_w])
			var max_lines := 1 if (profile == "phone") else 2
			if lines >= max_lines and n >= 2:
				var img := root.get_viewport().get_texture().get_image()
				img.save_png("builds/field_%s.png" % profile)
				print("[field] %s saved (hands=%d lines=%d)" % [profile, n, lines])
				quit(0)
	if f > 3600:
		print("[field] DONE (no full-field moment)")
		quit(0)
	return false
