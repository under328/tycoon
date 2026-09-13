## 三个新 JOKER 像素画大图目检(178x248), 截图到 builds/new_jokers.png
extends SceneTree

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		root.size = Vector2i(3 * 220 + 40, 320)
	if f == 3:
		var themes := [["card_dball", "七龙珠"], ["card_ninja", "火影"], ["card_rx", "RX骑士"]]
		var cv_script: GDScript = load("res://src/client/ui/card_view.gd")
		var bg := ColorRect.new()
		bg.color = Color("14142b")
		bg.size = Vector2(3 * 220 + 40, 320)
		root.add_child(bg)
		for i in 3:
			var cv: Control = cv_script.new(53)  # 大王
			cv.palette_id = str(themes[i][0])
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.position = Vector2(50 + i * 220, 20)
			cv.custom_minimum_size = Vector2(178, 248)
			cv.size = Vector2(178, 248)
			root.add_child(cv)
			var lb := Label.new()
			lb.text = str(themes[i][1])
			lb.position = Vector2(110 + i * 220, 282)
			lb.add_theme_font_size_override("font_size", 20)
			lb.add_theme_color_override("font_color", Color("f0f0f0"))
			root.add_child(lb)
	if f == 30:
		root.get_texture().get_image().save_png("res://builds/new_jokers.png")
		print("[strip] saved")
		quit(0)
	return false
