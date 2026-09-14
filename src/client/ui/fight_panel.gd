## 格斗试炼(无尽模式)全屏页: 选牌(8选5) → 小怪战 → Boss战 → 下一层…
## 玩家化身头像人物; 5 张扑克 = 装备(♠物攻暴击/♦护甲魔抗/♥生命/♣法术);
## 牌型协同(同花顺/四条/葫芦/顺子…)自动生效; 死亡结算, 按层数发钻石。
extends Control

signal closed

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const FightModeGd = preload("res://src/rules/fight/fight_mode.gd")
const CardViewScript = preload("res://src/client/ui/card_view.gd")
const AvatarScript = preload("res://src/client/ui/avatar.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")

var fm: FightModeGd
var phase := "select"        # select / battle / over
var floor_num := 1
var _sel: Array = []
var _cards_ui: Array = []    # {wrap, sb, id, on}
var _busy := false
var _run_diamonds := 0
var _bosses_killed := 0

var header: Control
var back_btn: Button
var stage_lbl: Label
var select_box: VBoxContainer
var select_hint: Label
var cards_row: HBoxContainer
var combo_lbl: Label
var confirm_btn: Button
var battle_box: Control
var avatar: Control
var php_bar: ColorRect
var php_fg: ColorRect
var php_txt: Label
var e_lbl: Label
var e_glyph: Label
var ehp_bar: ColorRect
var ehp_fg: ColorRect
var ehp_txt: Label
var _vs_lbl: Label
var floaters: Control
var log_lbl: Label
var combo_chip: Label
var act_atk: Button
var act_skill: Button
var act_def: Button
var hand_row: HBoxContainer
var overlay: CenterContainer = null
var e_intent: Label = null
var bless_row: HBoxContainer = null
var _shake_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = get_parent_area_size()
	fm = FightModeGd.new()

	var bg := ColorRect.new()
	bg.color = Color("191934")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	header = preload("res://src/client/ui/p5_header.gd").new()
	header.text = "格斗试炼"
	header.icon = "card"
	header.position = Vector2(36, 22)
	header.custom_minimum_size = Vector2(420, 54)
	header.size = Vector2(420, 54)
	add_child(header)

	stage_lbl = AppTheme.make_label(20, AppTheme.GOLD)
	stage_lbl.position = Vector2(480, 34)
	add_child(stage_lbl)

	var help_btn := AppTheme.make_button("?", Vector2(42, 42), 20)
	help_btn.position = Vector2(1064, 26)
	help_btn.pressed.connect(func() -> void:
		Audio.play("click")
		var fh: Control = (load("res://src/client/ui/fight_help.gd") as GDScript).new()
		fh.closed.connect(func() -> void: fh.queue_free())
		add_child(fh))
	add_child(help_btn)
	back_btn = AppTheme.make_button("放弃试炼", Vector2(130, 42), 15)
	back_btn.position = Vector2(1120, 26)
	back_btn.pressed.connect(func() -> void:
		Audio.play("click")
		if phase == "select":
			closed.emit()
			queue_free()
		else:
			_finish_run())
	add_child(back_btn)

	# ── 选牌阶段 ──
	select_box = VBoxContainer.new()
	select_box.position = Vector2(40, 110)
	select_box.custom_minimum_size = Vector2(1200, 560)
	select_box.add_theme_constant_override("separation", 16)
	add_child(select_box)
	select_hint = AppTheme.make_label(18, AppTheme.WHITE)
	select_hint.text = "第 %d 层 — 从 8 张牌中选择 5 张装备\n(♠物攻暴击 ♦护甲魔抗 ♥生命 ♣法术)" % floor_num
	select_box.add_child(select_hint)
	combo_lbl = AppTheme.make_label(16, AppTheme.GOLD)
	combo_lbl.text = "已选 0/5 · 选满 5 张显示牌型"
	select_box.add_child(combo_lbl)
	cards_row = HBoxContainer.new()
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.add_theme_constant_override("separation", 14)
	select_box.add_child(cards_row)
	var cc := CenterContainer.new()
	confirm_btn = AppTheme.make_button("出 战", Vector2(240, 52), 20)
	confirm_btn.disabled = true
	confirm_btn.pressed.connect(func() -> void:
		Audio.play("win")
		_start_battle())
	cc.add_child(confirm_btn)
	select_box.add_child(cc)
	_fill_candidates()

	# ── 战斗阶段(自由布局: 血条/敌我位置手工摆放, 不可用 VBox 堆叠) ──
	battle_box = Control.new()
	battle_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	battle_box.visible = false
	add_child(battle_box)

	avatar = AvatarScript.new()
	avatar.custom_minimum_size = Vector2(150, 150)
	avatar.size = Vector2(150, 150)
	avatar.position = Vector2(180, 250)
	battle_box.add_child(avatar)
	var pname := AppTheme.make_label(17, AppTheme.WHITE)
	pname.text = str(GameSettings.nickname)
	pname.position = Vector2(170, 410)
	battle_box.add_child(pname)
	php_bar = ColorRect.new()
	php_bar.color = Color(0, 0, 0, 0.6)
	php_bar.position = Vector2(165, 442)
	php_bar.size = Vector2(280, 20)
	battle_box.add_child(php_bar)
	php_fg = ColorRect.new()
	php_fg.color = Color("58c858")
	php_fg.position = Vector2(2, 2)
	php_bar.add_child(php_fg)
	php_txt = _label(13, AppTheme.WHITE)
	php_txt.position = Vector2(165, 464)
	battle_box.add_child(php_txt)

	e_lbl = _label(17, AppTheme.WHITE)
	e_lbl.position = Vector2(880, 210)
	e_lbl.custom_minimum_size = Vector2(280, 26)
	e_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle_box.add_child(e_lbl)
	e_intent = _label(14, Color("ffb14e"))
	e_intent.position = Vector2(880, 178)
	e_intent.custom_minimum_size = Vector2(280, 24)
	e_intent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle_box.add_child(e_intent)
	e_glyph = _label(96, AppTheme.WHITE)
	e_glyph.position = Vector2(940, 240)
	battle_box.add_child(e_glyph)
	ehp_bar = ColorRect.new()
	ehp_bar.color = Color(0, 0, 0, 0.6)
	ehp_bar.position = Vector2(860, 380)
	ehp_bar.size = Vector2(280, 20)
	battle_box.add_child(ehp_bar)
	ehp_fg = ColorRect.new()
	ehp_fg.color = Color("d05050")
	ehp_fg.position = Vector2(2, 2)
	ehp_bar.add_child(ehp_fg)
	ehp_txt = _label(13, AppTheme.WHITE)
	ehp_txt.position = Vector2(860, 402)
	battle_box.add_child(ehp_txt)

	_vs_lbl = _label(30, AppTheme.GOLD)
	_vs_lbl.text = "VS"
	_vs_lbl.position = Vector2(size.x / 2.0 - 24.0, size.y * 0.44)
	battle_box.add_child(_vs_lbl)

	floaters = Control.new()
	floaters.set_anchors_preset(Control.PRESET_FULL_RECT)
	floaters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_box.add_child(floaters)

	log_lbl = _label(14, Color("c9b06a"))
	log_lbl.position = Vector2(40, 500)
	log_lbl.custom_minimum_size = Vector2(420, 160)
	log_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	battle_box.add_child(log_lbl)

	combo_chip = AppTheme.make_label(16, AppTheme.GOLD)
	combo_chip.position = Vector2(520, 120)
	combo_chip.custom_minimum_size = Vector2(320, 26)
	combo_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle_box.add_child(combo_chip)
	bless_row = HBoxContainer.new()
	bless_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bless_row.add_theme_constant_override("separation", 8)
	bless_row.position = Vector2(440, 152)
	bless_row.custom_minimum_size = Vector2(400, 24)
	battle_box.add_child(bless_row)

	act_atk = AppTheme.make_button("⚔ 攻击", Vector2(170, 56), 18)
	act_skill = AppTheme.make_button("✨ 技能", Vector2(170, 56), 18)
	act_def = AppTheme.make_button("🛡 防御", Vector2(170, 56), 18)
	act_atk.pressed.connect(func() -> void: _on_action("attack"))
	act_skill.pressed.connect(func() -> void: _on_action("skill"))
	act_def.pressed.connect(func() -> void: _on_action("defend"))
	hand_row = HBoxContainer.new()
	hand_row.add_theme_constant_override("separation", 6)
	hand_row.position = Vector2(40, 620)
	battle_box.add_child(hand_row)
	var acts := HBoxContainer.new()
	acts.alignment = BoxContainer.ALIGNMENT_CENTER
	acts.add_theme_constant_override("separation", 20)
	acts.position = Vector2(340, 620)
	acts.custom_minimum_size = Vector2(600, 56)
	acts.add_child(act_atk)
	acts.add_child(act_skill)
	acts.add_child(act_def)
	battle_box.add_child(acts)

	Responsive.watch(self, _relayout)


