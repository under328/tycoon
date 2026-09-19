## 联机格斗对战竞技场 v3: 左侧 = 本地样式完整格斗面板(精修像素头像 +
## 变身光环 / 生命·怒气条 / 装备槽 5 + 奇物槽 2 / 牌型·属性 / 编成进度),
## 右侧 = 对手面板 RTL 镜像对称。底部 = 二选一抽牌(2 张候选 + 奇物第三
## 选项)或对战行动行。渲染服务器下发的 s_fight_state, 本页不驱动任何规则。
## 观战者全程可见但无操作按钮。
extends Control

signal finished  # 离开竞技场 → 返回大厅

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const FightModeGd = preload("res://src/rules/fight/fight_mode.gd")
const CardsGd = preload("res://src/rules/cards.gd")
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
var _conn_lbl: Label
var leave_btn: Button
var log_lbl: Label
var bottom_box: Control        # 底部操作区(每次状态变化重建)
var floaters: Control
var _side: Array = []          # 面板(0=左/我方视角, 1=右/对手镜像)
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
	header.text = "格斗试炼 · 双人对战"
	header.icon = "card"
	header.position = Vector2(36, 22)
	header.custom_minimum_size = Vector2(400, 54)
	header.size = Vector2(400, 54)
	add_child(header)

	phase_lbl = AppTheme.make_label(18, AppTheme.GOLD)
	phase_lbl.text = "等待服务器…"
	add_child(phase_lbl)
	score_lbl = AppTheme.make_label(20, AppTheme.WHITE)
	add_child(score_lbl)

	spec_lbl = AppTheme.make_label(15, Color("9fd8ff"))
	spec_lbl.visible = false
	add_child(spec_lbl)

	# 连接状态提示: 竞技场盖住大厅, 断线/重连必须在本页可见
	_conn_lbl = AppTheme.make_label(16, AppTheme.RED)
	_conn_lbl.visible = false
	add_child(_conn_lbl)
	if net != null:
		net.server_disconnected.connect(func() -> void:
			_conn_lbl.visible = true
			_conn_lbl.text = "⚠ 连接中断 — 自动重连中…")
		net.connected_ok.connect(func() -> void:
			if _conn_lbl.visible:
				_conn_lbl.visible = false
				_floater(tr("已重新连接"), size.x * 0.5, size.y * 0.18,
						Color("7dd87d")))

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
	Audio.play_bgm("fight")


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
	# 阶段切换语音: 编成 / 对决 / 得分失分 / 终局
	if phase != prev_phase:
		match phase:
			"draft":
				Audio.say("f_draft")
			"battle":
				Audio.say("f_vs", 1.0, true)
			"round_end":
				Audio.say("f_round_win" if int(v.get("round_winner", -1)) \
						== int(v.get("my_seat", -1)) else "f_round_lose", 1.0, true)
			"over":
				if fighter:
					Audio.say("victory" if int(v.get("winner", -1)) \
							== int(v.get("my_seat", -1)) else "defeat", 1.0, true)
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
		var won: bool = rw == _seat_at(0) and not bool(v.get("spectator", true))
		_floater(tr("回合胜利!") if won else tr("回合落败"),
				size.x * 0.5, size.y * 0.30,
				Color("7dd87d") if won else Color("ff8866"))
	if phase == "over" and not _rewarded:
		_rewarded = true
		_show_result()


## 座位 → 展示位: 我方(格斗者)永远在左 0 号位; 观战者按 1/2 号位左右排
func _seat_at(idx: int) -> int:
	var fighters: Array = view.get("fighters", [])
	if fighters.is_empty():
		return -1
	if bool(view.get("spectator", true)):
		return int(fighters[idx]) if idx < fighters.size() else -1
	var my_seat := int(view.get("my_seat", -1))
	if idx == 0:
		return my_seat
	return int(fighters[0]) if int(fighters[1]) == my_seat else int(fighters[1])


func _side_of_seat(seat: int) -> int:
	return 0 if int(seat) == _seat_at(0) else 1


