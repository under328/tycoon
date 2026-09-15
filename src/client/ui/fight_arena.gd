## 联机格斗对战竞技场(1v1 + 观战): 渲染服务器下发的 s_fight_state 视图。
## 阶段: 选牌(10 选 5) → 回合制互殴(攻击/技能/防御) → 终局结算。
## 观战者全程可见但无操作按钮。本页不驱动任何规则 — 服务器权威。
extends Control

signal finished  # 离开竞技场 → 返回大厅

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const FightModeGd = preload("res://src/rules/fight/fight_mode.gd")
const CardViewScript = preload("res://src/client/ui/card_view.gd")
const AvatarScript = preload("res://src/client/ui/avatar.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")

var mode := "online"
var net: Node = null

var view: Dictionary = {}      # 最近一次服务器视图
var _sel: Array = []           # 本地选牌(提交前)
var _cards_ui: Array = []      # {wrap, sb, id, on}
var _hand_built: Dictionary = {}  # seat → 装备卡已渲染的牌列表(免重建)
var _rewarded := false         # 结算只入账一次
var _turn_remain := -1.0
var _timer_shown := -1
var _act_timer: Label = null   # 我的回合操作区的倒计时文字
var _pick_info: Label = null   # 选牌预览文字(原地刷新)
var _pick_confirm: Button = null
var _card_w := 82.0            # 候选卡宽(窄窗自适应收缩)
var _events_q: Array = []      # 待播放飘字事件
var _playing := false
var overlay: CenterContainer = null

var phase_lbl: Label
var spec_lbl: Label
var leave_btn: Button
var log_lbl: Label
var bottom_box: Control        # 底部操作区(每次状态变化重建)
var floaters: Control
# 双方格斗面板: 下标 0/1 = fighters[0]/[1]
var _side: Array = []
var _vs_lbl: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = get_parent_area_size()

	var bg := ColorRect.new()
	bg.color = Color("1c1428")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var header = preload("res://src/client/ui/p5_header.gd").new()
	header.text = "格斗对战"
	header.icon = "card"
	header.position = Vector2(36, 22)
	header.custom_minimum_size = Vector2(420, 54)
	header.size = Vector2(420, 54)
	add_child(header)

	phase_lbl = AppTheme.make_label(18, AppTheme.GOLD)
	phase_lbl.text = "等待服务器…"
	add_child(phase_lbl)

	spec_lbl = AppTheme.make_label(15, Color("9fd8ff"))
	spec_lbl.visible = false
	add_child(spec_lbl)

	leave_btn = AppTheme.make_button("离开", Vector2(110, 42), 15)
	leave_btn.pressed.connect(_do_leave)
	add_child(leave_btn)

	_vs_lbl = _label(34, AppTheme.GOLD)
	_vs_lbl.text = "VS"
	add_child(_vs_lbl)

	for i in 2:
		_side.append(_build_fighter_panel(i))

	log_lbl = _label(14, Color("c9b06a"))
	log_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(log_lbl)

	floaters = Control.new()
	floaters.set_anchors_preset(Control.PRESET_FULL_RECT)
	floaters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floaters)

	bottom_box = Control.new()
	bottom_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_box)

	if net != null:
		net.fight_state.connect(_on_fight_state)
		if not (net.latest_fight as Dictionary).is_empty():
			_apply(net.latest_fight, [])
	Responsive.watch(self, _relayout)
	_relayout.call_deferred()
	Audio.play_bgm("table")


## ── 服务器视图驱动 ──
func _on_fight_state(v: Dictionary) -> void:
	_apply(v, [])


