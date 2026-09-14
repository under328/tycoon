## E2E: 本地局 → 返回菜单(托管保留) → 再选模式 → 确认框"开始新游戏"
## 必须以所选模式开新局(回归: 曾因托管桌残留陷入续局确认死循环)。
## 运行: godot --headless --path . --script tests/e2e_local_reentry.gd
extends SceneTree

var f := 0
var main = null
var table1 = null
var stage := 0
var done := false


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		main = (load("res://src/client/main.tscn") as PackedScene).instantiate()
		root.add_child(main)
	if f < 6 or done:
		return false
	match stage:
		0:
			main._start_local("rogue")
			stage = 1
		1:
			if main.table != null and main.table.rogue \
					and not main.table.state.is_empty():
				table1 = main.table
				table1._do_leave()  # 返回菜单: 托管保留
				stage = 2
		2:
			if main.menu != null and main.menu.visible and main.table == table1:
				main._start_local("rogue")  # 再点本地游戏并选肉鸽
				stage = 3
			elif f > 300:
				_fail("托管桌未保留")
		3:
			if main._resume_dlg != null:
				# 点『开始新游戏』
				for b in main._resume_dlg.find_children("*", "Button", true, false):
					if str((b as Button).text).contains("开始新"):
						(b as Button).pressed.emit()
						stage = 4
						break
			elif f > 400:
				_fail("续局确认框未弹出(死循环回归?)")
		4:
			if f > 500 and main.table != null and main.table != table1:
				var ok_rogue: bool = main.table.rogue
				var old_gone: bool = not is_instance_valid(table1)
				var menu_hidden: bool = not main.menu.visible
				if ok_rogue and old_gone and menu_hidden:
					done = true
					print("[e2e] LOCAL_REENTRY_OK —— 托管桌让位, 所选模式新局正常进入")
					quit(0)
				else:
					_fail("新局状态异常 rogue=%s old_gone=%s menu_hidden=%s"
							% [ok_rogue, old_gone, menu_hidden])
	if f > 900:
		_fail("超时 stage=%d" % stage)
	return false


func _fail(msg: String) -> void:
	print("[e2e] FAIL: " + msg)
	quit(1)
