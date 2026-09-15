## 牌桌。mode="local"：本地人+3AI（本机驱动规则引擎）；mode="online"：
## 渲染来自服务器的 game_view，动作经 net 发送。
## M4 视听：程序化卡牌控件、出牌/清桌/革命/终局动画、回合计时、程序化音效。
extends Control

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")

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

const EMOJIS := ["👍", "😂", "😱", "😭", "😡", "👏", "🤔", "🎉"]
## 快捷短语(短标 → 全句): 热门牌类游戏标配的社交快捷语音包
const QUICK_PHRASES := [
	["快点吧", "快点吧，我等到花儿都谢了"],
	["大家好", "大家好，很高兴见到各位"],
	["打得好", "你的牌打得太好了"],
	["别走", "不要走，决战到天亮"],
	["底牌多", "底牌留太多了吧"],
	["手气差", "唉，手气太差了"],
	["稳住", "稳住，我们能赢"],
	["关照", "大家好，多多关照"],
]
const AI_THINK_SEC := 0.7


var mode := "local"
var net: Node = null

var state: Dictionary = {}
var selected: Array = []
var advancing := false
var auto_pilot := false       # 本地托管中: AI 代打玩家座位(返回菜单后继续)
var _advance_gen := 0         # 驱动循环代际: 重启循环时使旧协程失效
var _at_game_end := false
var _emoji_cd := 0.0
var _chat_cd := 0.0
var _emoji_toggle: Button        # 表情栏折叠切换钮
var _emoji_open := false         # 表情栏是否展开
var _prev_tick := -1
var _timer_shown := -1           # 倒计时已显示的整数秒(文字门控)
var _auto_pass_done := false     # 本回合已自动"不要"(防重复)
var _my_follow_ms := -1.0        # 本地跟牌计时(30s 自动不要)
var _pulse: Tween = null       # "轮到你"状态文字呼吸脉冲
var _seat_skins: Array = ["skin_default", "skin_default", "skin_default", "skin_default"]
var _opp_avatars: Array = []       # 对手头像(内嵌于信息面板)
var self_panel: Control
var rules_btn: Button
var ops_row: Control
var _seat_panels: Array = []       # 对手信息面板
var _opp_hands: Array = []
var avatar_me: Control

# M4 视听状态
var _last_hand: Array = []
var _prev_revolution := false
var _prev_phase := ""
var _last_round_ids: Array = []
var _end_shown := false
var _field_count := -1
var _had_field := false         # 出牌区是否有过牌(区分清桌音效与首次刷新)
var _trick_texts: Array = []    # 本轮已出各手文本(清桌时整体转上轮)
var _last_trick: Array = []     # 上一轮完整出牌回顾(清桌后常显)
var trick_lbl: Label = null     # 上轮回顾标签(出牌区空时显示)
var counter_lbl: Label = null   # 记牌器 HUD(按点数显示未被出的牌数)
var counter_toggle: Button = null
var _counter_played := {}       # 点数值 -> 已出张数(本局累计)
var _counter_totals := {}       # 点数值 -> 总张数(王受命运卡影响)
var emoji_popup: PanelContainer = null  # 表情/快捷回复向上弹出面板
var emoji_grid: GridContainer = null
var phrase_grid: GridContainer = null
var _tab_emoji_btn: Button = null
var _tab_phrase_btn: Button = null
var _emoji_tab := "emoji"
var settings_btn: Button = null      # 对局内设置入口(右上)
var _settings_page: Control = null   # 对局内打开的设置页
var _turn_total := -1.0
var _turn_remain := -1.0
var _last_turn_seat := -99
var _kbd_shift := 0.0   # 虚拟键盘避让位移(移动端聊天聚焦时)

var info_label: Label
var rogue := false              # 肉鸽模式(仅本地): 每局随机命运卡
var rogue_lbl: Label = null     # 场内命运卡标签
var _rogue_dlg: Control = null  # 命运卡揭示弹窗
var self_label: RichTextLabel
var status_label: Label
var error_label: Label
var timer_label: Label
var chat_log: Label
var chat_edit: LineEdit
var seat_labels: Array = []
var hand_box: Control
var _hand_cards: Array = []     # 手牌卡牌控件(按手牌顺序)
var field_box: HFlowContainer
var field_panel: Panel
var chat_btn: Button
var field_hint: Label
var fx_layer: Control
var btn_play: Button
var btn_hint: Button
var btn_pass: Button
var btn_rematch: Button
var btn_leave: Button


func _ready() -> void:
	_build_ui()
	# 自适应重排: 本地/联机都要(原先连接在 _new_match, 联机永不触发)
	resized.connect(_relayout)
	_relayout.call_deferred()
	if mode == "online":
		_bind_net()
		_refresh()
	else:
		_new_match()
	Audio.play_bgm("rogue" if rogue else "table")


func _process(delta: float) -> void:
	if _emoji_cd > 0.0:
		_emoji_cd -= delta
	if _chat_cd > 0.0:
		_chat_cd -= delta
	# 本地对局: 跟牌超过 30 秒自动"不要"(领出时无法 Pass, 不适用)
	if mode == "local" and visible and not state.is_empty() \
			and str(state["phase"]) == "play" and int(state["turn"]) == 0 \
			and not auto_pilot and not (state["lead"] as Dictionary).is_empty():
		if _my_follow_ms < 0.0:
			_my_follow_ms = 0.0
		else:
			_my_follow_ms += delta
			if _my_follow_ms >= 30.0:
				_my_follow_ms = -1.0
				_auto_pass()
	else:
		_my_follow_ms = -1.0
	# 在线模式回合倒计时(仅整数秒变化时更新文字, 避免每帧重排)
	if mode == "online" and _turn_remain > 0.0:
		_turn_remain -= delta
		if _turn_total > 0:
			var remain := maxf(_turn_remain, 0.0)
			var cur := int(ceil(remain))
			if cur != _timer_shown:
				_timer_shown = cur
				timer_label.text = "⏱ %d" % cur
				timer_label.add_theme_color_override("font_color",
						AppTheme.RED if remain <= 5.0 else AppTheme.WHITE)
				if remain <= 5.0 and cur >= 1:
					_sfx("tick")
	# 移动端: 聊天框聚焦时虚拟键盘会盖住底部输入行 → 整行上移避让
	if mode == "online" and OS.has_feature("android"):
		_update_keyboard_avoid()


## 虚拟键盘高度(物理px)换算到逻辑画布并驱动避让; 失焦归零由 _relayout 复位
func _update_keyboard_avoid() -> void:
	var kh := float(DisplayServer.virtual_keyboard_get_height())
	var target := 0.0
	if chat_edit.has_focus() and kh > 0.0:
		var wsize := Vector2(DisplayServer.window_get_size())
		if wsize.y > 0.0:
			target = minf(kh * (size.y / wsize.y), size.y * 0.45)
	if target == _kbd_shift:
		return
	_kbd_shift = target
	_relayout()


## ESC / 安卓返回键 = 返回菜单(先弹确认框); 确认框打开时先关框
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return  # 后台托管中隐藏的牌桌不抢 ESC(确认框等由当前界面处理)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _settings_page != null and is_instance_valid(_settings_page):
			_settings_page._close()
			return
		if _rogue_dlg != null:
			_close_rogue_reveal()
			return
		if _leave_dlg != null:
			_close_leave_dialog()
			return
		_on_leave_pressed()


# ---------------------------------------------------------------- 驱动（本地）

func _new_match() -> void:
	for child in fx_layer.get_children():
		child.queue_free()  # 关闭上一场的结算面板/特效
	# 肉鸽模式: 引擎启用命运卡(每局二选一), 普通模式不受影响
	state = GameStateGd.new_match({"rogue": rogue}, -1) if rogue 			else GameStateGd.new_match({}, -1)
	selected.clear()
	# 重置视听状态(上场的革命/阶段/桌面/手牌缓存全部作废)
	_end_shown = false
	_prev_revolution = false
	_prev_phase = ""
	_last_round_ids = []
	_field_count = -1
	_had_field = false
	_last_hand = []
	# 本地: 我用已装备皮肤, AI 随机皮肤
	var ids: Array = []
	for s in SkinsLib.SKINS:
		ids.append(str(s["id"]))
	_seat_skins = [Wallet.equipped_skin, "", "", ""]
	for i in range(1, 4):
		_seat_skins[i] = ids[randi() % ids.size()]
	if rogue:
		_show_rogue_flow()  # draft → 选择 → 确认揭示 → _advance
	else:
		_advance()