func _apply(v: Dictionary, events: Array) -> void:
	var prev_phase := str(view.get("phase", ""))
	view = v
	var phase := str(v.get("phase", ""))
	phase_lbl.text = {"pick": "选牌阶段 — 10 选 5", "battle": "战斗中",
			"over": "终局"}.get(phase, phase)
	var fighter: bool = not bool(v.get("spectator", true))
	spec_lbl.visible = not fighter
	spec_lbl.text = "👁 观战中 — 本房间仅 1/2 号位可出战"
	if phase == "pick" and prev_phase != "pick":
		_rewarded = false   # 新一局开始: 重置结算入账标记
		_sel.clear()
		_close_overlay()
	_refresh_sides()
	_refresh_log()
	_reset_timer()
	_rebuild_bottom()
	if not (events as Array).is_empty() and phase != "pick":
		_play_events(events)
	if phase == "over" and not _rewarded:
		_rewarded = true
		_show_result()


func _refresh_sides() -> void:
	var fighters: Array = view.get("fighters", [])
	for i in 2:
		if i >= fighters.size():
			continue
		var seat := int(fighters[i])
		var p: Dictionary = _side[i]
		(p["name"] as Label).text = str((view.get("names", {}) as Dictionary)
				.get(seat, "玩家"))
		(p["you"] as Label).visible = seat == int(view.get("my_seat", -1))
		if net != null:
			(p["avatar"] as Control).skin_id = net.skin_of_seat(seat)
		# 血条
		var hp: int = int((view.get("hp", {}) as Dictionary).get(seat, 0))
		var mh: int = maxi(int((view.get("max_hp", {}) as Dictionary)
				.get(seat, 1)), 1)
		var frac := float(clampi(hp, 0, mh)) / float(mh)
		var fg: ColorRect = p["hp_fg"]
		fg.size = Vector2(maxi(fg.get_parent().size.x * frac - 4.0, 2.0), 16)
		fg.color = Color("58c858") if frac > 0.5 \
				else (Color("ffb14e") if frac > 0.25 else Color("d05050"))
		(p["hp_txt"] as Label).text = "HP %d / %d" % [maxi(hp, 0), mh]
		# 当前回合高亮
		var is_turn: bool = int(view.get("turn", -1)) == seat \
				and str(view.get("phase", "")) == "battle"
		(p["turn_chip"] as Label).visible = is_turn
		var sb: StyleBoxFlat = p["sb"]
		sb.border_color = AppTheme.GOLD if is_turn else Color(1, 1, 1, 0.18)
		sb.set_border_width_all(3 if is_turn else 1)
		# 牌型/装备/属性(战斗阶段起公开)
		var combos: Dictionary = view.get("combo", {})
		if (combos as Dictionary).has(seat):
			var c: Dictionary = combos[seat]
			(p["combo"] as Label).text = "牌型 %s · %s" % [c["name"], c["desc"]]
			(p["hand"] as HBoxContainer).visible = true
			_fill_hand(i, seat)
			var br: Dictionary = (view.get("stats_brief", {}) as Dictionary)[seat]
			var kinds := {"fire": "🔥火球", "frost": "❄冰霜", "light": "✟圣光"}
			(p["stats"] as Label).text = "⚔%d  🛡%d  ✟%d  %s" % [
				int(br["atk"]), int(br["def"]), int(br["skill"]),
				str(kinds.get(str((view.get("skill_kind", {}) as Dictionary)
						.get(seat, "fire")), ""))]
		else:
			(p["combo"] as Label).text = "选牌中…"
			(p["hand"] as HBoxContainer).visible = false
			(p["stats"] as Label).text = ""


func _fill_hand(_idx: int, seat: int) -> void:
	var hands: Dictionary = view.get("hands", {})
	if not (hands as Dictionary).has(seat):
		return
	var want: Array = hands[seat]
	if int(_hand_built.get(seat, -1)) == hash(want):
		return
	_hand_built[seat] = hash(want)
	var row: HBoxContainer = _side[_idx]["hand"]
	for c in row.get_children():
		c.queue_free()
	for id in want:
		var cv: Control = CardViewScript.new(int(id))
		cv.custom_minimum_size = Vector2(52, 74)
		cv.size = Vector2(52, 74)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(cv)


