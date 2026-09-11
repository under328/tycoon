## 牌面批量导出工具（计划 tools/card_gen）。
## 把 CardView 的程序化牌面渲染成 54 张 PNG + 牌背，输出到 assets/cards/preview/。
## 用途：下载页展示 / moodboard / 未来换皮时的对比基线。
## 运行（需要桌面会话渲染，不要加 --headless）：
##   godot --path . --script tools/card_gen.gd
extends SceneTree

const CardViewScript = preload("res://src/client/ui/card_view.gd")

const OUT := "res://assets/cards/preview"
const W := 116
const H := 160


func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var jobs: Array = []
	for i in 54:
		jobs.append({"card": i, "name": "card_%02d" % i, "down": false})
	jobs.append({"card": -1, "name": "card_back", "down": true})

	for j in jobs:
		var cv := CardViewScript.new(int(j["card"]))
		cv.face_down = bool(j.get("down", false))
		cv.custom_minimum_size = Vector2(W, H)
		cv.size = Vector2(W, H)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vp.add_child(cv)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = vp.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT, j["name"]]))
		vp.remove_child(cv)
		cv.free()

	print("card_gen: 已导出 %d 张 PNG → %s" % [jobs.size(), OUT])
	quit(0)
