## 牌桌。mode="local"：本地人+3AI（本机驱动规则引擎）；mode="online"：
## 渲染来自服务器的 game_view，动作经 net 发送。
## M4 视听：程序化卡牌控件、出牌/清桌/革命/终局动画、回合计时、程序化音效。
extends Control

const AppTheme = preload("res://src/client/theme/app_theme.gd")

signal finished  # online：玩家点"返回大厅"

const CardsGd = preload("res://src/rules/cards.gd")
const GameStateGd = preload("res://src/rules/game_state.gd")
const BotPlayerGd = preload("res://src/rules/ai/bot_player.gd")
const ScoringGd = preload("res://src/rules/scoring.gd")
const ViewGd = preload("res://src/protocol/view.gd")
const CardViewScript = preload("res://src/client/ui/card_view.gd")
const TutorialScript = preload("res://src/client/scenes/tutorial.gd")
const BackdropScript = preload("res://src/client/ui/table_backdrop.gd")
const GameEndPanelScript = preload("res://src/client/ui/game_end_panel.gd")
const FxOverlayScript = preload("res://src/client/ui/fx_overlay.gd")
const SkinsLib = preload("res://src/client/ui/skins.gd")
const AvatarScript = preload("res://src/client/ui/avatar.gd")

const SEAT_NAMES := ["你", "东家", "北家", "西家"]
const EMOJIS := ["👍", "😂", "😱", "😭", "😡", "👏", "🤔", "🎉"]
const AI_THINK_SEC := 0.7
const EXCHANGE_SHOW_SEC := 1.4


var mode := "local"
var net: Node = null

var state: Dictionary = {}
var selected: Array = []
var advancing := false
var _at_game_end := false
var _emoji_cd := 0.0
var _chat_cd := 0.0
var _emoji_btns: Array = []
var _prev_tick := -1
var _leave_confirm_at := 0
var _seat_skins: Array = ["skin_default", "skin_default", "skin_default", "skin_default"]
var seat_avatars: Array = []
var avatar_me: Control

# M4 视听状态
var _last_hand: Array = []
var _prev_revolution := false
var _prev_phase := ""
var _last_round_ids: Array = []
var _end_shown := false
var _field_count := -1
var _turn_total := -1.0
var _turn_remain := -1.0
var _last_turn_seat := -99

var info_label: Label
var status_label: Label
var error_label: Label
var timer_label: Label
var chat_log: Label
var chat_edit: LineEdit
var seat_labels: Array = []
var hand_box: HFlowContainer
var field_box: HBoxContainer
var field_hint: Label
var fx_layer: Control
var btn_play: Button
var btn_hint: Button
var btn_pass: Button
var btn_next: Button
var btn_rematch: Button
var btn_leave: Button


func _ready() -> void:
	_build_ui()
	if mode == "online":
		_bind_net()
		_refresh()
	else:
		_new_match()
	Audio.play_bgm("table")


func _process(delta: float) -> void:
	if _emoji_cd > 0.0:
		_emoji_cd -= delta
	if _chat_cd > 0.0:
		_chat_cd -= delta
	# 在线模式回合倒计时
	if mode == "online" and _turn_remain > 0.0:
		_turn_remain -= delta
		if _turn_total > 0:
			var remain := maxf(_turn_remain, 0.0)
			var cur := int(ceil(remain))
			timer_label.text = "⏱ %d" % cur
			timer_label.add_theme_color_override("font_color",
					AppTheme.RED if remain <= 5.0 else AppTheme.WHITE)
			if remain <= 5.0 and cur >= 1 and cur != _prev_tick:
				_prev_tick = cur
				Audio.play("tick")


# ---------------------------------------------------------------- 驱动（本地）

func _new_match() -> void:
	state = GameStateGd.new_match({}, -1)
	selected.clear()
	_end_shown = false
	_prev_revolution = false
	_prev_phase = ""
	_last_round_ids = []
	_field_count = -1
	_last_hand = []
	# 本地: 我用已装备皮肤, AI 随机皮肤
	var ids: Array = []
	for s in SkinsLib.SKINS:
		ids.append(str(s["id"]))
	_seat_skins = [Wallet.equipped_skin, "", "", ""]
	for i in range(1, 4):
		_seat_skins[i] = ids[randi() % ids.size()]
	_end_shown = false
	_prev_revolution = false
	_prev_phase = ""
	_last_round_ids = []
	_field_count = -1
	_last_hand = []
	_advance()