func _refresh_sides() -> void:
	var phase := str(view.get("phase", ""))
	var per_all: Dictionary = view.get("per", {})
	var sc: Dictionary = view.get("score", {})
	for i in 2:
		var seat := _seat_at(i)
		if seat < 0:
			continue
		var p: Dictionary = _side[i]
		var mine: bool = seat == int(view.get("my_seat", -1)) \
				and not bool(view.get("spectator", true))
		(p["name"] as Label).text = str((view.get("names", {}) as Dictionary)
				.get(seat, "玩家"))
		(p["you"] as Label).visible = mine
		if net != null:
			(p["avatar"] as Control).skin_id = net.skin_of_seat(seat)
		(p["score"] as Label).text = tr("回合胜 %d") % int(sc.get(seat, 0))
		var per: Dictionary = (per_all as Dictionary).get(seat, {})
		(p["prog"] as Label).text = tr("装备 %d/5 · 奇物 %d/2") % [
				int(per.get("slots_count", 0)), int(per.get("specials_count", 0))]
		var done_lb: Label = p["done"]
		done_lb.visible = phase == "draft"
		done_lb.text = tr("已编成 ✓") if bool(per.get("done", false)) \
				else tr("选牌中…")
		# 当前回合高亮
		var is_turn: bool = int(view.get("turn", -1)) == seat \
				and phase == "battle"
		(p["turn_chip"] as Label).visible = is_turn
		var sb: StyleBoxFlat = p["sb"]
		sb.border_color = AppTheme.GOLD if is_turn else Color(1, 1, 1, 0.18)
		sb.set_border_width_all(3 if is_turn else 1)
		_refresh_slots(i, seat, mine)
		_refresh_relics(i, seat, per)
		_refresh_bars(i, seat)
		# 变身光环: 集满 5 张且处于编成/对战阶段(过场与终局自动消失)
		var on: bool = bool(per.get("transformed", false))
		var aura: Control = p["aura"]
		aura.visible = on
		if on:
			aura.queue_redraw()


## 装备槽行: 我方显示真实卡面(可点替换); 对手开战后披露, 编成中只给暗格
func _refresh_slots(idx: int, seat: int, mine: bool) -> void:
	var p: Dictionary = _side[idx]
	# 我方优先用自己的编成; 双方开战后都由 hands 披露
	var revealed: Array = []
	if mine:
		revealed = (((view.get("my", {}) as Dictionary)
				.get("slots", [])) as Array).duplicate()
	var hands: Dictionary = view.get("hands", {})
	if (hands as Dictionary).has(seat):
		revealed = (hands[seat] as Array).duplicate()
	var per: Dictionary = (view.get("per", {}) as Dictionary).get(seat, {})
	var count: int = (revealed as Array).size() \
			if not (revealed as Array).is_empty() \
			else int(per.get("slots_count", 0))
	var replace_mode: bool = mine and _pending_cand >= 0
	for s in 5:
		var ui: Dictionary = p["slots_ui"][s]
		var wrap: PanelContainer = ui["wrap"]
		var sb: StyleBoxFlat = ui["sb"]
		for c in (ui["card_box"] as Control).get_children():
			c.queue_free()
		var has_card: bool = s < (revealed as Array).size()
		var ghost: bool = not has_card and s < count
		if has_card:
			var cv: Control = CardViewScript.new(int(revealed[s]))
			cv.custom_minimum_size = Vector2(40, 56)
			cv.size = Vector2(40, 56)
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			(ui["card_box"] as Control).add_child(cv)
		elif ghost:
			var ph := _label(15, Color(1, 1, 1, 0.35))
			ph.text = "▣"
			(ui["card_box"] as Control).add_child(ph)
		if replace_mode and mine:
			sb.border_color = AppTheme.GOLD if s < count else Color(1, 1, 1, 0.25)
			sb.set_border_width_all(3 if s < count else 1)
			wrap.tooltip_text = "点击替换此槽位"
		else:
			sb.border_color = AppTheme.GOLD if has_card else Color(1, 1, 1, 0.25)
			sb.set_border_width_all(2 if has_card else 1)
			wrap.tooltip_text = ""


