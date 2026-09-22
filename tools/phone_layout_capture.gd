## 手机布局截图验收: 20:9 手机逻辑视口(1248x576) + 触屏模拟(force_touch)。
## 覆盖: 牌桌普通 play / 肉鸽 draft+play / 格斗竞技场 battle / 新手引导第6页 /
## 联机房间页 → builds/phone_*.png。人工核对防重叠(对照 2026-09-21 手机 bug 单)。
## 运行: godot --path . --script tools/phone_layout_capture.gd (非 headless)
extends SceneTree

const Responsive = preload("res://src/client/theme/responsive.gd")
const FightPvpGd = preload("res://src/rules/fight/fight_pvp.gd")
const TutorialScript = preload("res://src/client/scenes/tutorial.gd")

var f := 0
var main = null
var arena: Control = null
var fake = null
var tut: Control = null
var _rng := RandomNumberGenerator.new()


class FakeNet extends Node:
	signal fight_state(view: Dictionary)
	var latest_fight: Dictionary = {}
	func skin_of_seat(_seat: int) -> String:
		return "skin_aka"
	func send_fight_pick(_cand: int, _slot: int = -1) -> void:
		pass
	func send_fight_act(_action: String) -> void:
		pass


func _initialize() -> void:
	Responsive.force_touch = true
	root.size = Vector2i(1560, 720)      # /1.25 → 逻辑视口 1248x576
	root.content_scale_factor = 1.25
	_rng.seed = 42


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("builds/" + name)
	print("[phone] saved " + name)


func _process(_d: float) -> bool:
	f += 1
	match f:
		10:
			main = (load("res://src/client/main.tscn") as PackedScene).instantiate()
			root.add_child(main)
		25:
			main._launch_new_local(false)
		175:
			_shot("phone_table_normal.png")
			main._launch_new_local(true)
		330:
			# 肉鸽 draft: 命运二选一面板应铺满中央出牌区
			_shot("phone_table_rogue_draft.png")
			if main.table != null and main.table._rogue_dlg != null \
					and is_instance_valid(main.table._rogue_dlg):
				_press_pick(main.table._rogue_dlg)
		395:
			# 关掉揭示弹窗 → play 阶段(命运卡提示收进出牌区提示行)
			if main.table != null and main.table._rogue_dlg != null \
					and is_instance_valid(main.table._rogue_dlg):
				main.table._close_rogue_reveal()
		403:
			# 弹窗 queue_free 延迟到帧尾 → 隔几帧再截, play 阶段画面才干净
			_shot("phone_table_rogue_play.png")
		407:
			if main.table != null and is_instance_valid(main.table):
				main.table.queue_free()
			# 竞技场 battle 画面(手机视口)
			arena = (load("res://src/client/ui/fight_arena.gd") as GDScript).new()
			arena.name = "Arena"
			fake = FakeNet.new()
			fake.name = "FakeNet"   # 不可叫 "Net": 与 main._start_online 的真 Net 撞名被改名, RPC 路径会失效
			main.add_child(fake)
			arena.net = fake
			main.add_child(arena)
			arena.size = root.get_viewport().get_visible_rect().size
			var st: Dictionary = FightPvpGd.new_state([0, 1],
					{0: "滴哩咕噜", 1: "妮可"})
			FightPvpGd.open_round(st, _rng)
			var guard := 0
			while str(st["phase"]) != "battle" and guard < 40:
				guard += 1
				for seat in st["fighters"]:
					var per: Dictionary = st["per"][seat]
					if not bool(per["done"]):
						var cand: int = (per["pair"] as Array)[0]
						var slot := -1
						if (per["slots"] as Array).size() >= 5:
							slot = 0
						FightPvpGd.draft_pick(st, int(seat), cand, slot, _rng)
			fake.latest_fight = FightPvpGd.view(st, 0)
			arena._apply(fake.latest_fight, [])
		450:
			_shot("phone_arena_battle.png")
		460:
			if arena != null and is_instance_valid(arena):
				arena.queue_free()
			tut = TutorialScript.new()
			(tut as Control).size = root.get_viewport().get_visible_rect().size
			main.add_child(tut)
			tut._show(5)   # 第 6 页(身份与换牌, 正文 4 行最长)
		495:
			_shot("phone_tutorial_p6.png")
		505:
			if tut != null and is_instance_valid(tut):
				tut.queue_free()
			# 联机房间页(本机开房内嵌服, 固定测试端口避免冲突)
			for c in root.get_children():
				if c.name == "GameSettings":
					c.host_port = 24701
			main._start_online()
			main._start_host()
		560:
			_shot("phone_room.png")
			print("[phone] lobby view=", str(main.lobby._view) if main.lobby != null else "?")
		700:
			_shot("phone_room2.png")
			print("[phone] lobby view=", str(main.lobby._view) if main.lobby != null else "?")
			for i in 4:
				var nml: Label = main.lobby._seat_cards[i]["name"]
				print("[phone] seat%d name='%s' visible=%s size=%s" % [i + 1,
						str(nml.text), str(nml.visible), str(nml.size)])
		760:
			quit(0)
	return false


## 递归找"命运二选一"候选按钮并按下(跳过重抽)
func _press_pick(n: Node) -> void:
	for c in n.get_children():
		if c is Button and "重抽" not in str(c.text) and str(c.text) != "":
			c.pressed.emit()
			return
		_press_pick(c)
