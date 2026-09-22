## 个人档案面板: 成就 + 战绩 双页签(主菜单徽章区入口)。
## 成就=全目录(已解锁金框/未解锁暗格+进度来源), 战绩=最近对局记录列表。
## 居中弹窗式(与设置弹窗同款): 窄宽面板 + 滚动区(触摸滑动/滚轮)。
extends Control

signal closed
signal replay_selected(entry: Dictionary)

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const WalletGd = preload("res://src/autoload/wallet.gd")
const GameStateGd = preload("res://src/rules/game_state.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")

var _tab := "ach"
var _tab_ach_btn: Button
var _tab_hist_btn: Button
var _tab_replay_btn: Button
var _tab_mission_btn: Button
var _tab_stats_btn: Button
var _scroll: ScrollContainer
var _grid: VBoxContainer
var _toast: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 代码 new 出的 Control 挂 Control 父下锚点不自动求值(size 停留 0×0) → 显式铺满
	size = get_parent_area_size()
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 半透明遮罩(点击空白关闭)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_close())
	add_child(dim)
	Responsive.expand_to_viewport(dim)   # 遮罩延伸到避让条, 页面内外一致

	# 居中容器 + 弹窗面板
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(AppTheme.PANEL, AppTheme.GOLD, 16, 2)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 18
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	# PanelContainer 会把每个子控件拉伸铺满面板 → 头部/页签/滚动区包进同一 VBox
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	panel.add_child(page)

	# 标题 + 关闭
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	page.add_child(head)
	var title := AppTheme.make_label(24, AppTheme.GOLD)
	title.text = tr("个 人 档 案")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	var close_btn := AppTheme.make_button("✕", Vector2(40, 40), 20)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	close_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_close())
	head.add_child(close_btn)

	# 页签行(成就/战绩/对局回放/每日任务/统计)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(tabs)
	_tab_ach_btn = AppTheme.make_button("成  就", Vector2(104, 42), 15)
	_tab_ach_btn.toggle_mode = true
	_tab_ach_btn.pressed.connect(func() -> void: _set_tab("ach"))
	tabs.add_child(_tab_ach_btn)
	_tab_hist_btn = AppTheme.make_button("战  绩", Vector2(104, 42), 15)
	_tab_hist_btn.toggle_mode = true
	_tab_hist_btn.pressed.connect(func() -> void: _set_tab("hist"))
	tabs.add_child(_tab_hist_btn)
	_tab_replay_btn = AppTheme.make_button("对局回放", Vector2(104, 42), 15)
	_tab_replay_btn.toggle_mode = true
	_tab_replay_btn.pressed.connect(func() -> void: _set_tab("replay"))
	tabs.add_child(_tab_replay_btn)
	_tab_mission_btn = AppTheme.make_button("每日任务", Vector2(104, 42), 15)
	_tab_mission_btn.toggle_mode = true
	_tab_mission_btn.pressed.connect(func() -> void: _set_tab("mission"))
	tabs.add_child(_tab_mission_btn)
	_tab_stats_btn = AppTheme.make_button("统  计", Vector2(104, 42), 15)
	_tab_stats_btn.toggle_mode = true
	_tab_stats_btn.pressed.connect(func() -> void: _set_tab("stats"))
	tabs.add_child(_tab_stats_btn)

	# 滚动内容(触摸滑动/滚轮; 宽度固定窄栏)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(520, 0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_scroll)
	_grid = VBoxContainer.new()
	_grid.add_theme_constant_override("separation", 12)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不吃触屏拖动, 保证滑屏顺滑
	_scroll.add_child(_grid)

	# 底部提示(领取奖励回执等)
	_toast = AppTheme.make_label(14, AppTheme.GOLD)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_toast)

	_set_tab("ach")
	Responsive.watch(self, _relayout)


func _relayout() -> void:
	var h := size.y
	if h < 100.0:
		return
	# 滚动区高度随视口收缩(小屏弹窗不超屏, 大屏封顶)
	_scroll.custom_minimum_size.y = minf(h * 0.62, 540.0)


func _set_tab(tab: String) -> void:
	_tab = tab
	_tab_ach_btn.button_pressed = tab == "ach"
	_tab_hist_btn.button_pressed = tab == "hist"
	_tab_replay_btn.button_pressed = tab == "replay"
	_tab_mission_btn.button_pressed = tab == "mission"
	_tab_stats_btn.button_pressed = tab == "stats"
	# 底部回执只在当前页签显示: 切页即清(避免"已删除回放"残留到别的页)
	_toast.text = ""
	_refresh()


func _refresh() -> void:
	for child in _grid.get_children():
		child.queue_free()
	if _tab == "ach":
		_build_achievements()
	elif _tab == "replay":
		_build_replays()
	elif _tab == "mission":
		_build_missions()
	elif _tab == "stats":
		_build_stats()
	else:
		_build_history()