## 驱动循环：AI 依次行动 / 阶段过渡，停在人需要操作处。
func _advance() -> void:
	if mode == "online":
		return
	if advancing:
		return
	advancing = true
	var guard := 0
	while true:
		guard += 1
		if guard > 2000:
			push_error("local table: 驱动循环超限")
			break
		var phase: String = state["phase"]
		if phase == "play":
			if int(state["turn"]) == 0:
				break  # 等玩家操作
			_refresh()
			await get_tree().create_timer(AI_THINK_SEC).timeout
			var action := BotPlayerGd.decide(state, int(state["turn"]))
			var r := _local_apply(action)
			if not bool(r["ok"]):
				push_error("local table: AI 非法动作 %s" % str(r["error"]))
				break
			_detect_local_eight_cut(action, r["state"])
			state = r["state"]
		elif phase == "exchange":
			_refresh()
			await get_tree().create_timer(EXCHANGE_SHOW_SEC).timeout
			var r2 := GameStateGd.apply(state, {"t": "exchange_done", "seat": int(state["turn"])})
			state = r2["state"]
		elif phase == "round_end" or phase == "game_end":
			break  # 等按钮
	_refresh()
	advancing = false


func _local_apply(action: Dictionary) -> Dictionary:
	return GameStateGd.apply(state, action)


func _human_apply(action: Dictionary) -> void:
	if advancing or state.is_empty():
		return
	if str(action["t"]) == "pass":
		Audio.play("pass")
	var r := GameStateGd.apply(state, action)
	if not bool(r["ok"]):
		_flash_error(str(r["error"]))
		return
	_detect_local_eight_cut(action, r["state"])
	state = r["state"]
	selected.clear()
	_refresh()
	_advance()


func _on_play_pressed() -> void:
	Audio.play("click")
	if mode == "online":
		if selected.is_empty():
			_flash_error("先选牌")
			return
		net.play(selected.duplicate())
		selected.clear()
		return
	if selected.is_empty():
		_flash_error("先选牌")
		return
	_human_apply({"t": "play", "seat": 0, "cards": selected.duplicate()})


## 提示: 用 AI 策略自动选中一手合理牌型, 玩家确认后打出; 压不过则自动不要。
func _on_hint_pressed() -> void:
	Audio.play("click")
	var view: Dictionary
	if mode == "online" and net != null:
		view = net.latest_view
	elif not state.is_empty():
		view = ViewGd.build(state, 0)
	if view.is_empty() or str(view["phase"]) != "play" 			or int(view["turn"]) != int(view["my_seat"]):
		return
	var action := BotPlayerGd.decide_from_view(view)
	if str(action.get("t")) == "play":
		selected = (action.get("cards", []) as Array).duplicate()
		_refresh()
	else:
		_on_pass_pressed()


func _on_pass_pressed() -> void:
	Audio.play("click")
	if mode == "online":
		net.pass_turn()
		return
	_human_apply({"t": "pass", "seat": 0})


func _on_next_pressed() -> void:
	Audio.play("click")
	_human_apply({"t": "next_round"})


func _on_rematch_pressed() -> void:
	Audio.play("click")
	_new_match()


func _on_leave_pressed() -> void:
	Audio.play("click")
	# 联机对局中离开=弃局交给 AI, 需 3 秒内二次确认; 本地模式直接返回
	if mode == "online" and not _at_game_end:
		var now := Time.get_ticks_msec()
		if now - _leave_confirm_at > 3000:
			_leave_confirm_at = now
			btn_leave.text = "确认弃局?"
			var tw := create_tween()
			tw.tween_interval(3.0)
			tw.tween_callback(func() -> void: btn_leave.text = "返回大厅")
			return
	if net != null:
		net.leave_room()
	finished.emit()


# ---------------------------------------------------------------- 网络

