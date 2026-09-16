## 个人档案面板: 成就 + 战绩 双页签(主菜单徽章区入口)。
## 成就=全目录(已解锁金框/未解锁暗格+进度来源), 战绩=最近对局记录列表。
extends Control

signal closed

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const WalletGd = preload("res://src/autoload/wallet.gd")
const GameStateGd = preload("res://src/rules/game_state.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")

var _tab := "ach"
var _tab_ach_btn: Button
var _tab_hist_btn: Button
var _tab_mission_btn: Button
var _tab_stats_btn: Button
var _scroll: ScrollContainer
var _grid: VBoxContainer
var _toast: Label
var _back_btn: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 代码 new 出的 Control 挂 Control 父下锚点不自动求值(size 停留 0×0) → 显式铺满
	size = get_parent_area_size()
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = AppTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var header: Control = preload("res://src/client/ui/p5_header.gd").new()
	header.text = "个 人 档 案"
	header.icon = "scroll"
	header.position = Vector2(36, 22)
	header.custom_minimum_size = Vector2(340, 54)
	header.size = Vector2(340, 54)
	add_child(header)

	_back_btn = AppTheme.make_button("返 回", Vector2(100, 42), 17)
	_back_btn.position = Vector2(1150, 24)
	_back_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_close())
	add_child(_back_btn)

	_tab_ach_btn = AppTheme.make_button("成  就", Vector2(200, 46), 18)
	_tab_ach_btn.position = Vector2(40, 110)
	_tab_ach_btn.toggle_mode = true
	_tab_ach_btn.pressed.connect(func() -> void: _set_tab("ach"))
	add_child(_tab_ach_btn)
	_tab_hist_btn = AppTheme.make_button("战  绩", Vector2(200, 46), 18)
	_tab_hist_btn.position = Vector2(255, 110)
	_tab_hist_btn.toggle_mode = true
	_tab_hist_btn.pressed.connect(func() -> void: _set_tab("hist"))
	add_child(_tab_hist_btn)
	_tab_mission_btn = AppTheme.make_button("每日任务", Vector2(200, 46), 18)
	_tab_mission_btn.position = Vector2(470, 110)
	_tab_mission_btn.toggle_mode = true
	_tab_mission_btn.pressed.connect(func() -> void: _set_tab("mission"))
	add_child(_tab_mission_btn)
	_tab_stats_btn = AppTheme.make_button("统  计", Vector2(200, 46), 18)
	_tab_stats_btn.position = Vector2(685, 110)
	_tab_stats_btn.toggle_mode = true
	_tab_stats_btn.pressed.connect(func() -> void: _set_tab("stats"))
	add_child(_tab_stats_btn)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(40, 170)
	_scroll.custom_minimum_size = Vector2(1200, 484)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_grid = VBoxContainer.new()
	_grid.add_theme_constant_override("separation", 12)
	_scroll.add_child(_grid)

	_toast = AppTheme.make_label(15, AppTheme.DIM)
	_toast.position = Vector2(40, 660)
	add_child(_toast)

	_set_tab("ach")
	Responsive.watch(self, _relayout)


func _relayout() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	_back_btn.position = Vector2(w - 130.0, 24)
	_scroll.position = Vector2(40, 170)
	_scroll.size = Vector2(w - 80.0, h - 236.0)
	_toast.position = Vector2(40, h - 60)


func _set_tab(tab: String) -> void:
	_tab = tab
	_tab_ach_btn.button_pressed = tab == "ach"
	_tab_hist_btn.button_pressed = tab == "hist"
	_tab_mission_btn.button_pressed = tab == "mission"
	_tab_stats_btn.button_pressed = tab == "stats"
	_refresh()


func _refresh() -> void:
	for child in _grid.get_children():
		child.queue_free()
	if _tab == "ach":
		_build_achievements()
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
	head.text = tr("已解锁 %d / %d") % [done, WalletGd.ACHIEVEMENTS.size()]
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
			AppTheme.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	wrap.add_child(head)
	_grid.add_child(wrap)
	_grid.move_child(wrap, 0)


func _ach_row(a: Dictionary, unlocked: bool) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		["📅 每日挑战", "%s · " + tr("累计参与 %d 天") % Wallet.daily_days],
		["📕 命运卡图鉴", tr("已见 %d / %d 种") % [Wallet.mod_seen.size(),
				_preload_mods().size()]],
	]
	for r in rows:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := AppTheme.flat(Color(0.13, 0.13, 0.28), Color(1, 1, 1, 0.12), 10, 1)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		panel.add_theme_stylebox_override("panel", sb)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		panel.add_child(h)
		var nm := AppTheme.make_label(18, AppTheme.GOLD)
		nm.text = str(r[0])
		nm.custom_minimum_size = Vector2(220, 0)
		h.add_child(nm)
		var v := AppTheme.make_label(16, AppTheme.WHITE)
		v.text = str(r[1])
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


## 战绩: 头部汇总 + 最近记录行(模式/名次/积分/奖励)
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