## 成就行: 金框(已解锁) / 暗格(未锁定) + 名称/描述 + 状态
func _build_achievements() -> void:
	var done := 0
	for a in WalletGd.ACHIEVEMENTS:
		var unlocked := Wallet.unlocked.has(str(a["id"]))
		if unlocked:
			done += 1
		_grid.add_child(_ach_row(a, unlocked))
	var head := AppTheme.make_label(15, AppTheme.DIM)
	head.text = tr("已解锁 %d / %d · 每枚成就 +2钻石, 集齐全部再 +36钻石") \
			% [done, WalletGd.ACHIEVEMENTS.size()]
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
			AppTheme.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	wrap.add_child(head)
	_grid.add_child(wrap)
	_grid.move_child(wrap, 0)


func _ach_row(a: Dictionary, unlocked: bool) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不吃触屏拖动
	var sb := AppTheme.flat(Color(0.13, 0.13, 0.28),
			AppTheme.GOLD if unlocked else Color(1, 1, 1, 0.12), 10, 1 if not unlocked else 2)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	panel.add_child(h)
	var icon := AppTheme.make_label(26, AppTheme.GOLD if unlocked else AppTheme.DIM)
	icon.text = "🏆" if unlocked else "🔒"
	icon.custom_minimum_size = Vector2(40, 0)
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var nm := AppTheme.make_label(18, AppTheme.WHITE if unlocked else AppTheme.DIM)
	nm.text = str(a["name"])
	v.add_child(nm)
	var ds := AppTheme.make_label(13, AppTheme.DIM)
	ds.text = str(a["desc"])
	v.add_child(ds)
	var tag := AppTheme.make_label(15, AppTheme.GOLD if unlocked else AppTheme.DIM)
	tag.text = "已解锁" if unlocked else "未解锁"
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(tag)
	return panel


## 每日任务行: 进度/奖励/领取
func _build_missions() -> void:
	var day_lbl := AppTheme.make_label(15, AppTheme.DIM)
	day_lbl.text = "每日 0 点重置 · 完成对局与任务可获金币钻石"
	_grid.add_child(day_lbl)
	for m in WalletGd.MISSIONS:
		var st: Dictionary = Wallet.mission_state(str(m["id"]))
		var prog := int(st["progress"])
		var target := int(m["target"])
		var claimed := bool(st["claimed"])
		var done := prog >= target and not claimed
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不吃触屏拖动
		var sb := AppTheme.flat(Color(0.13, 0.13, 0.28),
				AppTheme.GOLD if claimed else Color(1, 1, 1, 0.12), 10, 1)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		panel.add_theme_stylebox_override("panel", sb)
		_grid.add_child(panel)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		panel.add_child(h)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 2)
		h.add_child(v)
		var nm := AppTheme.make_label(17, AppTheme.WHITE)
		nm.text = str(m["name"])
		v.add_child(nm)
		var ds := AppTheme.make_label(13, AppTheme.DIM)
		var rw: Array = []
		if int(m.get("reward_gold", 0)) > 0:
			rw.append("%d金币" % int(m["reward_gold"]))
		if int(m.get("reward_diamonds", 0)) > 0:
			rw.append("%d钻石" % int(m["reward_diamonds"]))
		ds.text = "奖励: %s · 进度 %d/%d" % [" + ".join(PackedStringArray(rw)), prog, target]
		v.add_child(ds)
		var btn := AppTheme.make_button(
				"已领取" if claimed else ("领 取" if done else "未完成"),
				Vector2(110, 40), 14)
		btn.disabled = claimed or not done
		var mid := str(m["id"])
		btn.pressed.connect(func() -> void:
			var r: Dictionary = Wallet.claim_mission(mid)
			if not r.is_empty():
				Audio.play("win")
				_toast.text = "任务奖励: %+d金币 %+d钻石" % [int(r["gold"]), int(r["diamonds"])]
			_refresh())
		h.add_child(btn)


## 统计: 各模式场次/胜率/最佳一览
func _build_stats() -> void:
	var rows := [
		["🂡 大富豪", tr("场次 %d · 胜 %d · 胜率 %d%%") % [Wallet.local_matches,
				Wallet.local_wins,
				(100 * Wallet.local_wins / Wallet.local_matches)
						if Wallet.local_matches > 0 else 0]],
		["🎲 肉鸽模式", tr("场次 %d · 胜 %d") % [Wallet.rogue_runs, Wallet.rogue_wins]],
		["⚔ 格斗试炼", tr("局数 %d · 通关 %d · 最远第 %d 回合 · 击破 BOSS %d") % [
				Wallet.fight_runs, Wallet.fight_clears, Wallet.fight_best,
				Wallet.fight_bosses]],
		["🥊 联机格斗对战", tr("胜场 %d") % Wallet.pvp_wins],
		["📅 每日挑战", _daily_text() + " · " + tr("累计参与 %d 天") % Wallet.daily_days],
		["📕 命运卡图鉴", tr("已见 %d / %d 种") % [Wallet.mod_seen.size(),
				_preload_mods().size()]],
	]
	for r in rows:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不吃触屏拖动
		var sb := AppTheme.flat(Color(0.13, 0.13, 0.28), Color(1, 1, 1, 0.12), 10, 1)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		panel.add_theme_stylebox_override("panel", sb)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		panel.add_child(h)
		var nm := AppTheme.make_label(16, AppTheme.GOLD)
		nm.text = str(r[0])
		nm.custom_minimum_size = Vector2(150, 0)
		h.add_child(nm)
		var v := AppTheme.make_label(14, AppTheme.WHITE)
		v.text = str(r[1])
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # 窄栏下长行折行
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		_grid.add_child(panel)


