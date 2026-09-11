## AI 自打 fuzz：200 个种子完整对局，断言不变式（无非法状态、积分守恒、终局可达）。
extends RefCounted

const GameStateGd = preload("res://src/rules/game_state.gd")
const BotPlayerGd = preload("res://src/rules/ai/bot_player.gd")
const ViewGd = preload("res://src/protocol/view.gd")

const MATCHES := 200
const BASE_SEED := 1000


func run(t) -> void:
	for i in MATCHES:
		if i % 25 == 0:
			print("  fuzz 进度: %d/%d" % [i, MATCHES])
		var seed_v := BASE_SEED + i
		var st := GameStateGd.new_match({}, seed_v)
		var guard := 0
		while str(st["phase"]) != "game_end" and guard < 20000:
			guard += 1
			if guard == 19999:
				print("  seed %d 接近 guard 上限 phase=%s" % [seed_v, str(st["phase"])])
			_invariants(t, st, seed_v)
			var action := _bot_action(st)
			var r := GameStateGd.apply(st, action)
			if not bool(r["ok"]):
				t.expect(false, "seed %d: AI 非法动作 %s @%s" % [seed_v, str(r["error"]), str(st["phase"])])
				return
			st = r["state"]
		t.expect(str(st["phase"]) == "game_end", "seed %d 到达 game_end (guard=%d)" % [seed_v, guard])
		var total := 0
		for p in st["scores"]:
			total += int(p)
		t.expect_eq(total, 0, "seed %d 总分守恒为 0" % seed_v)


func _bot_action(st: Dictionary) -> Dictionary:
	match str(st["phase"]):
		"play":
			return BotPlayerGd.decide(st, int(st["turn"]))
		"exchange":
			return BotPlayerGd.decide(st, int(st["turn"]))
		"round_end":
			return {"t": "next_round"}
	return {}


func _invariants(t, st: Dictionary, seed_v: int) -> void:
	match str(st["phase"]):
		"play":
			t.expect(st["turn"] is int and int(st["turn"]) >= 0, "seed %d: play 阶段有当前玩家" % seed_v)
			t.expect(not (st["finish_order"] as Array).has(int(st["turn"])),
					"seed %d: 轮转不含已出完者" % seed_v)
			if not (st["lead"] as Dictionary).is_empty():
				t.expect(int(st["passes"]) < 3, "seed %d: pass 计数未越界" % seed_v)
		"exchange":
			t.expect((st["exchange"] as Array).size() >= 2, "seed %d: 交换至少两笔" % seed_v)