func _bind_net() -> void:
	net.view_changed.connect(func(view: Dictionary) -> void:
		_at_game_end = str(view["phase"]) == "game_end"
		# 回合变化 → 重置倒计时
		var new_turn := int(view["turn"])
		if new_turn != _last_turn_seat:
			_last_turn_seat = new_turn
			if str(view["phase"]) == "play" and new_turn >= 0:
				_turn_total = float(int(view["rules"]["turn_seconds"]))
				_turn_remain = _turn_total
				if new_turn == int(view["my_seat"]):
					Audio.play("turn")
		_refresh())
	net.game_event.connect(_on_game_event)
	net.errored.connect(func(code: String, _msg: String) -> void:
		_flash_error(code))
	net.server_disconnected.connect(func() -> void:
		status_label.text = "连接断开，自动重连中…"
		status_label.add_theme_color_override("font_color", AppTheme.RED))
	net.rejoined.connect(func() -> void:
		_flash_error("已重新连上，座位已恢复"))
	# 对局结束后服务器广播 room_state → 自动回到房间（再来一局流转）
	net.room_state.connect(func(_state: Dictionary) -> void:
		if _at_game_end:
			_at_game_end = false
			finished.emit())


func _on_game_event(event: String, data: Dictionary) -> void:
	if event == "emoji":
		_show_emoji(int(data.get("seat", 0)), int(data.get("id", 0)))
		Audio.play("pop")
	elif event == "chat":
		_append_chat(int(data.get("seat", 0)), str(data.get("text", "")))
	elif event == "played" and bool(data.get("eight_cut", false)):
		_spawn_fx("eight_cut")


func _append_chat(seat: int, text: String) -> void:
	var view: Dictionary = net.latest_view if mode == "online" and net != null else {}
	var lines := chat_log.text.split("\n")
	var keep := lines.slice(maxi(lines.size() - 4, 0))
	keep.append("%s: %s" % [_seat_name(view, seat), text])
	chat_log.text = "\n".join(keep)


func _on_chat_send() -> void:
	var text := chat_edit.text.strip_edges()
	if text == "":
		return
	if _chat_cd > 0.0:
		_flash_error("说太快了")
		return
	_chat_cd = 1.0
	chat_edit.clear()
	if mode == "online" and net != null:
		net.send_chat(text)
		var view: Dictionary = net.latest_view
		_append_chat(int(view.get("my_seat", 0)), text)


# ---------------------------------------------------------------- UI 构建

