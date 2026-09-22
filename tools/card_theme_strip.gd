## 新卡面主题目检: 全部主题各渲染 牌背/♦5/J♥/♠A/JOKER 五张(88x122),
## 截图到 builds/。用法: godot --path . --script tools/card_theme_strip.gd
extends SceneTree

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		root.size = Vector2i(3 * 900 + 60, 440)
	if f == 3:
		var themes := [["card_p5", "女神异闻录"], ["card_gundam", "机动战士"],
			["card_ppg", "飞天小女警"]]
		var cv_script: GDScript = load("res://src/client/ui/card_view.gd")
		var bg := ColorRect.new()
		bg.color = Color("14142b")
		bg.size = Vector2(themes.size() * 620 + 60, 420)
		root.add_child(bg)
		var ids := [-1, 10, 33, 44, 53]  # 牌背 / ♦5 / J♥ / ♠A / 大王
		for t in themes.size():
			for i in ids.size():
				var cv: Control = cv_script.new(ids[i])
				cv.palette_id = str(themes[t][0])
				cv.face_down = ids[i] < 0
				cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cv.position = Vector2(30 + t * 900 + i * 122, 40)
				cv.custom_minimum_size = Vector2(96, 134)
				cv.size = Vector2(96, 134)
				root.add_child(cv)
			var lb := Label.new()
			lb.text = str(themes[t][1])
			lb.position = Vector2(30 + t * 900, 360)
			lb.add_theme_font_size_override("font_size", 18)
			lb.add_theme_color_override("font_color", Color("f0f0f0"))
			root.add_child(lb)
	if f == 30:
		root.get_texture().get_image().save_png("res://builds/card_theme_strip.png")
		print("[strip] saved")
		quit(0)
	return false
