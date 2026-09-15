## 格斗试炼真实 UI 试玩: 挂载 fight_panel, 以"人类-ish"策略驱动真实
## 处理器(_on_candidate/_on_slot_clicked/按钮 pressed)连玩多局,
## 验证: 不卡死 / 状态合法 / 结算可达 / 关闭干净。time_scale 加速演出。
## 运行: godot --headless --path . --script tests/e2e_fight_play.gd
extends SceneTree

const FightModeGdPath := "res://src/rules/fight/fight_mode.gd"

var panel: Control = null
var PanelScript: GDScript = null
var run := 0
var runs_total := 20
var frames_in_run := 0
var state := "boot"          # boot | playing | settle | closing | done
var wins := 0
var losses := 0
var rounds_sum := 0
var failures: Array = []
var seed_base := int(Time.get_unix_time_from_system()) % 100000


func _fail(msg: String) -> void:
	failures.append(msg)
	print("[play] FAIL: " + msg)


func _process(_delta: float) -> bool:
	frames_in_run += 1
	match state:
		"boot":
			# 运行时 load(页面脚本引用 autoload)
			PanelScript = load("res://src/client/ui/fight_panel.gd")
			Engine.time_scale = 10.0   # 加速事件演出/横幅
			_start_run()
			state = "playing"
		"playing":
			if panel == null or not is_instance_valid(panel):
				_fail("面板意外消失 run=%d" % run)
				return _next_run()
			_drive()
			if frames_in_run > 30000:
				_fail("卡死 run=%d engine=%s busy=%s act_row=%s hp=%d/%d ehp=%s log=%s" % [
						run, str(panel.fm.phase), str(panel._busy),
						str(panel.act_row.visible), panel.fm.hp,
						int(panel.fm.stats["max_hp"]),
						str(panel.fm.enemy.get("hp", -1)),
						str(panel.fm.log_lines)])
				return _next_run()
		"settle":
			# 结算面板已出现: 点"返回菜单"
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


var _last_won := false


func _start_run() -> void:
	run += 1
	frames_in_run = 0
	panel = PanelScript.new()
	panel.fm = load(FightModeGdPath).new(seed_base + run * 17)
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


var _last_rounds := 0


func _record_result() -> void:
	_last_won = bool(panel.fm.run_won)
	_last_rounds = int(panel.fm.round_num)
	if _last_won:
		wins += 1
	else:
		losses += 1


## 驱动一步(真实处理器)
func _drive() -> void:
	if panel.fm == null:
		return
	# 状态合法性抽查
	var hp: int = panel.fm.hp
	var mh: int = int(panel.fm.stats["max_hp"])
	if hp > mh + 1 or (panel.fm.slots as Array).size() > 5:
		_fail("非法状态 run=%d hp=%d max=%d slots=%d" % [run, hp, mh,
				(panel.fm.slots as Array).size()])
		state = "settle"
		return
	match str(panel.fm.phase):
		"draft":
			if not panel.draft_panel.visible:
				return   # 等渲染
			if panel._pending_cand >= 0:
				# 替换模式: 换掉点数最小的槽(真实点击路径)
				var worst := 0
				var wv := 999
				for i in (panel.fm.slots as Array).size():
					var v: int = int(int(panel.fm.slots[i]) / 4)
					if v < wv:
						wv = v
						worst = i
				panel._on_slot_clicked(worst)
				return
			var pair: Array = panel.fm.pair
			if (pair as Array).is_empty():
				return
			# 策略: 35% 优先未持有特殊牌, 否则点数最大
			var cand := -1
			if randf() < 0.35:
				for c in pair:
					if c >= 100 and not (panel.fm.specials as Array).has(c - 100):
						cand = c
			if cand == -1:
				var best_v := -1
				for c in pair:
					var v: int = int(c / 4.0) + 3
					if c < 100 and v > best_v:
						best_v = v
						cand = c
				if cand == -1:
					cand = pair[0]   # 只剩特殊牌
			panel._on_candidate(cand)
		"battle":
			if panel.phase == "over":
				# 死亡/放弃结算窗口: 引擎停在 battle, 面板已进结算
				if panel.overlay != null:
					_record_result()
					state = "settle"
					frames_in_run = 0
				return
			if panel._busy or not panel.act_row.visible:
				return
			# 策略: 技能就绪且强度够 → 技能; 残血遇重击 → 防御; 否则攻击
			if panel.fm.skill_cd() <= 0 and int(panel.fm.stats["skill"]) > 25:
				panel.act_skill.pressed.emit()
			elif panel.fm.hp < int(panel.fm.stats["max_hp"]) * 0.25 \
					and str(panel.fm.enemy.get("intent", "")) == "heavy":
				panel.act_def.pressed.emit()
			else:
				panel.act_atk.pressed.emit()
		"round_end":
			pass   # 横幅回调自动推进
		"over":
			# 结算面板在事件播完后才弹出 → overlay 未现时继续等(有总帧看门狗)
			if panel.overlay == null:
				return
			_record_result()
			state = "settle"
			frames_in_run = 0


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
