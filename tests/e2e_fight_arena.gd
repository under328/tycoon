## 格斗竞技场 UI 冒烟: 挂载 fight_arena(伪 net) → 选牌视图 → 出战 →
## 战斗视图(我的回合/对方回合) → 事件飘字 → 终局结算(观战/格斗两视角)。
## 验证: 页面可构建、状态切换正确、按钮/提示随操作权变化、结算只入账一次。
## 注意: 视图结构与 FightPvp.view 对齐(含 spectator 字段)。
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
	var sent_picks: Array = []
	var sent_acts: Array = []

	func skin_of_seat(_seat: int) -> String:
		return "skin_aka"

	func send_fight_pick(cards: Array) -> void:
		sent_picks.append(cards)

	func send_fight_act(action: String) -> void:
		sent_acts.append(action)


func _process(_delta: float) -> bool:
	frames += 1
	match step:
		0:
			if frames < 3:
				return false
			step = 1
			_mount()
		1:
			_apply_pick(false)
			_test_pick_phase()
			step = 2
		2:
			_apply_battle(true, [], {})
			step = 3
		3:
			_test_my_turn()
			step = 4
		4:
			_apply_battle(false, [
				{"who": 0, "target": 1, "kind": "dmg", "v": 12},
				{"who": 1, "target": 0, "kind": "skill", "v": 10},
				{"who": 1, "target": 1, "kind": "heal", "v": 3},
			], {"log": ["我方 攻击 对手 — 12 伤害",
					"对手 释放【火球】— 我方 受到 10 伤害"]})
			step = 5
		5:
			_test_wait_turn()
			step = 6
		6:
			_apply_over()
			step = 7
		7:
			_test_over()
			step = 8
		8:
			# 窄窗(手机横屏)自适应: 候选卡收缩不溢出
			_apply_pick(false)
			arena.size = Vector2(800, 460)
			step = 9
		9:
			_test_narrow_window()
			arena.size = Vector2(1280, 720)
			step = 10
		10:
			_remount_spectator()
			_apply_pick(true)
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
	# 运行时 load(而非 preload): 脚本内引用 Audio/Wallet 等 autoload,
	# 只有 autoload 注册完成后才可编译
	var arena_script: GDScript = load("res://src/client/ui/fight_arena.gd")
	arena = arena_script.new()
	arena.name = "Arena"
	arena.net = fake_net
	main.add_child(arena)
	arena.size = Vector2(1280, 720)


func _base_view() -> Dictionary:
	return {
		"phase": "pick", "my_seat": 0, "fighters": [0, 1],
		"spectator": false,
		"names": {0: "我方", 1: "对手"},
		"picks_done": {0: false, 1: false},
		"turn": -1, "round_no": 0, "winner": -1,
		"log": [], "turn_seconds": 20, "pick_seconds": 30,
		"hp": {}, "max_hp": {}, "combo": {},
	}


func _apply_pick(spectator: bool) -> void:
	var v := _base_view()
	v["spectator"] = spectator
	v["candidates"] = [8, 9, 0, 4, 12, 16, 25, 34, 44, 51]
	v["my_pick"] = []
	v["skill_cd"] = {}
	fake_net.latest_fight = v
	arena._apply(v, [])


func _apply_battle(my_turn: bool, events: Array, extra: Dictionary) -> void:
	var v := _base_view()
	v["phase"] = "battle"
	v["picks_done"] = {0: true, 1: true}
	v["hands"] = {0: [8, 9, 0, 4, 12], 1: [16, 25, 34, 44, 51]}
	v["combo"] = {0: {"name": "一对", "desc": "全属性+15%", "tier": "pair"},
			1: {"name": "高牌", "desc": "无加成", "tier": "high"}}
	v["skill_cd"] = {0: 0, 1: 0}
	v["skill_kind"] = {0: "fire", 1: "fire"}
	v["stats_brief"] = {0: {"atk": 30, "def": 9, "mres": 6, "skill": 0},
			1: {"atk": 30, "def": 9, "mres": 6, "skill": 10}}
	v["hp"] = {0: 100, 1: 100}
	v["max_hp"] = {0: 100, 1: 100}
	v["turn"] = 0 if my_turn else 1
	v["my_turn"] = my_turn
	for k in extra:
		v[k] = extra[k]
	fake_net.latest_fight = v
	arena._apply(v, events)


