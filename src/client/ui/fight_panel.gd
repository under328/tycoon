## 格斗试炼(回合制)全屏页: 每回合『二选一』抽牌 → 编成左上 5 槽装备 →
## 小怪/精英/Boss 战(R1 小怪 R2 小怪 R3 精英 R4 小怪 R5 BOSS)。
## 特殊牌不占槽: 抽到立即生效并补抽普通牌, 保证 Boss 战恰好 5 张。
## 怪物形象按主题组像素画; 玩家按皮肤演出攻击动作。纯渲染+输入, 规则在引擎。
extends Control

signal closed

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const FightModeGd = preload("res://src/rules/fight/fight_mode.gd")
const CardsGd = preload("res://src/rules/cards.gd")
const CardViewScript = preload("res://src/client/ui/card_view.gd")
const MonsterViewScript = preload("res://src/client/ui/monster_view.gd")
const AvatarScript = preload("res://src/client/ui/avatar.gd")
const SkinsLib = preload("res://src/client/ui/skins.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")

var daily := false           # 每日挑战: 当日固定种子, 结算计入每日最佳
var fm: FightModeGd
var phase := "run"           # run(试炼中) / over(已结束)
var _run_diamonds := 0
var _busy := false
var _pending_cand := -1      # 槽满替换: 待放入的候选
var _voice_phase := ""       # 语音: 已播报的引擎阶段(切换时播报)
var _banner: Label = null
var _slot_ui: Array = []     # {wrap, sb, card} 装备槽
var _sp_row: HBoxContainer = null
var _combo_lbl: Label = null

var header: Control
var back_btn: Button
var help_btn: Button
var round_lbl: Label
var slots_box: VBoxContainer
var player_box: Control
var avatar: Control
var php_fg: ColorRect
var php_txt: Label
var shield_fg: ColorRect
var enemy_box: Control
var monster: Control
var ehp_fg: ColorRect
var ehp_txt: Label
var ehp_bar: Control
var e_name: Label
var e_intent: Label
var floaters: Control
var log_lbl: Label
var act_row: HBoxContainer
var act_atk: Button
var act_skill: Button
var act_def: Button
var draft_panel: PanelContainer
var _aura: Control            # 变身光环(五张集满显示, 随主花色变色)
var _aura_spin := 0.0
var _transform_floor := -1    # 已播变身演出的层(每层首次集满五张触发)
var _bg: ColorRect            # 战斗背景(随怪群主题变色)
# 每怪群背景色调: 翡翠森林/回声洞穴/熔火之心/冰封雪原/幽暗墓地
const GROUP_TINTS := [Color("16281a"), Color("221a38"), Color("341a12"),
		Color("122530"), Color("261a2e")]
