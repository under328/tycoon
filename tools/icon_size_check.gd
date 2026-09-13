## 图标小尺寸可读性对比: 192 + 432fg 拼图, 输出 builds/icon_size_check.png
extends SceneTree

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		# 直接读文件, 绕过 .import 缓存的旧贴图
		var i192: Image = Image.load_from_file(ProjectSettings.globalize_path("res://icon_192.png"))
		var ifg: Image = Image.load_from_file(ProjectSettings.globalize_path("res://icon_432_fg.png"))
		var canvas := Image.create(684, 472, false, Image.FORMAT_RGBA8)
		canvas.fill(Color("14142b"))
		canvas.blit_rect(i192, Rect2i(0, 0, 192, 192), Vector2i(20, 20))
		canvas.blit_rect(ifg, Rect2i(0, 0, 432, 432), Vector2i(232, 20))
		canvas.save_png("res://builds/icon_size_check.png")
		print("[icon] size check saved")
		quit(0)
	return false
