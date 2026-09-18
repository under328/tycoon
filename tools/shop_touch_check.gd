## 商城触屏滑动体检: 三个页签下, 网格子树内除按钮外不允许有 STOP 控件
## (STOP 会吃掉 ScrollContainer 的触摸拖动 → 手机上部分区域滑不动)
extends SceneTree


func _initialize() -> void:
	root.size = Vector2i(720, 480)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var shop: Control = (load("res://src/client/ui/shop.gd") as GDScript).new()
	root.add_child(shop)
	await process_frame
	var fails := 0
	for tab: String in ["skin", "card", "item"]:
		shop._set_tab(tab)
		await process_frame
		var grid: GridContainer = shop._grid
		if grid == null:
			print("[TOUCH] tab=%s grid is null!" % tab)
			fails += 1
			continue
		var n := _scan(grid)
		if n > 0:
			fails += n
			print("[TOUCH] tab=%s offenders=%d" % [tab, n])
	print("[TOUCH] check done, fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func _scan(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is Control and not (child is Button):
			if (child as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
				print("[TOUCH] STOP control: %s (%s)" % [
						child.get_class(), str(child.get("text"))])
				n += 1
		n += _scan(child)
	return n