func _apply_over() -> void:
	var v := _base_view()
	v["phase"] = "over"
	v["picks_done"] = {0: true, 1: true}
	v["hp"] = {0: 0, 1: 55}
	v["max_hp"] = {0: 100, 1: 100}
	v["turn"] = -1
	v["winner"] = 1
	v["log"] = ["★ 对手 击倒 我方 — 获胜!"]
	arena._rewarded = false
	fake_net.latest_fight = v
	arena._apply(v, [])


func _test_pick_phase() -> void:
	_expect(str(arena.phase_lbl.text).contains("选牌"), "选牌阶段标题")
	_expect(not bool(arena.view.get("spectator", true)), "座位0 非观战")
	_expect(arena.spec_lbl.visible == false, "格斗者不显示观战标")
	# 候选卡行已渲染(10 张)
	var rows := 0
	for c in arena.bottom_box.get_children():
		for cc in (c as Control).get_children():
			if cc is HBoxContainer:
				rows = maxi(rows, (cc as HBoxContainer).get_child_count())
	_expect(rows == 10, "候选卡 10 张(got=%d)" % rows)
	for id in [8, 9, 0, 4, 12]:
		arena._toggle_select(id)
	_expect(arena._sel.size() == 5, "本地预选 5 张")
	arena._rebuild_bottom()
	var confirm: Button = _find_button("出 战")
	_expect(confirm != null, "出战按钮存在")
	_expect(confirm != null and not confirm.disabled, "选满 5 张后出战可用")
	if confirm != null:
		confirm.pressed.emit()
	_expect((fake_net.sent_picks as Array).size() == 1, "选牌已发送")


func _test_my_turn() -> void:
	_expect(str(arena.phase_lbl.text) == "战斗中", "战斗阶段标题")
	_expect(_find_button("⚔ 攻击") != null, "我的回合显示攻击按钮")
	_expect(_find_button("🛡 防御") != null, "我的回合显示防御按钮")
	var skill := _find_button("🔥火球")
	_expect(skill != null and not skill.disabled, "技能就绪可用")
	var atk := _find_button("⚔ 攻击")
	if atk != null:
		atk.pressed.emit()
	_expect((fake_net.sent_acts as Array) == ["attack"], "攻击指令已发送")


func _test_wait_turn() -> void:
	_expect(_find_button("⚔ 攻击") == null, "对方回合无操作按钮")
	_expect(str(arena.log_lbl.text).contains("火球"), "战报渲染")


func _test_over() -> void:
	var wallet = root.get_node("/root/Wallet")
	var gold0: int = wallet.gold
	_expect(arena.overlay == null or is_instance_valid(arena.overlay),
			"终局面板状态有效")
	_apply_over()
	_expect(arena.overlay != null, "终局弹出结算面板")
	_expect(wallet.gold > gold0, "败北也有参与奖励入账")
	var gold1: int = wallet.gold
	arena._apply(fake_net.latest_fight, [])   # 重复广播
	_expect(wallet.gold == gold1, "结算幂等(重复广播不再入账)")


func _remount_spectator() -> void:
	arena.queue_free()
	var arena_script: GDScript = load("res://src/client/ui/fight_arena.gd")
	arena = arena_script.new()
	arena.net = fake_net
	(root.get_node("Main") as Node).add_child(arena)
	arena.size = Vector2(1280, 720)


func _test_narrow_window() -> void:
	_expect(arena.size.x == 800.0, "窄窗尺寸生效")
	var overflow := 0
	for e in arena._cards_ui:
		var wrap: Control = e["wrap"]
		if wrap.position.x + wrap.size.x > arena.size.x + 1.0 \
				or wrap.position.x < -1.0:
			overflow += 1
	_expect(overflow == 0, "候选卡不溢出窄窗(溢出 %d 张)" % overflow)
	_expect(arena._card_w < 82.0, "窄窗候选卡收缩(w=%.0f)" % arena._card_w)
	_expect(_find_button("出 战") != null, "收缩后出战按钮仍在")


func _test_spectator() -> void:
	_expect(bool(arena.view.get("spectator", false)), "座位2 为观战者")
	_expect(arena.spec_lbl.visible, "观战提示可见")
	_expect(_find_button("出 战") == null, "观战者无出战按钮")


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