func _daily_text() -> String:
	var today := Time.get_date_string_from_system()
	if Wallet.daily_day != today:
		return tr("今日未挑战")
	if int(Wallet.daily_best_round) >= 5:
		return tr("今日已通关(剩余生命 %d%%)") % Wallet.daily_best_hp
	return tr("今日最佳: 到达第 %d 回合") % Wallet.daily_best_round


func _preload_mods() -> Array:
	return GameStateGd.ROGUE_MODS


## 对局回放: 独立页签 — 最近回放列表(点击观看 / 删除); 右上角"清空全部"
func _build_replays() -> void:
	var head := AppTheme.make_label(15, AppTheme.DIM)
	head.text = tr("最近 %d 场回放 · 点击观看, ✕ 删除") % [Wallet.replays.size()]
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 10)
	head_row.add_child(head)
	# 右上角: 一键删除所有回放(二次确认, 3 秒不确认自动还原)
	if not (Wallet.replays as Array).is_empty():
		var armed := [false]
		var clear_btn := AppTheme.make_button("🗑 清空全部", Vector2(118, 36), 13)
		clear_btn.tooltip_text = "删除所有对局回放(不可恢复)"
		clear_btn.pressed.connect(func() -> void:
			Audio.play("click")
			if not armed[0]:
				armed[0] = true
				clear_btn.text = "确认清空?"
				var tw := clear_btn.create_tween()
				tw.tween_interval(3.0)
				tw.tween_callback(func() -> void:
					armed[0] = false
					if is_instance_valid(clear_btn) and clear_btn.is_inside_tree():
						clear_btn.text = "🗑 清空全部")
				return
			Wallet.clear_replays()
			_toast.text = "已删除全部回放"
			_refresh())
		head_row.add_child(clear_btn)
	_grid.add_child(head_row)
	if (Wallet.replays as Array).is_empty():
		var empty := AppTheme.make_label(15, AppTheme.DIM)
		empty.text = "还没有对局回放 — 完成一局本地大富豪后可在这里观看"
		_grid.add_child(empty)
		return
	for i in Wallet.replays.size():
		var rp: Dictionary = Wallet.replays[i]
		var idx := i
		var hands: int = (rp.get("actions", []) as Array).size()
		var txt := "▶ %s · %s · %d 手" % [str(rp.get("day", "")),
				str(rp.get("mode", "")), hands]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_grid.add_child(row)
		var btn := AppTheme.make_button(txt, Vector2(0, 40), 13)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.pressed.connect(func() -> void:
			Audio.play("click")
			replay_selected.emit(rp))
		row.add_child(btn)
		var del := AppTheme.make_button("✕", Vector2(40, 40), 16)
		del.tooltip_text = "删除这场回放"
		del.pressed.connect(func() -> void:
			Audio.play("click")
			Wallet.delete_replay(idx)
			_toast.text = "已删除该场回放"
			_refresh())
		row.add_child(del)


## 战绩: 汇总 + 最近记录行(模式/名次/积分/奖励; 回放列表见独立页签)
func _build_history() -> void:
	var total := Wallet.local_matches
	var wins := Wallet.local_wins
	var head := AppTheme.make_label(16, AppTheme.WHITE)
	head.text = tr("共 %d 场 · 胜 %d 场 · 胜率 %d%% · 称号 %s") % [total, wins,
			(100 * wins / total) if total > 0 else 0, Wallet.rank_title()]
	_grid.add_child(head)
	var fight := AppTheme.make_label(16, AppTheme.GOLD)
	fight.text = tr("⚔ 格斗试炼最高纪录: 第 %d 回合") % Wallet.fight_best
	_grid.add_child(fight)
	if (Wallet.history as Array).is_empty():
		var empty := AppTheme.make_label(15, AppTheme.DIM)
		empty.text = "还没有对局记录 — 去打一局吧!"
		_grid.add_child(empty)
		return
	for e in Wallet.history:
		if str(e.get("mode", "")) == "格斗":
			var fr := AppTheme.make_label(15, AppTheme.GOLD)
			fr.text = "%s · ⚔格斗试炼 · 到达第 %d 层 · %+d钻石" % [
					str(e.get("day", "")), int(e.get("floor", 0)),
					int(e.get("diamonds", 0))]
			_grid.add_child(fr)
			continue
		var rank := int(e.get("rank", 0))
		var row := AppTheme.make_label(15,
				AppTheme.GOLD if rank == 1 else AppTheme.DIM)
		row.text = "%s · %s · 第%d名 · %+d分 · %+d金币 %+d钻石" % [
			str(e.get("day", "")), str(e.get("mode", "")), rank,
			int(e.get("points", 0)), int(e.get("gold", 0)), int(e.get("diamonds", 0)),
		]
		_grid.add_child(row)


func _close() -> void:
	closed.emit()
	queue_free()
