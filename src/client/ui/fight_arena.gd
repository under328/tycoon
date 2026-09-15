## 联机格斗对战竞技场 v2(回合制): 每回合『二选一』抽牌 → 玩家之间对战(无怪)。
## 先胜 3 回合获胜。渲染服务器下发的 s_fight_state 视图, 本页不驱动任何规则。
## 观战者全程可见但无操作按钮。特殊牌/补抽/替换机制与本地格斗试炼同源。
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
var _pending_cand := -1        # 槽满替换: 待放入的候选
var _act_timer: Label = null
var _events_q: Array = []
var _playing := false
var overlay: CenterContainer = null
var _rewarded := false

var phase_lbl: Label
var score_lbl: Label
var spec_lbl: Label
var leave_btn: Button
var log_lbl: Label
var bottom_box: Control        # 底部操作区(每次状态变化重建)
var floaters: Control
var _side: Array = []          # 双方面板(下标0/1 = fighters[0]/[1])
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
	header.custom_minimum_size = Vector2(360, 54)
	header.size = Vector2(360, 54)
	add_child(header)

	phase_lbl = AppTheme.make_label(18, AppTheme.GOLD)
	phase_lbl.text = "等待服务器…"
	add_child(phase_lbl)
	score_lbl = AppTheme.make_label(20, AppTheme.WHITE)
	add_child(score_lbl)

	spec_lbl = AppTheme.make_label(15, Color("9fd8ff"))
	spec_lbl.visible = false
	add_child(spec_lbl)

	leave_btn = AppTheme.make_button("离开", Vector2(110, 42), 15)
	leave_btn.pressed.connect(_do_leave)
	add_child(leave_btn)

	_vs_lbl = _label(30, AppTheme.GOLD)
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
	phase_lbl.text = {
		"draft": tr("第 %d/%d 回合 — 二选一编成") % [int(v.get("round_num", 1)),
				int(v.get("rounds_total", 5))],
		"battle": tr("第 %d 回合 — 对战!") % int(v.get("round_num", 1)),
		"round_end": tr("第 %d 回合 结束") % int(v.get("round_num", 1)),
		"over": "终局",
	}.get(phase, phase)
	var sc: Dictionary = v.get("score", {})
	var f: Array = v.get("fighters", [])
	score_lbl.text = "%d : %d" % [int(sc.get(int(f[0]) if f.size() > 0 else 0, 0)),
			int(sc.get(int(f[1]) if f.size() > 1 else 1, 0))]
	var fighter: bool = not bool(v.get("spectator", true))
	spec_lbl.visible = not fighter
	spec_lbl.text = "👁 观战中 — 本房间仅 1/2 号位可出战"
	if phase == "draft" and prev_phase != "draft":
		_rewarded = false
		_pending_cand = -1
		_close_overlay()
	_refresh_sides()
	_refresh_log()
	_reset_timer()
	_rebuild_bottom()
	if not (events as Array).is_empty() and phase != "draft":
		_play_events(events)
	if phase == "round_end" and prev_phase != "round_end":
		var rw := int(v.get("round_winner", -1))
		var my_seat := int(v.get("my_seat", -1))
		var won: bool = rw == my_seat
		_floater("回合胜利!" if won else "回合落败",
				size.x * 0.5, size.y * 0.32,
				Color("7dd87d") if won else Color("ff8866"))
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
		# 回合分
		var sc: Dictionary = view.get("score", {})
		(p["score"] as Label).text = tr("回合胜 %d") % int(sc.get(seat, 0))
		# 编成进度(奇物/装备数) — draft 阶段唯一可见信息
		var per: Dictionary = (view.get("per", {}) as Dictionary).get(seat, {})
		(p["prog"] as Label).text = tr("装备 %d/5 · 奇物 %d") % [
				int(per.get("slots_count", 0)), int(per.get("specials_count", 0))]
		(p["done"] as Label).visible = str(view.get("phase", "")) == "draft"
		(p["done"] as Label).text = "已编成" if bool(per.get("done", false)) \
				else "选牌中…"
		# 当前回合高亮
		var is_turn: bool = int(view.get("turn", -1)) == seat \
				and str(view.get("phase", "")) == "battle"
		(p["turn_chip"] as Label).visible = is_turn
		var sb: StyleBoxFlat = p["sb"]
		sb.border_color = AppTheme.GOLD if is_turn else Color(1, 1, 1, 0.18)
		sb.set_border_width_all(3 if is_turn else 1)
		# 战斗阶段: 血条/牌型/装备公开
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
			var hp: int = int((view.get("hp", {}) as Dictionary).get(seat, 0))
			var mh: int = maxi(int((view.get("max_hp", {}) as Dictionary)
					.get(seat, 1)), 1)
			var frac := float(clampi(hp, 0, mh)) / float(mh)
			var fg: ColorRect = p["hp_fg"]
			fg.size = Vector2(maxi(fg.get_parent().size.x * frac - 4.0, 2.0), 16)
			fg.color = Color("58c858") if frac > 0.5 \
					else (Color("ffb14e") if frac > 0.25 else Color("d05050"))
			(p["hp_txt"] as Label).text = "HP %d / %d" % [maxi(hp, 0), mh]
			var sh: int = int((view.get("shield", {}) as Dictionary).get(seat, 0))
			(p["shield_txt"] as Label).text = "🔮%d" % sh if sh > 0 else ""
		else:
			(p["combo"] as Label).text = "编成中…"
			(p["hand"] as HBoxContainer).visible = false
			(p["stats"] as Label).text = ""
			(p["hp_txt"] as Label).text = ""
			(p["shield_txt"] as Label).text = ""


