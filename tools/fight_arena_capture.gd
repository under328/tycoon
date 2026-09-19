## 联机格斗竞技场截图验证: 无网络, 用伪造 s_fight_state 视图驱动
## 编成/对战/终局三阶段截图 — 验证左侧本地样式面板、右侧 RTL 镜像、
## 变身光环(编成+对战显示, 终局消失)、装备槽+奇物槽、奇物第三选项卡。
extends SceneTree

var frames := 0
var arena: Control = null
var stage := 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)


func _mk_arena() -> void:
	arena = (load("res://src/client/ui/fight_arena.gd") as GDScript).new()
	arena.name = "ArenaProbe"
	root.add_child(arena)
	arena.size = root.size
	# 手动指定皮肤(无 net 时刷新不覆盖)
	(arena._side[0]["avatar"] as Control).skin_id = "skin_aka"
	(arena._side[1]["avatar"] as Control).skin_id = "skin_kitsu"


func _view_draft(transformed: bool) -> Dictionary:
	return {
		"phase": "draft", "my_seat": 0, "fighters": [0, 1],
		"spectator": false,
		"names": {0: "阿蛮", 1: "小狐"},
		"round_num": 4, "rounds_total": 5, "win_score": 3,
		"score": {0: 1, 1: 1}, "round_winner": -1, "winner": -1,
		"log": ["第 4 回合 — 二选一编成", "阿蛮 装备 ♠9(3/5)", "小狐 获得奇物【狂化面具】"],
		"turn": -1, "turn_seconds": 20, "pick_seconds": 30,
		"my": {
			"slots": [18, 33, 5] if not transformed else [18, 33, 5, 40, 11],
			"specials": [2], "pair": [24, 205], "bonus_relic": 103,
			"done": false, "pairs_left": 1,
		},
		"per": {
			0: {"slots_count": 3 if not transformed else 5,
					"specials_count": 1, "done": false,
					"transformed": transformed, "relics": [2]},
			1: {"slots_count": 4, "specials_count": 1, "done": true,
					"transformed": false, "relics": []},
		},
	}


func _view_battle() -> Dictionary:
	return {
		"phase": "battle", "my_seat": 0, "fighters": [0, 1],
		"spectator": false,
		"names": {0: "阿蛮", 1: "小狐"},
		"round_num": 4, "rounds_total": 5, "win_score": 3,
		"score": {0: 1, 1: 1}, "round_winner": -1, "winner": -1,
		"log": ["对战开始 — 阿蛮 先攻", "阿蛮 装备 ♠9(3/5)"],
		"turn": 0, "turn_seconds": 20, "pick_seconds": 30,
		"my_turn": true,
		"my": {"slots": [18, 33, 5, 40, 11], "specials": [2, 5],
				"pair": [], "bonus_relic": -1, "done": true, "pairs_left": 0},
		"per": {
			0: {"slots_count": 5, "specials_count": 2, "done": true,
					"transformed": true, "relics": [2, 5]},
			1: {"slots_count": 5, "specials_count": 1, "done": true,
					"transformed": true, "relics": [6]},
		},
		"hp": {0: 88, 1: 46}, "max_hp": {0: 120, 1: 110},
		"shield": {0: 0, 1: 22},
		"fury": {0: 74, 1: 100}, "skill_cd": {0: 0, 1: 1},
		"hands": {0: [18, 33, 5, 40, 11], 1: [2, 29, 46, 15, 37]},
		"combo": {
			0: {"name": "高牌", "desc": "无协同", "tier": "high"},
			1: {"name": "一对", "desc": "物攻小成", "tier": "pair"}},
		"skill_kind": {0: "fire", 1: "frost"},
		"stats_brief": {
			0: {"atk": 26, "def": 12, "mres": 9, "skill": 22},
			1: {"atk": 21, "def": 10, "mres": 14, "skill": 25}},
		"suit": {0: 0, 1: 3},
	}


func _view_over() -> Dictionary:
	var v := _view_battle()
	v["phase"] = "over"
	v["winner"] = 1
	v["my_seat"] = 9          # 观战视角: 不触发钱包入账
	v["spectator"] = true
	v["turn"] = -1
	v["my_turn"] = false
	v["per"][0]["transformed"] = false   # 终局: 光环必须消失
	v["per"][1]["transformed"] = false
	return v


func _shot(name_: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("builds/" + name_)
	print("[arena-cap] saved ", name_)


func _process(_delta: float) -> bool:
	frames += 1
	match frames:
		5:
			_mk_arena()
		15:
			arena._apply(_view_draft(false), [])
		30:
			_shot("arena_draft.png")
			arena._apply(_view_draft(true), [])
		48:
			_shot("arena_transformed.png")
			arena._apply(_view_battle(), [])
		66:
			_shot("arena_battle.png")
			arena._apply(_view_over(), [])
		84:
			_shot("arena_over.png")
			print("[arena-cap] PROBE_DONE")
		95:
			quit(0)
	return false
