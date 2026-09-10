## 本地调试牌桌：你（座位 0）+ 3 AI。占位美术，M4 换正式皮肤。
## 复用与联机服务器完全相同的规则引擎（src/rules/）。
extends Control

const CardsGd = preload("res://src/rules/cards.gd")
const GameStateGd = preload("res://src/rules/game_state.gd")
const BotPlayerGd = preload("res://src/rules/ai/bot_player.gd")
const ScoringGd = preload("res://src/rules/scoring.gd")
const ViewGd = preload("res://src/protocol/view.gd")

const SEAT_NAMES := ["你", "东家", "北家", "西家"]
const AI_THINK_SEC := 0.7
const EXCHANGE_SHOW_SEC := 1.4

const COLOR_BG := Color("14142b")
const COLOR_GOLD := Color("e0a83c")
const COLOR_RED := Color("ff6b6b")
const COLOR_WHITE := Color("f0f0f0")
const COLOR_GREEN := Color("7dd87d")
const COLOR_DIM := Color("8a8ab0")

var state: Dictionary = {}
var selected: Array = []
var advancing := false

var info_label: Label
var field_label: Label
var status_label: Label
var error_label: Label
var seat_labels: Array = []
var hand_box: HFlowContainer
var btn_play: Button
var btn_pass: Button
var btn_next: Button
var btn_rematch: Button


func _ready() -> void:
	_build_ui()
	_new_match()


# ---------------------------------------------------------------- 驱动

func _new_match() -> void:
	state = GameStateGd.new_match({}, -1)
	selected.clear()
	_advance()


## 驱动循环：AI 依次行动 / 阶段过渡，停在人需要操作处。
func _advance() -> void:
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
			var r := GameStateGd.apply(state, action)
			if not bool(r["ok"]):
				push_error("local table: AI 非法动作 %s" % str(r["error"]))
				break
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


func _human_apply(action: Dictionary) -> void:
	if advancing or state.is_empty():
		return
	var r := GameStateGd.apply(state, action)
	if not bool(r["ok"]):
		_flash_error(str(r["error"]))
		return
	state = r["state"]
	selected.clear()
	_refresh()
	_advance()


func _on_play_pressed() -> void:
	if selected.is_empty():
		_flash_error("先选牌")
		return
	_human_apply({"t": "play", "seat": 0, "cards": selected.duplicate()})


func _on_pass_pressed() -> void:
	_human_apply({"t": "pass", "seat": 0})


func _on_next_pressed() -> void:
	_human_apply({"t": "next_round"})


func _on_rematch_pressed() -> void:
	_new_match()


# ---------------------------------------------------------------- UI 构建