var draft_title: Label
var cand_row: HBoxContainer
var draft_ops: HBoxContainer
var battle_box: Control
var _shake_t := 0.0
var overlay: CenterContainer = null   # 结算弹窗(成员持有, 关闭可靠)
var fury_bar: ColorRect
var fury_fg: ColorRect
var hits_lbl: Label
var act_ult: Button
var _bob_t := 0.0
var _player_home: Vector2
var _enemy_home: Vector2


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = get_parent_area_size()
	fm = FightModeGd.new(Wallet.daily_seed()) if daily \
			else FightModeGd.new()
	fm.hard = daily   # 每日挑战: 怪物 HP/攻击 +25%, 玩家伤害 -20%
	if daily:
		Wallet.mark_daily_played()   # 每日一次: 开局即占用当日名额
	Audio.play_bgm("fight")   # 格斗专属战斗曲
	if daily:
		Audio.say("daily_start", 1.0, true)   # 每日挑战开场播报

	_bg = ColorRect.new()
	_bg.color = Color("191934")
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	header = preload("res://src/client/ui/p5_header.gd").new()
	header.text = "每日挑战" if daily else "格斗试炼"
	header.icon = "card"
	header.position = Vector2(36, 22)
	header.custom_minimum_size = Vector2(360, 54)
	header.size = Vector2(360, 54)
	add_child(header)

	round_lbl = AppTheme.make_label(19, AppTheme.GOLD)
	add_child(round_lbl)

	help_btn = AppTheme.make_button("?", Vector2(42, 42), 20)
	help_btn.position = Vector2(1040, 26)
	help_btn.pressed.connect(func() -> void:
		Audio.play("click")
		var fh: Control = (load("res://src/client/ui/fight_help.gd") as GDScript).new()
		fh.closed.connect(func() -> void: fh.queue_free())
		add_child(fh))
	add_child(help_btn)
	back_btn = AppTheme.make_button("放弃试炼", Vector2(130, 42), 15)
	back_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_finish_run())
	add_child(back_btn)

	# ── 左上: 装备槽(5) + 奇物 + 牌型 ──
	slots_box = VBoxContainer.new()
	slots_box.add_theme_constant_override("separation", 4)
	add_child(slots_box)
	var slots_title := AppTheme.make_label(14, AppTheme.DIM)
	slots_title.text = "装备槽"
	slots_box.add_child(slots_title)
	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 6)
	slots_box.add_child(slots_row)
	for i in 5:
		var wrap := PanelContainer.new()
		var sb := AppTheme.flat(Color(0.06, 0.06, 0.14),
				Color(1, 1, 1, 0.25), 6, 1)
		# 边框内边距: 卡牌与边框留出呼吸感, 不再顶边贴边
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		wrap.add_theme_stylebox_override("panel", sb)
		wrap.custom_minimum_size = Vector2(56, 78)
		wrap.mouse_filter = Control.MOUSE_FILTER_STOP
		var idx := i
		wrap.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_LEFT:
				_on_slot_clicked(idx))
		slots_row.add_child(wrap)
		_slot_ui.append({"wrap": wrap, "sb": sb, "card": -1})
	var sp_row2 := HBoxContainer.new()
	sp_row2.add_theme_constant_override("separation", 4)
	slots_box.add_child(sp_row2)
	_sp_row = sp_row2
	_combo_lbl = AppTheme.make_label(13, AppTheme.GOLD)
	slots_box.add_child(_combo_lbl)

	# ── 战场: 玩家(左) / 怪物(右) ──
	battle_box = Control.new()
	battle_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	battle_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(battle_box)

	avatar = AvatarScript.new()
	avatar.custom_minimum_size = Vector2(140, 140)
	avatar.size = Vector2(140, 140)
	battle_box.add_child(avatar)
	var pname := AppTheme.make_label(16, AppTheme.WHITE)
	pname.text = str(GameSettings.nickname)
	battle_box.add_child(pname)
	var php_bar := ColorRect.new()
	php_bar.color = Color(0, 0, 0, 0.6)
	php_bar.size = Vector2(240, 18)
	battle_box.add_child(php_bar)
	php_fg = ColorRect.new()
	php_fg.color = Color("58c858")
	php_fg.position = Vector2(2, 2)
	php_bar.add_child(php_fg)
	php_txt = _label(12, AppTheme.WHITE)
	battle_box.add_child(php_txt)
	var shield_bar := ColorRect.new()
	shield_bar.color = Color(0, 0, 0, 0.35)
	shield_bar.size = Vector2(240, 6)
	battle_box.add_child(shield_bar)
	shield_fg = ColorRect.new()
	shield_fg.color = Color("6ad0e8")
	shield_bar.add_child(shield_fg)

	monster = MonsterViewScript.new()
	monster.custom_minimum_size = Vector2(230, 230)
	monster.size = Vector2(230, 230)
	battle_box.add_child(monster)
	e_name = AppTheme.make_label(18, AppTheme.WHITE)
	e_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e_name.custom_minimum_size = Vector2(260, 24)
	battle_box.add_child(e_name)
	e_intent = _label(14, Color("ffb14e"))
	e_intent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e_intent.custom_minimum_size = Vector2(260, 20)
	battle_box.add_child(e_intent)
	ehp_bar = ColorRect.new()
	ehp_bar.color = Color(0, 0, 0, 0.6)
	ehp_bar.size = Vector2(240, 18)
	battle_box.add_child(ehp_bar)
	ehp_fg = ColorRect.new()
	ehp_fg.color = Color("d05050")
	ehp_fg.position = Vector2(2, 2)
	ehp_bar.add_child(ehp_fg)
	ehp_txt = _label(12, AppTheme.WHITE)
	battle_box.add_child(ehp_txt)

	# 怒气条(奥义能量, 金色)
	fury_bar = ColorRect.new()
	fury_bar.color = Color(0, 0, 0, 0.45)
	fury_bar.size = Vector2(240, 8)
	battle_box.add_child(fury_bar)
	fury_fg = ColorRect.new()
	fury_fg.color = Color("ffd166")
	fury_bar.add_child(fury_fg)
	# 连击大字(中央)
	hits_lbl = _label(44, Color("ffd166"))
	hits_lbl.visible = false
	hits_lbl.z_index = 15
	battle_box.add_child(hits_lbl)
	floaters = Control.new()
	floaters.set_anchors_preset(Control.PRESET_FULL_RECT)
	floaters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_box.add_child(floaters)

	log_lbl = _label(13, Color("c9b06a"))
	log_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_lbl.custom_minimum_size = Vector2(430, 120)
	add_child(log_lbl)

	# ── 战斗操作按钮 ──
	act_row = HBoxContainer.new()
	act_row.alignment = BoxContainer.ALIGNMENT_CENTER
	act_row.add_theme_constant_override("separation", 16)
	add_child(act_row)
	act_atk = AppTheme.make_button("⚔ 攻击", Vector2(160, 56), 18)
	act_skill = AppTheme.make_button("✨ 技能", Vector2(160, 56), 18)
	act_def = AppTheme.make_button("🛡 防御", Vector2(160, 56), 18)
	act_ult = AppTheme.make_button("⚡ 奥义", Vector2(160, 56), 18)
	act_ult.disabled = true
	act_atk.pressed.connect(func() -> void: _on_action("attack"))
	act_skill.pressed.connect(func() -> void: _on_action("skill"))
	act_def.pressed.connect(func() -> void: _on_action("defend"))
	act_ult.pressed.connect(func() -> void: _on_action("ult"))
	act_row.add_child(act_atk)
	act_row.add_child(act_skill)
	act_row.add_child(act_def)
	act_row.add_child(act_ult)

	# ── 抽牌面板(底部) ──
	draft_panel = PanelContainer.new()
	var dsb := AppTheme.flat(Color(0.08, 0.07, 0.18, 0.96), AppTheme.GOLD, 12, 1)
	draft_panel.add_theme_stylebox_override("panel", dsb)
	add_child(draft_panel)
	var dbox := VBoxContainer.new()
	dbox.add_theme_constant_override("separation", 8)
	draft_panel.add_child(dbox)
	draft_title = AppTheme.make_label(16, AppTheme.GOLD)
	dbox.add_child(draft_title)
	cand_row = HBoxContainer.new()
	cand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cand_row.add_theme_constant_override("separation", 26)
	dbox.add_child(cand_row)
	draft_ops = HBoxContainer.new()
	draft_ops.alignment = BoxContainer.ALIGNMENT_CENTER
	draft_ops.add_theme_constant_override("separation", 14)
	dbox.add_child(draft_ops)

	_aura = Control.new()
	_aura.size = Vector2(140, 140)
	_aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aura.visible = false
	_aura.draw.connect(_draw_aura)
	add_child(_aura)

	Responsive.watch(self, _relayout)
	_render()
	Audio.play_bgm("table")


