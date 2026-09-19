## 奇物系统截图验证: 强制一轮附带奇物(金色第三选项) +
## 预置 1 个已装奇物槽, 走真实 _on_candidate 点击拾取后截图 ——
## 验证第三选项卡/双奇物槽/拾取后卡面撤下且候选组保留。
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
				" bonus_before=", panel.fm.bonus_relic)
		# 预置: 奇物槽 1/2 已装(id 2), 本轮附带奇物 = 池首(与已装不同)
		panel.fm.specials = [2]
		var sp0: int = int(panel.fm.specials_left[0])
		panel.fm.specials_left.erase(sp0)
		panel.fm.bonus_relic = 100 + sp0
		panel._render()
		print("[cap] forced bonus=", panel.fm.bonus_relic,
				" specials=", str(panel.fm.specials))
	elif frames == 20:
		root.get_viewport().get_texture().get_image() \
				.save_png("builds/fight_relic_ui.png")
		print("[cap] fight_relic_ui saved (拾取前)")
		# 真实点击路径拾取奇物(防抖/音效/浮字/引擎落槽)
		panel._on_candidate(int(panel.fm.bonus_relic))
		print("[cap] clicked relic, bonus_after=", panel.fm.bonus_relic,
				" specials=", str(panel.fm.specials),
				" slots=", str(panel.fm.slots), " phase=", panel.fm.phase)
	elif frames == 40:
		root.get_viewport().get_texture().get_image() \
				.save_png("builds/fight_relic_picked.png")
		print("[cap] fight_relic_picked saved (拾取后, 候选组应保留)")
	elif frames == 50:
		quit(0)
	return false