## 驱动循环：AI 依次行动 / 阶段过渡，停在人需要操作处。
## 代际计数: 离开对局会重启新循环, 挂起中的旧协程恢复后凭 gen 失配自灭,
## 否则旧+新两个循环会同时驱动 AI(双出牌/非法动作)。
func _advance() -> void:
	if mode == "online":
		return
	if advancing:
		return
	advancing = true
	_advance_gen += 1
	var gen := _advance_gen
	var guard := 0
	while true:
		guard += 1
		if guard % 25 == 0:
			var tr := FileAccess.open("C:/Users/Administrator/AppData/Local/Temp/adv_trace.txt", FileAccess.WRITE)
			if tr != null:
				tr.store_line("guard=%d phase=%s round=%d turn=%s pend=%s adv=%s" % [guard,
						str(state.get("phase", "?")), int(state.get("round", -1)),
						str(state.get("turn", "?")),
						str((state.get("exchange_returns", []) as Array).size()), advancing])
				tr.close()
		if guard > 2000:
			push_error("local table: 驱动循环超限")
			break
		var phase: String = state["phase"]
		if phase == "play":
			var seat_to_act := int(state["turn"])
			if seat_to_act == 0 and not auto_pilot:
				# 停靠在玩家回合: 压不过也自动"不要"(无需等玩家手动)
				if not (state["lead"] as Dictionary).is_empty():
					var act: Dictionary = BotPlayerGd.decide(state, 0, GameSettings.ai_level)
					if str(act.get("t")) == "pass":
						_auto_pass()
						continue
				_vibrate(40)  # 轮到你(移动端触感)
				break  # 等玩家操作(托管中则 AI 代打)
			_refresh()
			await get_tree().create_timer(AI_THINK_SEC).timeout
			if gen != _advance_gen or not is_inside_tree():
				return
			# 等待期间局面可能被推进(如自动"不要"): 重新评估而非套用旧座位,
			# 否则 AI 动作打在错误座位上(not_your_turn)导致循环死亡
			if str(state["phase"]) != "play" or int(state["turn"]) != seat_to_act:
				continue
			print("[adv] t=%d seat=%d decide begin" % [Time.get_ticks_msec(), seat_to_act])
			var action := BotPlayerGd.decide(state, seat_to_act, GameSettings.ai_level)
			print("[adv] seat=%d decided t=%s" % [seat_to_act, str(action.get("t", "?"))])
			var r := _local_apply(action)
			print("[adv] t=%d seat=%d applied ok=%s" % [Time.get_ticks_msec(), seat_to_act,
					str(r["ok"])])
			if not bool(r["ok"]):
				var tr := FileAccess.open("C:/Users/Administrator/AppData/Local/Temp/adv_err.txt", FileAccess.WRITE)
				if tr != null:
					tr.store_line("AI illegal seat=%d err=%s hand=%s lead=%s" % [seat_to_act,
							str(r["error"]), str(state["hands"][seat_to_act]),
							str(state.get("lead", {}))])
					tr.close()
				push_error("local table: AI 非法动作 %s" % str(r["error"]))
				break
			_detect_local_eight_cut(action, r["state"])
			state = r["state"]
		elif phase == "exchange":
			_refresh()
			# 返还选牌: 轮到玩家(座位0)且未托管时等待其确认; 托管中由 bot 代打
			var er: Dictionary = _pending_return_for(0)
			if not er.is_empty() and not auto_pilot:
				_vibrate(40)  # 该你选牌返还(移动端触感)
				break  # 等玩家选牌
			await get_tree().create_timer(AI_THINK_SEC).timeout
			if gen != _advance_gen or not is_inside_tree():
				return
			if str(state["phase"]) != "exchange":
				continue
			var action := BotPlayerGd.decide(state, int(state["turn"]), GameSettings.ai_level)
			var r2 := GameStateGd.apply(state, action)
			if not bool(r2["ok"]):
				push_error("local table: 换牌返还非法 %s" % str(r2["error"]))
				break
			state = r2["state"]
		elif phase == "round_end":
			_refresh()
			# 回合制: 每局结束短展示本局结果后自动进入下一局;
			# 最后一局自动进入全场结算(结算面板统一弹出)
			var is_last: bool = int(state["round"]) + 1 >= int(state["cfg"]["rounds"])
			await get_tree().create_timer(1.4 if is_last else 1.2).timeout
			if gen != _advance_gen or not is_inside_tree():
				return
			var r := GameStateGd.apply(state, {"t": "next_round"})
			if bool(r["ok"]):
				state = r["state"]
				_counter_reset()
				if rogue:
					# 揭示期间停循环, 关闭后重启。必须同步清 advancing:
					# gen 已自增, 循环尾部的清位不会执行, 否则关闭弹窗时
					# 看到 advancing==true 直接 return → 第 2 局起永久卡死
					_advance_gen += 1
					advancing = false
					_show_rogue_choice()  # 次局命运二选一
					break
		elif phase == "draft" and rogue:
			_advance_gen += 1
			advancing = false
			_show_rogue_choice()
			break
		elif phase == "game_end":
			break  # 等按钮
	_refresh()
	if gen == _advance_gen:
		advancing = false


## 当前待返还的换牌任务(本地=state, 联机=latest_view)
func _current_view() -> Dictionary:
	if mode == "online" and net != null and not (net.latest_view as Dictionary).is_empty():
		return net.latest_view
	if state.is_empty():
		return {}
	return ViewGd.build(state, 0)


func _pending_return_for(seat: int) -> Dictionary:
	var er: Dictionary = _current_view().get("exchange_return", {})
	if er.is_empty() or int(er.get("seat", -1)) != seat:
		return {}
	return er


func _my_pending_return(view: Dictionary) -> Dictionary:
	var er: Dictionary = view.get("exchange_return", {})
	if er.is_empty() or int(er.get("seat", -1)) != int(view["my_seat"]):
		return {}
	return er


func _local_apply(action: Dictionary) -> Dictionary:
	var r := GameStateGd.apply(state, action)
	if bool(r["ok"]) and int(action.get("seat", -1)) == 0 			and str(action["t"]) == "play" 			and (action["cards"] as Array).size() == 4:
		Wallet.note_mission("m_quad")  # 我方四条=炸弹(本规则集 4 张组合仅四条)
	return r


func _human_apply(action: Dictionary) -> void:
	if advancing or state.is_empty():
		return
	if str(action["t"]) == "pass":
		_sfx("pass")
	var r := GameStateGd.apply(state, action)
	if not bool(r["ok"]):
		_flash_error(GameStateGd.error_msg(str(r["error"])))
		return
	if str(action["t"]) == "play" and (action["cards"] as Array).size() == 4:
		Wallet.note_mission("m_quad")  # 我方四条
	_detect_local_eight_cut(action, r["state"])
	state = r["state"]
	selected.clear()
	_refresh()
	_advance()


func _on_play_pressed() -> void:
	_sfx("click")
	# 换牌阶段: 确认返还所选牌
	var cur_view: Dictionary = _current_view()
	if str(cur_view.get("phase", "")) == "exchange":
		var er: Dictionary = _my_pending_return(cur_view)
		if er.is_empty():
			return
		if selected.size() != int(er["n"]):
			_flash_error("需选择 %d 张返还" % int(er["n"]))
			return
		var cards: Array = selected.duplicate()
		selected.clear()
		if mode == "online":
			net.exchange_return(cards)
		else:
			_human_apply({"t": "exchange_return", "seat": 0, "cards": cards})
		return
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
	_sfx("click")
	var view: Dictionary
	if mode == "online" and net != null:
		view = net.latest_view
	elif not state.is_empty():
		view = ViewGd.build(state, 0)
	if view.is_empty() or str(view["phase"]) != "play" \
			or int(view["turn"]) != int(view["my_seat"]):
		return
	var action := BotPlayerGd.decide_from_view(view)
	if str(action.get("t")) == "play":
		selected = (action.get("cards", []) as Array).duplicate()
		_refresh()
	else:
		_on_pass_pressed()


func _on_pass_pressed() -> void:
	_sfx("click")
	if mode == "online":
		net.pass_turn()
		return
	_human_apply({"t": "pass", "seat": 0})


## 自动"不要": 本地须直改状态——它恰在 AI 移交回合的刷新中触发,
## 此时 advancing=true 会拦掉 _human_apply; 联机走网络不受限。
func _auto_pass() -> void:
	_sfx("pass")
	if mode == "online":
		net.pass_turn()
		return
	var r := GameStateGd.apply(state, {"t": "pass", "seat": 0})
	print("[auto] pass ok=%s passes=%d turn=%d" % [str(r["ok"]),
			int(r["state"].get("passes", -9)) if bool(r["ok"]) else -9,
			int(r["state"].get("turn", -9)) if bool(r["ok"]) else -9])
	if not bool(r["ok"]):
		return
	state = r["state"]
	selected.clear()
	_refresh()
	_advance()


func _on_rematch_pressed() -> void:
	_sfx("click")
	_new_match()


## 返回菜单/大厅: 对局进行中先弹确认框, 确认后才真正离开
func _on_leave_pressed() -> void:
	_sfx("click")
	var local_live: bool = mode == "local" and not state.is_empty() \
			and str(state["phase"]) != "game_end"
	var online_live: bool = mode == "online" and not _at_game_end
	if local_live or online_live:
		_show_leave_dialog()
		return
	_do_leave()


func _do_leave() -> void:
	if net != null:
		net.leave_room()
	# 本地模式中途返回菜单: 托管继续(牌桌保留), 重新进入可继续本局
	if mode == "local" and not state.is_empty() \
			and str(state["phase"]) != "game_end":
		auto_pilot = true
		advancing = false
		_advance()
	finished.emit()


## 离开确认框(与首页"返回上一局"确认框同款样式)
var _leave_dlg: Control = null