func _process(delta: float) -> void:
	# 怪物呼吸浮动 + 玩家轻微起伏(战斗阶段)
	if fm != null and fm.phase == "battle":
		_bob_t += delta
		monster.position.y = _enemy_home.y + sin(_bob_t * 2.2) * 6.0
		monster.position.x = _enemy_home.x + sin(_bob_t * 0.8) * 3.0
		avatar.position.y = _player_home.y + sin(_bob_t * 1.7) * 4.0
		avatar.rotation = sin(_bob_t * 1.2) * 0.02
	if _aura != null and _aura.visible:
		_aura_spin += delta * 1.5   # 变身光环旋转
		_aura.position = _player_home - _aura.size / 2.0
		_aura.queue_redraw()


func _label(size_num: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size_num)
	lb.add_theme_color_override("font_color", color)
	return lb


func _update_hits() -> void:
	if fm != null and fm.phase == "battle" and fm.hits >= 2:
		hits_lbl.visible = true
		hits_lbl.text = "COMBO x%d" % fm.hits
		hits_lbl.position = Vector2(_px(0.5) - 90.0, _py(0.16))
		var tw := create_tween()
		hits_lbl.scale = Vector2(1.25, 1.25)
		tw.tween_property(hits_lbl, "scale", Vector2.ONE, 0.12)
	else:
		hits_lbl.visible = false


## ── 总渲染: 按引擎 phase 切换可见区 ──
func _render() -> void:
	_say_phase()
	_update_transform()
	round_lbl.text = ("[%s] " % Wallet.daily_day if daily and Wallet.daily_day != ""
		else "") + tr("第 %d 层 · 第 %d/%d 回合 · %s") % [fm.floor_num,
		fm.round_num, FightModeGd.ROUNDS,
		str(FightModeGd.GROUPS[fm.group]["name"])]
	_refresh_bars()
	_refresh_slots()   # 选牌/替换后立即反映到左上装备槽(原来只在战斗事件里刷)
	_update_hits()
	var is_battle: bool = fm.phase == "battle"
	var is_draft: bool = fm.phase == "draft"
	battle_box.visible = is_battle or is_draft
	# 怪物未生成(draft)时隐藏敌方区, 避免显示占位形象
	var enemy_ready: bool = is_battle and not fm.enemy.is_empty()
	monster.visible = enemy_ready
	e_name.visible = enemy_ready
	e_intent.visible = enemy_ready
	ehp_bar.visible = enemy_ready
	ehp_txt.visible = enemy_ready
	act_row.visible = is_battle and not _busy
	draft_panel.visible = is_draft
	log_lbl.text = "\n".join((fm.log_lines as Array).slice(
			maxi(fm.log_lines.size() - 4, 0)))
	if enemy_ready:
		_fill_enemy_view()
		_layout_bars(size.x, size.y)
		_refresh_actions()
	if is_draft:
		_render_draft()
	if fm.phase == "battle" and fm.player_dead() and not _busy:
		# 复活币自动生效(与旧版一致); 无币则结算
		if Wallet.try_consume_revive():
			fm.revive()
			_refresh_bars()
			_floater(tr("复活币生效!"), _px(0.17), _py(0.42), AppTheme.GOLD)
		else:
			_finish_run()


func _fill_enemy_view() -> void:
	(monster as Control).group = int(fm.enemy.get("group", 0))
	(monster as Control).kind = str(fm.enemy.get("kind", "mob"))
	(monster as Control).variant = int(fm.enemy.get("variant", 0))
	var kind_txt: String = {"mob": tr("小怪"), "elite": tr("精英怪"),
			"boss": "BOSS"}.get(str(fm.enemy.get("kind", "mob")), "")
	e_name.text = "%s · %s" % [str(fm.enemy.get("name", "")), kind_txt]
	_refresh_bars()


## ── 五张变身 ──
func _transformed() -> bool:
	return fm != null and fm.slots.size() >= 5


func _dominant_suit() -> int:
	var cnt := [0, 0, 0, 0]
	var best := 0
	for c in fm.slots:
		var su := CardsGd.suit(int(c))
		cnt[su] += 1
		if cnt[su] > cnt[best]:
			best = su
	return best


func _suit_color(su: int) -> Color:
	return [Color("ff7050"), Color("7dd87d"), Color("ffd166"), Color("7ec8ff")][su]


func _update_transform() -> void:
	if _aura == null:
		return
	if _bg != null and fm.group < GROUP_TINTS.size():
		_bg.color = Color("191934").lerp(GROUP_TINTS[fm.group], 0.6)
	var on := _transformed()
	_aura.visible = on
	_aura.position = _player_home - _aura.size / 2.0
	avatar.modulate = Color(1, 1, 1).lerp(_suit_color(_dominant_suit()), 0.3) if on 			else Color.WHITE
	if on and _transform_floor != fm.floor_num:
		_transform_floor = fm.floor_num
		_play_transform()


func _draw_aura() -> void:
	if not _transformed():
		return
	var c := _aura.size / 2.0
	var col := _suit_color(_dominant_suit())
	_aura.draw_arc(c, 52.0, 0, TAU, 40, Color(col, 0.8), 3.0, true)
	_aura.draw_arc(c, 45.0, 0, TAU, 40, Color(col, 0.35), 7.0, true)
	for i in 8:
		var a := TAU * i / 8.0 + _aura_spin
		_aura.draw_line(c + Vector2.from_angle(a) * 57.0,
				c + Vector2.from_angle(a) * 65.0, Color(col, 0.85), 2.5, true)


