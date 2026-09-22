## 竞技场 v4 新布局截图验收: draft / battle / 特效三个画面存到 builds/。
## 运行: godot --path . --script tools/arena_capture.gd (非 headless)
extends SceneTree

const FightPvpGd = preload("res://src/rules/fight/fight_pvp.gd")

var f := 0
var arena: Control = null
var fake = null
var stage := 0


class FakeNet extends Node:
	signal fight_state(view: Dictionary)
	var latest_fight: Dictionary = {}
	func skin_of_seat(_seat: int) -> String:
		return "skin_aka"
	func send_fight_pick(_cand: int, _slot: int = -1) -> void:
		pass
	func send_fight_act(_action: String) -> void:
		pass


func _process(_d: float) -> bool:
	f += 1
	match f:
		10:
			var main := Node.new()
			main.name = "Main"
			root.add_child(main)
			fake = FakeNet.new()
			fake.name = "Net"
			main.add_child(fake)
			var script: GDScript = load("res://src/client/ui/fight_arena.gd")
			arena = script.new()
			arena.name = "Arena"
			arena.net = fake
			main.add_child(arena)
			arena.size = Vector2(1280, 720)
		30:
			# 画面1: 编成阶段
			var st: Dictionary = _state("draft")
			FightPvpGd.open_round(st, _rng())
			fake.latest_fight = FightPvpGd.view(st, 0)
			arena._apply(fake.latest_fight, [])
		60:
			root.get_viewport().get_texture().get_image() \
					.save_png("builds/arena_v4_draft.png")
			print("[cap] draft saved")
		62:
			# 画面2: 对战阶段(满槽 + 我的回合 + 行动行)
			var st2: Dictionary = _state("battle")
			_force_battle(st2)
			fake.latest_fight = FightPvpGd.view(st2, 0)
			arena._apply(fake.latest_fight, [])
		100:
			# 画面3: 连击+技能弹道+奥义特效连发
			arena._apply(fake.latest_fight, [
				{"who": 0, "target": 1, "kind": "comboup", "v": 4},
				{"who": 0, "target": 1, "kind": "crit", "v": 66},
			])
		130:
			root.get_viewport().get_texture().get_image() \
					.save_png("builds/arena_v4_battle.png")
			print("[cap] battle saved")
			arena._apply(fake.latest_fight, [
				{"who": 1, "target": 0, "kind": "ult", "v": 120},
				{"who": 1, "target": 0, "kind": "evade", "v": 0},
			])
		180:
			root.get_viewport().get_texture().get_image() \
					.save_png("builds/arena_v4_fx.png")
			print("[cap] fx saved")
			quit(0)
			return true
	return false


func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 42
	return r


func _state(phase: String) -> Dictionary:
	var st: Dictionary = FightPvpGd.new_state([0, 1], {0: "Under", 1: "328"})
	if phase != "draft":
		FightPvpGd.open_round(st, _rng())
	return st


func _force_battle(st: Dictionary) -> void:
	# 直接灌满双方编成 → 开战
	for seat in st["fighters"]:
		var per: Dictionary = st["per"][seat]
		per["slots"] = [0, 4, 8, 12, 16]
		per["specials"] = [3]
		per["done"] = true
	FightPvpGd._begin_round_battle(st)
	# 打几轮让 HP 有落差
	var rng := _rng()
	FightPvpGd.apply_action(st, int(st["battle"]["turn"]), "attack", rng)
	FightPvpGd.apply_action(st, int(st["battle"]["turn"]), "attack", rng)
	FightPvpGd.apply_action(st, int(st["battle"]["turn"]), "ult", rng)
	st["battle"]["fury"][0] = 80