func _build_ui() -> void:
	theme = AppTheme.build_theme()

	# 动态和风夜景背景(弱化, 与主菜单同源)
	var bg := BackdropScript.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 头像: 三个对手 + 我(左上)
	for pos: Vector2 in [Vector2(1008, 246), Vector2(444, 20), Vector2(24, 240)]:
		var av := AvatarScript.new()
		av.position = pos
		av.custom_minimum_size = Vector2(56, 56)
		av.size = Vector2(56, 56)
		add_child(av)
		seat_avatars.append(av)
	avatar_me = AvatarScript.new()
	avatar_me.position = Vector2(16, 56)
	avatar_me.custom_minimum_size = Vector2(52, 52)
	avatar_me.size = Vector2(52, 52)
	add_child(avatar_me)

	info_label = _make_label(20, AppTheme.GOLD)
	info_label.position = Vector2(20, 12)
	add_child(info_label)

	timer_label = _make_label(22, AppTheme.WHITE)
	timer_label.position = Vector2(1180, 12)
	timer_label.visible = mode == "online"
	add_child(timer_label)

	var rules_btn := _button("规则")
	rules_btn.position = Vector2(1076, 10)
	rules_btn.custom_minimum_size = Vector2(72, 32)
	rules_btn.add_theme_font_size_override("font_size", 15)
	rules_btn.pressed.connect(func() -> void:
		Audio.play("click")
		var tut := TutorialScript.new()
		add_child(tut))
	add_child(rules_btn)

	seat_labels.append(null)  # 座位0=自己，信息在底部手牌区
	seat_labels.append(_make_seat_label(Vector2(1064, 300)))
	seat_labels.append(_make_seat_label(Vector2(500, 14)))
	seat_labels.append(_make_seat_label(Vector2(20, 300)))

	# 牌桌中央: 桌面区
	var field_panel := Panel.new()
	var field_sb := StyleBoxFlat.new()
	field_sb.bg_color = AppTheme.PANEL
	field_sb.set_corner_radius_all(12)
	field_sb.set_border_width_all(1)
	field_sb.border_color = Color(0.79, 0.66, 0.24, 0.45)
	field_panel.add_theme_stylebox_override("panel", field_sb)
	field_panel.position = Vector2(320, 216)
	field_panel.custom_minimum_size = Vector2(640, 214)
	add_child(field_panel)

	field_hint = _make_label(16, AppTheme.DIM)
	field_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	field_hint.position = Vector2(20, 6)
	field_hint.custom_minimum_size = Vector2(600, 24)
	field_panel.add_child(field_hint)

	field_box = HBoxContainer.new()
	field_box.alignment = BoxContainer.ALIGNMENT_CENTER
	field_box.position = Vector2(20, 36)
	field_box.custom_minimum_size = Vector2(600, 130)
	field_box.add_theme_constant_override("separation", 8)
	field_panel.add_child(field_box)

	status_label = _make_label(18, AppTheme.DIM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.position = Vector2(320, 496)
	status_label.custom_minimum_size = Vector2(640, 56)
	add_child(status_label)

	error_label = _make_label(16, AppTheme.RED)
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.position = Vector2(320, 470)
	error_label.custom_minimum_size = Vector2(640, 26)
	add_child(error_label)

	hand_box = HFlowContainer.new()
	hand_box.position = Vector2(16, 552)
	hand_box.custom_minimum_size = Vector2(1248, 104)
	hand_box.add_theme_constant_override("h_separation", 6)
	add_child(hand_box)

	var row := HBoxContainer.new()
	row.position = Vector2(826, 662)
	row.custom_minimum_size = Vector2(408, 44)
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	btn_play = _button("出牌")
	btn_play.pressed.connect(_on_play_pressed)
	btn_hint = _button("提示")
	btn_hint.pressed.connect(_on_hint_pressed)
	btn_pass = _button("不要")
	btn_pass.pressed.connect(_on_pass_pressed)
	btn_next = _button("下一局")
	btn_next.pressed.connect(_on_next_pressed)
	btn_rematch = _button("再来一场")
	btn_rematch.pressed.connect(_on_rematch_pressed)
	btn_leave = _button("返回大厅")
	btn_leave.pressed.connect(_on_leave_pressed)
	for b: Button in [btn_play, btn_hint, btn_pass, btn_next, btn_rematch, btn_leave]:
		row.add_child(b)

	# 快捷表情（仅联机模式）
	for i in EMOJIS.size():
		var id := i
		var eb := Button.new()
		eb.text = EMOJIS[i]
		eb.position = Vector2(16 + i * 52, 664)
		eb.custom_minimum_size = Vector2(44, 40)
		eb.add_theme_font_size_override("font_size", 20)
		eb.pressed.connect(func() -> void:
			if _emoji_cd > 0.0:
				_flash_error("表情发太快了")
				return
			_emoji_cd = 1.0
			Audio.play("pop")
			if mode == "online" and net != null:
				net.send_emoji(id))
		add_child(eb)
		_emoji_btns.append(eb)
	if mode == "local":
		for eb: Button in _emoji_btns:
			eb.visible = false

	# 文本聊天（仅联机模式）
	chat_log = _make_label(14, AppTheme.WHITE)
	chat_log.position = Vector2(16, 462)
	chat_log.custom_minimum_size = Vector2(296, 84)
	chat_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(chat_log)
	chat_edit = LineEdit.new()
	chat_edit.position = Vector2(440, 666)
	chat_edit.custom_minimum_size = Vector2(340, 36)
	chat_edit.placeholder_text = "说点什么…"
	chat_edit.max_length = 80
	chat_edit.add_theme_font_size_override("font_size", 15)
	chat_edit.text_submitted.connect(func(_t: String) -> void: _on_chat_send())
	add_child(chat_edit)
	var chat_btn := _button("发送")
	chat_btn.position = Vector2(792, 666)
	chat_btn.custom_minimum_size = Vector2(60, 36)
	chat_btn.add_theme_font_size_override("font_size", 15)
	chat_btn.pressed.connect(_on_chat_send)
	add_child(chat_btn)
	if mode == "local":
		chat_log.visible = false
		chat_edit.visible = false
		chat_btn.visible = false

	# 特效层（全屏最上层）
	fx_layer = Control.new()
	fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)


