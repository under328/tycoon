## E2E: 本地游戏 → 模式选择弹窗(2×2 模式方块 / ? 帮助) 信号链路。
## 运行: godot --headless --path . --script tests/e2e_mode_select.gd
extends SceneTree

var f := 0
var menu = null
var got := []
var help_opened := false
var rogue_q: Button = null
var rogue_card: Button = null


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
		# 2×2 方块: 卡 = 空文本 Button(内含名称 Label), 每卡右上角圆包 ? 钮
		# 总按钮数: 2(难度) + 4(卡) + 4(?) = 10
		var btns: Array = dlg.find_children("*", "Button", true, false)
		if btns.size() < 10:
			_fail("弹窗按钮数量异常 %d" % btns.size())
			return false
		for b in btns:
			if str((b as Button).text) == "?":
				var card := (b as Button).get_parent()
				for c in card.get_children():
					if c is Label and str((c as Label).text) == "肉鸽模式":
						rogue_q = b
						rogue_card = card
		if rogue_q == null or rogue_card == null:
			_fail("肉鸽方块未找到 ? 帮助钮")
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
		# 关闭帮助 → 点肉鸽模式方块
		for c in menu.get_children():
			var sc: Script = (c as Control).get_script()
			if sc != null and str(sc.resource_path).ends_with("rogue_help.gd"):
				c._close()
	if f == 15:
		if not is_instance_valid(rogue_card):
			_fail("肉鸽方块已失效")
			return false
		rogue_card.pressed.emit()
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
