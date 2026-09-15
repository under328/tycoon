extends SceneTree

var panel: Control = null
var step := 0
var frames := 0
var _pending := ""


func _process(_delta: float) -> bool:
	_flush()
	frames += 1
	match step:
		0:
			if frames < 5:
				return false
			panel = (load("res://src/client/ui/fight_panel.gd") as GDScript).new()
			root.add_child(panel)
			panel.size = root.size
			step = 1
			frames = 0
		1:
			if frames < 8:
				return false
			# 推进到第 3 回合并制造战斗画面: 高连击 + 怒气将满
			_drive_to_battle(3)
			panel.fm.hits = 5
			panel.fm.fury = 80
			panel._render()
			_shot("juice_battle")
			step = 2
			frames = 0
		2:
			if frames < 3:
				return false
			i18n_setup()
			_shot("juice_en")
			step = 3
			frames = 0
		3:
			if frames < 3:
				return false
			print("[jcap] DONE")
			quit(0)
	return false


func i18n_setup() -> void:
	var i18n = null
	for c in root.get_children():
		if c.name == "I18n":
			i18n = c
	i18n._register_translations()
	i18n.set_language("en")
	panel._render()


func _drive_to_battle(n: int) -> void:
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
	# 强制进入战斗
	var guard2 := 0
	while str(panel.fm.phase) == "draft" and guard2 < 30:
		guard2 += 1
		panel.fm.draft_pick(panel.fm.pair[0],
				0 if panel.fm.slots.size() >= 5 else -1)
	panel.fm.hp = int(panel.fm.stats["max_hp"])
	panel.fm.fury = 80
	panel.fm.hits = 5
	panel._render()


func _shot(tag: String) -> void:
	_pending = tag


func _flush() -> void:
	if _pending == "":
		return
	var img := root.get_texture().get_image()
	img.save_png("res://builds/cap_%s.png" % _pending)
	print("[jcap] saved ", _pending)
	_pending = ""