func _make_seat_label(pos: Vector2) -> Label:
	var lb := _make_label(17, AppTheme.WHITE)
	lb.position = pos
	lb.custom_minimum_size = Vector2(180, 110)
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var plate := AppTheme.flat(Color(0.07, 0.07, 0.16, 0.72), Color(AppTheme.GOLD, 0.30), 10, 1)
	plate.content_margin_left = 12
	plate.content_margin_right = 12
	plate.content_margin_top = 8
	plate.content_margin_bottom = 8
	lb.add_theme_stylebox_override("normal", plate)
	add_child(lb)
	return lb


func _make_label(size: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", color)
	return lb


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 44)
	b.add_theme_font_size_override("font_size", 19)
	return b


func _flash_error(msg: String) -> void:
	error_label.text = _error_text(msg)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(func() -> void: error_label.text = "")


func _error_text(code: String) -> String:
	match code:
		"not_your_turn":
			return "还没轮到你"
		"invalid_combo":
			return "牌型不合法"
		"cannot_beat":
			return "压不过上一手"
		"must_include_diamond3":
			return "首局首出必须包含 ♦3"
		"card_not_in_hand":
			return "没有这张牌"
		"cannot_pass_on_lead":
			return "领出时不能不要"
		_:
			return "操作无效 (%s)" % code


# ---------------------------------------------------------------- 表情

func _show_emoji(seat: int, id: int) -> void:
	var view: Dictionary = {}
	if mode == "online" and net != null:
		view = net.latest_view
	var pos := Vector2(560, 470)  # 自己的表情出现在手牌上方
	if seat != int(view.get("my_seat", 0)):
		var idx := seat
		if idx >= 1 and idx <= 3:
			var positions := [Vector2.ZERO, Vector2(1010, 300), Vector2(430, 14), Vector2(160, 300)]
			pos = positions[idx]
	var lb := Label.new()
	lb.text = EMOJIS[clampi(id, 0, EMOJIS.size() - 1)]
	lb.add_theme_font_size_override("font_size", 42)
	lb.position = pos
	fx_layer.add_child(lb)
	var tw := create_tween()
	tw.tween_property(lb, "position:y", pos.y - 50.0, 1.6)
	tw.parallel().tween_property(lb, "modulate:a", 0.0, 1.6).set_delay(0.4)
	tw.tween_callback(lb.queue_free)


# ---------------------------------------------------------------- 刷新

func _refresh() -> void:
	if mode == "online":
		if net == null or (net.latest_view as Dictionary).is_empty():
			return
		_refresh_view(net.latest_view)
	elif not state.is_empty():
		_refresh_view(ViewGd.build(state, 0))


