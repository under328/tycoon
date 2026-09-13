## 个人档案面板: 成就 + 战绩 双页签(主菜单徽章区入口)。
## 成就=全目录(已解锁金框/未解锁暗格+进度来源), 战绩=最近对局记录列表。
extends Control

signal closed

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const WalletGd = preload("res://src/autoload/wallet.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")

var _tab := "ach"
var _tab_ach_btn: Button
var _tab_hist_btn: Button
var _scroll: ScrollContainer
var _grid: VBoxContainer
var _toast: Label
var _back_btn: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(AppTheme.BG, 0.98)
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
	_refresh()


func _refresh() -> void:
	for child in _grid.get_children():
		child.queue_free()
	if _tab == "ach":
		_build_achievements()
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
	head.text = "已解锁 %d / %d" % [done, WalletGd.ACHIEVEMENTS.size()]
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
			AppTheme.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	wrap.add_child(head)
	_grid.add_child(wrap)
	_grid.move_child(wrap, 0)


func _ach_row(a: Dictionary, unlocked: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1180, 0)
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


## 战绩: 头部汇总 + 最近记录行(模式/名次/积分/奖励)
func _build_history() -> void:
	var total := Wallet.local_matches
	var wins := Wallet.local_wins
	var head := AppTheme.make_label(16, AppTheme.WHITE)
	head.text = "共 %d 场 · 胜 %d 场 · 胜率 %d%% · 称号 %s" % [total, wins,
			(100 * wins / total) if total > 0 else 0, Wallet.rank_title()]
	_grid.add_child(head)
	if (Wallet.history as Array).is_empty():
		var empty := AppTheme.make_label(15, AppTheme.DIM)
		empty.text = "还没有对局记录 — 去打一局吧!"
		_grid.add_child(empty)
		return
	for e in Wallet.history:
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
