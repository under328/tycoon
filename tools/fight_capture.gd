## 格斗试炼(回合制 v2)视觉截图: draft 候选 / 替换模式 / 战斗 / 三个怪物组。
## 用法: godot --path . --script tools/fight_capture.gd  (非 headless, 需渲染)
extends SceneTree

var PanelScript: GDScript = null
var panel: Control = null
var step := 0
var frames := 0


func _initialize() -> void:
	# 运行时 load: 页面脚本引用 Audio/Wallet autoload, 需注册完成后编译
	PanelScript = load("res://src/client/ui/fight_panel.gd")
	root.size = Vector2i(1280, 720)


func _process(_delta: float) -> bool:
	frames += 1
	_flush_shot()
	match step:
		0:
			if frames < 5:
				return false
			panel = PanelScript.new()
			root.add_child(panel)
			panel.size = root.size
			step = 1
			frames = 0
		1:
			# draft 阶段(开局候选)
			if frames > 10:
				_shot("fight_v2_draft")
				step = 2
				frames = 0
		2:
			# 连选三张(推进到第 3 回合精英)
			if frames > 8:
				_drive_to_round(3)
				_shot("fight_v2_r3_elite_draft")
				step = 3
				frames = 0
		3:
			if frames > 8:
				_drive_to_round(4)
				# 强制进入战斗画面
				var guard := 0
				while str(panel.fm.phase) == "draft" and guard < 20:
					guard += 1
					panel.fm.draft_pick(panel.fm.pair[0],
							0 if panel.fm.slots.size() >= 5 else -1)
				panel._render()
				panel.fm.hp = int(panel.fm.stats["max_hp"])
				_shot("fight_v2_r4_battle")
				step = 4
				frames = 0
		4:
			if frames > 8:
				# BOSS 战画面(第 5 回合)
				_drive_to_round(5)
				var guard2 := 0
				while str(panel.fm.phase) == "draft" and guard2 < 30:
					guard2 += 1
					panel.fm.draft_pick(panel.fm.pair[0],
							0 if panel.fm.slots.size() >= 5 else -1)
				panel.fm.hp = int(panel.fm.stats["max_hp"])
				panel._render()
				_shot("fight_v2_boss")
				step = 5
				frames = 0
		5:
			# 换主题组: 洞穴(add_child 后注入 — _ready 会覆盖先注入的 fm)
			if frames > 8:
				panel.queue_free()
				panel = PanelScript.new()
				root.add_child(panel)
				panel.size = root.size
				panel.fm.group = 1
				var g3 := 0
				while str(panel.fm.phase) == "draft" and g3 < 30:
					g3 += 1
					panel.fm.draft_pick(panel.fm.pair[0],
							0 if panel.fm.slots.size() >= 5 else -1)
				panel.fm.hp = int(panel.fm.stats["max_hp"])
				panel._render()
				_shot("fight_v2_group_cave")
				step = 6
				frames = 0
		6:
			if frames > 8:
				# 熔岩组 BOSS 战(第 5 回合)
				panel.queue_free()
				panel = PanelScript.new()
				root.add_child(panel)
				panel.size = root.size
				panel.fm.group = 2
				panel.fm.round_num = 5
				panel.fm._open_round()
				var g4 := 0
				while str(panel.fm.phase) == "draft" and g4 < 40:
					g4 += 1
					panel.fm.draft_pick(panel.fm.pair[0],
							0 if panel.fm.slots.size() >= 5 else -1)
				panel.fm.hp = int(panel.fm.stats["max_hp"])
				panel._render()
				_shot("fight_v2_group_magma_boss")
				step = 7
				frames = 0
		7:
			if frames > 8:
				print("[fcap] DONE")
				quit(0)
	return false


func _drive_to_round(n: int) -> void:
	var guard := 0
	while int(panel.fm.round_num) < n and guard < 200:
		guard += 1
		match str(panel.fm.phase):
			"draft":
				panel.fm.draft_pick(panel.fm.pair[0],
						0 if panel.fm.slots.size() >= 5 else -1)
			"battle":
				panel.fm.hp = int(panel.fm.stats["max_hp"])
				if int(panel.fm.enemy["hp"]) > 0:
					panel.fm.step("attack")
			"round_end":
				panel.fm.advance_round()
	if str(panel.fm.phase) == "round_end":
		panel.fm.advance_round()
	panel._render()


var _pending_tag := ""

func _shot(tag: String) -> void:
	_pending_tag = tag   # 下一帧再截(渲染晚一帧)

func _flush_shot() -> void:
	if _pending_tag == "":
		return
	var img := root.get_texture().get_image()
	img.save_png("res://builds/fightcap_%s.png" % _pending_tag)
	print("[fcap] saved ", _pending_tag)
	_pending_tag = ""