## 奇物槽行(2 格, 紫色): 我方实时, 对手开战后披露
func _refresh_relics(idx: int, seat: int, per: Dictionary) -> void:
	var p: Dictionary = _side[idx]
	var relics: Array = (per.get("relics", []) as Array).duplicate()
	var total: int = maxi((relics as Array).size(),
			int(per.get("specials_count", 0)))
	for r in 2:
		var ui: Dictionary = p["relic_ui"][r]
		var gl: Label = ui["glyph"]
		var sb: StyleBoxFlat = ui["sb"]
		var filled: bool = r < (relics as Array).size()
		if filled:
			gl.text = str(FightModeGd.sp_meta(int(relics[r]))["icon"])
		else:
			gl.text = "◇"
		sb.border_color = Color("b070e0") if filled else Color("b070e0", 0.45)
		sb.set_border_width_all(2 if filled else 1)


func _refresh_bars(idx: int, seat: int) -> void:
	var p: Dictionary = _side[idx]
	var hp: int = int((view.get("hp", {}) as Dictionary).get(seat, 0))
	var mh: int = maxi(int((view.get("max_hp", {}) as Dictionary).get(seat, 0)), 0)
	var has_battle: bool = (view.get("hp", {}) as Dictionary).has(seat)
	if not has_battle:
		(p["hp_fg"] as ColorRect).size = Vector2(0, 16)
		(p["fury_fg"] as ColorRect).size = Vector2(0, 8)
		(p["hp_txt"] as Label).text = ""
		(p["fury_txt"] as Label).text = ""
		(p["shield_txt"] as Label).text = ""
		(p["stats"] as Label).text = ""
		(p["combo"] as Label).text = tr("编成中 — 集卡触发牌型协同")
		return
	var frac := float(clampi(hp, 0, mh)) / float(maxf(float(mh), 1.0))
	var bg_w: float = (p["hp_bg"] as ColorRect).custom_minimum_size.x
	var fg: ColorRect = p["hp_fg"]
	var fsize := Vector2(maxf(bg_w * frac - 4.0, 2.0), 16)
	fg.size = fsize
	if idx == 1:   # 右侧镜像: 血条从右往左消
		fg.position = Vector2(bg_w - fsize.x - 2.0, 2.0)
	else:
		fg.position = Vector2(2, 2)
	fg.color = Color("58c858") if frac > 0.5 \
			else (Color("ffb14e") if frac > 0.25 else Color("d05050"))
	(p["hp_txt"] as Label).text = "HP %d / %d" % [maxi(hp, 0), mh]
	var fury: int = int((view.get("fury", {}) as Dictionary).get(seat, 0))
	var ffg: ColorRect = p["fury_fg"]
	var fw := maxf(bg_w * clampf(float(fury) / 100.0, 0.0, 1.0) - 4.0, 0.0)
	ffg.size = Vector2(fw, 8)
	if idx == 1:
		ffg.position = Vector2(bg_w - fw - 2.0, 2.0)
	else:
		ffg.position = Vector2(2, 2)
	(p["fury_txt"] as Label).text = tr("怒气 %d") % fury
	var sh: int = int((view.get("shield", {}) as Dictionary).get(seat, 0))
	(p["shield_txt"] as Label).text = "🔮%d" % sh if sh > 0 else ""
	var combos: Dictionary = view.get("combo", {})
	if (combos as Dictionary).has(seat):
		var c: Dictionary = combos[seat]
		(p["combo"] as Label).text = "牌型 %s · %s" % [c["name"], c["desc"]]
		var br: Dictionary = (view.get("stats_brief", {}) as Dictionary)[seat]
		var kinds := {"fire": "🔥火球", "frost": "❄冰霜", "light": "✟圣光"}
		(p["stats"] as Label).text = "⚔%d  🛡%d  ✟%d  %s%s" % [
			int(br["atk"]), int(br["def"]), int(br["skill"]),
			str(kinds.get(str((view.get("skill_kind", {}) as Dictionary)
					.get(seat, "fire")), "")),
			("  ⏱冷却%d" % int((view.get("skill_cd", {}) as Dictionary)
					.get(seat, 0))) if int((view.get("skill_cd", {})
					as Dictionary).get(seat, 0)) > 0 else ""]


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
	var fighter: bool = not bool(view.get("spectator", true))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	bottom_box.add_child(box)
	# 重建后立即定位(否则新子节点默认落 (0,0) 盖住侧面板); 构建完再算行数
	_layout_bottom.call_deferred(box)
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


