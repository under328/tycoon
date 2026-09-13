## 头像条带目检: 六个人物像素头像各渲染 160px + 名字标签, 截图到 builds/。
## 用法: godot --path . --script tools/avatar_strip.gd (非 headless)
extends SceneTree

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		var skins: Array = load("res://src/client/ui/skins.gd").SKINS
		var avatar_script: GDScript = load("res://src/client/ui/avatar.gd")
		var bg := ColorRect.new()
		bg.color = Color("14142b")
		bg.size = Vector2(6 * 190 + 40, 280)
		bg.position = Vector2.ZERO
		root.add_child(bg)
		for i in skins.size():
			var av: Control = avatar_script.new()
			av.skin_id = str(skins[i]["id"])
			av.position = Vector2(30 + i * 190, 40)
			av.custom_minimum_size = Vector2(160, 160)
			av.size = Vector2(160, 160)
			root.add_child(av)
			var lb := Label.new()
			lb.text = str(skins[i]["name"])
			lb.position = Vector2(30 + i * 190 + 50, 210)
			lb.add_theme_font_size_override("font_size", 20)
			lb.add_theme_color_override("font_color", Color("f0f0f0"))
			root.add_child(lb)
	if f == 30:
		root.get_texture().get_image().save_png("res://builds/avatar_strip.png")
		print("[strip] saved")
		quit(0)
	return false

