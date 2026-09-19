## 格斗选牌即时上槽验证: draft 阶段走真实 _on_candidate 选牌,
## 不进入战斗即截图 —— 选中的牌必须立即出现在左上装备槽。
extends SceneTree

var frames := 0
var panel: Control = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	panel = (load("res://src/client/ui/fight_panel.gd") as GDScript).new()
	panel.daily = false
	root.add_child(panel)
	panel.size = root.size


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		print("[cap] phase=", panel.fm.phase, " pair=", str(panel.fm.pair),
				" slots_before=", str(panel.fm.slots))
		# 走真实选牌路径(候选组只出普通/稀有牌, 未满 5 槽 → 直接装备)
		var cand: int = int(panel.fm.pair[0])
		panel._on_candidate(cand)
		print("[cap] picked=", cand, " slots_after=", str(panel.fm.slots))
	elif frames == 25:
		var img := root.get_viewport().get_texture().get_image()
		img.get_region(Rect2i(0, 0, 480, 300)).save_png("builds/fight_slots.png")
		print("[cap] fight_slots saved (draft 阶段, 未攻击)")
		print("[cap] slots_ui_check=", str(panel.fm.slots))
	elif frames == 35:
		quit(0)
	return false
