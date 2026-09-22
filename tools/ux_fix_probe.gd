## UX 修复探针: 教程首/末页按钮状态 + 革命徽标 + "要不起"5秒倒计时显示。
## 用法: godot --path . --script tools/ux_fix_probe.gd
extends SceneTree

var f := 0
var table: Control = null
var tut: Control = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_factor = 1.0


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("builds/probe_%s.png" % name)
	print("[probe] %s saved" % name)


func _process(_d: float) -> bool:
	f += 1
	match f:
		5:
			# 教程: 首页(上一页应禁用) / 末页(下一页→关闭)
			tut = (load("res://src/client/scenes/tutorial.gd") as GDScript).new()
			root.add_child(tut)
			tut.size = root.size
		45:
			_shot("tut_first")
			tut._show(tut.PAGES.size() - 1)
		55:
			_shot("tut_last")
			tut.queue_free()
		60:
			var main = (load("res://src/client/main.tscn") as PackedScene).instantiate()
			root.add_child(main)
			set_meta("main", main)
		75:
			var main: Node = get_meta("main")
			main._launch_new_local(false)
		300:
			var main: Node = get_meta("main")
			table = main.table
			if table == null or str(table._current_view().get("phase", "")) != "play":
				f = 299   # 等待 play 阶段
				return false
			# 强制革命态 → 徽标
			table.state["revolution"] = true
			table.state["quads"] = 1
			table._prev_revolution = false
			table._refresh()
		330:
			_shot("rev_badge")
			# 强制"要不起": 轮到我 + 场上四条领出 + 我只有小单张
			table.state["turn"] = 0
			table.state["lead"] = {"type": 3, "key": 12.0, "cards": [36, 37, 38, 39],
					"len": 4}
			table.state["hands"][0] = [0, 1, 4, 5, 8, 9]
			table._auto_pass_done = false
			table._last_hand = []   # 强制手牌重建
			table._refresh()
		336:
			_shot("pass_wait_5")
		500:
			_shot("pass_wait_3")   # ~3.3s: 特效已散, 数字应跳到 2/3
		640:
			_shot("pass_wait_after")   # ~5.7s: 应已自动"不要"
			var ok: bool = int(table.state["turn"]) != 0 \
					or (table.state["field"] as Array).is_empty()
			print("[probe] after countdown turn=%d field=%d passes=%d" % [
					int(table.state["turn"]), (table.state["field"] as Array).size(),
					int(table.state["passes"])])
			quit(0)
	return false