func _show_leave_dialog() -> void:
	if _leave_dlg != null:
		return
	var local := mode == "local"
	var dlg := Control.new()
	dlg.mouse_filter = Control.MOUSE_FILTER_STOP
	dlg.theme = AppTheme.build_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(center)
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(AppTheme.PANEL, AppTheme.GOLD, 14, 2)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := AppTheme.make_label(22, AppTheme.GOLD)
	title.text = "返回菜单？" if local else "离开对局？"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var desc := AppTheme.make_label(15, AppTheme.DIM)
	desc.text = "返回后本局由 AI 托管继续, 从首页可回到本局。" if local \
			else "离开后你的座位由 AI 代管(弃局), 并返回大厅。"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(desc)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var go := AppTheme.make_button("返回菜单" if local else "离开对局",
			Vector2(150, 46), 17)
	go.pressed.connect(func() -> void:
		Audio.play("click")
		_close_leave_dialog()
		_do_leave())
	row.add_child(go)
	var cancel := AppTheme.make_button("取消", Vector2(96, 46), 15)
	cancel.pressed.connect(func() -> void:
		Audio.play("click")
		_close_leave_dialog())
	row.add_child(cancel)
	_leave_dlg = dlg
	add_child(dlg)
	dlg.position = Vector2.ZERO
	dlg.size = size


## 对局内设置页: 复用全屏设置(音乐/页面/触感), 本地局打开时暂停驱动
func _open_settings_page() -> void:
	if _settings_page != null:
		return
	_settings_page = (load("res://src/client/ui/settings_panel.gd") as GDScript).new()
	add_child(_settings_page)
	_settings_page.position = Vector2.ZERO
	_settings_page.size = size
	_settings_page.open()  # 页面默认隐藏(同主菜单用法), open 后加载并显示
	_settings_page.closed.connect(func() -> void:
		if _settings_page != null and is_instance_valid(_settings_page):
			_settings_page.queue_free()
		_settings_page = null
		if mode == "local" and not state.is_empty() 				and str(state["phase"]) != "game_end":
			_advance())
	if mode == "local" and advancing:
		_advance_gen += 1  # 暂停: 挂起循环在下一个校验点自行退出
		advancing = false


func _close_leave_dialog() -> void:
	if _leave_dlg != null and is_instance_valid(_leave_dlg):
		_leave_dlg.queue_free()
	_leave_dlg = null


## 命运卡流程: draft 阶段二选一 → 选定后确认揭示(开始对局)
func _show_rogue_flow() -> void:
	if str(state.get("phase", "")) == "draft":
		_show_rogue_choice()
	else:
		_show_rogue_reveal()


## 二选一: 两张命运卡并排, 点击选定并应用
func _show_rogue_choice() -> void:
	if _rogue_dlg != null and is_instance_valid(_rogue_dlg):
		_rogue_dlg.queue_free()
	var dlg := Control.new()
	dlg.mouse_filter = Control.MOUSE_FILTER_STOP
	dlg.theme = AppTheme.build_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	var cap := AppTheme.make_label(26, AppTheme.GOLD)
	cap.text = "命运二选一 · 第 %d 层" % (int(state["round"]) + 1)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var choices: Array = state.get("rogue_choices", [])
	for i in choices.size():
		var meta := {}
		for m in GameStateGd.ROGUE_MODS:
			if str(m["id"]) == str(choices[i]):
				meta = m
				break
		var idx := i
		var pick := AppTheme.make_button(
				"【%s】%s
%s" % [meta.get("glyph", "?"), meta.get("name", ""),
				meta.get("desc", "")], Vector2(330, 130), 16)
		pick.pressed.connect(func() -> void:
			Audio.play("win")
			var r := GameStateGd.apply(state,
					{"t": "rogue_pick", "idx": idx})
			if bool(r["ok"]):
				state = r["state"]
			_show_rogue_reveal())
		row.add_child(pick)
	var dice_row := HBoxContainer.new()
	dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dice_row.add_theme_constant_override("separation", 10)
	box.add_child(dice_row)
	if Wallet.item_count("item_fate_dice") > 0:
		var dice := AppTheme.make_button(
				"🎲 掷命运骰重抽 (持有 %d)" % Wallet.item_count("item_fate_dice"),
				Vector2(320, 44), 15)
		dice.pressed.connect(func() -> void:
			Audio.play("click")
			if Wallet.consume_item("item_fate_dice"):
				var rr := GameStateGd.rogue_reroll_choices(state)
				state["rogue_choices"] = rr
				_close_rogue_reveal()
				_show_rogue_choice())
		dice_row.add_child(dice)
	var hint := AppTheme.make_label(14, AppTheme.DIM)
	hint.text = "选定的命运卡在本层生效"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_rogue_dlg = dlg
	add_child(dlg)
	dlg.position = Vector2.ZERO
	dlg.size = size


## 选定后的确认揭示(暗幕淡入 + 卡面弹出 + 开始对局)
func _show_rogue_reveal() -> void:
	if _rogue_dlg != null and is_instance_valid(_rogue_dlg):
		_rogue_dlg.queue_free()
	var mod_id := str(state["cfg"].get("rogue_mod", ""))
	var meta := {}
	for m in GameStateGd.ROGUE_MODS:
		if str(m["id"]) == mod_id:
			meta = m
			break
	var dlg := Control.new()
	dlg.mouse_filter = Control.MOUSE_FILTER_STOP
	dlg.theme = AppTheme.build_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(center)
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(AppTheme.PANEL, AppTheme.GOLD, 18, 2)
	sb.content_margin_left = 44
	sb.content_margin_right = 44
	sb.content_margin_top = 28
	sb.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var cap := AppTheme.make_label(15, AppTheme.DIM)
	cap.text = "命运卡 · 第 %d 局 · %s类效果" % [int(state["round"]) + 1,
			str(meta.get("cat", ""))]
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap)
	var glyph := AppTheme.make_label(88, AppTheme.GOLD)
	glyph.add_theme_font_override("font", AppTheme.title_font())
	glyph.text = str(meta.get("glyph", "?"))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(glyph)
	var name_lbl := AppTheme.make_label(30, AppTheme.WHITE)
	name_lbl.add_theme_font_override("font", AppTheme.title_font())
	name_lbl.text = str(meta.get("name", ""))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_lbl)
	var desc := AppTheme.make_label(16, AppTheme.DIM)
	desc.text = str(meta.get("desc", ""))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(desc)
	var go := AppTheme.make_button("开始对局", Vector2(190, 48), 18)
	go.pressed.connect(func() -> void:
		Audio.play("click")
		_close_rogue_reveal())
	var go_wrap := CenterContainer.new()
	go_wrap.add_child(go)
	box.add_child(go_wrap)
	_rogue_dlg = dlg
	add_child(dlg)
	dlg.position = Vector2.ZERO
	dlg.size = size
	_update_rogue_lbl()


## 确认揭示的关闭: 关闭后恢复驱动(本地局暂停/续玩由 _advance 代际管理)
func _close_rogue_reveal() -> void:
	if _rogue_dlg != null and is_instance_valid(_rogue_dlg):
		_rogue_dlg.queue_free()
	_rogue_dlg = null
	_update_rogue_lbl()
	if advancing:
		return
	_advance()


## 场内命运卡标签(该局生效中常显)
func _update_rogue_lbl() -> void:
	if rogue_lbl == null:
		return
	var mod_id := str(state["cfg"].get("rogue_mod", ""))
	var show := rogue and _rogue_dlg == null and mod_id != "" 			and str(state["phase"]) in ["play", "exchange"]
	rogue_lbl.visible = show
	if show:
		var meta := {}
		for m in GameStateGd.ROGUE_MODS:
			if str(m["id"]) == mod_id:
				meta = m
				break
		rogue_lbl.text = "【%s】%s — %s" % [meta.get("glyph", ""), meta.get("name", ""),
				meta.get("desc", "")]


## ESC 关闭命运卡弹窗(在 _unhandled_input 的 leave_dlg 分支旁)


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
					_sfx("turn")
					_vibrate(40)
		_refresh())
	net.game_event.connect(_on_game_event)
	net.errored.connect(func(code: String, msg: String) -> void:
		_flash_error(GameStateGd.error_msg(code) if msg == "" else msg))
	net.server_disconnected.connect(func() -> void:
		status_label.text = "连接断开，自动重连中…"
		status_label.add_theme_color_override("font_color", AppTheme.RED))
	net.rejoined.connect(func() -> void:
		_flash_error("已重新连上，座位已恢复")
		# 掉线期间对局可能已被 AI 打完: 重连后收不到对局视图 → 回大厅
		await get_tree().create_timer(1.2).timeout
		if not is_inside_tree() or mode != "online":
			return
		if (net.latest_view as Dictionary).is_empty():
			_flash_error("对局已结束，返回房间")
			finished.emit())
	# 对局结束后服务器广播 room_state → 自动回到房间（再来一局流转）
	net.room_state.connect(func(_state: Dictionary) -> void:
		if _at_game_end:
			_at_game_end = false
			finished.emit())