func _build_ui() -> void:
	var theme_res := Theme.new()
	var sys_font := SystemFont.new()
	sys_font.font_names = PackedStringArray([
		"Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC", "SimHei", "Arial",
	])
	theme_res.default_font = sys_font
	theme_res.default_font_size = 18
	theme = theme_res

	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	info_label = _make_label(20, COLOR_GOLD)
	info_label.position = Vector2(20, 12)
	add_child(info_label)

	seat_labels.append(null)  # 座位0=自己，信息在底部手牌区
	seat_labels.append(_make_seat_label(Vector2(1064, 300)))
	seat_labels.append(_make_seat_label(Vector2(500, 14)))
	seat_labels.append(_make_seat_label(Vector2(20, 300)))

	field_label = _make_label(26, COLOR_WHITE)
	field_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	field_label.position = Vector2(320, 280)
	field_label.custom_minimum_size = Vector2(640, 140)
	add_child(field_label)

	status_label = _make_label(18, COLOR_DIM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.position = Vector2(320, 496)
	status_label.custom_minimum_size = Vector2(640, 56)
	add_child(status_label)

	error_label = _make_label(16, COLOR_RED)
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
	row.position = Vector2(856, 662)
	row.custom_minimum_size = Vector2(408, 44)
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	btn_play = _button("出牌")
	btn_play.pressed.connect(_on_play_pressed)
	btn_pass = _button("不要")
	btn_pass.pressed.connect(_on_pass_pressed)
	btn_next = _button("下一局")
	btn_next.pressed.connect(_on_next_pressed)
	btn_rematch = _button("再来一场")
	btn_rematch.pressed.connect(_on_rematch_pressed)
	for b: Button in [btn_play, btn_pass, btn_next, btn_rematch]:
		row.add_child(b)


func _make_seat_label(pos: Vector2) -> Label:
	var lb := _make_label(17, COLOR_WHITE)
	lb.position = pos
	lb.custom_minimum_size = Vector2(180, 110)
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


# ---------------------------------------------------------------- 刷新

func _refresh() -> void:
	if state.is_empty():
		return
	var view := ViewGd.build(state, 0)
	var phase: String = view["phase"]

	info_label.text = "第 %d/%d 局    %s    积分 %s" % [
		int(view["round"]) + 1,
		int(view["rounds_total"]),
		"革命!" if bool(view["revolution"]) else "",
		str(view["scores"]),
	]

	for seat in range(1, 4):
		var lb: Label = seat_labels[seat]
		var turn_mark := "▶ " if int(view["turn"]) == seat else ""
		var ident := ""
		if (view["identities"] as Array).size() == 4 \
				and (view["finished"] as Array).has(seat):
			ident = "\n[%s]" % ScoringGd.IDENTITY_NAMES[int(view["identities"][seat])]
		lb.text = "%s%s\n剩 %d 张%s" % [
			turn_mark, SEAT_NAMES[seat], int(view["counts"][seat]), ident,
		]

	var lines: Array = []
	var lead: Dictionary = view["lead"]
	if phase == "play" and lead.is_empty():
		lines.append("—— 自由出牌 ——")
		if int(view["must_include"]) >= 0:
			lines.append("(首手必须包含 ♦3)")
	for entry: Dictionary in view["field"]:
		lines.append("%s：%s" % [
			SEAT_NAMES[int(entry["seat"])], CardsGd.labels(entry["combo"]["cards"]),
		])
	field_label.text = "\n".join(lines)

	_refresh_hand(view)

	var my_turn: bool = phase == "play" and int(view["turn"]) == 0
	if phase == "play":
		if my_turn:
			status_label.text = "轮到你出牌" + ("（需同牌型更大）" if not lead.is_empty() else "")
			status_label.add_theme_color_override("font_color", COLOR_GREEN)
		else:
			status_label.text = "等待 %s 出牌…" % SEAT_NAMES[int(view["turn"])]
			status_label.add_theme_color_override("font_color", COLOR_DIM)
	elif phase == "exchange":
		status_label.text = "局间交换：乞丐→大富豪 2 张，平民→富豪 1 张"
		status_label.add_theme_color_override("font_color", COLOR_GOLD)
	elif phase == "round_end":
		status_label.text = "本局结束   " + _round_end_text(view)
		status_label.add_theme_color_override("font_color", COLOR_GOLD)
	elif phase == "game_end":
		status_label.text = "全场结束！  " + _round_end_text(view)
		status_label.add_theme_color_override("font_color", COLOR_GOLD)

	btn_play.visible = my_turn
	btn_pass.visible = my_turn and not lead.is_empty()
	btn_next.visible = phase == "round_end"
	btn_rematch.visible = phase == "game_end"


func _round_end_text(view: Dictionary) -> String:
	var ids: Array = view["identities"]
	var pts: Array = view["last_points"]
	var parts: Array = []
	for s in 4:
		parts.append("%s=%s(%+d)" % [
			SEAT_NAMES[s], ScoringGd.IDENTITY_NAMES[int(ids[s])], int(pts[s]),
		])
	return "  ".join(parts)


func _refresh_hand(view: Dictionary) -> void:
	for child in hand_box.get_children():
		child.queue_free()
	for c in view["hand"]:
		var card: int = c
		var b := Button.new()
		b.toggle_mode = true
		b.text = CardsGd.label(card)
		b.custom_minimum_size = Vector2(62, 88)
		b.add_theme_font_size_override("font_size", 22)
		if CardsGd.is_red(card):
			b.add_theme_color_override("font_color", COLOR_RED)
		elif CardsGd.is_joker(card):
			b.add_theme_color_override("font_color", COLOR_GOLD)
		b.button_pressed = selected.has(card)
		b.toggled.connect(func(on: bool) -> void:
			if on:
				if not selected.has(card):
					selected.append(card)
			else:
				selected.erase(card))
		hand_box.add_child(b)