## 多设备自适应: 顶栏锚边, 战斗列按窗口比例摆位, 血条跟角色走
func _relayout() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	back_btn.position = Vector2(w - 150.0, 26)
	stage_lbl.position = Vector2(w / 2.0 - 120.0, 34)
	select_box.size = Vector2(w - 80.0, h - 140.0)
	avatar.position = Vector2(w * 0.14, h * 0.34)
	php_bar.position = avatar.position + Vector2(-15.0, 162.0)
	php_txt.position = php_bar.position + Vector2(0.0, 22.0)
	e_lbl.position = Vector2(w * 0.68, h * 0.28)
	e_intent.position = Vector2(w * 0.68, h * 0.28 - 30.0)
	e_glyph.position = Vector2(w * 0.70, h * 0.33)
	ehp_bar.position = Vector2(w * 0.67, h * 0.53)
	ehp_txt.position = Vector2(w * 0.67, h * 0.53 + 22.0)
	_vs_lbl.position = Vector2(w / 2.0 - 24.0, h * 0.44)
	log_lbl.position = Vector2(40, h - 210.0)
	combo_chip.position = Vector2(w / 2.0 - 160.0, 120.0)
	hand_row.position = Vector2(40, h - 96.0)


func _label(size_num: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size_num)
	lb.add_theme_color_override("font_color", color)
	return lb