func _on_game_event(event: String, data: Dictionary) -> void:
	if event == "emoji":
		_show_emoji(int(data.get("seat", 0)), int(data.get("id", 0)))
		_sfx("pop")
	elif event == "chat":
		_append_chat(int(data.get("seat", 0)), str(data.get("text", "")))
	elif event == "played":
		if int(data.get("seat", -1)) == int(net.latest_view.get("my_seat", -1)) 				and (data.get("combo", {}) as Dictionary).get("cards", []).size() == 4:
			Wallet.note_mission("m_quad")
		if bool(data.get("eight_cut", false)):
			_spawn_fx("eight_cut")
			if rogue and _rogue_mod_id_safe() == "eight_gift":
				var gift_tw := get_tree().create_timer(0.9)
				gift_tw.timeout.connect(func() -> void:
					if is_inside_tree():
						_spawn_fx("eight_gift"))


func _append_chat(seat: int, text: String) -> void:
	var view: Dictionary = net.latest_view if mode == "online" and net != null else {}
	var lines := chat_log.text.split("\n")
	var keep := lines.slice(maxi(lines.size() - 4, 0))
	keep.append("%s: %s" % [_seat_name(view, seat), text])
	chat_log.text = "\n".join(keep)


## 快捷短语发送: 本地=进聊天行+随机 AI 回应; 联机=聊天广播
func _send_phrase(full: String) -> void:
	if mode == "online" and net != null:
		net.send_chat(full)
		var view: Dictionary = net.latest_view
		_append_chat(int(view.get("my_seat", 0)), full)
	else:
		_append_chat(0, full)
		_bot_reply()


## 本地 AI 回应: 60% 概率一位随机 AI 回一句随机短语
func _bot_reply() -> void:
	if randf() > 0.6:
		return
	var full: String = str(QUICK_PHRASES[randi() % QUICK_PHRASES.size()][1])
	get_tree().create_timer(randf_range(0.8, 2.0)).timeout.connect(func() -> void:
		if is_inside_tree():
			_bot_say(full))


