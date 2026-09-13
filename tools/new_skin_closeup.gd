## 三个新皮肤大图目检(240px), 截图到 builds/new_skins.png
extends SceneTree

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		root.size = Vector2i(3 * 280 + 40, 340)
	if f == 3:
		var skins: Array = ["skin_dball", "skin_ninja", "skin_rx"]
		var names := ["龙珠战士", "木叶忍者", "RX骑士"]
		var avatar_script: GDScript = load("res://src/client/ui/avatar.gd")
		var bg := ColorRect.new()
		bg.color = Color("14142b")
		bg.size = Vector2(3 * 280 + 40, 340)
		root.add_child(bg)
		for i in 3:
			var av: Control = avatar_script.new()
			av.skin_id = str(skins[i])
			av.position = Vector2(50 + i * 280, 30)
			av.custom_minimum_size = Vector2(240, 240)
			av.size = Vector2(240, 240)
			root.add_child(av)
			var lb := Label.new()
			lb.text = names[i]
			lb.position = Vector2(130 + i * 280, 285)
			lb.add_theme_font_size_override("font_size", 22)
			lb.add_theme_color_override("font_color", Color("f0f0f0"))
			root.add_child(lb)
	if f == 30:
		root.get_texture().get_image().save_png("res://builds/new_skins.png")
		print("[strip] saved")
		quit(0)
	return false