## 底部操作区定位: 内容多(标题+卡行+跳过)时抬高, 单行状态贴底
func _layout_bottom(box: VBoxContainer) -> void:
	if not is_instance_valid(box) or not box.is_inside_tree():
		return
	box.position = Vector2(0.0, size.y - 254.0 if box.get_child_count() > 2
			else size.y - 84.0)
	box.custom_minimum_size = Vector2(size.x, 244.0)
	box.size = Vector2(size.x, 244.0)


## ── 抽牌: 2 张候选 + 奇物第三选项 ──
func _build_draft_ui(box: VBoxContainer) -> void:
	var my: Dictionary = view.get("my", {})
	var slots: Array = my.get("slots", [])
	if _pending_cand >= 0:
		var hint := AppTheme.make_label(15, AppTheme.GOLD)
		hint.text = tr("装备槽已满 — 点击左侧要替换的槽位，或跳过")
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.custom_minimum_size = Vector2(size.x, 0)
		box.add_child(hint)
	var pair: Array = my.get("pair", [])
	if (pair as Array).is_empty():
		return
	if _pending_cand < 0:
		var title := AppTheme.make_label(15, AppTheme.GOLD)
		title.text = tr("二选一 — 点选 1 张 (装备 %d/5%s)") % [
				(slots as Array).size(),
				tr("，本回合有额外候选组!") if int(my.get("pairs_left", 1)) > 1
						else ""]
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.custom_minimum_size = Vector2(size.x, 0)
		box.add_child(title)
	var cards_row := HBoxContainer.new()
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.add_theme_constant_override("separation", 26)
	box.add_child(cards_row)
	for cand in pair:
		cards_row.add_child(_build_normal_card(int(cand), my))
	# 附带奇物(金色第三选项): 拾取只入奇物槽, 不消耗卡牌选择
	var bonus: int = int(my.get("bonus_relic", -1))
	if bonus >= 0:
		cards_row.add_child(_build_relic_card(bonus))
	if _pending_cand >= 0:
		var skip_wrap := CenterContainer.new()
		var skip := AppTheme.make_button("跳过这组", Vector2(150, 40), 14)
		skip.pressed.connect(func() -> void:
			Audio.play("click")
			_pending_cand = -1
			if net != null:
				net.send_fight_pick(-1)
			_rebuild_bottom())
		skip_wrap.add_child(skip)
		box.add_child(skip_wrap)


## 附带奇物选项卡: 拾取装入奇物槽(上限 2), 不影响装备牌
func _build_relic_card(sp_cand: int) -> Control:
	var meta: Dictionary = FightModeGd.sp_meta(FightModeGd.sp_of(sp_cand))
	var wrap := PanelContainer.new()
	var sb := AppTheme.flat(Color(0.16, 0.09, 0.24), Color("e0a83c"), 10, 2)
	wrap.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(box)
	var cc := CenterContainer.new()
	var glyph := _label(34, Color("ffd166"))
	glyph.text = str(meta.get("icon", "?"))
	cc.add_child(glyph)
	box.add_child(cc)
	var nm := _label(14, Color("ffe6a0"))
	nm.text = tr("奇物·%s") % str(meta.get("name", ""))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(nm)
	var tip := _label(11, AppTheme.DIM)
	tip.text = tr("拾取后装入奇物槽(不影响装备牌)")
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(116, 0)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tip)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_candidate(sp_cand))
	wrap.set_meta("sp_cand", sp_cand)
	return wrap