func _bot_say(full: String) -> void:
	var seat := 1 + randi() % 3
	_append_chat(seat, full)


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
	if rogue:
		bg.modulate = Color(1.05, 0.82, 1.2)  # 肉鸽夜空: 偏紫氛围
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 头像: 三个对手 + 我(左上)
	# 自己的信息面板(手牌左侧): 头像内嵌 + 彩色信息
	self_panel = PanelContainer.new()
	var sp_sb := AppTheme.flat(Color(0.08, 0.08, 0.18, 0.92), Color(AppTheme.GOLD, 0.6), 12, 2)
	sp_sb.content_margin_left = 10
	sp_sb.content_margin_right = 12
	sp_sb.content_margin_top = 8
	sp_sb.content_margin_bottom = 8
	self_panel.add_theme_stylebox_override("panel", sp_sb)
	self_panel.position = Vector2(16, 556)
	self_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(self_panel)
	var sp_row := HBoxContainer.new()
	sp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sp_row.add_theme_constant_override("separation", 10)
	self_panel.add_child(sp_row)
	avatar_me = AvatarScript.new()
	avatar_me.custom_minimum_size = Vector2(52, 52)
	avatar_me.size = Vector2(52, 52)
	sp_row.add_child(avatar_me)
	self_label = RichTextLabel.new()
	self_label.bbcode_enabled = true
	self_label.scroll_active = false
	self_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	self_label.custom_minimum_size = Vector2(170 if Responsive.is_touch() else 140, 52)
	# 触屏设备信息文字加大一档(手机 720p 逻辑画布物理密度高, 14/15px 偏小)
	self_label.add_theme_font_size_override("normal_font_size",
			18 if Responsive.is_touch() else 15)
	sp_row.add_child(self_label)

	info_label = _make_label(20, AppTheme.GOLD)
	info_label.position = Vector2(20, 12)
	add_child(info_label)
	_add_text_shadow(info_label)
	# 肉鸽命运卡标签(顶部居中下移, 避开对家面板与计时器)
	rogue_lbl = _make_label(14, AppTheme.GOLD)
	rogue_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	rogue_lbl.add_theme_constant_override("shadow_offset_x", 1)
	rogue_lbl.add_theme_constant_override("shadow_offset_y", 1)
	rogue_lbl.visible = false
	add_child(rogue_lbl)

	timer_label = _make_label(22, AppTheme.WHITE)
	timer_label.position = Vector2(1180, 12)
	timer_label.visible = mode == "online"
	add_child(timer_label)

	rules_btn = _button("规则")
	settings_btn = _button("设置")
	settings_btn.position = Vector2(1076, 10)
	rules_btn.position = Vector2(964, 10)
	rules_btn.custom_minimum_size = Vector2(72, 32)
	rules_btn.add_theme_font_size_override("font_size", 15)
	rules_btn.pressed.connect(func() -> void:
		_sfx("click")
		var tut := TutorialScript.new()
		add_child(tut))
	settings_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_open_settings_page())
	add_child(rules_btn)
	add_child(settings_btn)

	seat_labels.append(null)  # 座位0=自己，信息在 self_label（头像旁）
	for i in 3:
		var pr := _make_seat_panel(i)
		_seat_panels.append(pr[0])
		seat_labels.append(pr[1])
		_opp_avatars.append(pr[2])

	# 对手手牌(重叠牌背): 右=下家(竖列), 上=对家(横排), 左=上家(竖列)
	for info: Dictionary in [
		{"pos": Vector2(1130, 108), "vert": true},
		{"pos": Vector2(700, 44), "vert": false},
		{"pos": Vector2(30, 50), "vert": true},
	]:
		var fan := Control.new()
		fan.position = info["pos"]
		fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fan.set_meta("vert", info["vert"])
		fan.set_meta("count", -1)
		add_child(fan)
		_opp_hands.append(fan)

	# 牌桌中央: 桌面区
	field_panel = Panel.new()
	# 点击出牌区 = 出牌(与"出牌"按钮等效; 换牌阶段为确认返还);
	# 非你回合时点出牌区无动作(不弹错误)
	field_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	field_panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			var v: Dictionary = _current_view()
			var er: Dictionary = _my_pending_return(v)
			if str(v.get("phase", "")) == "play" \
					and int(v.get("turn", -1)) != int(v.get("my_seat", -2)) \
					and er.is_empty():
				return
			_on_play_pressed())
	var field_sb := StyleBoxFlat.new()
	field_sb.bg_color = Color(0.09, 0.09, 0.20, 0.94)
	field_sb.set_corner_radius_all(14)
	field_sb.set_border_width_all(2)
	field_sb.border_color = Color(AppTheme.GOLD, 0.50)
	field_panel.add_theme_stylebox_override("panel", field_sb)
	field_panel.position = Vector2(320, 204)
	field_panel.custom_minimum_size = Vector2(640, 248)
	add_child(field_panel)

	field_hint = _make_label(16, AppTheme.DIM)
	field_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	field_hint.position = Vector2(20, 6)
	field_hint.custom_minimum_size = Vector2(600, 24)
	# 记牌器开关(顶栏)
	counter_toggle = _button("记牌")
	counter_toggle.custom_minimum_size = Vector2(84, 44)
	counter_toggle.toggle_mode = true
	counter_toggle.button_pressed = GameSettings.card_counter
	counter_toggle.pressed.connect(func() -> void:
		Audio.play("click")
		GameSettings.card_counter = counter_toggle.button_pressed
		GameSettings.save_settings()
		_update_counter())
	add_child(counter_toggle)
	# 记牌器 HUD(出牌区底部一行)
	counter_lbl = _make_label(13, Color("9fd8e8"))
	counter_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	counter_lbl.add_theme_constant_override("shadow_offset_x", 1)
	counter_lbl.add_theme_constant_override("shadow_offset_y", 1)
	field_panel.add_child(counter_lbl)
	trick_lbl = _make_label(13, Color("c9b06a"))
	trick_lbl.position = Vector2(20, 30)
	trick_lbl.custom_minimum_size = Vector2(600, 22)
	trick_lbl.visible = false
	field_panel.add_child(trick_lbl)
	field_panel.add_child(field_hint)

	# 出牌条目流式排布: 牌多时自动折两行, 不超出出牌区
	field_box = HFlowContainer.new()
	field_box.alignment = FlowContainer.ALIGNMENT_CENTER
	field_box.position = Vector2(20, 40)
	field_box.custom_minimum_size = Vector2(600, 196)
	field_box.add_theme_constant_override("h_separation", 16)
	field_box.add_theme_constant_override("v_separation", 8)
	field_panel.add_child(field_box)

	status_label = _make_label(18, AppTheme.DIM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.position = Vector2(320, 496)
	status_label.custom_minimum_size = Vector2(640, 56)
	add_child(status_label)
	_add_text_shadow(status_label)

	error_label = _make_label(16, AppTheme.RED)
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.position = Vector2(320, 470)
	error_label.custom_minimum_size = Vector2(640, 26)
	add_child(error_label)

	hand_box = Control.new()
	hand_box.position = Vector2(258, 534)
	hand_box.size = Vector2(1010, 130)
	hand_box.mouse_filter = Control.MOUSE_FILTER_STOP
	hand_box.gui_input.connect(_on_hand_gui_input)
	add_child(hand_box)

	ops_row = HBoxContainer.new()
	ops_row.position = Vector2(826, 662)
	ops_row.custom_minimum_size = Vector2(408, 44)
	ops_row.add_theme_constant_override("separation", 10)
	add_child(ops_row)

	btn_play = _button("出牌")
	btn_play.pressed.connect(_on_play_pressed)
	btn_hint = _button("提示")
	btn_hint.pressed.connect(_on_hint_pressed)
	btn_pass = _button("不要")
	btn_pass.pressed.connect(_on_pass_pressed)
	btn_rematch = _button("再来一场")
	btn_rematch.pressed.connect(_on_rematch_pressed)
	btn_leave = _button("返回大厅")
	btn_leave.pressed.connect(_on_leave_pressed)
	for b: Button in [btn_play, btn_hint, btn_pass, btn_rematch, btn_leave]:
		ops_row.add_child(b)

	# 快捷表达面板: 😀 钮向上弹出, 面板内 表情/快捷回复 双 Tab(不再横向铺开)
	emoji_popup = PanelContainer.new()
	var ep_sb := AppTheme.flat(AppTheme.PANEL, Color(AppTheme.GOLD, 0.6), 12, 2)
	ep_sb.content_margin_left = 12
	ep_sb.content_margin_right = 12
	ep_sb.content_margin_top = 10
	ep_sb.content_margin_bottom = 12
	emoji_popup.add_theme_stylebox_override("panel", ep_sb)
	emoji_popup.position = Vector2(16, 408)  # 😀 钮上方(664-面板高-8)
	emoji_popup.custom_minimum_size = Vector2(360, 248)
	emoji_popup.visible = false
	add_child(emoji_popup)
	var ep_box := VBoxContainer.new()
	ep_box.add_theme_constant_override("separation", 8)
	emoji_popup.add_child(ep_box)
	var ep_tabs := HBoxContainer.new()
	ep_tabs.add_theme_constant_override("separation", 8)
	ep_box.add_child(ep_tabs)
	_tab_emoji_btn = AppTheme.make_button("表情", Vector2(160, 36), 15)
	_tab_emoji_btn.toggle_mode = true
	_tab_emoji_btn.pressed.connect(func() -> void: _set_emoji_tab("emoji"))
	ep_tabs.add_child(_tab_emoji_btn)
	_tab_phrase_btn = AppTheme.make_button("快捷回复", Vector2(160, 36), 15)
	_tab_phrase_btn.toggle_mode = true
	_tab_phrase_btn.pressed.connect(func() -> void: _set_emoji_tab("phrase"))
	ep_tabs.add_child(_tab_phrase_btn)
	# 表情页(4 列网格)
	emoji_grid = GridContainer.new()
	emoji_grid.columns = 4
	emoji_grid.add_theme_constant_override("h_separation", 8)
	emoji_grid.add_theme_constant_override("v_separation", 8)
	ep_box.add_child(emoji_grid)
	for i in EMOJIS.size():
		var id := i
		var eb := AppTheme.make_button(EMOJIS[i], Vector2(72, 44), 20)
		eb.pressed.connect(func() -> void:
			if _emoji_cd > 0.0:
				_flash_error("表情发太快了")
				return
			_emoji_cd = 1.0
			_sfx("pop")
			if mode == "online" and net != null:
				net.send_emoji(id))
		emoji_grid.add_child(eb)
	# 快捷回复页(2 列, 发完整语句; 本地=气泡+AI回应, 联机=聊天广播)
	phrase_grid = GridContainer.new()
	phrase_grid.columns = 2
	phrase_grid.add_theme_constant_override("h_separation", 8)
	phrase_grid.add_theme_constant_override("v_separation", 8)
	phrase_grid.visible = false
	ep_box.add_child(phrase_grid)
	for ph: Array in QUICK_PHRASES:
		var short: String = str(ph[0])
		var full: String = str(ph[1])
		var pb := AppTheme.make_button(short, Vector2(160, 40), 14)
		pb.pressed.connect(func() -> void:
			if _chat_cd > 0.0:
				_flash_error("说太快了")
				return
			_chat_cd = 1.0
			_send_phrase(full))
		phrase_grid.add_child(pb)
	_emoji_toggle = AppTheme.make_button("😀",
			Vector2(48, 48) if Responsive.is_touch() else Vector2(44, 40), 20)
	_emoji_toggle.position = Vector2(16, 664)
	_emoji_toggle.pressed.connect(func() -> void:
		Audio.play("pop")
		_emoji_open = not _emoji_open
		_update_emoji_vis())
	add_child(_emoji_toggle)
	_update_emoji_vis()

	add_child(_emoji_toggle)
	_update_emoji_vis()
	# 开局问候: 本地模式随机一位 AI 打招呼(氛围)
	if mode == "local":
		var greet := func() -> void:
			if is_inside_tree() and not state.is_empty() 					and str(state.get("phase", "")) in ["play", "exchange"]:
				_bot_say("大家好，很高兴见到各位")
		get_tree().create_timer(1.6).timeout.connect(greet)

	# 文本聊天（仅联机模式）
	chat_log = _make_label(14, AppTheme.WHITE)
	chat_log.position = Vector2(16, 462)
	chat_log.custom_minimum_size = Vector2(296, 84)
	chat_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(chat_log)
	chat_edit = LineEdit.new()
	chat_edit.position = Vector2(360, 666)
	chat_edit.custom_minimum_size = Vector2(340, 36)
	chat_edit.placeholder_text = "说点什么…"
	chat_edit.max_length = 60
	chat_edit.add_theme_font_size_override("font_size", 15)
	chat_edit.text_submitted.connect(func(_t: String) -> void: _on_chat_send())
	add_child(chat_edit)
	chat_btn = _button("发送")
	chat_btn.position = Vector2(708, 662)
	# 紧凑小钮: 覆盖 _button 的触屏放大(与表情/操作行同排, 宽度受聊天区约束)
	var cb_min := Vector2(64, 48) if Responsive.is_touch() else Vector2(56, 36)
	chat_btn.custom_minimum_size = cb_min
	chat_btn.size = cb_min
	chat_btn.add_theme_font_size_override("font_size",
			18 if Responsive.is_touch() else 15)
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


## 对手信息面板: 头像内嵌 + 彩色信息(与自己面板同款样式)
## 对手座位基准位置(1280x720): 下家(右)/对家(上)/上家(左), _relayout 按屏幕重锚
const SEAT_PANEL_POS := [Vector2(996, 296), Vector2(420, 8), Vector2(16, 296)]


func _make_seat_panel(idx: int) -> Array:
	var pos: Vector2 = SEAT_PANEL_POS[idx]
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(Color(0.08, 0.08, 0.18, 0.92), Color(AppTheme.GOLD, 0.6), 12, 2)
	sb.content_margin_left = 8
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = pos
	panel.custom_minimum_size = Vector2(0, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var av := AvatarScript.new()
	av.custom_minimum_size = Vector2(44, 44)
	av.size = Vector2(44, 44)
	row.add_child(av)
	var lb := RichTextLabel.new()
	lb.bbcode_enabled = true
	lb.scroll_active = false
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lb.custom_minimum_size = Vector2(170 if Responsive.is_touch() else 140, 48)
	lb.add_theme_font_size_override("normal_font_size",
			16 if Responsive.is_touch() else 14)
	row.add_child(lb)
	return [panel, lb, av]


## 对局文字加细描边阴影, 深色桌面上更清晰
func _add_text_shadow(lb: Label) -> void:
	lb.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	lb.add_theme_constant_override("shadow_offset_x", 1)
	lb.add_theme_constant_override("shadow_offset_y", 1)


func _make_label(size: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", color)
	return lb


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	var sz := Vector2(116, 52) if Responsive.is_touch() else Vector2(96, 44)
	b.custom_minimum_size = sz
	b.size = sz
	b.add_theme_font_size_override("font_size", 21 if Responsive.is_touch() else 19)
	return b


## 音效统一入口: 隐藏的后台托管牌桌不发声 — 页面在首页时只应听到首页音乐
func _sfx(sfx_name: String) -> void:
	if visible:
		Audio.play(sfx_name)


## 触觉反馈(移动端): 轮到你/结算等关键时刻短震动
func _vibrate(ms: int) -> void:
	if Responsive.is_touch() and GameSettings.vibration:
		Input.vibrate_handheld(ms)


## 表达面板显隐: 😀 切换钮常显, 面板向上弹出(表情/快捷回复双 Tab);
## 本地模式同样可用(纯客户端气泡 + AI 随机回应), 联机走聊天广播。
func _update_emoji_vis() -> void:
	_emoji_toggle.visible = true
	if emoji_popup != null:
		emoji_popup.visible = _emoji_open
	_set_emoji_tab(_emoji_tab)


func _set_emoji_tab(tab: String) -> void:
	_emoji_tab = tab
	if emoji_grid == null or phrase_grid == null:
		return
	emoji_grid.visible = tab == "emoji"
	phrase_grid.visible = tab == "phrase"
	if _tab_emoji_btn != null:
		_tab_emoji_btn.set_pressed_no_signal(tab == "emoji")
	if _tab_phrase_btn != null:
		_tab_phrase_btn.set_pressed_no_signal(tab == "phrase")


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
	var my := int(view.get("my_seat", 0))
	# 表情从对应座位面板上方飘出(面板已随 _relayout 自适应)
	var pos := self_panel.position + Vector2(240, -90)
	if seat != my:
		var rel := (seat - my + 4) % 4
		if rel >= 1 and rel <= 3:
			var sp: Control = _seat_panels[rel - 1]
			pos = sp.position + Vector2(sp.size.x * 0.5, -64.0)
			if pos.y < 12.0:  # 对家面板贴顶 → 表情放面板下方
				pos.y = sp.position.y + sp.size.y + 12.0
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

## 响应式重排: 以设计基准 1280x720 为最小布局, 按实际可用区
## 重新锚定各区域 — 宽屏铺满全宽, 高屏上下扩展, 安全区由根偏移吸收。
func _relayout() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 100.0 or h < 100.0:
		return
	# 触屏加大尺寸 + 紧凑高度(手机逻辑视口 ~1248x576)双档布局
	var touch: bool = Responsive.is_touch()
	var compact: bool = h < 660.0
	var card_h := 134.0 if touch else 100.0
	var field_w := 760.0 if touch else 640.0
	var field_h := 280.0 if touch else 248.0
	if compact:
		field_w = 640.0   # 收窄让位两侧座位面板(面板 ~268 宽 + 左右余量)
		field_h = 236.0 if touch else 232.0
	var ops_h := 52.0 if touch else 44.0
	var ops_w := 494.0 if touch else 414.0   # 操作行满编宽度(4 钮 + 间距)
	# 顶部
	info_label.position = Vector2(20, 12)
	timer_label.position = Vector2(w - 100, 12)
	settings_btn.position = Vector2(w - 204, 10)
	rules_btn.position = Vector2(w - 308, 10)
	counter_toggle.position = Vector2(w - 412, 10)  # 96宽钮步进 104, 两两留 8px
	if counter_lbl != null:
		counter_lbl.position = Vector2(20, field_panel.size.y - 30.0)
		counter_lbl.size = Vector2(field_panel.size.x - 40.0, 22.0)
	if rogue_lbl != null:
		rogue_lbl.position = Vector2(w / 2.0 - 330.0, 12.0)
		rogue_lbl.custom_minimum_size = Vector2(660.0, 0)
		rogue_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 对家(上中) + 其牌背扇
	_seat_panels[1].position = Vector2(w / 2.0 - 230, 8)
	_opp_hands[1].position = Vector2(w / 2.0 + 60, 44)
	# 上家(左) 与 下家(右)
	_seat_panels[2].position = Vector2(16, h * 0.41)
	_opp_hands[2].position = Vector2(30, 50)
	_seat_panels[0].position = Vector2(w - 284, h * 0.41)
	_opp_hands[0].position = Vector2(w - 150, 108)
	# 操作行(先定位: 手牌让位) — 卡底不得压按钮; 且不与左侧聊天行重叠
	var ops_y := h - ops_h - 14.0
	var ops_x := maxf(w - 16.0 - (640.0 if touch else 420.0), 860.0)
	if compact:
		ops_x = w - 16.0 - ops_w   # 紧凑档右锚实宽, 4 触屏钮不溢出屏幕
	ops_row.position = Vector2(ops_x, ops_y)
	# 手牌区
	var hand_y := ops_y - 6.0 - 18.0 - card_h
	hand_box.position = Vector2(w - 1014, hand_y)
	hand_box.size = Vector2(1010, 28.0 + card_h)
	# 中央出牌区(水平居中; 顶不越过手牌抬起位)
	var field_x := (w - field_w) / 2.0
	var field_y: float = minf(204.0 + (h - 720.0) * 0.5, hand_y + 12.0 - field_h)
	field_panel.position = Vector2(field_x, field_y)
	field_panel.custom_minimum_size = Vector2(field_w, field_h)
	field_panel.size = Vector2(field_w, field_h)
	field_box.position = Vector2(20, 36)
	field_box.size = Vector2(field_w - 40, field_h - 64)
	# 紧凑档: 两侧座位面板上移至顶部带(避开出牌区), 牌背列上移至顶角(避开面板)
	if compact:
		_seat_panels[2].position = Vector2(16, 220)
		_seat_panels[0].position = Vector2(w - 284, 220)
		_opp_hands[2].position = Vector2(16, 8)
		_opp_hands[0].position = Vector2(w - 56, 8)
	# 底部: 自己面板 / 状态 / 错误
	self_panel.position = Vector2(16, h - 164)
	var status_y := h - 224.0
	var error_y := h - 250.0
	if field_y + field_h > status_y - 4.0:   # 高度不足: 状态/错误挪到场上方
		status_y = field_y - 30.0
		error_y = field_y - 56.0
	status_label.position = Vector2(field_x, status_y)
	status_label.custom_minimum_size = Vector2(field_w, 26)
	error_label.position = Vector2(field_x, error_y)
	error_label.custom_minimum_size = Vector2(field_w, 22)
	# 联机聊天(仅联机创建): 表情后固定左侧区(440..848), 与右锚操作行解耦;
	# 紧凑时输入行挪到顶部空带。发送钮尺寸在入树后补设(入树前赋值不生效)
	chat_btn.size = Vector2(64, 48) if touch else Vector2(56, 36)
	chat_log.position = Vector2(16, 120.0 if compact else h - 258.0)
	# 表情展开时聊天输入/发送右移让位(表情区 60..468)
	var chat_ex := 480.0 if _emoji_open else 440.0
	var send_x := 784.0 if _emoji_open else 744.0
	chat_edit.position = Vector2(chat_ex if not compact else 240.0,
			(8.0 if compact else (h - 58)))
	chat_btn.position = Vector2(send_x if not compact else 592.0,
			(8.0 if compact else (h - 58)))
	# 表达面板: 😀 钮贴底左; 面板固定锚在其上方(向上弹出)
	_emoji_toggle.position = Vector2(16, h - 58)
	if emoji_popup != null:
		emoji_popup.position = Vector2(16, h - 58.0 - 248.0 - 8.0)
	# 虚拟键盘避让: 聚焦聊天时底部整行抬到键盘上方
	if _kbd_shift > 0.0:
		chat_log.position.y -= _kbd_shift * 0.6
		chat_edit.position.y -= _kbd_shift
		chat_btn.position.y -= _kbd_shift
		if emoji_popup != null:
			emoji_popup.position.y -= _kbd_shift


func _refresh() -> void:
	if mode == "online":
		if net == null or (net.latest_view as Dictionary).is_empty():
			return
		_refresh_view(net.latest_view)
	elif not state.is_empty():
		_refresh_view(ViewGd.build(state, 0))


func _refresh_view(view: Dictionary) -> void:
	if view.is_empty() or not view.has("phase") \
			or not view.has("round") or not view.has("rounds_total"):
		return  # 服务器 view 尚未就绪, 跳过本帧刷新
	var phase: String = view["phase"]

	# 回合制展示: 一回合 = 3 局 → "第 X 回合 第 Y/Z 局"
	var round_num := int(view["round"]) + 1
	var rounds_total := int(view["rounds_total"])
	var in_round := (round_num - 1) % 3 + 1
	var round_idx := (round_num - 1) / 3 + 1
	var round_total := ceili(rounds_total / 3.0)
	info_label.text = "第 %d 回合 · 第 %d/%d 局    %s" % [
		round_idx, in_round, rounds_total,
		"革命!" if bool(view["revolution"]) else "",
	]

	var my := int(view["my_seat"])
	# 对手按相对方位入座: 右=下家, 上=对家, 左=上家
	for i in 3:
		var seat := (my + i + 1) % 4
		_opp_avatars[i].skin_id = _skin_for(view, seat)
		var lb: RichTextLabel = seat_labels[i + 1]
		lb.text = _seat_info_text(view, seat)
	if self_label != null:
		self_label.text = _seat_info_text(view, my)
	avatar_me.skin_id = _skin_for(view, my)
	_refresh_opp_hands(view)

	_refresh_field(view)
	_refresh_hand(view)

	# 革命检测（两种模式统一; 换局重置不播反革命）
	var rev: bool = bool(view["revolution"])
	if rev != _prev_revolution:
		_prev_revolution = rev
		if rev:
			_spawn_fx("revolution")
			Audio.play_bgm("table_rev")  # 革命: 切小调急板
		elif phase == "play":
			_spawn_fx("anti_revolution")
			Audio.play_bgm("rogue" if rogue else "table")  # 革命解除: 切回大调

	# 阶段切换: 交换过场 / 一落千丈(上局大富豪本轮垫底)
	if phase != _prev_phase:
		if phase == "exchange":
			_spawn_fx("exchange")
			_turn_total = float(int(view["rules"].get("exchange_seconds", 15)))
			_turn_remain = _turn_total
			_prev_tick = -1
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
	# 轮到你但压不过 → 自动"不要"(每回合一次; 手动选牌也没意义)
	if my_turn and not lead.is_empty() and str(view["phase"]) == "play":
		if not _auto_pass_done:
			_auto_pass_done = true
			var act: Dictionary = BotPlayerGd.decide_from_view(view)
			if str(act.get("t")) == "pass":
				_auto_pass()
				return
	elif not my_turn:
		_auto_pass_done = false
	# 轮到你: 状态文字金色呼吸脉冲(移动端视线不在屏幕中央也能注意到)
	if my_turn:
		if _pulse == null or not _pulse.is_valid():
			_pulse = create_tween().set_loops()
			_pulse.tween_property(status_label, "modulate",
					Color(1.4, 1.25, 0.75), 0.55)
			_pulse.tween_property(status_label, "modulate", Color.WHITE, 0.55)
	elif _pulse != null and _pulse.is_valid():
		_pulse.kill()
		_pulse = null
		status_label.modulate = Color.WHITE
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
		var er: Dictionary = _my_pending_return(view)
		if not er.is_empty():
			var remain_txt := "，剩余 %d 秒" % int(maxf(_turn_remain, 0.0)) if mode == "online" else ""
			status_label.text = "换牌：请选 %d 张返还给 %s（已选 %d%s）" % [
					int(er["n"]), _seat_name(view, int(er["to"])), selected.size(), remain_txt]
		elif int(view["turn"]) >= 0:
			status_label.text = "等待 %s 选牌返还…" % _seat_name(view, int(view["turn"]))
		else:
			status_label.text = "局间交换"
		status_label.add_theme_color_override("font_color", AppTheme.GOLD)
	elif phase == "round_end":
		status_label.text = "本局结束   " + _round_end_text(view)
		status_label.add_theme_color_override("font_color", AppTheme.GOLD)
	elif phase == "game_end":
		status_label.text = "全场结束！  " + _round_end_text(view)
		status_label.add_theme_color_override("font_color", AppTheme.GOLD)

	_update_rogue_lbl()
	var returning := not _my_pending_return(view).is_empty()
	btn_play.visible = my_turn or returning
	btn_play.text = "确认返还" if returning else "出牌"
	btn_hint.visible = my_turn
	btn_pass.visible = my_turn and not lead.is_empty()
	btn_rematch.visible = mode == "local" and phase == "game_end"
	btn_leave.visible = true
	btn_leave.text = "返回大厅" if mode == "online" else "返回菜单"

	# 终局演出（一次性）
	if phase == "game_end" and not _end_shown \
			and (view["identities"] as Array).size() == 4:
		_end_shown = true
		_sfx("result")
		_vibrate(80)  # 对局结束(移动端触感)
		var reward: Dictionary = {}
		if mode == "local":
			var seat_me := int(view["my_seat"])
			var my_rank := int(view["identities"][seat_me]) + 1  # 1=大富豪…4=大贫民
			var pts := int(view["scores"][seat_me])
			var stake_n := int(view["rules"].get("stakes", 1))
			reward = Wallet.grant_match_reward(pts, my_rank, stake_n)
			reward["wallet_gold"] = Wallet.gold
			reward["wallet_diamonds"] = Wallet.diamonds
			Wallet.push_history({
				"day": Time.get_date_string_from_system(),
				"mode": "肉鸽" if rogue else "本地",
				"rank": my_rank, "points": pts,
				"gold": int(reward["gold"]), "diamonds": int(reward["diamonds"]),
			})
		var panel := GameEndPanelScript.new()
		panel.setup(view, func(s: int) -> String: return _seat_name(view, s), reward)
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
	var real := _real_name(seat)
	if real != "":
		return real  # 联机: 显示真实昵称(座位面板位置已表达方位)
	var rel := (seat - my + 4) % 4
	var names := ["", "下家", "对家", "上家"]
	return names[rel]


## 联机房间的真实昵称(截断 6 字); 本地模式/机器人返回 ""(回退方位称呼)
func _real_name(seat: int) -> String:
	if mode != "online" or net == null:
		return ""
	for p in (net.last_room_state as Dictionary).get("players", []):
		if int(p.get("seat", -1)) != seat or bool(p.get("is_bot", false)) \
				or bool(p.get("empty", false)):
			continue
		var n := str(p.get("name", "")).strip_edges()
		if n == "":
			return ""
		if n.length() > 6:
			n = n.substr(0, 6) + "…"
		return n
	return ""


## 对手手牌: 重叠牌背(斗地主式), 数量跟随该座位剩牌数
## 增量增删(任一对手出牌只动差值, 不再整扇 39 张子树重建)
func _refresh_opp_hands(view: Dictionary) -> void:
	var my := int(view["my_seat"])
	var counts: Array = view["counts"]
	for i in 3:
		var box: Control = _opp_hands[i]
		var n := int(counts[(my + i + 1) % 4])
		if int(box.get_meta("count", -1)) == n:
			continue  # 数量未变不重建(消除每手 AI 动作的节点抖动)
		box.set_meta("count", n)
		var vert: bool = bool(box.get_meta("vert"))
		while box.get_child_count() > n:
			var dead: Control = box.get_child(box.get_child_count() - 1)
			box.remove_child(dead)
			dead.queue_free()
		while box.get_child_count() < n:
			var k := box.get_child_count()
			var cv := CardViewScript.new(-1)
			cv.face_down = true
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.custom_minimum_size = Vector2(40, 56)
			cv.size = Vector2(40, 56)
			cv.position = Vector2(0, k * 11) if vert else Vector2(k * 12, 0)
			box.add_child(cv)
		box.visible = n > 0


## 座位信息区文本: 名字 / 剩牌与积分 / 身份（出完才显示）
## 座位信息区(富文本): [身份]昵称 在前, 第二行 剩牌与积分
func _seat_info_text(view: Dictionary, seat: int) -> String:
	var gold := AppTheme.GOLD.to_html(false)
	var dim := AppTheme.DIM.to_html(false)
	var white := AppTheme.WHITE.to_html(false)
	var green := AppTheme.GREEN.to_html(false)
	var red := AppTheme.RED.to_html(false)
	var turn_mark := "[color=#%s]▶ [/color]" % gold if int(view["turn"]) == seat else ""
	# 当前身份(上局结算结果, 换牌与一落千丈的依据); 首局未定不显示
	var ids: Array = view["identities"]
	var id_colors := [gold, white, dim, red]
	var ident := ""
	if ids.size() == 4:
		var idn := int(ids[seat])
		ident = "[color=#%s]【%s】[/color]" % [id_colors[idn], ScoringGd.IDENTITY_NAMES[idn]]
	var sc := int(view["scores"][seat]) if (view["scores"] as Array).size() == 4 else 0
	var sc_col := green if sc > 0 else (red if sc < 0 else white)
	return "%s%s[color=#%s]%s[/color]\n[color=#%s]剩 %d 张 ·[/color] [color=#%s]积分 %+d[/color]" % [
		turn_mark, ident, white, _seat_name(view, seat),
		dim, int(view["counts"][seat]), sc_col, sc,
	]


func _round_end_text(view: Dictionary) -> String:
	var ids: Array = view["identities"]
	var pts: Array = view["last_points"]
	var parts: Array = []
	for s in 4:
		parts.append("%s=%s(%+d)" % [
			_seat_name(view, s), ScoringGd.IDENTITY_NAMES[int(ids[s])], int(pts[s]),
		])
	var mod := _rogue_mod_id_safe()
	if mod == "double_stakes":
		parts.append("命运卡: 结算×2")
	elif mod == "score_negate":
		parts.append("命运卡: 正负反转")
	return "  ".join(parts)


## 记牌器: 局初基数为各点数 4 张(命运卡『王者归来』王 4 张);
## 扣除本局已打出的, 余数=所有未出牌(含各家手牌与死牌)
func _counter_reset() -> void:
	_counter_played.clear()
	for v in range(3, 16):
		_counter_totals[v] = 4
	_counter_totals[16] = 4 if _rogue_mod_id_safe() == "joker_x2" else 2
	_update_counter()


func _rogue_mod_id_safe() -> String:
	if rogue and not state.is_empty():
		return str(state["cfg"].get("rogue_mod", ""))
	return ""


func _update_counter() -> void:
	if counter_lbl == null:
		return
	counter_lbl.visible = GameSettings.card_counter 			and str(state.get("phase", "")) in ["play", "exchange"]
	if not counter_lbl.visible:
		return
	var parts: Array = []
	for v in range(3, 16):
		var left := int(_counter_totals.get(v, 4)) - int(_counter_played.get(v, 0))
		parts.append("%s×%d" % [CardsGd.rank_label(v), left])
	parts.append("王×%d" % (int(_counter_totals.get(16, 2)) - int(_counter_played.get(16, 0))))
	counter_lbl.text = "  ".join(PackedStringArray(parts))


## 上轮回顾: 清桌后空场阶段常显上一轮各手(信息不因清桌丢失)
func _show_trick_recap() -> void:
	if trick_lbl == null:
		return
	var show := field_box.get_child_count() == 0 and not _last_trick.is_empty()
	trick_lbl.visible = show
	if show:
		var lines := _last_trick.slice(0, 3)
		trick_lbl.text = "上轮  " + "  |  ".join(PackedStringArray(lines))


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
	var grew := field.size() > _field_count and not field.is_empty()
	var emptied := field.is_empty()
	_field_count = field.size()
	if emptied:
		for child in field_box.get_children():
			child.queue_free()
		if _field_count == 0 and _had_field:
			_sfx("clear")  # 由有到无=清桌; 首次刷新(-1→0)不出声
			_last_trick = _trick_texts.duplicate()
			_trick_texts.clear()
			_show_trick_recap()
		_had_field = false
		return
	# 增量追加: 出牌只加最新一手(整排重建会闪一帧鬼影 — queue_free 延迟移除)
	if grew:
		var entry: Dictionary = field[field.size() - 1]
		for c in entry["combo"]["cards"]:
			var v := CardsGd.value(int(c))
			_counter_played[v] = int(_counter_played.get(v, 0)) + 1
		_update_counter()
		var labels: Array = []
		for c in entry["combo"]["cards"]:
			labels.append(CardsGd.label(int(c)))
		_trick_texts.append("%s: %s" % [_seat_name(view, int(entry["seat"])),
				" ".join(PackedStringArray(labels))])
		var holder := VBoxContainer.new()
		holder.add_theme_constant_override("separation", 2)
		var name_lb := _make_label(14, AppTheme.GOLD)
		name_lb.text = _seat_name(view, int(entry["seat"]))
		name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		holder.add_child(name_lb)
		var hz := HBoxContainer.new()
		hz.add_theme_constant_override("separation", 4)
		var fw := 70.0 if Responsive.is_touch() else 56.0
		var fh := 98.0 if Responsive.is_touch() else 78.0
		for c in entry["combo"]["cards"]:
			var old_card: Control = _make_card(int(c), fw, fh, false, false)
			old_card.modulate = Color.WHITE
			hz.add_child(old_card)
		holder.add_child(hz)
		field_box.add_child(holder)
		_had_field = true
		# 最新一手高亮: 淡入 + 弹性缩放; 上一手降为做旧
		var prev_idx := field_box.get_child_count() - 2
		if prev_idx >= 0:
			var prev: Control = field_box.get_child(prev_idx)
			prev.modulate = Color(0.75, 0.78, 0.92, 0.5)
			for lb in prev.get_children():
				if lb is Label:
					(lb as Label).add_theme_color_override("font_color", AppTheme.DIM)
		holder.pivot_offset = Vector2(120, 60)
		holder.modulate.a = 0.0
		holder.scale = Vector2(0.75, 0.75)
		var tw := holder.create_tween()
		tw.set_parallel(true)
		tw.tween_property(holder, "modulate:a", 1.0, 0.22)
		tw.tween_property(holder, "scale", Vector2.ONE, 0.22)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_sfx("play_card")
	else:
		# 手数变少(异常/回退): 全量重建兜底
		for child in field_box.get_children():
			child.queue_free()
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
			var fw := 70.0 if Responsive.is_touch() else 56.0
			var fh := 98.0 if Responsive.is_touch() else 78.0
			for c in entry["combo"]["cards"]:
				hz.add_child(_make_card(int(c), fw, fh, false, false))
			holder.add_child(hz)
			field_box.add_child(holder)


func _make_card(card_id: int, w: float, h: float, is_selected: bool, _clickable := true) -> Control:
	# 手牌输入统一由 hand_box 手势处理, 卡牌控件不接收鼠标(可整排拖动扫选)
	var cv := CardViewScript.new(card_id)
	cv.custom_minimum_size = Vector2(w, h)
	cv.size = Vector2(w, h)
	cv.selected = is_selected
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cv


## 手牌区统一手势(欢乐斗地主式横向扫选):
##   原地点击 = 单张翻转; 按住左右滑扫过 = 批量处理 — 模式由按下时
##   首张牌的状态钉定: 未选中→本次扫过全选, 已选中→本次扫过全取消。
## 输入统一在 hand_box 处理(拖动事件只发给按下控件, 跨卡扫选必须容器层做),
## 卡牌控件本身 mouse_filter=IGNORE。
var _drag_pressed := false
var _drag_active := false
var _drag_from := -1
var _drag_select := true
var _press_gx := 0.0


func _hand_index_at(local: Vector2) -> int:
	# 右压左叠放: 取包含该点的最大 index = 视觉最上层
	var best := -1
	for i in _hand_cards.size():
		var cv: Control = _hand_cards[i]
		if Rect2(cv.position, cv.size).has_point(local):
			best = i
	return best


func _set_card_selected(cv: Control, is_sel: bool) -> void:
	if is_sel:
		if not selected.has(cv.card):
			selected.append(cv.card)
	else:
		selected.erase(cv.card)
	cv.selected = is_sel
	_apply_hand_card_state(cv, is_sel)


func _on_hand_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_pressed = true
			_drag_active = false
			_drag_from = _hand_index_at(event.position)
			_press_gx = event.global_position.x
		else:
			_drag_pressed = false
			if not _drag_active and _drag_from >= 0:
				var cv: Control = _hand_cards[_drag_from]
				_set_card_selected(cv, not selected.has(cv.card))
				_sfx("click")
				_layout_hand()
			_drag_from = -1
			_drag_active = false
	elif event is InputEventMouseMotion and _drag_pressed and _drag_from >= 0:
		var dx: float = event.global_position.x - _press_gx
		if not _drag_active:
			if absf(dx) <= 14.0:
				return
			_drag_active = true
			_drag_select = not selected.has(_hand_cards[_drag_from].card)
			_sfx("click")
		var idx := _hand_index_at(event.position)
		if idx < 0:
			return
		for i in range(mini(_drag_from, idx), maxi(_drag_from, idx) + 1):
			var cv: Control = _hand_cards[i]
			if selected.has(cv.card) != _drag_select:
				_set_card_selected(cv, _drag_select)
		_layout_hand()


## 手牌：卡牌控件化；仅在手牌实际变化时重建并播放发牌动画。
func _refresh_hand(view: Dictionary) -> void:
	var hand: Array = view["hand"]
	if hand == _last_hand:
		# 只同步选中态
		var idx := 0
		for child in hand_box.get_children():
			if idx < hand.size():
				_apply_hand_card_state(child, selected.has(int(hand[idx])))
			idx += 1
		_layout_hand()
		return
	_last_hand = hand.duplicate()
	for child in hand_box.get_children():
		child.queue_free()
	_hand_cards.clear()
	# 手牌已变化: 清掉已不在手中的陈旧选牌(避免把不存在的牌发给服务器)
	selected = selected.filter(func(c: int) -> bool: return hand.has(c))
	var i := 0
	var hand_cw := 96.0 if Responsive.is_touch() else 72.0
	var hand_ch := 134.0 if Responsive.is_touch() else 100.0
	for c in hand:
		var card_id: int = c
		var is_sel := selected.has(card_id)
		var cv := _make_card(card_id, hand_cw, hand_ch, is_sel)
		hand_box.add_child(cv)
		_hand_cards.append(cv)
		_apply_hand_card_state(cv, is_sel)
		cv.modulate.a = 0.0
		var tw := cv.create_tween()  # 绑定卡牌节点: 重建释放时自动终止
		tw.tween_interval(0.02 * i)
		tw.tween_property(cv, "modulate:a", 1.0, 0.12)
		i += 1
	_layout_hand()
	if i > 0:
		_sfx("deal")


## 手牌排布: 排得下就等距, 排不下适当重叠(右牌压左牌, 露出左上点数)。
func _layout_hand() -> void:
	var n := _hand_cards.size()
	if n == 0:
		return
	var cw: float = _hand_cards[0].size.x
	var avail: float = hand_box.size.x if hand_box.size.x > 10.0 else 1010.0
	var step: float = cw + 6.0
	if n > 1 and step * (n - 1) + cw > avail:
		step = maxf((avail - cw) / float(n - 1), 34.0)
	for i in n:
		var cv: Control = _hand_cards[i]
		# 触屏选中抬升更深(扫选状态更醒目)
		var lift := (0.0 if Responsive.is_touch() else 4.0) \
				if selected.has(cv.card) else 18.0
		cv.position = Vector2(float(i) * step, lift)


## 手牌选中态视觉: 选中的上浮放大全亮, 未选中的微压暗
func _apply_hand_card_state(cv: Control, is_sel: bool) -> void:
	cv.pivot_offset = Vector2(cv.size.x / 2.0, cv.size.y)
	cv.scale = Vector2(1.07, 1.07) if is_sel else Vector2.ONE
	var a: float = cv.modulate.a
	cv.modulate = Color(1, 1, 1, a) if is_sel else Color(0.76, 0.78, 0.9, a)


# ---------------------------------------------------------------- 特效


func _spawn_fx(fx_type: String) -> void:
	var sounds := {
		"revolution": "revolution", "anti_revolution": "revolution",
		"eight_cut": "eight_cut", "fall": "fall", "exchange": "exchange",
	}
	_sfx(str(sounds.get(fx_type, "pop")))
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
			if rogue and _rogue_mod_id_safe() == "eight_gift":
				var gift_tw := get_tree().create_timer(0.9)
				gift_tw.timeout.connect(func() -> void:
					if is_inside_tree():
						_spawn_fx("eight_gift"))
			return