## ── 选牌阶段 ──
func _fill_candidates() -> void:
	var cands: Array = fm.draw_candidates(8)
	for c in cands:
		var wrap := PanelContainer.new()
		var sb := AppTheme.flat(Color(0.10, 0.10, 0.22), Color(1, 1, 1, 0.2), 8, 1)
		wrap.add_theme_stylebox_override("panel", sb)
		var cv: Control = CardViewScript.new(int(c))
		cv.custom_minimum_size = Vector2(96, 134)
		cv.size = Vector2(96, 134)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(cv)
		var id := int(c)
		wrap.mouse_filter = Control.MOUSE_FILTER_STOP
		wrap.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_LEFT:
				_toggle_select(wrap, sb, id))
		cards_row.add_child(wrap)
		_cards_ui.append({"wrap": wrap, "sb": sb, "id": id, "on": false})


func _toggle_select(wrap: PanelContainer, sb: StyleBoxFlat, id: int) -> void:
	Audio.play("click")
	var entry: Dictionary = {}
	for e in _cards_ui:
		if int(e["id"]) == id:
			entry = e
	if entry.is_empty():
		return
	var on: bool = not bool(entry["on"])
	if on and _sel.size() >= 5:
		_flash("最多装备 5 张")
		return
	entry["on"] = on
	if on:
		_sel.append(id)
	else:
		_sel.erase(id)
	sb.border_color = AppTheme.GOLD if on else Color(1, 1, 1, 0.2)
	sb.set_border_width_all(3 if on else 1)
	var info := "选满 5 张生效"
	if _sel.size() == 5:
		var c: Dictionary = FightModeGd.evaluate_combo(_sel)
		info = "牌型: %s(%s)" % [c["name"], c["desc"]]
	combo_lbl.text = "已选 %d/5 · %s" % [_sel.size(), info]
	confirm_btn.disabled = _sel.size() != 5