func _fill_hand(idx: int, seat: int) -> void:
	var hands: Dictionary = view.get("hands", {})
	if not (hands as Dictionary).has(seat):
		return
	var want: Array = hands[seat]
	var row: HBoxContainer = _side[idx]["hand"]
	if int(row.get_meta("ids", -1)) == hash(want):
		return
	row.set_meta("ids", hash(want))
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


## ── 底部操作区 ──
func _rebuild_bottom() -> void:
	for c in bottom_box.get_children():
		c.queue_free()
	_act_timer = null
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
	if phase == "draft":
		if not fighter:
			_status_line(row, "两位格斗者正在编成…")
			return
		var my: Dictionary = view.get("my", {})
		if bool(my.get("done", true)):
			_status_line(row, "已编成 — 等待对手…")
			return
		_build_draft_ui(box)
	elif phase == "battle":
		if bool(view.get("my_turn", false)):
			_build_act_row(row)
		else:
			var turn := int(view.get("turn", -1))
			var nm: String = str((view.get("names", {}) as Dictionary)
					.get(turn, "对方"))
			_status_line(row, tr("等待 %s 行动…") % nm)
	elif phase == "round_end":
		var rw := int(view.get("round_winner", -1))
		var nm: String = str((view.get("names", {}) as Dictionary).get(rw, ""))
		_status_line(row, tr("%s 拿下本回合 — 即将进入下一回合…") % nm)
	else:
		_status_line(row, "对局已结束 — 可等待房主开始下一局")


func _status_line(row: HBoxContainer, text: String) -> void:
	var lb := AppTheme.make_label(16, AppTheme.WHITE)
	lb.text = text
	row.add_child(lb)


func _build_draft_ui(box: VBoxContainer) -> void:
	var my: Dictionary = view.get("my", {})
	if _pending_cand >= 0:
		var hint := AppTheme.make_label(15, AppTheme.GOLD)
		hint.text = "装备槽已满 — 点上方要替换的槽位，或跳过"
		box.add_child(hint)
	var pair: Array = my.get("pair", [])
	if (pair as Array).is_empty():
		return
	if _pending_cand < 0:
		var title := AppTheme.make_label(15, AppTheme.GOLD)
		title.text = (tr("🟣 奇物生效! 补抽一张普通牌") if bool(my.get("comp", false))
				else tr("二选一 — 点选 1 张 (装备 %d/5%s)") % [
				(my.get("slots", []) as Array).size(),
				"，本回合有额外候选组!" if int(my.get("pairs_left", 1)) > 1 else ""])
		box.add_child(title)
	var cards_row := HBoxContainer.new()
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.add_theme_constant_override("separation", 26)
	box.add_child(cards_row)
	for cand in pair:
		if cand >= 100:
			cards_row.add_child(_build_special_card(int(cand)))
		else:
			cards_row.add_child(_build_normal_card(int(cand), my))
	# 我方槽位行(替换模式可点)
	var slots_row := HBoxContainer.new()
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_row.add_theme_constant_override("separation", 6)
	box.add_child(slots_row)
	var slots: Array = my.get("slots", [])
	for i in 5:
		var chip := PanelContainer.new()
		var hl: bool = _pending_cand >= 0 and i < slots.size()
		var sb := AppTheme.flat(Color(0.06, 0.06, 0.14),
				AppTheme.GOLD if _pending_cand >= 0 else Color(1, 1, 1, 0.2),
				6, 3 if hl else 1)
		chip.add_theme_stylebox_override("panel", sb)
		chip.custom_minimum_size = Vector2(48, 66)
		if i < slots.size():
			var cv: Control = CardViewScript.new(int(slots[i]))
			cv.custom_minimum_size = Vector2(44, 62)
			cv.size = Vector2(44, 62)
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(cv)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		var idx := i
		chip.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_LEFT:
				_on_slot_clicked(idx))
		slots_row.add_child(chip)
	if _pending_cand >= 0:
		var skip := AppTheme.make_button("跳过这组", Vector2(150, 40), 14)
		skip.pressed.connect(func() -> void:
			Audio.play("click")
			_pending_cand = -1
			if net != null:
				net.send_fight_pick(-1)
			_rebuild_bottom())
		box.add_child(skip)