func _refresh_log() -> void:
	var lines: Array = view.get("log", [])
	var show: Array = lines.slice(maxi(lines.size() - 4, 0))
	log_lbl.text = "\n".join(show)


## ── 底部操作区(随阶段/操作权重建) ──
func _rebuild_bottom() -> void:
	for c in bottom_box.get_children():
		c.queue_free()
	_act_timer = null
	_pick_info = null
	_pick_confirm = null
	var phase := str(view.get("phase", ""))
	var my_seat := int(view.get("my_seat", -1))
	var fighter: bool = not bool(view.get("spectator", true))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	bottom_box.add_child(box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	if phase == "pick":
		if not fighter:
			_status_line(row, "两位格斗者正在选牌(10 选 5)…")
			return
		var done: bool = bool((view.get("picks_done", {}) as Dictionary)
				.get(my_seat, false))
		if done:
			_status_line(row, "已出战 — 等待对手选牌…")
			return
		_build_candidate_row(box)   # 10 张候选卡
		_build_pick_row(row)
	elif phase == "battle":
		if bool(view.get("my_turn", false)):
			_build_act_row(row)
		else:
			var turn := int(view.get("turn", -1))
			var nm: String = str((view.get("names", {}) as Dictionary)
					.get(turn, "对方"))
			_status_line(row, "等待 %s 行动…" % nm)
	else:
		_status_line(row, "对局已结束 — 可等待房主开始下一局")


func _status_line(row: HBoxContainer, text: String) -> void:
	var lb := AppTheme.make_label(16, AppTheme.WHITE)
	lb.text = text
	row.add_child(lb)


## 候选卡行: 10 张可点选(本地预选, 出战时提交)。每次重建重画
## (选牌阶段服务器广播稀少, 重建开销可忽略; 常驻缓存会与重建时序打架)
func _build_candidate_row(box: VBoxContainer) -> void:
	var cards_row := HBoxContainer.new()
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.add_theme_constant_override("separation", 10)
	box.add_child(cards_row)
	_cards_ui.clear()
	var ch := _card_w * 116.0 / 82.0
	for c in view.get("candidates", []):
		var wrap := PanelContainer.new()
		var sb := AppTheme.flat(Color(0.10, 0.10, 0.22),
				Color(1, 1, 1, 0.2), 8, 1)
		wrap.add_theme_stylebox_override("panel", sb)
		var cv: Control = CardViewScript.new(int(c))
		cv.custom_minimum_size = Vector2(_card_w, ch)
		cv.size = Vector2(_card_w, ch)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(cv)
		var id := int(c)
		var on: bool = (_sel as Array).has(id)
		sb.border_color = AppTheme.GOLD if on else Color(1, 1, 1, 0.2)
		sb.set_border_width_all(3 if on else 1)
		wrap.mouse_filter = Control.MOUSE_FILTER_STOP
		wrap.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_LEFT:
				_toggle_select(id))
		cards_row.add_child(wrap)
		_cards_ui.append({"wrap": wrap, "sb": sb, "id": id})


func _toggle_select(id: int) -> void:
	Audio.play("click")
	var on := not (_sel as Array).has(id)
	if on and _sel.size() >= 5:
		return
	if on:
		_sel.append(id)
	else:
		_sel.erase(id)
	for e in _cards_ui:
		var active: bool = (_sel as Array).has(int(e["id"]))
		var sb: StyleBoxFlat = e["sb"]
		sb.border_color = AppTheme.GOLD if active else Color(1, 1, 1, 0.2)
		sb.set_border_width_all(3 if active else 1)
	_refresh_pick_row()   # 牌型预览/出战按钮(原地更新, 不重建卡行)