func _build_normal_card(cand: int, my: Dictionary) -> Control:
	# 稀有普通牌(200+): 显示剥离后的卡面, 点击回传完整候选值
	var rare := cand >= 200
	var card := cand - 200 if rare else cand
	var wrap := PanelContainer.new()
	var sb := AppTheme.flat(Color(0.10, 0.10, 0.22),
			Color("ffd166") if rare else Color(1, 1, 1, 0.2), 10,
			2 if rare else 1)
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
	var preview: Array = (slots as Array).duplicate()
	if (preview as Array).size() < 5:
		preview.append(card)
	else:
		preview[0] = card   # 槽满默认预览替换 0 号位
	var combo: Dictionary = FightModeGd.evaluate_combo(preview)
	var hint := _label(11, Color("c9b06a"))
	var rare_txt := (tr("稀有! 怒气+20 ") + "\n") if rare else ""
	hint.text = "%s%s: %s\n%s" % [rare_txt, CardsGd.SUIT_NAMES[CardsGd.suit(card)],
			_card_effect_text(card),
			(tr("替换后 %s") if (slots as Array).size() >= 5
					else tr("装备后 %s")) % tr(str(combo["name"]))]
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_candidate(cand))
	return wrap


func _on_candidate(cand: int) -> void:
	if Time.get_ticks_msec() < _pick_lock_ms:
		return
	var my: Dictionary = view.get("my", {})
	var slots: Array = my.get("slots", [])
	# 奇物第三选项: 直接拾取(服务器决定入槽); 图鉴收集
	if cand >= 100 and cand < 200:
		Audio.play("click")
		_pick_lock_ms = Time.get_ticks_msec() + 400
		Wallet.note_relic(FightModeGd.sp_of(cand))
		if net != null:
			net.send_fight_pick(cand)
		_rebuild_bottom()
		return
	if (slots as Array).size() >= 5:
		_pending_cand = cand
		_rebuild_bottom()
		return
	Audio.play("click")
	_pick_lock_ms = Time.get_ticks_msec() + 400
	if net != null:
		net.send_fight_pick(cand)
	_rebuild_bottom()


var _pick_lock_ms := 0   # 选牌防抖: 触屏连点/重渲染后的同位余点不生效


func _on_slot_clicked(idx: int) -> void:
	if _pending_cand < 0:
		return
	Audio.play("click")
	var cand := _pending_cand
	_pending_cand = -1
	_pick_lock_ms = Time.get_ticks_msec() + 400
	if cand >= 200:
		Audio.say("f_rare")
	if net != null:
		net.send_fight_pick(cand, idx)
	_rebuild_bottom()


## 单卡小加成文案(抽牌预览) — 与本地格斗试炼同源
func _card_effect_text(card: int) -> String:
	var pw := maxi(CardsGd.value(card) - 2, 0)
	match CardsGd.suit(card):
		0:
			return "物攻+4 · 暴击率+5%% · 点数+%d" % pw
		1:
			return "生命+5+3×点数(+%d) " % (pw * 3)
		2:
			return "护甲/魔抗+3 · 点数+%d" % pw
		3:
			return "技能+4 · 点数+%d" % pw
	return ""


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
	# 己方动作即时播报(欢乐斗地主式); 服务器回执事件照常驱动飘字
	match action:
		"attack":
			Audio.say("f_attack")
		"skill":
			Audio.say("f_skill")
		"defend":
			Audio.say("f_defend")
		"ult":
			Audio.say("f_ult", 1.0, true)
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
	var y := size.y * 0.30
	var kind := str(ev.get("kind", ""))
	var v := int(ev.get("v", 0))
	match kind:
		"crit":
			Audio.say("f_crit")
			_floater(tr("暴击 -%d") % v, x, y, Color("ffd166"))
			_sfx("play_card")
		"dmg":
			_floater("-%d" % v, x, y, Color("ff8866"))
			_sfx("play_card")
		"skill":
			_floater(tr("技能 -%d") % v, x, y, Color("7ec8ff"))
			_sfx("exchange")
		"heal":
			_floater("+%d" % v, x, y, Color("7dd87d"))
		"defend":
			_floater(tr("防御"), x, y, Color("7ec8ff"))
		"chill":
			_floater("❄ " + tr("被冻结"), x, y, Color("9fd8ff"))
		"thorns":
			_floater(tr("荆棘 -%d") % v, x, y, Color("7dd87d"))
		"ult":
			_floater(tr("奥义 -%d") % v, x, y, AppTheme.GOLD)
	var tw := create_tween()
	tw.tween_interval(0.45)
	tw.tween_callback(_play_next)


