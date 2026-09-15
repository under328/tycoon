## E2E: 本地游戏 → 模式选择弹窗(普通/肉鸽/? 帮助) 信号链路。
## 运行: godot --headless --path . --script tests/e2e_mode_select.gd
extends SceneTree

var f := 0
var menu = null
var got := []
var help_opened := false


func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		menu = (load("res://src/client/scenes/main_menu.gd") as GDScript).new()
		root.add_child(menu)
		menu.local_game.connect(func(mode: String) -> void: got.append(mode))
	if f == 6:
		menu._show_mode_select()
	if f == 9:
		var dlg = menu._mode_dlg
		if dlg == null:
			_fail("模式选择弹窗未出现")
			return false
		# 弹窗里应有 ? 帮助钮 + 两个模式钮(共 3 个 Button)
		var btns: Array = dlg.find_children("*", "Button", true, false)
		if btns.size() < 8:
			return false
		# 找肉鸽行: 行内含『肉鸽模式』按钮 + 它的 ? 帮助钮
		var rogue_q: Button = null
		for b in btns:
			if str((b as Button).text) == "肉鸽模式":
				var mrow: Control = (b as Button).get_parent()
				for c in mrow.find_children("*", "BaseButton", true, false):
					if str((c as BaseButton).text) == "?":
						rogue_q = c
		if rogue_q == null:
			_fail("肉鸽行未找到 ? 帮助钮")
			return false
		rogue_q.pressed.emit()
	if f == 12:
		if menu.find_children("*", "Control", true, false).filter(
				func(c) -> bool:
					var sc: Script = (c as Control).get_script()
					return sc != null and str(sc.resource_path).ends_with("rogue_help.gd")).is_empty():
			_fail("点击 ? 未打开 rogue_help")
			return false
		help_opened = true
		# 关闭帮助 → 点肉鸽模式
		for c in menu.get_children():
			var sc: Script = (c as Control).get_script()
			if sc != null and str(sc.resource_path).ends_with("rogue_help.gd"):
				c._close()
	if f == 15:
		var btns: Array = menu._mode_dlg.find_children("*", "Button", true, false)
		for b in btns:
			if str((b as Button).text) == "肉鸽模式":
				(b as Button).pressed.emit()
	if f == 18:
		if got != ["rogue"]:
			_fail("肉鸽模式信号链路失败 got=%s" % str(got))
			return false
		if menu._mode_dlg != null:
			_fail("选择后弹窗未关闭")
			return false
		print("[e2e-mode] MODE_SELECT_OK —— ?帮助 + 肉鸽链路通过")
		quit(0)
	return false


func _fail(msg: String) -> void:
	print("[e2e-mode] FAIL: " + msg)
	quit(1)