func _ternary(cond: bool, a: int, b: int) -> int:
	return a if cond else b


func _on_slot_clicked(idx: int) -> void:
	if _pending_cand < 0:
		return
	Audio.play("click")
	var cand := _pending_cand
	_pending_cand = -1
	if net != null:
		net.send_fight_pick(cand, idx)
	_rebuild_bottom()


func _build_normal_card(card: int, my: Dictionary) -> Control:
	var wrap := PanelContainer.new()
	var sb := AppTheme.flat(Color(0.10, 0.10, 0.22), Color(1, 1, 1, 0.2), 10, 1)
	wrap.add_theme_stylebox_override("panel", sb)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	wrap.add_child(vbox)
	var cc := CenterContainer.new()
	var cv: Control = CardViewScript.new(card)
	cv.custom_minimum_size = Vector2(88, 124)
	cv.size = Vector2(88, 124)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(cv)
	vbox.add_child(cc)
	var slots: Array = my.get("slots", [])
	var preview: Array = (slots as Array).slice(0, 4)
	if slots.size() < 5:
		preview = (slots as Array) + [card]
	else:
		preview = (slots as Array).duplicate()
		preview[0] = card   # 槽满默认预览替换 0 号位
	var combo: Dictionary = FightModeGd.evaluate_combo(preview)
	var hint := _label(11, Color("c9b06a"))
	hint.text = ("替换后 %s" if slots.size() >= 5 else "装备后 %s") \
			% str(combo["name"])
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_candidate(card))
	return wrap


func _build_special_card(cand: int) -> Control:
	var meta: Dictionary = FightModeGd.sp_meta(FightModeGd.sp_of(cand))
	var wrap := PanelContainer.new()
	var sb := AppTheme.flat(Color(0.16, 0.09, 0.24), Color("b070e0"), 10, 2)
	wrap.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	wrap.add_child(box)
	var icon := _label(38, Color("e8d0ff"))
	icon.text = str(meta["icon"])
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(icon)
	var nm := AppTheme.make_label(15, Color("e8d0ff"))
	nm.text = "【奇物】%s" % str(meta["name"])
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(nm)
	var desc := _label(12, Color("c8a8e0"))
	desc.text = str(meta["desc"])
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(170, 56)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(desc)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_candidate(cand))
	return wrap


func _on_candidate(cand: int) -> void:
	var my: Dictionary = view.get("my", {})
	var slots: Array = my.get("slots", [])
	if cand < 100 and slots.size() >= 5:
		_pending_cand = cand
		_rebuild_bottom()
		return
	Audio.play("click")
	if net != null:
		net.send_fight_pick(cand)
	_rebuild_bottom()


func _build_act_row(row: HBoxContainer) -> void:
	_act_timer = AppTheme.make_label(18, AppTheme.WHITE)
	_act_timer.text = "⏱ %d" % maxi(_timer_shown(), 0)
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
	var my_fury: int = int((view.get("fury", {}) as Dictionary).get(my_seat, 0))
	var ult := AppTheme.make_button("⚡ 奥义", Vector2(160, 54), 18)
	ult.disabled = my_fury < 100
	ult.tooltip_text = "怒气满 100 释放"
	ult.pressed.connect(func() -> void: _send_act("ult"))
	row.add_child(ult)


var _turn_remain := -1.0
var _timer_shown_v := -1


func _timer_shown() -> int:
	return _timer_shown_v


func _send_act(action: String) -> void:
	Audio.play("click")
	if net != null:
		net.send_fight_act(action)


