## 生成器像素分布探针: 从纹理读每行非透明像素数
extends SceneTree

func _initialize() -> void:
	var MA = load("res://src/client/ui/monster_art.gd")
	var art: Dictionary = MA.build(4, "boss", 0)
	var img: Image = (art["tex"] as ImageTexture).get_image()
	for y in 32:
		var n := 0
		for x in 32:
			if img.get_pixel(x, y).a > 0.1:
				n += 1
		print("row %02d: %d" % [y, n])
	quit(0)