## 变身演出: 白闪 + 「变 身!」横幅 + 光环展开 + 震屏 + 播报
func _play_transform() -> void:
	Audio.say("f_transform", 1.0, true)
	Audio.play("win")
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.85)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var ftw := flash.create_tween()
	ftw.tween_property(flash, "color:a", 0.0, 0.45)
	ftw.tween_callback(flash.queue_free)
	var lb := _label(42, _suit_color(_dominant_suit()))
	lb.text = tr("变 身!")
	lb.position = Vector2(_px(0.5) - 130.0, _py(0.20))
	lb.pivot_offset = Vector2(130, 30)
	lb.z_index = 30
	add_child(lb)
	var tw := lb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lb, "scale", Vector2(1.25, 1.25), 0.3) 			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lb, "modulate:a", 0.0, 0.8).set_delay(0.6)
	tw.chain().tween_callback(lb.queue_free)
	_aura.visible = true
	_aura.scale = Vector2(0.3, 0.3)
	var atw := _aura.create_tween()
	atw.tween_property(_aura, "scale", Vector2.ONE, 0.4) 			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_shake(8.0)


## 单卡小加成文案(抽牌预览/装备槽提示)
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


func _px(f: float) -> float:
	return size.x * f


## 阶段切换语音: 编成(第5回合=BOSS)/战斗开始/回合胜利
func _say_phase() -> void:
	if fm.phase == _voice_phase:
		return
	_voice_phase = fm.phase
	match fm.phase:
		"draft":
			Audio.say("f_boss" if fm.round_num >= FightModeGd.ROUNDS else "f_draft")
		"battle":
			Audio.say("battle_start", 1.0, true)
		"round_end":
			Audio.say("f_round_win", 1.0, true)


func _py(f: float) -> float:
	return size.y * f


## ── 装备槽 / 奇物 / 牌型 ──
func _refresh_slots() -> void:
	for i in 5:
		var e: Dictionary = _slot_ui[i]
		var wrap: PanelContainer = e["wrap"]
		var card := -1
		if i < fm.slots.size():
			card = int(fm.slots[i])
		if int(e["card"]) == card and not _replace_mode():
			continue
		for c in wrap.get_children():
			c.queue_free()
		e["card"] = card
		if card >= 0:
			var cv: Control = CardViewScript.new(card)
			# 槽 56×78 − 内边距 4×2 → 内容区 48×70; 卡 min 略小交给容器拉伸
			cv.custom_minimum_size = Vector2(46, 68)
			cv.size = Vector2(48, 70)
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wrap.add_child(cv)
			# 悬停提示: 当前装备牌的单卡效果 + 全套牌型协同效果
			wrap.tooltip_text = "%s
单卡: %s
牌型协同: %s · %s" % [CardsGd.label(card),
					_card_effect_text(card), tr(str(fm.combo["name"])),
					tr(str(fm.combo["desc"]))]
		else:
			wrap.tooltip_text = "空槽位 — 抽牌阶段点选装备"
		var sb: StyleBoxFlat = e["sb"]
		if _replace_mode():
			sb.border_color = AppTheme.GOLD
			sb.set_border_width_all(3)
		else:
			sb.border_color = AppTheme.GOLD if card >= 0 else Color(1, 1, 1, 0.25)
			sb.set_border_width_all(2 if card >= 0 else 1)
	for c in _sp_row.get_children():
		c.queue_free()
	for sp_id in fm.specials:
		var meta: Dictionary = FightModeGd.sp_meta(sp_id)
		var chip := AppTheme.make_label(13, Color("c89ae8"))
		chip.text = "%s %s" % [str(meta["icon"]), str(meta["name"])]
		chip.tooltip_text = str(meta["desc"])
		_sp_row.add_child(chip)
	if fm.specials.is_empty():
		var hint := AppTheme.make_label(12, AppTheme.DIM)
		hint.text = "奇物(特殊牌不占槽)"
		_sp_row.add_child(hint)
	if fm.slots.is_empty():
		_combo_lbl.text = "集齐 5 张触发牌型协同"
	else:
		_combo_lbl.text = tr("牌型 %s · %s") % [tr(str(fm.combo["name"])), tr(str(fm.combo["desc"]))]


func _replace_mode() -> bool:
	return _pending_cand >= 0


func _on_slot_clicked(idx: int) -> void:
	if not _replace_mode() or _busy or idx >= fm.slots.size():
		return
	Audio.play("click")
	var cand := _pending_cand
	_pending_cand = -1
	var r: Dictionary = fm.draft_pick(cand, idx)
	if bool(r["ok"]):
		_after_pick_feedback(cand, idx)
	_render()


func _after_pick_feedback(cand: int, _slot: int) -> void:
	if cand >= 0 and cand < 100:
		_floater(tr("装备 %s") % CardsGd.label(cand),
				_px(0.17), _py(0.30), AppTheme.GOLD)


## ── 抽牌面板 ──
func _render_draft() -> void:
	for c in cand_row.get_children():
		c.queue_free()
	for c in draft_ops.get_children():
		c.queue_free()
	if fm.comp:
		draft_title.text = tr("🟣 奇物已生效 — 补抽一张普通牌 (装备 %d/5)") % fm.slots.size()
	else:
		draft_title.text = tr("第 %d 回合 — 二选一 (装备 %d/5)%s") % [fm.round_num,
				fm.slots.size(),
				"，额外候选组!" if fm.pairs_left > 1 else ""]
	for cand in fm.pair:
		if cand >= 100:
			cand_row.add_child(_build_special_card(int(cand)))
		else:
			cand_row.add_child(_build_normal_card(int(cand)))
	if _replace_mode():
		draft_title.text = "装备槽已满 — 点击左上要替换的槽位，或跳过"
		var skip := AppTheme.make_button("跳过这组", Vector2(150, 40), 14)
		skip.pressed.connect(func() -> void:
			Audio.play("click")
			_pending_cand = -1
			var r: Dictionary = fm.draft_pick(-1)
			if bool(r["ok"]):
				_render())
		draft_ops.add_child(skip)