## ── 事件飘字 ──
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
	var y := size.y * 0.32
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
		"thorns":
			_floater("荆棘 -%d" % v, x, y, Color("7dd87d"))
		"ult":
			_floater(tr("奥义 -%d") % v, x, y, AppTheme.GOLD)
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
	var sc: Dictionary = view.get("score", {})
	var f: Array = view.get("fighters", [])
	var body := tr("比分 %d : %d — 胜者 %s") % [int(sc.get(int(f[0]) if f.size() > 0 else 0, 0)),
			int(sc.get(int(f[1]) if f.size() > 1 else 1, 0)),
			str((view.get("names", {}) as Dictionary).get(winner, "—"))]
	if fighter:
		var win: bool = winner == my_seat
		title = "胜 利 !" if win else "败 北…"
		var r: Dictionary = Wallet.grant_pvp_result(win)
		body += "\n" + tr("奖励: %+d 金币 %+d 钻石 已入账") % [int(r["gold"]),
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


## ── 回合计时 ──
func _reset_timer() -> void:
	if str(view.get("phase", "")) == "battle":
		_turn_remain = float(view.get("turn_seconds", 20))
	else:
		_turn_remain = -1.0
	_timer_shown_v = -1


func _process(delta: float) -> void:
	if _turn_remain > 0.0:
		_turn_remain -= delta
		var cur := int(ceil(maxf(_turn_remain, 0.0)))
		if cur != _timer_shown_v:
			_timer_shown_v = cur
			if _act_timer != null and is_instance_valid(_act_timer) \
					and bool(view.get("my_turn", false)):
				_act_timer.text = "⏱ %d" % cur
				_act_timer.add_theme_color_override("font_color",
						AppTheme.RED if cur <= 5 else AppTheme.WHITE)


## ── 面板构建与布局 ──
func _build_fighter_panel(_idx: int) -> Dictionary:
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(Color(0.09, 0.07, 0.16, 0.92),
			Color(1, 1, 1, 0.18), 12, 1)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	var turn_chip := AppTheme.make_label(14, AppTheme.GOLD)
	turn_chip.text = "▶ 当前回合"
	turn_chip.visible = false
	box.add_child(turn_chip)
	var avatar: Control = AvatarScript.new()
	avatar.custom_minimum_size = Vector2(100, 100)
	avatar.size = Vector2(100, 100)
	var av_wrap := CenterContainer.new()
	av_wrap.add_child(avatar)
	box.add_child(av_wrap)
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 8)
	box.add_child(name_row)
	var nm := AppTheme.make_label(16, AppTheme.WHITE)
	name_row.add_child(nm)
	var you := AppTheme.make_label(13, Color("7dd87d"))
	you.text = "(你)"
	you.visible = false
	name_row.add_child(you)
	var score := AppTheme.make_label(14, AppTheme.GOLD)
	score.text = "回合胜 0"
	box.add_child(score)
	var prog := AppTheme.make_label(13, Color("c9b06a"))
	prog.text = "装备 0/5 · 奇物 0"
	box.add_child(prog)
	var done := AppTheme.make_label(13, Color("9fd8ff"))
	done.visible = false
	box.add_child(done)
	var combo := AppTheme.make_label(13, AppTheme.GOLD)
	combo.text = "编成中…"
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
	hp_txt.text = ""
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
	var shield_txt := _label(12, Color("6ad0e8"))
	box.add_child(shield_txt)
	return {"panel": panel, "sb": sb, "avatar": avatar, "name": nm,
			"you": you, "combo": combo, "hp_fg": hp_fg, "hp_txt": hp_txt,
			"stats": stats, "hand": hand, "turn_chip": turn_chip,
			"score": score, "prog": prog, "done": done,
			"shield_txt": shield_txt}


func _relayout() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	leave_btn.position = Vector2(w - 130.0, 26)
	phase_lbl.position = Vector2(w / 2.0 - 130.0, 36)
	score_lbl.position = Vector2(w / 2.0 - 20.0, 64)
	spec_lbl.position = Vector2(w / 2.0 - 140.0, 92)
	_vs_lbl.position = Vector2(w / 2.0 - 22.0, h * 0.36)
	log_lbl.position = Vector2(w / 2.0 - 200.0, h * 0.52)
	log_lbl.custom_minimum_size = Vector2(400.0, h * 0.18)
	var pw := minf(300.0, w * 0.27)
	var ph := h * 0.60
	for i in 2:
		var panel: PanelContainer = _side[i]["panel"]
		panel.size = Vector2(pw, ph)
		panel.position = Vector2(
				w * 0.05 if i == 0 else w - w * 0.05 - pw, h * 0.13)
	bottom_box.position = Vector2.ZERO
	bottom_box.size = Vector2(w, h)
	for c in bottom_box.get_children():
		if c is VBoxContainer:
			var vb := c as VBoxContainer
			vb.position = Vector2(0.0, h - 250.0 if vb.get_child_count() > 2
					else h - 76.0)
			vb.custom_minimum_size = Vector2(w, 240.0)
			vb.size = Vector2(w, 240.0)


func _label(size_num: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size_num)
	lb.add_theme_color_override("font_color", color)
	return lb


## 音效统一入口(页面隐藏时不发声)
func _sfx(sfx_name: String) -> void:
	if visible:
		Audio.play(sfx_name)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_do_leave()