func _flash(text: String) -> void:
	select_hint.text = text
	select_hint.add_theme_color_override("font_color", AppTheme.RED)


## ── 战斗阶段 ──
func _start_battle() -> void:
	fm.equip(_sel)  # 派生属性+生成牌型(此前仅 UI 预览)
	phase = "battle"
	select_box.visible = false
	battle_box.visible = true
	Audio.play_bgm("table")
	for id in _sel:
		var cv: Control = CardViewScript.new(int(id))
		cv.custom_minimum_size = Vector2(60, 84)
		cv.size = Vector2(60, 84)
		hand_row.add_child(cv)
	_next_encounter()
	_refresh_bars()
	_refresh_combo_chip()
	_refresh_actions()


func _next_encounter() -> void:
	fm.next_encounter()
	e_lbl.text = str(fm.enemy["name"])
	e_intent.text = "意图: %s" % _intent_text()
	e_glyph.text = str(fm.enemy["glyph"])
	stage_lbl.text = "第 %d 层 · %s" % [floor_num, fm.stage_label()]
	_log_clear()
	_log("%s 出现! (HP %d)" % [str(fm.enemy["name"]), int(fm.enemy["max_hp"])])
	_refresh_bars()


func _refresh_bars() -> void:
	var mh: int = maxi(int(fm.stats["max_hp"]), 1)
	php_fg.size = Vector2(276.0 * clampi(fm.hp, 0, mh) / float(mh), 16)
	php_txt.text = "HP %d / %d" % [maxi(fm.hp, 0), mh]
	if not fm.enemy.is_empty():
		var eh: int = maxi(int(fm.enemy["max_hp"]), 1)
		ehp_fg.size = Vector2(276.0 * clampi(int(fm.enemy["hp"]), 0, eh) / float(eh), 16)
		ehp_txt.text = "HP %d / %d" % [maxi(int(fm.enemy["hp"]), 0), eh]


func _refresh_combo_chip() -> void:
	combo_chip.text = "牌型: %s — %s" % [str(fm.combo["name"]), str(fm.combo["desc"])]


func _refresh_actions() -> void:
	var cd := int(fm._skill_cd)
	var kind := str(fm.stats.get("skill_kind", "fire"))
	var icon := "🔥" if kind == "fire" else ("❄" if kind == "frost" else "✟")
	var label := "火球" if kind == "fire" else ("冰霜" if kind == "frost" else "圣光")
	act_skill.disabled = cd > 0
	act_skill.text = ("%s %s" % [icon, label]) if cd <= 0 			else ("%s 冷却 %d" % [icon, cd])


func _on_action(action: String) -> void:
	if _busy or phase != "battle":
		return
	_busy = true
	var evs: Array = fm.step(action)
	_run_events(evs)