func _refresh_pick_row() -> void:
	if _pick_info == null or not is_instance_valid(_pick_info):
		return
	if _sel.size() == 5:
		var c: Dictionary = FightModeGd.evaluate_combo(_sel)
		_pick_info.text = "已选 5/5 · %s(%s)" % [c["name"], c["desc"]]
	else:
		_pick_info.text = "已选 %d/5 · ♠物攻暴击 ♦护甲魔抗 ♥生命 ♣法术" % _sel.size()
	if _pick_confirm != null and is_instance_valid(_pick_confirm):
		_pick_confirm.disabled = _sel.size() != 5


func _build_pick_row(row: HBoxContainer) -> void:
	_pick_info = AppTheme.make_label(15, AppTheme.GOLD)
	if _sel.size() == 5:
		var c: Dictionary = FightModeGd.evaluate_combo(_sel)
		_pick_info.text = "已选 5/5 · %s(%s)" % [c["name"], c["desc"]]
	else:
		_pick_info.text = "已选 %d/5 · ♠物攻暴击 ♦护甲魔抗 ♥生命 ♣法术" % _sel.size()
	row.add_child(_pick_info)
	_pick_confirm = AppTheme.make_button("出 战", Vector2(170, 50), 19)
	_pick_confirm.disabled = _sel.size() != 5
	_pick_confirm.pressed.connect(func() -> void:
		Audio.play("win")
		if net != null and _sel.size() == 5:
			net.send_fight_pick(_sel.duplicate())
		_rebuild_bottom())
	row.add_child(_pick_confirm)


func _build_act_row(row: HBoxContainer) -> void:
	_act_timer = AppTheme.make_label(18, AppTheme.WHITE)
	_act_timer.text = "⏱ %d" % maxi(_timer_shown, 0)
	row.add_child(_act_timer)
	var atk := AppTheme.make_button("⚔ 攻击", Vector2(160, 54), 18)
	atk.pressed.connect(func() -> void: _send_act("attack"))
	row.add_child(atk)
	var my_seat := int(view.get("my_seat", -1))
	var cd: int = int((view.get("skill_cd", {}) as Dictionary).get(my_seat, 0))
	var kind: String = str((view.get("skill_kind", {}) as Dictionary)
			.get(my_seat, "fire"))
	var icon: String = {"fire": "🔥火球", "frost": "❄冰霜",
			"light": "✟圣光"}.get(kind, "✨技能")
	var skill := AppTheme.make_button(str(icon) if cd <= 0 else "冷却 %d" % cd,
			Vector2(160, 54), 18)
	skill.disabled = cd > 0
	skill.pressed.connect(func() -> void: _send_act("skill"))
	row.add_child(skill)
	var def := AppTheme.make_button("🛡 防御", Vector2(160, 54), 18)
	def.pressed.connect(func() -> void: _send_act("defend"))
	row.add_child(def)


func _send_act(action: String) -> void:
	Audio.play("click")
	if net != null:
		net.send_fight_act(action)


## ── 事件飘字(顺序播放, 0.45s/条) ──
func _play_events(events: Array) -> void:
	_events_q.append_array(events)
	if _playing:
		return
	_playing = true
	_play_next()


func _play_next() -> void:
	if (_events_q as Array).is_empty():
		_playing = false
		return
	var ev: Dictionary = _events_q.pop_front()
	var x := _side_x(int(ev.get("target", int(ev.get("who", 0)))))
	var y := size.y * 0.30
	var kind := str(ev.get("kind", ""))
	var v := int(ev.get("v", 0))
	match kind:
		"crit":
			_floater("暴击 -%d" % v, x, y, Color("ffd166"))
			_sfx("play_card")
		"dmg":
			_floater("-%d" % v, x, y, Color("ff8866"))
			_sfx("play_card")
		"skill":
			_floater("技能 -%d" % v, x, y, Color("7ec8ff"))
			_sfx("exchange")
		"heal":
			_floater("+%d" % v, x, y, Color("7dd87d"))
		"defend":
			_floater("防御", x, y, Color("7ec8ff"))
		"chill":
			_floater("❄ 被冻结", x, y, Color("9fd8ff"))
	var tw := create_tween()
	tw.tween_interval(0.45)
	tw.tween_callback(_play_next)