func _build_normal_card(card: int) -> Control:
	var rare := card >= 200
	if rare:
		card = card - 200   # 稀有普通牌: 显示剥离后的卡面
	var wrap := PanelContainer.new()
	var sb := AppTheme.flat(Color(0.10, 0.10, 0.22), Color(1, 1, 1, 0.2), 10, 1)
	wrap.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	wrap.add_child(box)
	var cc := CenterContainer.new()
	var cv: Control = CardViewScript.new(card)
	cv.custom_minimum_size = Vector2(96, 134)
	cv.size = Vector2(96, 134)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(cv)
	box.add_child(cc)
	# 预览牌型: 未满按追加, 槽满按替换 0 号位估算
	var preview: Array = (fm.slots as Array).duplicate()
	if preview.size() < 5:
		preview.append(card)
	else:
		preview[0] = card
	var combo: Dictionary = FightModeGd.evaluate_combo(preview)
	var hint := _label(11, Color("c9b06a"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rare_txt := (tr("稀有!") + "
") if rare else ""
	hint.text = "此牌 %s: %s
%s%s" % [CardsGd.SUIT_NAMES[CardsGd.suit(card)],
			_card_effect_text(card), rare_txt,
			(tr("替换后 %s") if fm.slots.size() >= 5 else tr("装备后 %s"))
					% tr(str(combo["name"]))]
	box.add_child(hint)
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
	var icon := _label(40, Color("e8d0ff"))
	icon.text = str(meta["icon"])
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(icon)
	var nm := AppTheme.make_label(16, Color("e8d0ff"))
	nm.text = "【奇物】%s" % str(meta["name"])
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(nm)
	var desc := _label(12, Color("c8a8e0"))
	desc.text = str(meta["desc"])
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(180, 60)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(desc)
	var tag := _label(11, Color("a888c0"))
	tag.text = "不占装备槽" if fm.slots.size() < 5 else "槽满: 立即生效"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tag)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_candidate(cand))
	return wrap


func _on_candidate(cand: int) -> void:
	if _busy or fm.phase != "draft":
		return
	Audio.play("click")
	# 槽满 + 普通牌(引擎要求槽位) → 进入替换模式
	if not FightModeGd.is_sp(cand) and fm.slots.size() >= 5:   # 普通/稀有均走替换
		_pending_cand = cand
		_render()
		return
	var r: Dictionary = fm.draft_pick(cand)
	if not bool(r["ok"]):
		return
	if cand >= 200:
		Audio.say("f_rare")   # 稀有卡
		_floater(tr("稀有卡! 生命上限 +8%"), _px(0.5), _py(0.30),
				Color("ffd166"))
	elif cand >= 100:
		Audio.say("f_relic")   # 奇物
		var meta: Dictionary = FightModeGd.sp_meta(FightModeGd.sp_of(cand))
		_floater("%s %s" % [str(meta["icon"]), str(meta["name"])],
				_px(0.5), _py(0.34), Color("c89ae8"))
		Audio.play("exchange")
	_render()


## ── 战斗 ──
func _refresh_bars() -> void:
	var mh: int = maxi(int(fm.stats["max_hp"]), 1)
	php_fg.size = Vector2(236.0 * clampi(fm.hp, 0, mh) / float(mh), 14)
	php_txt.text = "HP %d / %d" % [maxi(fm.hp, 0), mh]
	if fury_fg != null:
		fury_fg.size = Vector2(236.0 * float(fm.fury) / 100.0, 8)
	shield_fg.size = Vector2(240.0 * clampi(float(fm.shield),
			0.0, float(mh)) / float(mh), 6)
	if fm.phase == "battle" and not fm.enemy.is_empty():
		var eh: int = maxi(int(fm.enemy["max_hp"]), 1)
		ehp_fg.size = Vector2(236.0 * clampi(int(fm.enemy["hp"]), 0, eh) / float(eh), 14)
		ehp_txt.text = "HP %d / %d" % [maxi(int(fm.enemy["hp"]), 0), eh]
		e_intent.text = tr("意图: %s") % _intent_text()


func _intent_text() -> String:
	if fm.enemy.is_empty():
		return ""
	match str(fm.enemy.get("intent", "attack")):
		"heavy":
			return "💥 重击(防御可减!)"
		"spell":
			return "🔥 法术(魔抗可减!)"
		"charge":
			var sn: String = str(fm.enemy.get("special", "必杀技"))
			return "⚡ 蓄力: %s(此回合承伤+50%!)" % sn
	return "⚔ 攻击"


func _refresh_actions() -> void:
	var cd := fm.skill_cd()
	var kind := str(fm.stats.get("skill_kind", "fire"))
	var icon := "🔥" if kind == "fire" else ("❄" if kind == "frost" else "✟")
	var label := "火球" if kind == "fire" else ("冰霜" if kind == "frost" else "圣光")
	act_skill.disabled = cd > 0
	act_ult.disabled = fm.fury < 100
	act_skill.text = ("%s %s" % [icon, label]) if cd <= 0 \
			else (tr("%s 冷却 %d") % [icon, cd])


func _on_action(action: String) -> void:
	if _busy or fm.phase != "battle":
		return
	_busy = true
	act_row.visible = false
	Audio.play("click")
	match action:
		"attack":
			Audio.say("f_attack")
		"skill":
			Audio.say("f_skill")
			_skill_cast(monster, Color("7ec8ff"))
		"defend":
			Audio.say("f_defend")
		"ult":
			Audio.say("f_ult", 1.0, true)
	if action != "defend":
		_player_strike()
	var fury_before := fm.fury
	var evs: Array = fm.step(action)
	# 怒气首次蓄满 / 连击 5 层里程碑
	if fury_before < 100 and fm.fury >= 100:
		Audio.say("f_fury")
	if fm.hits == 5:
		Audio.say("f_combo")
	_run_events(evs)