func _side_x(seat: int) -> float:
	return size.x * (0.25 if _side_of_seat(seat) == 0 else 0.75)


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
		if win:
			body += "\n" + tr("奖励: %+d 金币 %+d 钻石 已入账") % [int(r["gold"]),
					int(r["diamonds"])]
		else:
			body += "\n" + tr("失败惩罚: %d 金币 · 未获得钻石") % int(r["gold"])
		Audio.play("win" if win else "fall")
	_show_overlay(title, body, _am_host())


func _am_host() -> bool:
	# 房主可见「再来一局」快捷重开(同规则直接开新对局)
	return net != null \
			and int(net.last_room_state.get("host_seat", -1)) == int(net.my_seat)


func _show_overlay(title: String, body: String, restart := false) -> void:
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
	if restart:
		var again := AppTheme.make_button("🔁 再来一局", Vector2(160, 46), 16)
		again.pressed.connect(func() -> void:
			Audio.play("click")
			_close_overlay()   # 新对局视图到达后自动进入下一局编成
			if net != null:
				net.start_game())
		row.add_child(again)
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
	# 光环旋转
	for i in 2:
		var p: Dictionary = _side[i]
		var aura: Control = p.get("aura", null)
		if aura != null and aura.visible:
			p["aura_spin"] = float(p["aura_spin"]) + delta * 1.5
			aura.queue_redraw()
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
func _build_fighter_panel(idx: int) -> Dictionary:
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(Color(0.09, 0.07, 0.16, 0.92),
			Color(1, 1, 1, 0.18), 12, 1)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	# ── 头像 + 变身光环 ──
	var av_holder := Control.new()
	av_holder.custom_minimum_size = Vector2(112, 112)
	var aura := Control.new()
	aura.size = Vector2(112, 112)
	aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aura.visible = false
	aura.set_meta("side", idx)
	aura.draw.connect(_draw_aura.bind(aura))
	av_holder.add_child(aura)
	var avatar: Control = AvatarScript.new()
	avatar.custom_minimum_size = Vector2(112, 112)
	avatar.size = Vector2(112, 112)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av_holder.add_child(avatar)
	var av_wrap := CenterContainer.new()
	av_wrap.add_child(av_holder)
	box.add_child(av_wrap)
	# ── 名字行 ──
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 8)
	box.add_child(name_row)
	var turn_chip := AppTheme.make_label(14, AppTheme.GOLD)
	turn_chip.text = "▶"
	turn_chip.visible = false
	name_row.add_child(turn_chip)
	var nm := AppTheme.make_label(16, AppTheme.WHITE)
	nm.text = "玩家"
	name_row.add_child(nm)
	var you := AppTheme.make_label(13, Color("7dd87d"))
	you.text = tr("(你)")
	you.visible = false
	name_row.add_child(you)
	var score := AppTheme.make_label(14, AppTheme.GOLD)
	score.text = tr("回合胜 0")
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(score)
	var done := AppTheme.make_label(13, Color("9fd8ff"))
	done.visible = false
	done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(done)
	var prog := AppTheme.make_label(13, Color("c9b06a"))
	prog.text = tr("装备 0/5 · 奇物 0/2")
	prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(prog)
	# ── 生命条 ──
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.6)
	hp_bg.custom_minimum_size = Vector2(292, 20)
	var hp_fg := ColorRect.new()
	hp_fg.color = Color("58c858")
	hp_fg.position = Vector2(2, 2)
	hp_fg.size = Vector2(288, 16)
	hp_bg.add_child(hp_fg)
	var hp_center := CenterContainer.new()
	hp_center.add_child(hp_bg)
	box.add_child(hp_center)
	var hp_txt := _label(12, AppTheme.WHITE)
	hp_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hp_txt)
	# ── 怒气条 ──
	var fury_bg := ColorRect.new()
	fury_bg.color = Color(0, 0, 0, 0.6)
	fury_bg.custom_minimum_size = Vector2(292, 12)
	var fury_fg := ColorRect.new()
	fury_fg.color = AppTheme.GOLD
	fury_fg.position = Vector2(2, 2)
	fury_fg.size = Vector2(0, 8)
	fury_bg.add_child(fury_fg)
	var fury_center := CenterContainer.new()
	fury_center.add_child(fury_bg)
	box.add_child(fury_center)
	var fury_txt := _label(11, Color("ffd166"))
	fury_txt.text = tr("怒气 0")
	fury_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(fury_txt)
	# ── 牌型/属性 ──
	var combo := AppTheme.make_label(13, AppTheme.GOLD)
	combo.text = tr("编成中 — 集卡触发牌型协同")
	combo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	combo.custom_minimum_size = Vector2(300, 34)
	combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(combo)
	var stats := AppTheme.make_label(13, Color("c9b06a"))
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.custom_minimum_size = Vector2(300, 20)
	box.add_child(stats)
	# ── 装备槽 5 + 奇物槽 2 ──
	var slots_row := HBoxContainer.new()
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_row.add_theme_constant_override("separation", 4)
	box.add_child(slots_row)
	var slots_ui: Array = []
	for s in 5:
		var wrap := PanelContainer.new()
		var ssb := AppTheme.flat(Color(0.06, 0.06, 0.14),
				Color(1, 1, 1, 0.25), 6, 1)
		ssb.content_margin_left = 3
		ssb.content_margin_right = 3
		ssb.content_margin_top = 3
		ssb.content_margin_bottom = 3
		wrap.add_theme_stylebox_override("panel", ssb)
		wrap.custom_minimum_size = Vector2(46, 62)
		wrap.mouse_filter = Control.MOUSE_FILTER_STOP
		var card_box := CenterContainer.new()
		wrap.add_child(card_box)
		slots_row.add_child(wrap)
		var slot_idx := s
		wrap.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_LEFT:
				_on_slot_clicked(slot_idx))
		slots_ui.append({"wrap": wrap, "sb": ssb, "card_box": card_box})
	var relic_gap := Control.new()
	relic_gap.custom_minimum_size = Vector2(8, 0)
	slots_row.add_child(relic_gap)
	var relic_ui: Array = []
	for r in 2:
		var rwrap := PanelContainer.new()
		var rsb := AppTheme.flat(Color(0.16, 0.09, 0.24),
				Color("b070e0", 0.45), 6, 1)
		rwrap.add_theme_stylebox_override("panel", rsb)
		rwrap.custom_minimum_size = Vector2(46, 62)
		rwrap.tooltip_text = "奇物槽 — 拾取奇物自动装入(最多 2 个)"
		var rcc := CenterContainer.new()
		var rglyph := AppTheme.make_label(22, Color("c89ae8"))
		rglyph.text = "◇"
		rcc.add_child(rglyph)
		rwrap.add_child(rcc)
		slots_row.add_child(rwrap)
		relic_ui.append({"wrap": rwrap, "sb": rsb, "glyph": rglyph})
	# ── 护盾/状态 ──
	var shield_txt := _label(12, Color("6ad0e8"))
	shield_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(shield_txt)
	if idx == 1:
		box.layout_direction = Control.LAYOUT_DIRECTION_RTL   # 右侧镜像对称
	return {"panel": panel, "sb": sb, "avatar": avatar, "aura": aura,
			"aura_spin": 0.0, "name": nm, "you": you, "combo": combo,
			"hp_fg": hp_fg, "hp_bg": hp_bg, "hp_txt": hp_txt,
			"fury_fg": fury_fg, "fury_txt": fury_txt,
			"stats": stats, "turn_chip": turn_chip, "score": score,
			"prog": prog, "done": done, "shield_txt": shield_txt,
			"slots_ui": slots_ui, "relic_ui": relic_ui}


