## 格斗竞技场 UI 冒烟 v2(回合制): 挂载 fight_arena(伪 net) → 逐回合编成
## (二选一/槽满替换) → 回合对战(我的回合/对方回合) → 事件飘字 → 终局结算
## → 观战视角。视图结构与 FightPvp.view 对齐。
## 运行: godot --headless --path . --script tests/e2e_fight_arena.gd
extends SceneTree

var checks := 0
var failures: Array = []
var arena: Control = null
var fake_net = null
var step := 0
var frames := 0


func _expect(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)


class FakeNet extends Node:
	signal fight_state(view: Dictionary)
	var latest_fight: Dictionary = {}
	var sent: Array = []   # [ [cand, slot], ... ]
	var acts: Array = []

	func skin_of_seat(_seat: int) -> String:
		return "skin_aka"

	func send_fight_pick(cand: int, slot: int = -1) -> void:
		sent.append([cand, slot])

	func send_fight_act(action: String) -> void:
		acts.append(action)


func _process(_delta: float) -> bool:
	frames += 1
	match step:
		0:
			if frames < 3:
				return false
			step = 1
			_mount()
		1:
			_apply_draft(2, false)
			_test_draft()
			step = 2
		2:
			_apply_draft(5, false)   # 槽满: 触发替换模式
			step = 3
		3:
			_test_replace_flow()
			step = 4
		4:
			_apply_battle(true, [])
			step = 5
		5:
			_test_my_turn()
			step = 6
		6:
			var evs := [
				{"who": 0, "target": 1, "kind": "dmg", "v": 12},
				{"who": 1, "target": 0, "kind": "skill", "v": 10},
			]
			_apply_battle(false, evs)
			fake_net.latest_fight["log"] = ["甲 装备 ♠A(5/5)",
					"甲 攻击 乙 — 12 伤害"]
			arena._apply(fake_net.latest_fight, evs)
			step = 7
		7:
			_test_wait_turn()
			step = 8
		8:
			_apply_over()
			step = 9
		9:
			_test_over()
			step = 10
		10:
			_remount_spectator()
			_apply_draft(0, true)
			step = 11
		11:
			_test_spectator()
			_finish()
			return true
	return false


func _mount() -> void:
	var main := Node.new()
	main.name = "Main"
	root.add_child(main)
	fake_net = FakeNet.new()
	fake_net.name = "Net"
	main.add_child(fake_net)
	# 运行时 load: 脚本内引用 Audio/Wallet autoload, 需注册完成后编译
	var arena_script: GDScript = load("res://src/client/ui/fight_arena.gd")
	arena = arena_script.new()
	arena.name = "Arena"
	arena.net = fake_net
	main.add_child(arena)
	arena.size = Vector2(1280, 720)


func _base_view() -> Dictionary:
	return {
		"phase": "draft", "my_seat": 0, "fighters": [0, 1],
		"spectator": false,
		"names": {0: "我方", 1: "对手"},
		"round_num": 1, "rounds_total": 5, "win_score": 3,
		"score": {}, "round_winner": -1, "winner": -1,
		"log": [], "turn": -1, "turn_seconds": 20, "pick_seconds": 30,
		"my": {}, "per": {0: {"slots_count": 0, "specials_count": 0,
			"done": false}, 1: {"slots_count": 0, "specials_count": 0,
			"done": false}},
	}


func _apply_draft(slots: int, spectator: bool) -> void:
	var v := _base_view()
	v["spectator"] = spectator
	v["my_seat"] = 2 if spectator else 0
	var my := {
		"slots": [], "specials": [], "pair": [], "comp": false,
		"done": false, "pairs_left": 1,
	}
	for i in slots:
		my["slots"].append(8 + i)
	my["pair"] = [20, 21]
	v["my"] = my
	fake_net.latest_fight = v
	arena._apply(v, [])


func _apply_battle(my_turn: bool, events: Array, extra: Dictionary = {}) -> void:
	var v := _base_view()
	v["phase"] = "battle"
	v["round_num"] = 2
	v["per"] = {0: {"slots_count": 5, "specials_count": 0, "done": true},
			1: {"slots_count": 5, "specials_count": 0, "done": true}}
	v["hp"] = {0: 200, 1: 160}
	v["max_hp"] = {0: 200, 1: 200}
	v["shield"] = {0: 0, 1: 0}
	v["skill_cd"] = {0: 0, 1: 0}
	v["skill_kind"] = {0: "fire", 1: "fire"}
	v["hands"] = {0: [8, 9, 10, 11, 12], 1: [20, 21, 22, 23, 24]}
	v["combo"] = {0: {"name": "一对", "desc": "全属性+15%", "tier": "pair"},
			1: {"name": "高牌", "desc": "无加成", "tier": "high"}}
	v["stats_brief"] = {0: {"atk": 40, "def": 20, "mres": 10, "skill": 0},
			1: {"atk": 35, "def": 15, "mres": 9, "skill": 20}}
	v["turn"] = 0 if my_turn else 1
	v["my_turn"] = my_turn
	fake_net.latest_fight = v
	arena._apply(v, events)