## 顺序播放事件(飘字/血条), 完毕后处理阶段推进
func _run_events(evs: Array) -> void:
	if evs.is_empty():
		_after_events()
		return
	var ev = evs.pop_front()
	var kind := str(ev["kind"])
	var is_enemy_target := str(ev["who"]) == "e"
	var tx: float = 980.0 if is_enemy_target else 260.0
	var ty: float = 300.0 if is_enemy_target else 280.0
	match kind:
		"crit":
			_floater("暴击 -%d" % int(ev["v"]), tx, ty, Color("ffd166"))
			_sfx("play_card" if not is_enemy_target else "fall")
		"skill":
			var sk := str(ev.get("skill_kind", "fire"))
			var scol := Color("7ec8ff") if sk == "frost" 					else (Color("7dd87d") if sk == "light" else Color("ff9a3d"))
			var stxt: String = str({"fire": "火球", "frost": "冰霜",
					"light": "圣光"}.get(sk, "技能"))
			_floater("%s -%d" % [stxt, int(ev["v"])], tx, ty, scol)
			_sfx("exchange" if not is_enemy_target else "fall")
		"heavy":
			_floater("重击 -%d" % int(ev["v"]), tx, ty, Color("ff5050"))
			_sfx("fall")
		"dmg":
			_floater("-%d" % int(ev["v"]), tx, ty,
					AppTheme.RED if is_enemy_target else Color("ff8866"))
			_sfx("play_card" if not is_enemy_target else "fall")
		"heal":
			_floater("+%d" % int(ev["v"]), 260.0, 240.0, Color("7dd87d"))
		"defend":
			_floater("防御", 260.0, 240.0, Color("7ec8ff"))
		"die":
			_floater("击破!", 980.0, 280.0, AppTheme.GOLD)
			if bool(fm.enemy.get("is_boss", false)):
				_bosses_killed += 1
	if is_enemy_target and not e_glyph.has_tween():
		var flash := create_tween()
		flash.tween_property(e_glyph, "modulate", Color(2.5, 1.2, 1.2), 0.06)
		flash.tween_property(e_glyph, "modulate", Color.WHITE, 0.18)
	if not is_enemy_target:
		_shake(8.0 if kind == "heavy" else 4.0)
	# 冲撞演出: 施攻方朝受方突进再回位
	var lunge_from: float = avatar.position.x + 150.0 			if not is_enemy_target else e_glyph.position.x + 40.0
	var lunge_to: float = avatar.position.x + 210.0 			if not is_enemy_target else e_glyph.position.x - 60.0
	var target: Control = avatar if not is_enemy_target else e_glyph
	var lt := create_tween()
	lt.tween_property(target, "position:x", lunge_to, 0.12)
	lt.tween_property(target, "position:x", target.position.x, 0.16)
	_refresh_bars()
	_refresh_actions()
	if kind == "dmg" or kind == "heavy":
		e_intent.text = "意图: %s" % _intent_text()
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void: _run_events(evs))


func _after_events() -> void:
	if fm.player_dead():
		_finish_run()
		return
	if fm.encounter_cleared():
		fm.advance_stage()               # mob→boss→clear
		if fm.all_stages_cleared():
			_floor_cleared()             # 本层通关(祝福三选一)
		else:
			_next_encounter()            # 下一场: Boss(或小怪)
			_refresh_actions()
			_busy = false
		return
	_busy = false


## ── 通关/终局 ──
func _floor_cleared() -> void:
	fm.advance_stage()
	var r: Dictionary = Wallet.grant_fight_reward(floor_num)
	_run_diamonds += int(r["diamonds"])
	Wallet.note_mission("m_fight")
	_show_blessing_draft("奖励: %+d 钻石 · 本局累计 %d 钻" % [
				int(r["diamonds"]), _run_diamonds])


func _finish_run() -> void:
	if phase == "over":
		return
	phase = "over"
	var r: Dictionary = Wallet.grant_fight_reward(floor_num, _bosses_killed)
	_run_diamonds += int(r["diamonds"])
	Wallet.push_history({
		"day": Time.get_date_string_from_system(),
		"mode": "格斗", "floor": floor_num, "rank": 0, "points": 0,
		"gold": 0, "diamonds": _run_diamonds,
	})
	_show_overlay("试炼结束",
			"到达第 %d 层 · 历史最佳第 %d 层\n奖励: %d 钻石 已入账" % [
				floor_num, int(r["best"]), _run_diamonds],
			"返回菜单",
			func() -> void:
				_close_overlay()
				closed.emit()
				queue_free())


func _show_overlay(title: String, body: String, btn_text: String,
		on_btn: Callable) -> void:
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = CenterContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
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
	var t := AppTheme.make_label(30, AppTheme.GOLD)
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var b := AppTheme.make_label(16, AppTheme.WHITE)
	b.text = body
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(b)
	var cc := CenterContainer.new()
	var btn := AppTheme.make_button(btn_text, Vector2(240, 50), 18)
	btn.pressed.connect(func() -> void:
		Audio.play("click")
		on_btn.call())
	cc.add_child(btn)
	box.add_child(cc)
	add_child(overlay)


func _close_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null


## ── 演出辅助 ──
func _floater(text: String, x: float, y: float, col: Color) -> void:
	var lb := _label(24, col)
	lb.text = text
	lb.position = Vector2(x, y)
	lb.z_index = 10
	floaters.add_child(lb)
	var tw := lb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lb, "position:y", y - 56.0, 0.6)
	tw.tween_property(lb, "modulate:a", 0.0, 0.6).set_delay(0.1)
	tw.chain().tween_callback(lb.queue_free)