## 变身光环(主花色变色): 旋转外环 + 辉光内环 + 8 向射线
func _draw_aura(aura: Control) -> void:
	if not aura.visible:
		return
	var idx: int = int(aura.get_meta("side", 0))
	var seat := _seat_at(idx)
	var col := _suit_color(seat)
	var c := aura.size / 2.0
	var spin: float = float(_side[idx].get("aura_spin", 0.0))
	aura.draw_arc(c, 50.0, 0, TAU, 40, Color(col, 0.8), 3.0, true)
	aura.draw_arc(c, 43.0, 0, TAU, 40, Color(col, 0.35), 7.0, true)
	for i in 8:
		var a := TAU * i / 8.0 + spin
		aura.draw_line(c + Vector2.from_angle(a) * 55.0,
				c + Vector2.from_angle(a) * 63.0, Color(col, 0.85), 2.5, true)


func _suit_color(seat: int) -> Color:
	var suits: Dictionary = view.get("suit", {})
	if (suits as Dictionary).has(seat):
		var su: int = int(suits[seat])
		return [Color("ff7050"), Color("7dd87d"), Color("ffd166"),
				Color("7ec8ff")][su]
	# 编成阶段对手未披露: 我方按自己装备算, 对手用金色
	if seat == _seat_at(0) and not bool(view.get("spectator", true)):
		var slots: Array = (view.get("my", {}) as Dictionary).get("slots", [])
		if (slots as Array).size() >= 5:
			var cnt := [0, 0, 0, 0]
			var best := 0
			for c in slots:
				var su := CardsGd.suit(int(c))
				cnt[su] += 1
				if cnt[su] > cnt[best]:
					best = su
			return [Color("ff7050"), Color("7dd87d"), Color("ffd166"),
					Color("7ec8ff")][best]
	return AppTheme.GOLD


