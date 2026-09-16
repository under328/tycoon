## 商城页自适应诊断: 多档逻辑尺寸挂载, 打印列数/最小宽/容器尺寸并截图。
## (--script 模式须运行时 load; holder 精确模拟 main._fit_safe_area 后的父级)
extends SceneTree

const PROFILES := [
	["pc", Vector2(1280, 720)],
	["compact", Vector2(998, 461)],   # 手机横屏 csf1.25 逻辑视口
	["narrow", Vector2(700, 576)],    # 窄屏两列
	["portrait", Vector2(480, 700)],  # 极窄单列
]

var step := -1
var frames := 0
var holder: Control = null
var shop: Control = null


func _initialize() -> void:
	_next()


func _next() -> void:
	step += 1
	frames = 0
	if step >= PROFILES.size():
		print("[cap] DONE")
		quit(0)
		return
	if holder != null:
		holder.queue_free()
		holder = null
		shop = null
	holder = Control.new()
	holder.size = Vector2(PROFILES[step][1])
	root.add_child(holder)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 20 and shop == null:
		shop = (load("res://src/client/ui/shop.gd") as GDScript).new()
		holder.add_child(shop)
	if frames == 170 and shop != null:
		var img := root.get_viewport().get_texture().get_image()
		img = img.get_region(Rect2(Vector2.ZERO, Vector2(PROFILES[step][1])))
		img.save_png("builds/shop_%s.png" % str(PROFILES[step][0]))
		var card_mins := ""
		for c in shop._grid.get_children():
			card_mins += "%d " % int((c as Control).get_combined_minimum_size().x)
		var margin_c := (shop.get_child(1) as Container)
		var vbox_c := (margin_c.get_child(0) as Container)
		print("[cap] %s cols=%d shop=%s margin=%s(min %s) vbox=%s(min %s) scroll=%s(min %s) grid=%s(min %s)" % [
				str(PROFILES[step][0]), shop._grid.columns, str(shop.size),
				str(margin_c.size), str(margin_c.get_combined_minimum_size()),
				str(vbox_c.size), str(vbox_c.get_combined_minimum_size()),
				str(shop._scroll.size), str(shop._scroll.get_combined_minimum_size()),
				str(shop._grid.size), str(shop._grid.get_combined_minimum_size())])
		print("[cap] card_mins=[%s]" % card_mins.trim_suffix(" "))
		_next()
	return false