## 顺序播放事件 → 收尾(阶段推进/死亡判定)
func _run_events(evs: Array) -> void:
	if evs.is_empty():
		_after_events()
		return
	var ev = evs.pop_front()
	var kind := str(ev["kind"])
	var is_enemy_target := str(ev["who"]) == "e"
	var tx := _px(0.68) if is_enemy_target else _px(0.17)
	var ty := _py(0.36) if is_enemy_target else _py(0.34)
	match kind:
		"crit":
			Audio.say("f_crit")
			_floater(tr("暴击 -%d") % int(ev["v"]), tx, ty, Color("ffd166"))
			_sfx("crit")
		"skill":
			var sk := str(ev.get("skill_kind", "fire"))
			var stxt: String = str({"fire": "火球", "frost": "冰霜",
					"light": "圣光"}.get(sk, "技能"))
			_floater("%s -%d" % [stxt, int(ev["v"])], tx, ty, Color("7ec8ff"))
			_sfx("exchange")
		"heavy":
			_floater(tr("重击 -%d") % int(ev["v"]), tx, ty, Color("ff5050"))
			_enemy_strike("slam" if str(fm.enemy.get("kind")) != "mob" else "lunge")
			_sfx("fall")
		"dmg":
			_floater("-%d" % int(ev["v"]), tx, ty,
					AppTheme.RED if is_enemy_target else Color("ff8866"))
			if is_enemy_target:
				_hit_flash(monster)
				if fm.hits >= 4:
					_shake(6.0)
			else:
				_sfx("hit")
		"thorns":
			_floater(tr("荆棘 -%d") % int(ev["v"]), tx, ty, Color("7dd87d"))
		"heal":
			_floater(tr("+%d") % int(ev["v"]), _px(0.17), _py(0.30), Color("7dd87d"))
			_sfx("pop")
		"defend":
			_floater("防御", _px(0.17), _py(0.30), Color("7ec8ff"))
		"ult":
			_floater(tr("奥义 -%d") % int(ev["v"]), _px(0.68), _py(0.30), AppTheme.GOLD)
			_shake(12.0)
			_sfx("crit")
		"parry":
			Audio.say("f_parry", 1.0, true)
			_floater(tr("完美格挡! 反击 -%d") % int(ev["v"]), _px(0.68), _py(0.36), Color("7ec8ff"))
			_sfx("crit")
		"combo":
			_update_hits()   # 连击大字刷新
			_sfx("tick")
		"charging":
			_skill_cast(monster, Color("ffb14e"))
			_floater(tr("⚡ 蓄力中…"), _px(0.68), _py(0.24), Color("ffb14e"))
		"special":
			Audio.say("f_boss_skill", 1.0, true)   # BOSS 喊话
			_floater("%s -%d" % [tr("必杀"), int(ev["v"])], _px(0.68), _py(0.30),
					Color("ff9a5a"))
			_shake(9.0)
			if ev.has("burn"):
				_floater(tr("🔥 灼烧 %d 回合") % 2, _px(0.17), _py(0.26), Color("ff8850"))
			if ev.has("frozen"):
				_floater(tr("❄ 被冰冻!"), _px(0.17), _py(0.24), Color("9fd8ff"))
		"burn":
			_floater("🔥 灼烧 -%d" % int(ev["v"]), _px(0.17), _py(0.32), Color("ff8850"))
			_sfx("hurt")
		"chilled":
			_floater("❄ 冻结", _px(0.68), _py(0.36), Color("9fd8ff"))
		"die":
			Audio.say("f_kill", 1.0, true)
			_monster_die()
	if kind == "heavy" or kind == "spell":
		_hit_flash(avatar)
		_shake(6.0)
		_sfx("hurt")
	if kind == "dmg" and not is_enemy_target:
		_enemy_strike("lunge")
		_hit_flash(avatar)
		_shake(4.0)
	_refresh_bars()
	_refresh_slots()
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void: _run_events(evs))


func _after_events() -> void:
	_refresh_bars()
	if fm.player_dead():
		if Wallet.try_consume_revive():
			fm.revive()
			_refresh_bars()
			_refresh_actions()
			_floater(tr("复活币生效!"), _px(0.17), _py(0.30), AppTheme.GOLD)
			_busy = false
			act_row.visible = true
			return
		_finish_run()
		return
	if fm.phase == "round_end":
		_show_round_banner()
		return
	if fm.phase == "over":
		_finish_run()
		return
	_busy = false
	_render()   # 战斗继续: 刷新按钮/意图


func _show_round_banner() -> void:
	if _banner != null and is_instance_valid(_banner):
		_banner.queue_free()
	_banner = _label(30, AppTheme.GOLD)
	if fm.phase == "round_end":
		_banner.text = tr("第 %d 回合 胜利!") % fm.round_num
		if fm.last_rank != "":
			_banner.text += tr("  评级 %s") % fm.last_rank
	else:
		_banner.text = ""
	_banner.position = Vector2(_px(0.5) - 120.0, _py(0.30))
	_banner.z_index = 20
	add_child(_banner)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(func() -> void:
		if _banner != null and is_instance_valid(_banner):
			_banner.queue_free()
		_banner = null
		if fm.run_won and fm.round_num == fm.ROUNDS:
			_show_endless_choice()   # R5 通关: 无尽选择
		else:
			fm.advance_round()
		_busy = false
		_render())


## ── 演出: 玩家出击(按皮肤差异化) / 怪物攻击(按类别差异化) / 受击 / 死亡 ──
func _player_strike() -> void:
	var skin := "skin_default"
	if is_inside_tree():
		var w := get_node_or_null("/root/Wallet")
		if w != null:
			skin = str(w.equipped_skin)
	# 每个皮肤不同动作: 狐妖/花魁=疾冲, 鬼类=跳劈, 其他=直进
	# 变身状态: 一律疾冲且位移更大(打出残影级气势)
	var hop := skin in ["skin_aka", "skin_ao", "skin_tengu"] and not _transformed()
	var dash := (skin in ["skin_kitsu", "skin_oiran"] or _transformed())
	var reach := (78.0 if _transformed() else (70.0 if dash else 52.0))
	var tw := create_tween()
	if hop:
		tw.tween_property(avatar, "position",
				_player_home + Vector2(reach * 0.6, -46.0), 0.16)
		tw.tween_property(avatar, "position",
				_player_home + Vector2(reach, 0.0), 0.12)
	else:
		tw.tween_property(avatar, "position",
				_player_home + Vector2(reach, 0.0), 0.16)
	tw.tween_callback(func() -> void: _slash_flash(skin))
	tw.tween_property(avatar, "position", _player_home, 0.2)


