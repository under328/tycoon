## E2E 肉鸽桌流(引擎级): draft 二选一 → 多局打完 → 对局内设置页开/关。
## 运行: godot --headless --path . --script tests/e2e_rogue_flow.gd
extends SceneTree

const GameStateGd = preload("res://src/rules/game_state.gd")

var f := 0
var table = null
var picks := 0
var done := false
var settings_checked := false
var settings_closed := false


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		Engine.time_scale = 8.0
		# 运行时 load(--script 模式 const preload 早于 autoload 注册, 编译会丢单例)
		table = (load("res://src/client/scenes/table.tscn") as PackedScene).instantiate()
		table.mode = "local"
		table.rogue = true
		root.add_child(table)
		table.auto_pilot = true  # 人座也由 AI 代打, 全自动跑到终局
		return false
	if done or table == null or not is_instance_valid(table):
		return false
	# 每局开始(draft): 引擎级选定第一张候选 → 发牌开局
	if str(table.state.get("phase", "")) == "draft":
		picks += 1
		print("[e2e-rogue] draft pick #%d (round %d)" % [picks,
				int(table.state.get("round", -1))])
		var pick = GameStateGd.apply(table.state, {"t": "rogue_pick", "idx": 0})
		if not bool(pick["ok"]):
			print("[e2e-rogue] FAIL: rogue_pick 失败 %s" % str(pick.get("error", "")))
			quit(1)
			return false
		table.state = pick["state"]
		table._advance()  # 引擎级驱动: 选卡后启动对局循环
	# 对局内设置页: 第 2 层开始后开/关一次(验证暂停/恢复)
	if int(table.state.get("round", -1)) >= 1 and picks >= 1 \
			and not settings_checked and str(table.state.get("phase", "")) == "play":
		settings_checked = true
		table._open_settings_page()
	var sp: Control = table._settings_page
	if settings_checked and not settings_closed and sp != null and is_instance_valid(sp) \
			and sp.visible:
		settings_closed = true
		sp._close()
	if str(table.state.get("phase", "")) == "game_end":
		done = true
		var rounds := int(table.state.get("round", -1)) + 1
		if picks < rounds:
			print("[e2e-rogue] FAIL: picks=%d < rounds=%d" % [picks, rounds])
			quit(1)
			return false
		if not settings_closed:
			print("[e2e-rogue] FAIL: 设置页未打开或未关闭")
			quit(1)
			return false
		print("[e2e-rogue] ROGUE_FLOW_OK —— %d 局全部打完, 每局命运二选一, 对局内设置页开/关正常" % rounds)
		quit(0)
	if f > 600000:
		print("[e2e-rogue] FAIL: 超时 phase=%s picks=%d rounds=%d" % [
				str(table.state.get("phase", "?")), picks,
				int(table.state.get("round", -1))])
		quit(1)
	return false
