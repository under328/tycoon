## E2E 肉鸽桌流: 首局揭示 → 多局命运卡 → 打到全场结束(防局间卡死回归)。
## 运行: godot --headless --path . --script tests/e2e_rogue_flow.gd
extends SceneTree

var f := 0
var table = null
var reveals := 0
var done := false
var settings_checked := false
var settings_closed := false


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		Engine.time_scale = 8.0  # AI 思考是真实秒计时器, 加速整局回放
		# 运行时 load(--script 模式 const preload 早于 autoload 注册, 编译会丢单例)
		table = (load("res://src/client/scenes/table.tscn") as PackedScene).instantiate()
		table.mode = "local"
		table.rogue = true
		root.add_child(table)
		table.auto_pilot = true  # 人座也由 AI 代打, 全自动跑到终局
		return false
	if done or table == null:
		return false
	# 每帧: 揭示弹窗一出现就自动关闭(模拟玩家点继续)
	if table._rogue_dlg != null:
		reveals += 1
		table._close_rogue_reveal()
	# 第二局开始后: 开一次对局内设置页 → 关闭 → 验证对局继续(暂停/恢复)
	if reveals >= 2 and not settings_checked and table._rogue_dlg == null:
		settings_checked = true
		table._open_settings_page()
	if settings_checked and not settings_closed 			and table._settings_page != null 			and table._settings_page.visible:
		settings_closed = true
		table._settings_page._close()
	if str(table.state.get("phase", "")) == "game_end":
		done = true
		var rounds := int(table.state.get("round", -1)) + 1
		if reveals < 2:
			print("[e2e-rogue] FAIL: 揭示次数=%d (期望 ≥2: 多局流)" % reveals)
			quit(1)
			return false
		if not settings_closed:
			print("[e2e-rogue] FAIL: 设置页未打开或未关闭")
			quit(1)
			return false
		print("[e2e-rogue] ROGUE_FLOW_OK —— %d 局全部打完, 揭示 %d 次, 对局内设置页开/关正常" % [rounds, reveals])
		quit(0)
	if f > 200000:
		print("[e2e-rogue] FAIL: 超时 phase=%s reveals=%d (局间卡死?)"
				% [table.state.get("phase", "?"), reveals])
		quit(1)
	return false