func _apply_over() -> void:
	var v := _base_view()
	v["phase"] = "over"
	v["per"] = {0: {"slots_count": 5, "specials_count": 0, "done": true},
			1: {"slots_count": 5, "specials_count": 0, "done": true}}
	v["hp"] = {0: 0, 1: 60}
	v["max_hp"] = {0: 200, 1: 200}
	v["score"] = {0: 1, 1: 3}
	v["winner"] = 1
	arena._rewarded = false
	fake_net.latest_fight = v
	arena._apply(v, [])


func _test_draft() -> void:
	_expect(str(arena.phase_lbl.text).contains("二选一"), "回合编成标题")
	_expect(not bool(arena.view.get("spectator", true)), "座位0 非观战")
	_expect(str(arena.score_lbl.text) == "0 : 0", "比分显示")
	var cards := _count_candidate_cards()
	_expect(cards == 2, "候选卡 2 张(got=%d)" % cards)
	# 点选候选 → 直接发送(槽未满)
	arena._on_candidate(20)
	_expect((fake_net.sent as Array).size() == 1, "选牌已发送")
	_expect(fake_net.sent[0][0] == 20, "发送的是所点候选")


func _test_replace_flow() -> void:
	arena._on_candidate(20)
	_expect(arena._pending_cand == 20, "槽满进入替换模式")
	arena._on_slot_clicked(0)
	_expect((fake_net.sent as Array).size() == 2, "替换选牌已发送")
	if (fake_net.sent as Array).size() == 2:
		_expect(fake_net.sent[1] == [20, 0], "替换带槽位 0")


func _test_my_turn() -> void:
	_expect(str(arena.phase_lbl.text).contains("对战"), "对战标题")
	_expect(_find_button("⚔ 攻击") != null, "我的回合显示攻击按钮")
	_expect(_find_button("🛡 防御") != null, "我的回合显示防御按钮")
	var skill := _find_button("🔥火球")
	_expect(skill != null and not skill.disabled, "技能就绪可用")
	var atk := _find_button("⚔ 攻击")
	if atk != null:
		atk.pressed.emit()
	_expect((fake_net.acts as Array) == ["attack"], "攻击指令已发送")


func _test_wait_turn() -> void:
	_expect(_find_button("⚔ 攻击") == null, "对方回合无操作按钮")
	_expect(str(arena.log_lbl.text).contains("攻击"), "战报渲染")


func _test_over() -> void:
	var wallet = root.get_node("/root/Wallet")
	var gold0: int = wallet.gold
	_apply_over()
	_expect(arena.overlay != null, "终局弹出结算面板")
	_expect(str(arena.score_lbl.text) == "1 : 3", "终局比分")
	# 失败惩罚(新经济规则): 败北扣 10 金币(下限 0), 不发放钻石
	_expect(wallet.gold == maxi(gold0 - 10, 0), "败北扣 10 金币(失败惩罚)")
	var gold1: int = wallet.gold
	arena._apply(fake_net.latest_fight, [])
	_expect(wallet.gold == gold1, "结算幂等(重复广播不再入账)")


func _remount_spectator() -> void:
	arena.queue_free()
	var arena_script: GDScript = load("res://src/client/ui/fight_arena.gd")
	arena = arena_script.new()
	arena.net = fake_net
	(root.get_node("Main") as Node).add_child(arena)
	arena.size = Vector2(1280, 720)


func _test_spectator() -> void:
	_expect(bool(arena.view.get("spectator", false)), "座位2 为观战者")
	_expect(arena.spec_lbl.visible, "观战提示可见")
	_expect(_find_button("⚔ 攻击") == null, "观战者无战斗按钮")


func _count_candidate_cards() -> int:
	var n := 0
	var stack: Array = []
	if arena.bottom_box.get_child_count() > 0:
		stack.append(arena.bottom_box.get_child(0))
	while not stack.is_empty():
		var c: Node = stack.pop_front()
		if c is HBoxContainer and (c as HBoxContainer).alignment \
				== BoxContainer.ALIGNMENT_CENTER \
				and (c as HBoxContainer).get_child_count() == 2:
			n = (c as HBoxContainer).get_child_count()
		for cc in c.get_children():
			stack.append(cc)
	return n


func _find_button(text: String) -> Button:
	if arena == null:
		return null
	var stack: Array = [arena.bottom_box]
	while not stack.is_empty():
		var c: Node = stack.pop_front()
		if is_instance_valid(c) and c is Button \
				and str((c as Button).text) == text:
			return c
		for cc in c.get_children():
			stack.append(cc)
	return null


func _finish() -> void:
	if failures.is_empty():
		print("ARENA_SMOKE_OK  (%d checks)" % checks)
		quit(0)
	else:
		for f in failures:
			print("FAIL: " + f)
		print("ARENA_SMOKE %d/%d checks FAILED" % [failures.size(), checks])
		quit(1)