func _relayout() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	leave_btn.position = Vector2(w - 130.0, 26)
	phase_lbl.position = Vector2(w / 2.0 - 150.0, 36)
	score_lbl.position = Vector2(w / 2.0 - 20.0, 66)
	spec_lbl.position = Vector2(w / 2.0 - 140.0, 94)
	_conn_lbl.position = Vector2(w / 2.0 - 150.0, 120)
	_vs_lbl.position = Vector2(w / 2.0 - 22.0, h * 0.30)
	log_lbl.position = Vector2(w / 2.0 - 200.0, h * 0.56)
	log_lbl.custom_minimum_size = Vector2(400.0, h * 0.16)
	var pw := minf(340.0, w * 0.30)
	var ph := h * 0.72
	for i in 2:
		var panel: PanelContainer = _side[i]["panel"]
		panel.size = Vector2(pw, ph)
		panel.position = Vector2(
				w * 0.03 if i == 0 else w - w * 0.03 - pw, h * 0.12)
	bottom_box.position = Vector2.ZERO
	bottom_box.size = Vector2(w, h)
	for c in bottom_box.get_children():
		if c is VBoxContainer:
			var vb := c as VBoxContainer
			vb.position = Vector2(0.0, h - 254.0 if vb.get_child_count() > 2
					else h - 84.0)
			vb.custom_minimum_size = Vector2(w, 244.0)
			vb.size = Vector2(w, 244.0)


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