func _side_x(seat: int) -> float:
	var fighters: Array = view.get("fighters", [])
	var idx := 0
	if fighters.size() > 1 and int(fighters[1]) == seat:
		idx = 1
	return size.x * (0.25 if idx == 0 else 0.75)


func _floater(text: String, x: float, y: float, col: Color) -> void:
	var lb := _label(24, col)
	lb.text = text
	lb.position = Vector2(x - 40.0, y)
	lb.z_index = 10
	floaters.add_child(lb)
	var tw := lb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lb, "position:y", y - 56.0, 0.6)
	tw.tween_property(lb, "modulate:a", 0.0, 0.6).set_delay(0.1)
	tw.chain().tween_callback(lb.queue_free)


## ── 终局结算(只入账一次; 观战者不入账) ──
func _show_result() -> void:
	var my_seat := int(view.get("my_seat", -1))
	var winner := int(view.get("winner", -1))
	var fighter: bool = not bool(view.get("spectator", true))
	var title := "终 局"
	var body := "胜者: %s" % str((view.get("names", {}) as Dictionary)
			.get(winner, "—"))
	if fighter:
		var win: bool = winner == my_seat
		title = "胜 利 !" if win else "败 北…"
		var r: Dictionary = Wallet.grant_pvp_result(win)
		body += "\n奖励: %+d 金币 %+d 钻石 已入账" % [int(r["gold"]),
				int(r["diamonds"])]
		Audio.play("win" if win else "fall")
	_show_overlay(title, body)


func _show_overlay(title: String, body: String) -> void:
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = CenterContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(AppTheme.PANEL, AppTheme.GOLD, 16, 2)
	sb.content_margin_left = 50
	sb.content_margin_right = 50
	sb.content_margin_top = 30
	sb.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", sb)
	overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var t := AppTheme.make_label(32, AppTheme.GOLD)
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var b := AppTheme.make_label(16, AppTheme.WHITE)
	b.text = body
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(b)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var stay := AppTheme.make_button("留在房间", Vector2(150, 46), 16)
	stay.pressed.connect(func() -> void:
		Audio.play("click")
		_close_overlay())
	row.add_child(stay)
	var back := AppTheme.make_button("返回大厅", Vector2(150, 46), 16)
	back.pressed.connect(func() -> void:
		Audio.play("click")
		_do_leave())
	row.add_child(back)
	add_child(overlay)
	overlay.position = Vector2.ZERO
	overlay.size = size


func _close_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null


## ── 离开 ──
func _do_leave() -> void:
	_close_overlay()
	if net != null:
		net.leave_room()
	finished.emit()


## ── 回合计时(本地递减, 视图刷新时复位) ──
func _reset_timer() -> void:
	if str(view.get("phase", "")) == "battle":
		_turn_remain = float(view.get("turn_seconds", 20))
	else:
		_turn_remain = -1.0
	_timer_shown = -1


func _process(delta: float) -> void:
	if _turn_remain > 0.0:
		_turn_remain -= delta
		var cur := int(ceil(maxf(_turn_remain, 0.0)))
		if cur != _timer_shown:
			_timer_shown = cur
			if _act_timer != null and is_instance_valid(_act_timer) \
					and bool(view.get("my_turn", false)):
				_act_timer.text = "⏱ %d" % cur
				_act_timer.add_theme_color_override("font_color",
						AppTheme.RED if cur <= 5 else AppTheme.WHITE)