func _refresh_view(view: Dictionary) -> void:
	var phase: String = view["phase"]

	info_label.text = "第 %d/%d 局    %s    积分 %s" % [
		int(view["round"]) + 1,
		int(view["rounds_total"]),
		"革命!" if bool(view["revolution"]) else "",
		str(view["scores"]),
	]

	for seat in range(1, 4):
		seat_avatars[seat - 1].skin_id = _skin_for(view, seat)
	for seat in range(1, 4):
		var lb: Label = seat_labels[seat]
		var turn_mark := "▶ " if int(view["turn"]) == seat else ""
		var ident := ""
		if (view["identities"] as Array).size() == 4 \
				and (view["finished"] as Array).has(seat):
			ident = "\n[%s]" % ScoringGd.IDENTITY_NAMES[int(view["identities"][seat])]
		lb.text = "%s%s\n剩 %d 张%s" % [
			turn_mark, _seat_name(view, seat), int(view["counts"][seat]), ident,
		]

	_refresh_field(view)
	_refresh_hand(view)

	# 革命检测（两种模式统一; 换局重置不播反革命）
	var rev: bool = bool(view["revolution"])
	if rev != _prev_revolution:
		_prev_revolution = rev
		if rev:
			_spawn_fx("revolution")
		elif phase == "play":
			_spawn_fx("anti_revolution")

	# 阶段切换: 交换过场 / 一落千丈(上局大富豪本轮垫底)
	if phase != _prev_phase:
		if phase == "exchange":
			_spawn_fx("exchange")
		var round_over := phase == "round_end" or phase == "game_end"
		if round_over and (view["identities"] as Array).size() == 4:
			if _last_round_ids.size() == 4:
				for s in range(4):
					if int(_last_round_ids[s]) == 0 and int(view["identities"][s]) == 3:
						_spawn_fx("fall")
						break
			_last_round_ids = (view["identities"] as Array).duplicate()
		_prev_phase = phase

	var lead: Dictionary = view["lead"]
	var my_turn: bool = phase == "play" and int(view["turn"]) == int(view["my_seat"])
	if phase != "play":
		_turn_remain = -1.0
		timer_label.text = ""
	if phase == "play":
		if my_turn:
			status_label.text = "轮到你出牌" + ("（需同牌型更大）" if not lead.is_empty() else "")
			status_label.add_theme_color_override("font_color", AppTheme.GREEN)
		else:
			status_label.text = "等待 %s 出牌…" % _seat_name(view, int(view["turn"]))
			status_label.add_theme_color_override("font_color", AppTheme.DIM)
	elif phase == "exchange":
		status_label.text = "局间交换：乞丐→大富豪 2 张，平民→富豪 1 张"
		status_label.add_theme_color_override("font_color", AppTheme.GOLD)
	elif phase == "round_end":
		status_label.text = "本局结束   " + _round_end_text(view)
		status_label.add_theme_color_override("font_color", AppTheme.GOLD)
	elif phase == "game_end":
		status_label.text = "全场结束！  " + _round_end_text(view)
		status_label.add_theme_color_override("font_color", AppTheme.GOLD)

	btn_play.visible = my_turn
	btn_hint.visible = my_turn
	btn_pass.visible = my_turn and not lead.is_empty()
	btn_next.visible = mode == "local" and phase == "round_end"
	btn_rematch.visible = mode == "local" and phase == "game_end"
	btn_leave.visible = true
	btn_leave.text = "返回大厅" if mode == "online" else "返回菜单"

	# 终局演出（一次性）
	if phase == "game_end" and not _end_shown \
			and (view["identities"] as Array).size() == 4:
		_end_shown = true
		var reward: Dictionary = {}
		if mode == "local":
			var my_rank := int(view["identities"][int(view["my_seat"])])
			reward = Wallet.grant_match_reward(my_rank + 1)
		var panel := GameEndPanelScript.new()
		panel.setup(view, _seat_name, reward)
		fx_layer.add_child(panel)


func _skin_for(view: Dictionary, seat: int) -> String:
	if mode == "online" and net != null:
		var s: String = net.skin_of_seat(seat)
		if s != "":
			return s
	return str(_seat_skins[seat]) if seat < _seat_skins.size() else "skin_default"


func _seat_name(view: Dictionary, seat: int) -> String:
	var my := int(view.get("my_seat", 0))
	if seat == my:
		return "你"
	var rel := (seat - my + 4) % 4
	var names := ["", "下家", "对家", "上家"]
	return names[rel]


func _round_end_text(view: Dictionary) -> String:
	var ids: Array = view["identities"]
	var pts: Array = view["last_points"]
	var parts: Array = []
	for s in 4:
		parts.append("%s=%s(%+d)" % [
			_seat_name(view, s), ScoringGd.IDENTITY_NAMES[int(ids[s])], int(pts[s]),
		])
	return "  ".join(parts)


