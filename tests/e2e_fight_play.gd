## 格斗试炼真实 UI 试玩: 挂载 fight_panel, 以策略驱动真实处理器连玩多局。
## 验证: 不卡死 / 状态合法 / 结算可达 / 关闭干净。time_scale 加速演出。
## 运行: godot --headless --path . --script tests/e2e_fight_play.gd
extends SceneTree

var PanelScript: GDScript = null
var panel: Control = null
var run := 0
var runs_total := 8
var frames_in_run := 0
var state := "boot"
var wins := 0
var losses := 0
var rounds_sum := 0
var failures: Array = []
var seed_base := int(Time.get_unix_time_from_system()) % 100000
var _last_won := false
var _last_rounds := 0
var _stall := 0
var _last_sig := "--"


func _fail(msg: String) -> void:
	failures.append(msg)
	print("[play] FAIL: " + msg)


func _process(_delta: float) -> bool:
	frames_in_run += 1
	match state:
		"boot":
			PanelScript = load("res://src/client/ui/fight_panel.gd")
			Engine.time_scale = 10.0
			_start_run()
			state = "playing"
		"playing":
			if panel == null or not is_instance_valid(panel):
				_fail("面板意外消失 run=%d" % run)
				return _next_run()
			_drive()
		"settle":
			if panel == null or not is_instance_valid(panel):
				return _next_run()
			var btn := _find_button("返回菜单")
			if btn != null:
				btn.pressed.emit()
				state = "closing"
				frames_in_run = 0
			elif frames_in_run > 600:
				_fail("结算面板无返回按钮 run=%d" % run)
				return _next_run()
		"closing":
			if panel == null or not is_instance_valid(panel):
				print("[play] run %d 完成: %s" % [run,
						"通关" if _last_won else "失败"])
				return _next_run()
			if frames_in_run > 300:
				_fail("关闭后残留 run=%d" % run)
				return _next_run()
		"done":
			Engine.time_scale = 1.0
			var total := wins + losses
			if failures.is_empty() and total == runs_total:
				print("FIGHT_PLAY_OK  runs=%d wins=%d losses=%d avg_rounds=%.1f" % [
						total, wins, losses, float(rounds_sum) / float(total)])
				quit(0)
			else:
				for f in failures:
					print("FAIL: " + f)
				print("FIGHT_PLAY %d FAILURES" % failures.size())
				quit(1)
	return false


func _start_run() -> void:
	run += 1
	frames_in_run = 0
	_stall = 0
	_last_sig = "--"
	panel = PanelScript.new()
	panel.fm = load("res://src/rules/fight/fight_mode.gd").new(seed_base + run * 17)
	panel.daily = false
	root.add_child(panel)
	panel.size = root.size


func _next_run() -> bool:
	rounds_sum += _last_rounds
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	panel = null
	if run >= runs_total:
		state = "done"
		return false
	_start_run()
	state = "playing"
	return false


func _record_result() -> void:
	_last_won = bool(panel.fm.run_won)
	_last_rounds = int(panel.fm.cleared)
	if _last_won:
		wins += 1
	else:
		losses += 1


func _drive() -> void:
	if panel.fm == null:
		return
	# 面板级终局(无尽模式: 引擎停在 round_end, 面板已进结算)
	if panel.phase == "over":
		if panel.overlay != null:
			_record_result()
			state = "settle"
			frames_in_run = 0
		return
	# 卡死检测: 状态签名 6000 帧无变化
	var sig := "%s/%s/%d/%d/%d" % [str(panel.fm.phase),
			str(panel.fm.round_num), panel.fm.hits, panel.fm.fury,
			(panel.fm.slots as Array).size()]
	if sig == _last_sig:
		_stall += 1
	else:
		_stall = 0
		_last_sig = sig
	if _stall > 6000:
		_fail("真卡死 run=%d state=%s" % [run, sig])
		return _next_run()
	match str(panel.fm.phase):
		"draft":
			if not panel.draft_panel.visible:
				return
			if panel._pending_cand >= 0:
				panel._on_slot_clicked(worst_of(panel.fm))
				return
			var pair: Array = panel.fm.pair
			if (pair as Array).is_empty():
				return
			var cand := _pick_candidate(panel.fm)
			panel._on_candidate(cand)
		"battle":
			if panel.phase == "over":
				_record_result()
				state = "settle"
				frames_in_run = 0
				return
			if panel._busy or not panel.act_row.visible:
				return
			if panel.fm.skill_cd() <= 0 and int(panel.fm.stats["skill"]) > 25:
				panel.act_skill.pressed.emit()
			elif panel.fm.hp < int(panel.fm.stats["max_hp"]) * 0.25 \
					and str(panel.fm.enemy.get("intent", "")) == "heavy":
				panel.act_def.pressed.emit()
			else:
				panel.act_atk.pressed.emit()
		"round_end":
			# R5 通关 → 无尽选择面板弹出 → 点击领奖结算完成本局
			var claim2 := _find_button("领奖结算")
			if claim2 != null:
				claim2.pressed.emit()
				return
			pass
		"over":
			if panel.overlay == null:
				return
			_record_result()
			state = "settle"
			frames_in_run = 0


func _pick_candidate(fm) -> int:
	var cand := -1
	if randf() < 0.35:
		for c in fm.pair:
			if c >= 100 and not (fm.specials as Array).has(c - 100):
				cand = c
	if cand == -1:
		var best_v := -1
		for c in fm.pair:
			var v: int = int(c / 4.0) + 3
			if c < 100 and v > best_v:
				best_v = v
				cand = c
		if cand == -1:
			cand = fm.pair[0]
	return cand


func worst_of(fm) -> int:
	var worst := 0
	var wv := 999
	for i in (fm.slots as Array).size():
		var v: int = int(int(fm.slots[i]) / 4)
		if v < wv:
			wv = v
			worst = i
	return worst


func _find_button(text: String) -> Button:
	if panel == null or not is_instance_valid(panel):
		return null
	var stack: Array = [panel]
	while not stack.is_empty():
		var c: Node = stack.pop_front()
		if is_instance_valid(c) and c is Button \
				and str((c as Button).text) == text:
			return c
		for cc in c.get_children():
			stack.append(cc)
	return null
