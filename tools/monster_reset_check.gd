## 怪物显形回归: 击杀淡出(_monster_die alpha→0)后, 下一只怪物登场必须
## 恢复可见(modulate 复位) — 复现"有时怪物未显示"。
extends SceneTree

var frames := 0
var panel: Control = null
var stage := 0
var draw_count := 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	panel = (load("res://src/client/ui/fight_panel.gd") as GDScript).new()
	panel.daily = false
	root.add_child(panel)
	panel.size = root.size


func _enter_battle() -> void:
	var fm = panel.fm   # _ready 已自建 → 运行期实时取
	fm.slots = [0, 8, 16, 24, 28]
	fm._open_round()
	var cand: int = int(fm.pair[0])
	if cand >= 100:
		cand = int(fm.pair[1])
	fm.draft_pick(cand, 0)   # 槽满 → 替换 0 槽 → 进入 battle
	panel._render()


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 4:
		panel.monster.draw.connect(func() -> void: draw_count += 1)
	if frames == 5 and stage == 0:
		stage = 1
		_enter_battle()
		print("[chk] 首战登场 modulate=", panel.monster.modulate,
				" visible=", panel.monster.visible)
	elif frames == 15 and stage == 1:
		var img1 := root.get_viewport().get_texture().get_image()
		img1.save_png("builds/monster_first.png")
		print("[cap] first battle saved")
	elif frames == 20 and stage == 1:
		stage = 2
		panel._monster_die()   # 击杀: 淡出 alpha→0, 0.5s
	elif frames == 60 and stage == 2:
		stage = 3
		print("[chk] 死亡淡出后 modulate=", panel.monster.modulate)
		var fm = panel.fm
		fm._open_round()       # 下一回合(引擎流程)
		var cand: int = int(fm.pair[0])
		if cand >= 100:
			cand = int(fm.pair[1])
		fm.draft_pick(cand, 0)
		panel._render()
		print("[chk] 新怪物登场 modulate=", panel.monster.modulate,
				" visible=", panel.monster.visible)
		print("[chk] monster size=", panel.monster.size,
				" pos=", panel.monster.position,
				" group=", panel.monster.group, " kind=", panel.monster.kind,
				" in_tree=", panel.monster.is_visible_in_tree())
		var ok: bool = panel.monster.visible \
				and panel.monster.modulate.a > 0.99 \
				and panel.monster.rotation == 0.0
		print("[chk] %s" % ("RESET_OK" if ok else "RESET_FAIL"))
		panel.monster.position = Vector2(400, 320)
		panel.monster.queue_redraw()
		print("[chk] draw 信号次数=", draw_count,
				" z=", panel.monster.z_index,
				" canvas_item=", panel.monster.get_canvas_item().get_id())
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("builds/monster_reset.png")
		print("[cap] monster_reset saved f60")
	elif frames == 90:
		var img2 := root.get_viewport().get_texture().get_image()
		img2.save_png("builds/monster_reset_f90.png")
		print("[cap] f90 saved; modulate=", panel.monster.modulate,
				" pos=", panel.monster.position)
	elif frames == 100:
		quit(0)
	return false