func _log(text: String) -> void:
	log_lbl.text = log_lbl.text + "\n" + text if log_lbl.text != "" else text
	var lines := log_lbl.text.split("\n")
	if lines.size() > 5:
		log_lbl.text = "\n".join(lines.slice(lines.size() - 5))


func _log_clear() -> void:
	log_lbl.text = ""


func _intent_text() -> String:
	if fm.enemy.is_empty():
		return ""
	var it := str(fm.enemy.get("intent", "attack"))
	if it == "heavy":
		return "💥 重击(防御可减!)"
	if it == "spell":
		return "🔥 法术(魔抗可减!)"
	return "⚔ 攻击"


## 打击感: 战斗区随机抖动后回位
func _shake(strength: float) -> void:
	if _shake_t > 0.0:
		return
	_shake_t = 0.18
	var tw := create_tween()
	for i in 5:
		var off := Vector2(rng_off(), rng_off()) * strength * 0.4
		tw.tween_property(battle_box, "position",
				Vector2.ZERO + off, 0.035)
	tw.tween_property(battle_box, "position", Vector2.ZERO, 0.035)


func rng_off() -> float:
	return randf_range(-1.0, 1.0)


## 祝福徽章刷新
func _refresh_bless_chips() -> void:
	for c in bless_row.get_children():
		c.queue_free()
	for b_id in fm.blessings:
		var chip := AppTheme.make_label(13, AppTheme.GOLD)
		var bname := ""
		for b in FightModeGd.BLESSINGS:
			if str(b["id"]) == str(b_id):
				bname = str(b["name"])
		chip.text = "·%s·" % bname
		bless_row.add_child(chip)


## 通关三选一祝福
func _show_blessing_draft(reward_text: String) -> void:
	var picks: Array = fm.roll_blessings()
	overlay = CenterContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(AppTheme.PANEL, AppTheme.GOLD, 16, 2)
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 26
	sb.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", sb)
	overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var t := AppTheme.make_label(30, AppTheme.GOLD)
	t.text = "第 %d 层 通关!" % floor_num
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var b := AppTheme.make_label(15, AppTheme.WHITE)
	b.text = reward_text + "
选择一项祝福(立即生效, 可叠加):"
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(b)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for m in picks:
		var mid := str(m["id"])
		var btn := AppTheme.make_button("%s
%s" % [str(m["name"]), str(m["desc"])],
				Vector2(190, 76), 14)
		btn.pressed.connect(func() -> void:
			Audio.play("win")
			fm.add_blessing(mid)
			_refresh_bless_chips()
			_after_blessing(mid))
		row.add_child(btn)
	var skip_cc := CenterContainer.new()
	var skip := AppTheme.make_button("跳过(不选祝福)", Vector2(220, 42), 14)
	skip.pressed.connect(func() -> void:
		Audio.play("click")
		_after_blessing(null))
	skip_cc.add_child(skip)
	box.add_child(skip_cc)
	add_child(overlay)


func _after_blessing(_picked) -> void:
	_goto_next_floor()


func _goto_next_floor() -> void:
	_close_overlay()
	floor_num += 1
	fm.next_floor()
	fm.equip(fm.hand)
	phase = "battle"
	for c in hand_row.get_children():
		c.queue_free()
	for id in fm.hand:
		var cv: Control = CardViewScript.new(int(id))
		cv.custom_minimum_size = Vector2(60, 84)
		cv.size = Vector2(60, 84)
		hand_row.add_child(cv)
	stage_lbl.text = "第 %d 层 · 小怪战" % floor_num
	_next_encounter()
	_refresh_bars()
	_refresh_combo_chip()
	_refresh_bless_chips()
	_refresh_actions()
	_busy = false


## 音效统一入口(与牌桌同款: 页面隐藏时不发声)
func _sfx(sfx_name: String) -> void:
	if visible:
		Audio.play(sfx_name)