## 桌面区：实体卡牌 + 出牌动画。
func _refresh_field(view: Dictionary) -> void:
	var field: Array = view["field"]
	field_hint.text = ""
	if str(view["phase"]) == "play" and (view["lead"] as Dictionary).is_empty():
		field_hint.text = "—— 自由出牌 ——"
		if int(view["must_include"]) >= 0:
			field_hint.text = "首手必须包含 ♦3"
	if field.size() == _field_count:
		return
	var grew := field.size() > _field_count
	var emptied := field.is_empty() and _field_count > 0
	_field_count = field.size()
	for child in field_box.get_children():
		child.queue_free()
	if emptied:
		Audio.play("clear")
		return
	for i in field.size():
		var entry: Dictionary = field[i]
		var holder := VBoxContainer.new()
		holder.add_theme_constant_override("separation", 2)
		var name_lb := _make_label(14, AppTheme.DIM)
		name_lb.text = _seat_name(view, int(entry["seat"]))
		name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		holder.add_child(name_lb)
		var hz := HBoxContainer.new()
		hz.add_theme_constant_override("separation", 4)
		for c in entry["combo"]["cards"]:
			hz.add_child(_make_card(int(c), 48, 66, false, false))
		holder.add_child(hz)
		field_box.add_child(holder)
		if i == field.size() - 1 and grew:
			# 最新一手: 淡入 + 弹性缩放（容器托管布局，位置不可直接动画）
			holder.pivot_offset = Vector2(120, 60)
			holder.modulate.a = 0.0
			holder.scale = Vector2(0.75, 0.75)
			var tw := holder.create_tween()
			tw.set_parallel(true)
			tw.tween_property(holder, "modulate:a", 1.0, 0.22)
			tw.tween_property(holder, "scale", Vector2.ONE, 0.22)\
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			Audio.play("play_card")


func _seat_dir(view: Dictionary, seat: int) -> Vector2:
	# 相对方位: 下家→右侧飞入, 对家→上方, 上家→左侧
	match (seat - int(view["my_seat"]) + 4) % 4:
		1:
			return Vector2(180, 0)
		2:
			return Vector2(0, -140)
		_:
			return Vector2(-180, 0)


func _make_card(card_id: int, w: float, h: float, is_selected: bool, clickable := true) -> Control:
	var cv := CardViewScript.new(card_id)
	cv.custom_minimum_size = Vector2(w, h)
	cv.size = Vector2(w, h)
	cv.selected = is_selected
	if not clickable:
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.picked.connect(_on_hand_card_picked)
	return cv


func _on_hand_card_picked(card: int) -> void:
	if selected.has(card):
		selected.erase(card)
	else:
		selected.append(card)
	Audio.play("click")
	# 更新所有手牌卡的选中态
	for child in hand_box.get_children():
		if "selected" in child:
			child.selected = selected.has(child.card)


## 手牌：卡牌控件化；仅在手牌实际变化时重建并播放发牌动画。
func _refresh_hand(view: Dictionary) -> void:
	var hand: Array = view["hand"]
	if hand == _last_hand:
		# 只同步选中态
		var idx := 0
		for child in hand_box.get_children():
			if idx < hand.size():
				child.selected = selected.has(int(hand[idx]))
			idx += 1
		return
	_last_hand = hand.duplicate()
	for child in hand_box.get_children():
		child.queue_free()
	var i := 0
	for c in hand:
		var card_id: int = c
		var cv := _make_card(card_id, 72, 100, selected.has(card_id))
		hand_box.add_child(cv)
		cv.modulate.a = 0.0
		var tw := cv.create_tween()  # 绑定卡牌节点: 重建释放时自动终止
		tw.tween_interval(0.02 * i)
		tw.tween_property(cv, "modulate:a", 1.0, 0.12)
		i += 1
	if i > 0:
		Audio.play("deal")


# ---------------------------------------------------------------- 特效


func _spawn_fx(fx_type: String) -> void:
	var sounds := {
		"revolution": "revolution", "anti_revolution": "revolution",
		"eight_cut": "eight_cut", "fall": "fall", "exchange": "exchange",
	}
	Audio.play(str(sounds.get(fx_type, "pop")))
	if fx_layer != null:
		fx_layer.add_child(FxOverlayScript.create(fx_type))


## 本地对局: 出牌动作后检测 8 切(含8的牌清空了桌面)
func _detect_local_eight_cut(action: Dictionary, st_after: Dictionary) -> void:
	if str(action.get("t", "")) != "play":
		return
	var field_empty: bool = (st_after["field"] as Array).is_empty()
	var lead_empty: bool = (st_after["lead"] as Dictionary).is_empty()
	if not (field_empty and lead_empty):
		return
	for c in action.get("cards", []):
		if CardsGd.value(int(c)) == 8:
			_spawn_fx("eight_cut")
			return