## ── 布局 ──
func _build_fighter_panel(_idx: int) -> Dictionary:
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(Color(0.09, 0.07, 0.16, 0.92),
			Color(1, 1, 1, 0.18), 12, 1)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var turn_chip := AppTheme.make_label(14, AppTheme.GOLD)
	turn_chip.text = "▶ 当前回合"
	turn_chip.visible = false
	box.add_child(turn_chip)
	var avatar: Control = AvatarScript.new()
	avatar.custom_minimum_size = Vector2(110, 110)
	avatar.size = Vector2(110, 110)
	var av_wrap := CenterContainer.new()
	av_wrap.add_child(avatar)
	box.add_child(av_wrap)
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 8)
	box.add_child(name_row)
	var nm := AppTheme.make_label(17, AppTheme.WHITE)
	name_row.add_child(nm)
	var you := AppTheme.make_label(14, Color("7dd87d"))
	you.text = "(你)"
	you.visible = false
	name_row.add_child(you)
	var combo := AppTheme.make_label(13, AppTheme.GOLD)
	combo.text = "选牌中…"
	combo.custom_minimum_size = Vector2(280, 20)
	combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(combo)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.6)
	hp_bg.custom_minimum_size = Vector2(276, 20)
	var hp_fg := ColorRect.new()
	hp_fg.color = Color("58c858")
	hp_fg.position = Vector2(2, 2)
	hp_fg.size = Vector2(272, 16)
	hp_bg.add_child(hp_fg)
	var hp_center := CenterContainer.new()
	hp_center.add_child(hp_bg)
	box.add_child(hp_center)
	var hp_txt := _label(12, AppTheme.WHITE)
	hp_txt.text = "HP —"
	box.add_child(hp_txt)
	var stats := AppTheme.make_label(13, Color("c9b06a"))
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.custom_minimum_size = Vector2(280, 20)
	box.add_child(stats)
	var hand := HBoxContainer.new()
	hand.alignment = BoxContainer.ALIGNMENT_CENTER
	hand.add_theme_constant_override("separation", 4)
	hand.visible = false
	box.add_child(hand)
	return {"panel": panel, "sb": sb, "avatar": avatar, "name": nm,
			"you": you, "combo": combo, "hp_fg": hp_fg, "hp_txt": hp_txt,
			"stats": stats, "hand": hand, "turn_chip": turn_chip}


func _relayout() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	leave_btn.position = Vector2(w - 130.0, 26)
	phase_lbl.position = Vector2(w / 2.0 - 100.0, 36)
	spec_lbl.position = Vector2(w / 2.0 - 140.0, 64)
	_vs_lbl.position = Vector2(w / 2.0 - 24.0, h * 0.34)
	log_lbl.position = Vector2(w / 2.0 - 200.0, h * 0.50)
	log_lbl.custom_minimum_size = Vector2(400.0, h * 0.18)
	# 双方面板: 左右对称
	var pw := minf(320.0, w * 0.28)
	var ph := h * 0.62
	for i in 2:
		var panel: PanelContainer = _side[i]["panel"]
		panel.size = Vector2(pw, ph)
		panel.position = Vector2(
				w * 0.05 if i == 0 else w - w * 0.05 - pw, h * 0.13)
	# 底部操作区铺满, 内容行贴底居中
	bottom_box.position = Vector2.ZERO
	bottom_box.size = Vector2(w, h)
	for c in bottom_box.get_children():
		if c is VBoxContainer:
			var vb := c as VBoxContainer
			vb.position = Vector2(0.0, h - 150.0 if vb.get_child_count() > 1
					else h - 76.0)
			vb.custom_minimum_size = Vector2(w, 140.0)
			vb.size = Vector2(w, 140.0)
	# 候选卡随窗宽收缩(10 张不溢出); 尺寸档位变化时重建选牌行
	var cw := clampf((w - 60.0) / 10.0 - 10.0, 44.0, 82.0)
	if absf(cw - _card_w) > 2.0:
		_card_w = cw
		if str(view.get("phase", "")) == "pick" \
				and _pick_info != null and is_instance_valid(_pick_info):
			_rebuild_bottom()


func _label(size_num: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size_num)
	lb.add_theme_color_override("font_color", color)
	return lb


## 音效统一入口(与牌桌同款: 页面隐藏时不发声)
func _sfx(sfx_name: String) -> void:
	if visible:
		Audio.play(sfx_name)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_do_leave()