## 挥砍弧光: 颜色取皮肤主色
func _slash_flash(skin: String) -> void:
	var col: Color = SkinsLib._skin_theme(skin).get("cloth", Color("e0a83c"))
	var slash := SlashArc.new()
	slash.color = col
	slash.position = monster.position + monster.size / 2.0 - Vector2(60, 60)
	slash.size = Vector2(120, 120)
	slash.z_index = 15
	battle_box.add_child(slash)
	var tw := slash.create_tween()
	tw.tween_interval(0.22)
	tw.tween_callback(slash.queue_free)
	_hit_flash(monster)


## 闪避演出: 快速侧移
func _dodge_fighter(target: Control, home: Vector2) -> void:
	var ghost := ColorRect.new()
	ghost.color = Color(1, 1, 1, 0.15)
	ghost.size = target.size
	ghost.position = target.position
	ghost.z_index = 5
	battle_box.add_child(ghost)
	var tw := target.create_tween()
	tw.tween_property(target, "position:x", home.x + 60.0, 0.1)
	tw.tween_property(target, "position:x", home.x + 30.0, 0.08)
	tw.tween_property(target, "position:x", home.x, 0.12)
	tw.tween_callback(func() -> void: ghost.queue_free())


## 技能蓄力演出
func _skill_cast(target: Control, col: Color) -> void:
	var glow := SlashArc.new()
	glow.color = col
	glow.position = target.position + target.size / 2.0
	glow.size = Vector2(target.size.x * 1.4, target.size.y * 1.4)
	glow.z_index = 14
	battle_box.add_child(glow)
	var tw := glow.create_tween()
	tw.tween_property(glow, "scale", Vector2(1.3, 1.3), 0.25)
	tw.tween_property(glow, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(glow.queue_free)


func _enemy_strike(style: String) -> void:
	var tw := create_tween()
	if style == "slam":
		tw.tween_property(monster, "position:y", _enemy_home.y - 40.0, 0.14)
		tw.tween_property(monster, "position:y", _enemy_home.y + 6.0, 0.10)
		tw.tween_callback(func() -> void: _shake(9.0))
		tw.tween_property(monster, "position:y", _enemy_home.y, 0.14)
	else:
		tw.tween_property(monster, "position:x", _enemy_home.x - 46.0, 0.14)
		tw.tween_property(monster, "position:x", _enemy_home.x, 0.18)


func _monster_die() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(monster, "modulate", Color(2.0, 2.0, 2.0, 0.0), 0.5)
	tw.tween_property(monster, "rotation", 0.6, 0.5)
	tw.tween_property(monster, "position:y", _enemy_home.y + 20.0, 0.5)
	Audio.play("win")


func _hit_flash(target: Control) -> void:
	var tw := create_tween()
	tw.tween_property(target, "modulate", Color(2.5, 1.2, 1.2), 0.06)
	tw.tween_property(target, "modulate", Color.WHITE, 0.16)


func _shake(strength: float) -> void:
	if _shake_t > 0.0:
		return
	_shake_t = 0.18
	var tw := create_tween()
	for i in 5:
		var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * 0.4
		tw.tween_property(battle_box, "position", off, 0.035)
	tw.tween_property(battle_box, "position", Vector2.ZERO, 0.035)


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


## ── 结算 ──
func _show_endless_choice() -> void:
	Audio.say("f_clear", 1.0, true)   # R5 通关
	_busy = true
	_close_overlay()
	var overlay := CenterContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(AppTheme.PANEL, AppTheme.GOLD, 16, 2)
	sb.content_margin_left = 44
	sb.content_margin_right = 44
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", sb)
	overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var t := AppTheme.make_label(28, AppTheme.GOLD)
	t.text = tr("试炼通关!")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var b := AppTheme.make_label(15, AppTheme.WHITE)
	b.text = tr("深入无尽挑战, 怪物每轮更强, 奖励随层数增长")
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(b)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var go := AppTheme.make_button(tr("继续无尽挑战"), Vector2(200, 50), 17)
	go.pressed.connect(func() -> void:
		Audio.play("win")
		_close_overlay()
		fm.start_next_floor()   # R5 通关后 advance_round 会提前返回, 必须开新层
		_busy = false
		_render())
	row.add_child(go)
	var take := AppTheme.make_button(tr("领奖结算"), Vector2(170, 50), 17)
	take.pressed.connect(func() -> void:
		Audio.play("click")
		_close_overlay()
		_finish_run())
	row.add_child(take)
	add_child(overlay)
	overlay.position = Vector2.ZERO
	overlay.size = size


func _finish_run() -> void:
	if phase == "over":
		return
	phase = "over"
	Audio.say("victory" if fm.run_won else "defeat", 1.0, true)   # 结算播报
	var cleared: int = fm.cleared
	var r: Dictionary = Wallet.grant_fight_reward(cleared,
			1 if fm.run_won else 0, daily, fm.run_won)   # 通关击破 BOSS; 失败扣金
	_run_diamonds += int(r["diamonds"])
	var run_gold := int(r["gold"])
	Wallet.note_mission("m_fight")
	Wallet.push_history({
		"day": Time.get_date_string_from_system(),
		"mode": "格斗", "floor": cleared, "rank": 0, "points": 0,
		"gold": run_gold, "diamonds": _run_diamonds,
	})
	var title := (tr("每日挑战通关!") if fm.run_won else tr("每日挑战结束")) \
			if daily else (tr("试炼通关!") if fm.run_won else tr("试炼结束"))
	var body: String
	if fm.run_won:
		body = tr("通过 %d/5 回合 · 历史最佳第 %d 层\n奖励: %d 钻石 已入账") % [
			cleared, int(r["best"]), _run_diamonds]
	else:
		body = tr("通过 %d/5 回合 · 历史最佳第 %d 层\n失败惩罚: %d 金币 · 未获得钻石") % [
			cleared, int(r["best"]), run_gold]
	if daily:
		var hp_pct := int(100.0 * clampi(fm.hp, 0, int(fm.stats["max_hp"]))
				/ float(maxi(int(fm.stats["max_hp"]), 1)))
		var d: Dictionary = Wallet.record_daily(cleared, hp_pct)
		var best_txt := (tr("通关! 剩余生命 %d%%") % int(d["best_hp"])) \
				if int(d["best_round"]) >= 5 \
				else tr("到达第 %d 回合") % int(d["best_round"])
		body += "\n" + tr("今日最佳: %s%s") % [best_txt,
				tr(" (新纪录!)") if bool(d["better"]) else ""]
	_show_overlay(title, body, "返回菜单", func() -> void:
		_close_overlay()
		closed.emit()
		queue_free())


func _show_overlay(title: String, body: String, btn_text: String,
		on_btn: Callable) -> void:
	_close_overlay()
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
	overlay.position = Vector2.ZERO
	overlay.size = size


func _close_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null


## ── 布局 ──
func _relayout() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	back_btn.position = Vector2(w - 150.0, 26)
	help_btn.position = Vector2(w - 260.0, 26)
	round_lbl.position = Vector2(w / 2.0 - 130.0, 34)
	# 左上装备槽区
	slots_box.position = Vector2(36.0, 84.0)
	slots_box.size = Vector2(minf(340.0, w * 0.3), 160.0)
	# 战场: 玩家左下 / 怪物右上
	var fighter_y := h * 0.42
	_player_home = Vector2(w * 0.12, fighter_y)
	_enemy_home = Vector2(w * 0.62, fighter_y)
	avatar.position = _player_home
	monster.position = _enemy_home
	_layout_bars(w, h)
	# 日志与按钮
	log_lbl.position = Vector2(36.0, h - 176.0)   # 左下: 避开底部抽牌面板
	log_lbl.custom_minimum_size = Vector2(minf(270.0, w * 0.24), 150.0)
	act_row.position = Vector2(w * 0.32, h - 92.0)
	act_row.custom_minimum_size = Vector2(w * 0.42, 60)
	# 抽牌面板: 底部居中
	draft_panel.position = Vector2(w / 2.0 - 330.0, maxf(h * 0.30, 90.0))
	draft_panel.custom_minimum_size = Vector2(640, 0)
	draft_panel.size = Vector2(640, 0)   # 高度随内容(提示多行)自动撑开


func _layout_bars(w: float, h: float) -> void:
	# battle_box 子节点按创建顺序: [avatar, pname, php_bar, php_txt,
	#  shield_bar, monster, e_name, e_intent, ehp_bar, ehp_txt, floaters]
	var kids := battle_box.get_children()
	if kids.size() < 10:
		return
	var pname: Control = kids[1]
	pname.position = _player_home + Vector2(-10.0, 142.0)
	var php_bar: Control = kids[2]
	php_bar.position = _player_home + Vector2(-10.0, 170.0)
	php_fg.size = Vector2(maxf(php_bar.size.x * _hp_frac() - 4.0, 2.0), 14)
	php_txt.position = php_bar.position + Vector2(0.0, 20.0)
	var shield_bar: Control = kids[4]
	shield_bar.position = php_bar.position + Vector2(0.0, 40.0)
	fury_bar.position = shield_bar.position + Vector2(0.0, 12.0)
	fury_fg.size = Vector2(maxf(fury_bar.size.x * float(fm.fury) / 100.0, 0.0), 8)
	shield_fg.size = Vector2(maxf(shield_bar.size.x * _shield_frac(), 0.0), 6)
	e_name.position = _enemy_home + Vector2(-30.0, -34.0)
	e_intent.position = _enemy_home + Vector2(-30.0, -12.0)
	var ehp_bar: Control = kids[8]
	ehp_bar.position = _enemy_home + Vector2(-20.0, 202.0)
	ehp_fg.size = Vector2(maxf(ehp_bar.size.x * _enemy_hp_frac() - 4.0, 2.0), 14)
	ehp_txt.position = ehp_bar.position + Vector2(0.0, 20.0)


func _hp_frac() -> float:
	var mh: int = maxi(int(fm.stats["max_hp"]), 1)
	return float(clampi(fm.hp, 0, mh)) / float(mh)


func _shield_frac() -> float:
	var mh: int = maxi(int(fm.stats["max_hp"]), 1)
	return clampf(float(fm.shield) / float(mh), 0.0, 1.0)


func _enemy_hp_frac() -> float:
	if fm.enemy.is_empty():
		return 0.0
	var eh: int = maxi(int(fm.enemy["max_hp"]), 1)
	return float(clampi(int(fm.enemy["hp"]), 0, eh)) / float(eh)


## 挥砍弧光(攻击演出)
class SlashArc extends Control:
	var color := Color("e0a83c")

	func _draw() -> void:
		draw_arc(Vector2.ZERO, size.x * 0.46, PI * 0.9, PI * 1.9, 20,
				Color(color, 0.9), size.x * 0.08, true)
		draw_arc(Vector2.ZERO, size.x * 0.30, PI * 1.0, PI * 1.8, 16,
				Color(1, 1, 1, 0.7), size.x * 0.04, true)


## 音效统一入口(页面隐藏时不发声)
func _sfx(sfx_name: String) -> void:
	if visible:
		Audio.play(sfx_name)
