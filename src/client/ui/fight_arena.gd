## 联机格斗对战竞技场 v4: HUD 化布局 — 双方 7 槽(装备5+奇物2)分列左上/右上
## 两角, 中央舞台留给大尺寸无框头像对战(冲刺/弹道/闪避/狂暴/连击/震屏特效)。
## 渲染服务器下发的 s_fight_state, 本页不驱动任何规则; 观战者全程可见无操作。
## 离开 = 退出本场留在房间(双方都退 → 服务器自动收尾)。
extends Control

signal finished  # 离开竞技场 → 返回房间页

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const FightModeGd = preload("res://src/rules/fight/fight_mode.gd")
const CardsGd = preload("res://src/rules/cards.gd")
const CardViewScript = preload("res://src/client/ui/card_view.gd")
const AvatarScript = preload("res://src/client/ui/avatar.gd")
const FightSpriteScript = preload("res://src/client/ui/fight_sprite.gd")
## 联机格斗: 九组像素背景随机登场
const STAGE_BGS := ["forest", "cave", "lava", "ice", "graveyard", "waste",
		"village", "palace", "colony"]
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
var _pick_lock_ms := 0         # 选牌防抖: 触屏连点/重渲染后的同位余点不生效

var phase_lbl: Label
var score_lbl: Label
var spec_lbl: Label
var _conn_lbl: Label
var leave_btn: Button
var log_lbl: Label
var bottom_box: Control        # 底部操作区(每次状态变化重建)
var floaters: Control
var _stage: Control            # 中央对战舞台(头像/特效/震屏载体)
var _hud: Array = []           # 0=左/我方视角, 1=右/对手镜像
var _vs_lbl: Label
var _stage_flash: ColorRect = null
var _auto_leave_timer: SceneTreeTimer = null

# 舞台演出状态
var _avatar_home: Array = [Vector2.ZERO, Vector2.ZERO]
var _bob_t := 0.0
var _shake_t := 0.0
var _avatar_busy := [false, false]   # 事件动画(冲刺/受击/闪避)进行中: 暂停呼吸浮动
var _left_announced := {}   # 已播报过"退出对局"的座位


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = get_parent_area_size()

	var bg_tex := TextureRect.new()
	bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
	bg_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_name: String = STAGE_BGS[randi() % STAGE_BGS.size()]
	var bg_path := "res://assets/fight/bg/%s.png" % bg_name
	if ResourceLoader.exists(bg_path):
		bg_tex.texture = load(bg_path)
	add_child(bg_tex)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.10, 0.42)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var header = preload("res://src/client/ui/p5_header.gd").new()
	header.text = "格斗试炼 · 双人对战"
	header.icon = "card"
	header.position = Vector2(36, 22)
	header.custom_minimum_size = Vector2(400, 54)
	header.size = Vector2(400, 54)
	add_child(header)

	phase_lbl = AppTheme.make_label(19, AppTheme.GOLD)
	phase_lbl.text = "等待服务器…"
	add_child(phase_lbl)
	score_lbl = AppTheme.make_label(22, AppTheme.WHITE)
	add_child(score_lbl)

	spec_lbl = AppTheme.make_label(15, Color("9fd8ff"))
	spec_lbl.visible = false
	add_child(spec_lbl)

	# 连接状态提示: 竞技场盖住大厅, 断线/重连必须在本页可见
	# (has_signal 防御: 兼容测试桩等精简 net 实现)
	_conn_lbl = AppTheme.make_label(16, AppTheme.RED)
	_conn_lbl.visible = false
	add_child(_conn_lbl)
	if net != null and net.has_signal("server_disconnected"):
		net.server_disconnected.connect(func() -> void:
			_conn_lbl.visible = true
			_conn_lbl.text = tr("⚠ 连接中断 — 自动重连中…"))
	if net != null and net.has_signal("connected_ok"):
		net.connected_ok.connect(func() -> void:
			if _conn_lbl.visible:
				_conn_lbl.visible = false
				_floater(tr("已重新连接"), size.x * 0.5, size.y * 0.18,
						Color("7dd87d")))

	leave_btn = AppTheme.make_button("离开对局", Vector2(120, 42), 15)
	leave_btn.pressed.connect(_do_leave)
	add_child(leave_btn)

	_vs_lbl = _label(34, AppTheme.GOLD)
	_vs_lbl.text = "VS"
	_vs_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_vs_lbl.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_vs_lbl)

	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	for i in 2:
		_hud.append(_build_hud(i))
	_build_stage()

	log_lbl = _label(13, Color("c9b06a"))
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
		# has_signal 防御: 兼容测试桩等精简 net 实现
		if net.has_signal("fight_events"):
			net.fight_events.connect(_on_fight_events)
		if not (net.latest_fight as Dictionary).is_empty():
			_apply(net.latest_fight, [])
	Responsive.watch(self, _relayout)
	_relayout.call_deferred()
	Audio.play_bgm("fight")


## ── 服务器视图驱动 ──
func _on_fight_state(v: Dictionary) -> void:
	_apply(v, [])


## 战斗事件(伤害/暴击/闪避/奥义…)在视图应用后逐条演出
func _on_fight_events(events: Array) -> void:
	if (events as Array).is_empty():
		return
	_play_events(events)


func _apply(v: Dictionary, events: Array) -> void:
	var prev_phase := str(view.get("phase", ""))
	var prev_hp: Dictionary = view.get("hp", {})
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
	# 比分以我方视角显示(左=我/1号位, 右=对手) — 此前按房间座位序展示,
	# 2 号位玩家看到的比分是反的
	var seat_l := _seat_at(0) if (f as Array).size() >= 2 else 0
	var seat_r := _seat_at(1) if (f as Array).size() >= 2 else 1
	score_lbl.text = "%d : %d" % [int(sc.get(int(seat_l), 0)),
			int(sc.get(int(seat_r), 0))]
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
	_refresh_huds()
	_refresh_stage()
	_refresh_log()
	_reset_timer()
	_rebuild_bottom()
	if not (events as Array).is_empty() and phase != "draft":
		_play_events(events)
	# 生命变化: 血条白闪 + 平滑掉血
	for i in 2:
		var seat := _seat_at(i)
		if seat >= 0 and (prev_hp as Dictionary).has(seat) \
				and (v.get("hp", {}) as Dictionary).has(seat):
			var before: int = int(prev_hp[seat])
			var now: int = int((v["hp"] as Dictionary)[seat])
			if now < before:
				_hp_flash(i)
	if phase == "round_end" and prev_phase != "round_end":
		var rw := int(v.get("round_winner", -1))
		var won: bool = rw == _seat_at(0) and not bool(v.get("spectator", true))
		_banner(tr("回合胜利!") if won else tr("回合落败"),
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


func _refresh_huds() -> void:
	var phase := str(view.get("phase", ""))
	var per_all: Dictionary = view.get("per", {})
	var sc: Dictionary = view.get("score", {})
	for i in 2:
		var seat := _seat_at(i)
		if seat < 0:
			continue
		var p: Dictionary = _hud[i]
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
		(p["prog"] as Label).visible = false   # 计数并入编成状态行(卡槽区减高)
		var done_lb: Label = p["done"]
		done_lb.visible = phase == "draft"
		done_lb.text = tr("已编成 ✓") if bool(per.get("done", false)) \
				else tr("选牌中… %s") % str((p["prog"] as Label).text)
		var is_turn: bool = int(view.get("turn", -1)) == seat \
				and phase == "battle"
		(p["turn_chip"] as Label).visible = is_turn
		# 对手退出本场 → AI 代管徽标 + 一次性提示
		var is_left: bool = bool((view.get("left", {}) as Dictionary)
				.get(seat, false))
		(p["left_chip"] as Label).visible = is_left
		if is_left and not _left_announced.has(seat):
			_left_announced[seat] = true
			_floater(tr("%s 退出对局 — AI 代管接管") % str(
					(view.get("names", {}) as Dictionary).get(seat, "")),
					size.x * (0.30 if i == 0 else 0.70), size.y * 0.34,
					Color("ff9a6a"), 18)
		_refresh_slots(i, seat, mine)
		_refresh_relics(i, seat, per)
		_refresh_bars(i, seat)


## 装备槽: 我方显示真实卡面(可点替换); 对手开战后披露, 编成中只给暗格
func _refresh_slots(idx: int, seat: int, mine: bool) -> void:
	var p: Dictionary = _hud[idx]
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
			cv.custom_minimum_size = Vector2(42, 58)
			cv.size = Vector2(42, 58)
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			(ui["card_box"] as Control).add_child(cv)
		elif ghost:
			var ph := _label(15, Color(1, 1, 1, 0.35))
			ph.text = "▣"
			(ui["card_box"] as Control).add_child(ph)
		if replace_mode and mine:
			sb.border_color = AppTheme.GOLD if s < count else Color(1, 1, 1, 0.25)
			sb.set_border_width_all(3 if s < count else 1)
			wrap.tooltip_text = tr("点击替换此槽位")
		else:
			sb.border_color = AppTheme.GOLD if has_card else Color(1, 1, 1, 0.25)
			sb.set_border_width_all(2 if has_card else 1)
			wrap.tooltip_text = ""


## 奇物槽(2 格, 紫色): 我方实时, 对手开战后披露
func _refresh_relics(idx: int, seat: int, per: Dictionary) -> void:
	var p: Dictionary = _hud[idx]
	var relics: Array = (per.get("relics", []) as Array).duplicate()
	for r in 2:
		var ui: Dictionary = p["relic_ui"][r]
		var gl: Label = ui["glyph"]
		var sb: StyleBoxFlat = ui["sb"]
		var filled: bool = r < (relics as Array).size()
		gl.text = str(FightModeGd.sp_meta(int(relics[r]))["icon"]) if filled else "◇"
		sb.border_color = Color("b070e0") if filled else Color("b070e0", 0.45)
		sb.set_border_width_all(2 if filled else 1)


func _refresh_bars(idx: int, seat: int) -> void:
	var p: Dictionary = _hud[idx]
	var hp: int = int((view.get("hp", {}) as Dictionary).get(seat, 0))
	var mh: int = maxi(int((view.get("max_hp", {}) as Dictionary).get(seat, 0)), 0)
	var has_battle: bool = (view.get("hp", {}) as Dictionary).has(seat)
	if not has_battle:
		(p["hp_bg"] as ColorRect).visible = false
		(p["fury_bg"] as ColorRect).visible = false
		(p["hp_fg"] as ColorRect).size = Vector2(0, 14)
		(p["fury_fg"] as ColorRect).size = Vector2(0, 7)
		(p["hp_txt"] as Label).text = tr("编成中 — 集卡触发牌型协同")
		(p["stats"] as Label).text = ""
		return
	(p["hp_bg"] as ColorRect).visible = true
	(p["fury_bg"] as ColorRect).visible = true
	var frac := float(clampi(hp, 0, mh)) / float(maxf(float(mh), 1.0))
	var bg_w: float = (p["hp_bg"] as ColorRect).custom_minimum_size.x
	var fg: ColorRect = p["hp_fg"]
	var fsize := Vector2(maxf(bg_w * frac - 4.0, 2.0), 14)
	var fpos := Vector2(bg_w - fsize.x - 2.0, 2.0) if idx == 1 else Vector2(2, 2)
	# 血条平滑掉血(0.22s) — 配合伤害数字, 掉多少一目了然
	var old_tw: Tween = p.get("hp_tw")
	if old_tw != null and old_tw.is_valid():
		old_tw.kill()
	if not fg.is_inside_tree() or absf(fg.size.x - fsize.x) < 1.5:
		fg.size = fsize
		fg.position = fpos
	else:
		fg.position = fpos
		var tw := fg.create_tween()
		p["hp_tw"] = tw
		tw.tween_property(fg, "size:x", fsize.x, 0.22) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fg.color = Color("58c858") if frac > 0.5 \
			else (Color("ffb14e") if frac > 0.25 else Color("d05050"))
	# 怒气条
	var fury: int = int((view.get("fury", {}) as Dictionary).get(seat, 0))
	var ffg: ColorRect = p["fury_fg"]
	var fw := maxf(bg_w * clampf(float(fury) / 100.0, 0.0, 1.0) - 2.0, 0.0)
	ffg.size = Vector2(fw, 7)
	if idx == 1:
		ffg.position = Vector2(bg_w - fw - 2.0, 2.0)
	else:
		ffg.position = Vector2(2, 2)
	# 行1: HP · 护盾 · 牌型协同(两行显示 — 原三行状态区占高太多)
	var sh: int = int((view.get("shield", {}) as Dictionary).get(seat, 0))
	var line1 := "HP %d / %d" % [maxi(hp, 0), mh]
	if sh > 0:
		line1 += "  🔮%d" % sh
	var combos: Dictionary = view.get("combo", {})
	if (combos as Dictionary).has(seat):
		var c: Dictionary = combos[seat]
		line1 += "  ·  %s·%s" % [c["name"], c["desc"]]
	(p["hp_txt"] as Label).text = line1
	# 行2: 攻/防/技属性(+护盾图标/技能冷却)
	var br: Dictionary = (view.get("stats_brief", {}) as Dictionary).get(seat, {})
	if (br as Dictionary).is_empty():
		(p["stats"] as Label).text = ""
	else:
		var kinds := {"fire": "🔥烈焰", "frost": "❄冰霜", "light": "✟圣光"}
		(p["stats"] as Label).text = "⚔%d  🛡%d  ✟%d  %s%s%s" % [
			int(br["atk"]), int(br["def"]), int(br["skill"]),
			str(kinds.get(str((view.get("skill_kind", {}) as Dictionary)
					.get(seat, "fire")), "")),
			("  🔮%d" % sh) if sh > 0 else "",
			("  ⏱冷却%d" % int((view.get("skill_cd", {}) as Dictionary)
					.get(seat, 0))) if int((view.get("skill_cd", {})
					as Dictionary).get(seat, 0)) > 0 else ""]


func _refresh_stage() -> void:
	# 舞台纵向位置随底部占用(编成面板 254 / 行动行 84)动态让位:
	# 头像永不压进底部操作区, 也不被其遮挡(任务反馈: 联机格斗玩家被遮挡)
	_layout_stage()
	# 变身金环: 集满 5 张装备(编成/对战阶段显示)
	for i in 2:
		var seat := _seat_at(i)
		if seat < 0:
			continue
		var per: Dictionary = (view.get("per", {}) as Dictionary).get(seat, {})
		var transformed: bool = bool(per.get("transformed", false))
		var aura: Control = _hud[i]["aura"]
		aura.visible = transformed
		if transformed:
			aura.queue_redraw()
			# 集满五张: 变身动画(首次)+按主花色染色的能量态
			var spr: Control = _hud[i]["avatar"]
			if spr is FightSpriteScript and str(spr.get("action")) != "transform":
				if not bool(_hud[i].get("transform_played", false)):
					_hud[i]["transform_played"] = true
					spr.play_once("transform")
				spr.modulate = Color(1, 1, 1).lerp(_suit_color(seat), 0.35)
		else:
			_hud[i]["transform_played"] = false
			(_hud[i]["avatar"] as Control).modulate = Color.WHITE
		# 回合指示圈(脚下, 金色) — 对战阶段当前行动方
		var is_turn: bool = int(view.get("turn", -1)) == seat \
				and str(view.get("phase", "")) == "battle"
		var ring: Control = _hud[i]["turn_ring"]
		ring.visible = is_turn
		if is_turn:
			ring.queue_redraw()


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
	# 重建后立即定位(否则新子节点默认落 (0,0) 盖住舞台); 构建完再算行数
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
		_status_line(row, "对局已结束 — 即将返回房间…")


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
		hint.text = tr("装备槽已满 — 点击左上角要替换的槽位，或跳过")
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
	var icon: String = {"fire": "🔥烈焰", "frost": "❄冰霜",
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
	# 己方动作即时播报(欢乐斗地主式); 服务器回执事件照常驱动演出
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


## ── 战斗事件演出: 冲刺/弹道/闪避/狂暴/连击/震屏/血条闪 ──
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
	var who: int = int(ev.get("who", 0))
	var side: int = _side_of_seat(who)
	var target_side: int = _side_of_seat(int(ev.get("target", who)))
	var x := _side_x(who)
	var tx := _side_x(int(ev.get("target", who)))
	var y: float = _avatar_home[side].y - 20.0
	var kind := str(ev.get("kind", ""))
	var v := int(ev.get("v", 0))
	match kind:
		"dmg", "crit":
			if kind == "crit":
				Audio.say("f_crit")
				_shake(10.0)
			else:
				_shake(4.0)
			_play_action(side, "attack")
			_play_action(target_side, "hit")
			_lunge(side)
			_spark(Vector2(tx, y), Color("ffd166") if kind == "crit"
					else Color("ff9a6a"))
			_hit_pose(target_side)
			_floater(("暴击 -%d" % v) if kind == "crit" else ("-%d" % v),
					tx, y - 20.0,
					Color("ffd166") if kind == "crit" else Color("ff8866"),
					26 if kind == "crit" else 22)
			_sfx("crit" if kind == "crit" else "hit")
		"skill":
			var sk: String = str(view.get("skill_kind", {}).get(who, "fire"))
			var col: Color = {"fire": Color("ff7f3c"), "frost": Color("7ec8ff"),
					"light": Color("ffe9a0")}.get(sk, Color("7ec8ff"))
			_play_action(side, "skill_" + sk)
			_skill_cast_pose(side)
			_projectile(_avatar_home[side] + Vector2(0, -30),
					_avatar_home[target_side] + Vector2(0, -30), col)
			_floater(tr("技能 -%d") % v, tx, y - 20.0, col)
			_sfx("exchange")
		"evade":
			_dodge(target_side)
			_floater(tr("闪避!"), tx, y - 30.0, Color("9fd8ff"), 24)
			_sfx("pass")
		"enrage":
			_enrage_fx(side)
			_sfx("crit")
		"comboup":
			_combo_chip(side, v)
			_sfx("tick")
		"heal":
			_floater("+%d" % v, x, y - 20.0, Color("7dd87d"))
			_ring(_avatar_home[side] + Vector2(0, -20), Color("7dd87d"))
		"defend":
			_play_action(side, "defend")
			_ring(_avatar_home[side] + Vector2(0, -20), Color("7ec8ff"))
			_floater(tr("防御"), x, y - 20.0, Color("7ec8ff"))
		"ult":
			_flash()
			_shake(16.0)
			_play_action(side, "ult")
			_play_action(target_side, "hit")
			_lunge(side, 110.0)
			_spark(Vector2(tx, y), AppTheme.GOLD)
			_ring(_avatar_home[target_side] + Vector2(0, -20), AppTheme.GOLD)
			_hit_pose(target_side)
			_floater(tr("奥义 -%d") % v, tx, y - 30.0, AppTheme.GOLD, 30)
			_sfx("crit")
		"chill":
			_floater("❄ " + tr("被冻结"), tx, y, Color("9fd8ff"))
		"burn":
			_floater("🔥 " + tr("灼烧 -%d") % v, tx, y - 10.0, Color("ff8850"))
			_sfx("hurt")
		"surge":
			_floater("⚡ " + tr("战意涌动!") , x, y - 20.0, Color("ffd166"))
			_sfx("turn")
		"thorns":
			_floater(tr("荆棘 -%d") % v, tx, y - 10.0, Color("7dd87d"))
			_sfx("hit")
	var tw := create_tween()
	tw.tween_interval(0.42)
	tw.tween_callback(_play_next)


## 精灵动作(一次性, 播完自动回待机); 兼容回退头像(无动作直接忽略)
func _play_action(side: int, p_action: String) -> void:
	var spr: Control = _hud[side]["avatar"]
	if spr is FightSpriteScript:
		spr.play_once(p_action)


func _avatar_center(side: int) -> Vector2:
	return _avatar_home[side] + _av_size / 2.0


const _AVATAR_SIZE := Vector2(168, 168)
var _av_size := _AVATAR_SIZE   # 紧凑视口(手机)缩到 132, 给底部操作行让位


func _side_x(seat: int) -> float:
	return _avatar_center(_side_of_seat(seat)).x


## 冲刺攻击: 向对手方向突进后回位
func _lunge(side: int, reach := 84.0) -> void:
	var avatar: Control = _hud[side]["avatar"]
	var home := Vector2.ZERO   # avatar 在 holder 内的局部原点(舞台坐标见 _avatar_home)
	var dir := 1.0 if side == 0 else -1.0
	_avatar_busy[side] = true
	var tw := avatar.create_tween()
	tw.tween_property(avatar, "position",
			home + Vector2(dir * reach, -14.0), 0.13) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(avatar, "position", home, 0.2) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void: _avatar_busy[side] = false)


## 受击姿态: 后仰抖动 + 白闪
func _hit_pose(side: int) -> void:
	var avatar: Control = _hud[side]["avatar"]
	avatar.modulate = Color(2.4, 1.2, 1.2)
	var home := Vector2.ZERO
	_avatar_busy[side] = true
	var tw := avatar.create_tween()
	tw.tween_property(avatar, "position", home + Vector2(-6.0 if side == 0
			else 6.0, 4.0), 0.06)
	tw.tween_property(avatar, "position", home, 0.1)
	tw.parallel().tween_property(avatar, "modulate", Color.WHITE, 0.16)
	tw.tween_callback(func() -> void: _avatar_busy[side] = false)


## 技能施法姿态: 后仰蓄力 + 前倾释放
func _skill_cast_pose(side: int) -> void:
	var avatar: Control = _hud[side]["avatar"]
	var home := Vector2.ZERO
	var dir := -1.0 if side == 0 else 1.0
	_avatar_busy[side] = true
	var tw := avatar.create_tween()
	tw.tween_property(avatar, "position", home + Vector2(dir * 18.0, 4.0), 0.1)
	tw.tween_property(avatar, "position", home + Vector2(-dir * 14.0, -6.0), 0.12)
	tw.tween_property(avatar, "position", home, 0.14)
	tw.tween_callback(func() -> void: _avatar_busy[side] = false)


## 闪避: 快速侧移回位
func _dodge(side: int) -> void:
	var avatar: Control = _hud[side]["avatar"]
	var home := Vector2.ZERO
	var dir := 1.0 if side == 0 else -1.0
	_avatar_busy[side] = true
	var tw := avatar.create_tween()
	tw.tween_property(avatar, "position",
			home + Vector2(dir * 56.0, 0.0), 0.09)
	tw.tween_property(avatar, "position",
			home + Vector2(dir * 30.0, 0.0), 0.07)
	tw.tween_property(avatar, "position", home, 0.1)
	tw.tween_callback(func() -> void: _avatar_busy[side] = false)


## 技能弹道: 元素色光球从施法者飞向目标, 命中炸开光环
func _projectile(from: Vector2, to: Vector2, col: Color) -> void:
	var orb := _FXOrb.new()
	orb.color = col
	orb.position = from
	orb.size = Vector2(18, 18)
	orb.z_index = 14
	_stage.add_child(orb)
	var tw := orb.create_tween()
	tw.tween_property(orb, "position", to, 0.28) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		_ring(to, col)
		_spark(to, col)
		orb.queue_free())


func _spark(at: Vector2, col: Color) -> void:
	var sp := _FXSpark.new()
	sp.color = col
	sp.position = at - Vector2(40, 40)
	sp.size = Vector2(80, 80)
	sp.z_index = 14
	_stage.add_child(sp)
	var tw := sp.create_tween()
	tw.tween_property(sp, "scale", Vector2(1.35, 1.35), 0.16)
	tw.parallel().tween_property(sp, "modulate:a", 0.0, 0.18)
	tw.tween_callback(sp.queue_free)


func _ring(at: Vector2, col: Color) -> void:
	var rg := _FXRing.new()
	rg.color = col
	rg.position = at - Vector2(50, 50)
	rg.size = Vector2(100, 100)
	rg.z_index = 13
	_stage.add_child(rg)
	var tw := rg.create_tween()
	tw.tween_property(rg, "scale", Vector2(1.7, 1.7), 0.3)
	tw.parallel().tween_property(rg, "modulate:a", 0.0, 0.32)
	tw.tween_callback(rg.queue_free)


## 全屏白闪(奥义)
func _flash() -> void:
	if _stage_flash != null and is_instance_valid(_stage_flash):
		_stage_flash.queue_free()
	_stage_flash = ColorRect.new()
	_stage_flash.color = Color(1, 1, 1, 0.75)
	_stage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_flash.z_index = 20
	add_child(_stage_flash)
	var tw := _stage_flash.create_tween()
	tw.tween_property(_stage_flash, "color:a", 0.0, 0.35)
	tw.tween_callback(func() -> void:
		if _stage_flash != null and is_instance_valid(_stage_flash):
			_stage_flash.queue_free()
			_stage_flash = null)


## 狂暴演出: 红环 + 横幅
func _enrage_fx(side: int) -> void:
	var c := _avatar_center(side)
	_ring(c, Color("ff5050"))
	_ring(c, Color("ff8866"))
	_banner(tr("狂暴!"), Color("ff6b6b"))
	Audio.say("f_fury")


## 连击计数牌: 打击者头顶弹出
func _combo_chip(side: int, streak: int) -> void:
	var c := _avatar_center(side)
	var lb := _label(22, Color("ffd166"))
	lb.text = tr("连击 ×%d") % streak
	lb.z_index = 12
	lb.position = c + Vector2(-40, -110)
	lb.pivot_offset = Vector2(40, 14)
	floaters.add_child(lb)
	lb.scale = Vector2(1.5, 1.5)
	var tw := lb.create_tween()
	tw.tween_property(lb, "scale", Vector2.ONE, 0.14)
	tw.tween_interval(0.5)
	tw.tween_property(lb, "modulate:a", 0.0, 0.25)
	tw.tween_callback(lb.queue_free)


## 血条白闪
func _hp_flash(side: int) -> void:
	var p: Dictionary = _hud[side]
	var bg: ColorRect = p["hp_bg"]
	var fl: ColorRect = ColorRect.new()
	fl.color = Color(1, 1, 1, 0.85)
	fl.size = bg.size
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fl)
	var tw := fl.create_tween()
	tw.tween_property(fl, "color:a", 0.0, 0.25)
	tw.tween_callback(fl.queue_free)


## 大字横幅(回合胜负/狂暴)
func _banner(text: String, col: Color) -> void:
	var lb := _label(40, col)
	lb.text = text
	lb.z_index = 18
	lb.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	lb.add_theme_constant_override("shadow_offset_y", 3)
	floaters.add_child(lb)
	lb.reset_size()
	lb.position = Vector2(size.x / 2.0 - lb.size.x / 2.0, size.y * 0.30)
	lb.pivot_offset = lb.size / 2.0
	lb.scale = Vector2(1.6, 1.6)
	var tw := lb.create_tween()
	tw.tween_property(lb, "scale", Vector2.ONE, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.7)
	tw.tween_property(lb, "modulate:a", 0.0, 0.3)
	tw.tween_callback(lb.queue_free)


func _shake(strength: float) -> void:
	if _shake_t > 0.0:
		return
	_shake_t = 0.18
	var tw := _stage.create_tween()
	for i in 5:
		var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * 0.4
		tw.tween_property(_stage, "position", off, 0.035)
	tw.tween_property(_stage, "position", Vector2.ZERO, 0.035)


func _floater(text: String, x: float, y: float, col: Color, fsize := 22) -> void:
	var lb := _label(fsize, col)
	lb.text = text
	lb.z_index = 10
	lb.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	lb.add_theme_constant_override("shadow_offset_y", 2)
	floaters.add_child(lb)
	lb.reset_size()
	lb.position = Vector2(x - lb.size.x / 2.0, y)
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
	var body := tr("比分 %d : %d — 胜者 %s") % [int(sc.get(_seat_at(0), 0)),
			int(sc.get(_seat_at(1), 0)),
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
	# 房主可见「再来一局」快捷重开(同规则直接开新对局)。
	# 属性存在性防御: 兼容测试桩等精简 net 实现。
	if net == null or not ("last_room_state" in net) or not ("my_seat" in net):
		return false
	return int(net.last_room_state.get("host_seat", -1)) == int(net.my_seat)


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
			_auto_leave_timer = null
			_close_overlay()   # 新对局视图到达后自动进入下一局编成
			if net != null:
				net.start_game())
		row.add_child(again)
	var room_btn := AppTheme.make_button("返回房间", Vector2(150, 46), 16)
	room_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_do_leave())
	row.add_child(room_btn)
	add_child(overlay)
	overlay.position = Vector2.ZERO
	overlay.size = size
	# 终局展示 6 秒后自动返回房间页(可点按钮提前)
	_auto_leave_timer = get_tree().create_timer(6.0)
	var my_overlay := overlay
	_auto_leave_timer.timeout.connect(func() -> void:
		if is_instance_valid(my_overlay) and overlay == my_overlay:
			_do_leave())


func _close_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null


## ── 离开: 退出本场留在房间(双方都退 → 服务器自动收尾) ──
func _do_leave() -> void:
	_close_overlay()
	_auto_leave_timer = null
	if net != null:
		net.leave_match()
	finished.emit()


## ── 回合计时 ──
func _reset_timer() -> void:
	if str(view.get("phase", "")) == "battle":
		_turn_remain = float(view.get("turn_seconds", 20))
	else:
		_turn_remain = -1.0
	_timer_shown_v = -1


func _process(delta: float) -> void:
	# 头像呼吸浮动(战斗阶段) + 光环/回合圈旋转
	if str(view.get("phase", "")) == "battle":
		_bob_t += delta
		for i in 2:
			var avatar: Control = _hud[i]["avatar"]
			if avatar != null and is_instance_valid(avatar) \
					and not bool(_avatar_busy[i]):
				# 位移动画(冲刺/受击/闪避)期间让位 — 否则每帧覆盖, 动画全被吃掉
				avatar.position = Vector2(0.0,
						sin(_bob_t * 2.0 + i * 2.1) * 5.0)
	for i in 2:
		var p: Dictionary = _hud[i]
		for key in ["aura", "turn_ring"]:
			var fx: Control = p.get(key, null)
			if fx != null and is_instance_valid(fx) and fx.visible:
				p[key + "_spin"] = float(p[key + "_spin"]) + delta * 1.5
				fx.queue_redraw()
	if _shake_t > 0.0:
		_shake_t -= delta
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


## ── HUD 构建(左上/右上两角): 7 槽 + 名字/比分 + 血条/怒气 ──
func _build_hud(idx: int) -> Dictionary:
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(Color(0.09, 0.07, 0.16, 0.92),
			Color(1, 1, 1, 0.18), 12, 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	# ── 名字行: ▶ 名字 (你) · 回合胜 n · 编成状态 ──
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 6)
	box.add_child(name_row)
	var turn_chip := AppTheme.make_label(14, AppTheme.GOLD)
	turn_chip.text = "▶"
	turn_chip.visible = false
	name_row.add_child(turn_chip)
	var nm := AppTheme.make_label(15, AppTheme.WHITE)
	nm.text = "玩家"
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(96, 0)
	name_row.add_child(nm)
	var you := AppTheme.make_label(12, Color("7dd87d"))
	you.text = tr("(你)")
	you.visible = false
	name_row.add_child(you)
	var score := AppTheme.make_label(13, AppTheme.GOLD)
	score.text = tr("回合胜 0")
	name_row.add_child(score)
	var done := AppTheme.make_label(12, Color("9fd8ff"))
	done.visible = false
	name_row.add_child(done)
	var left_chip := AppTheme.make_label(12, Color("ff9a6a"))
	left_chip.text = tr("🤖 AI 代管")
	left_chip.visible = false
	name_row.add_child(left_chip)
	# ── 装备槽 5 + 奇物槽 2(合并一行; 手机 HUD 收窄不遮挡中央舞台) ──
	# 槽位 46×62(任务反馈: 原 34×46 看不清): 卡面与牌点清晰可读
	var slots_row := HBoxContainer.new()
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_row.add_theme_constant_override("separation", 4)
	box.add_child(slots_row)
	var slots_ui: Array = []
	for s in 5:
		var wrap := PanelContainer.new()
		var ssb := AppTheme.flat(Color(0.06, 0.06, 0.14),
				Color(1, 1, 1, 0.25), 6, 1)
		ssb.content_margin_left = 2
		ssb.content_margin_right = 2
		ssb.content_margin_top = 2
		ssb.content_margin_bottom = 2
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
		var rglyph := AppTheme.make_label(24, Color("c89ae8"))
		rglyph.text = "◇"
		rcc.add_child(rglyph)
		rwrap.add_child(rcc)
		slots_row.add_child(rwrap)
		relic_ui.append({"wrap": rwrap, "sb": rsb, "glyph": rglyph})
	# ── 生命条 ──
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.6)
	hp_bg.custom_minimum_size = Vector2(280, 16)
	var hp_fg := ColorRect.new()
	hp_fg.color = Color("58c858")
	hp_fg.position = Vector2(2, 2)
	hp_fg.size = Vector2(302, 12)
	hp_bg.add_child(hp_fg)
	box.add_child(hp_bg)
	var hp_txt := _label(12, AppTheme.WHITE)
	hp_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hp_txt)
	# ── 怒气条 ──
	var fury_bg := ColorRect.new()
	fury_bg.color = Color(0, 0, 0, 0.6)
	fury_bg.custom_minimum_size = Vector2(280, 9)
	var fury_fg := ColorRect.new()
	fury_fg.color = AppTheme.GOLD
	fury_fg.position = Vector2(2, 2)
	fury_fg.size = Vector2(0, 5)
	fury_bg.add_child(fury_fg)
	box.add_child(fury_bg)
	# ── 状态区两行(任务反馈: 原 HP/牌型/属性三行占高太多) ──
	# 行1: HP(+护盾) · 牌型协同;  行2: 攻/防/技属性(+技能冷却)
	var stats := AppTheme.make_label(12, Color("c9b06a"))
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.custom_minimum_size = Vector2(320, 18)
	box.add_child(stats)
	# 装备/奇物计数并入"选牌中/已编成"文案(独立行已并入, 卡槽区高度 -18px)
	var prog := AppTheme.make_label(12, Color("c9b06a"))
	prog.visible = false
	box.add_child(prog)
	if idx == 1:
		box.layout_direction = Control.LAYOUT_DIRECTION_RTL   # 右侧镜像对称
	return {"panel": panel, "sb": sb, "name": nm, "you": you,
			"hp_fg": hp_fg, "hp_bg": hp_bg, "hp_txt": hp_txt,
			"fury_bg": fury_bg, "fury_fg": fury_fg, "stats": stats,
			"turn_chip": turn_chip, "score": score, "prog": prog, "done": done,
			"slots_ui": slots_ui, "relic_ui": relic_ui,
			"left_chip": left_chip}


## ── 中央对战舞台: 无框大头像 + 脚下回合圈 + 变身光环 ──
func _build_stage() -> void:
	for i in 2:
		var holder := Control.new()
		holder.custom_minimum_size = _AVATAR_SIZE
		var aura := Control.new()
		aura.size = _AVATAR_SIZE
		aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
		aura.visible = false
		aura.set_meta("side", i)
		aura.draw.connect(_draw_ring.bind(aura, true))
		holder.add_child(aura)
		_hud[i]["aura"] = aura
		_hud[i]["aura_spin"] = 0.0
		var turn_ring := Control.new()
		turn_ring.size = _AVATAR_SIZE
		turn_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		turn_ring.visible = false
		turn_ring.set_meta("side", i)
		turn_ring.draw.connect(_draw_ring.bind(turn_ring, false))
		holder.add_child(turn_ring)
		_hud[i]["turn_ring"] = turn_ring
		_hud[i]["turn_ring_spin"] = 0.0
		var avatar: Control = FightSpriteScript.new()
		avatar.flip_h = i == 1   # 右侧格斗者镜像, 面向左侧对手
		avatar.custom_minimum_size = _AVATAR_SIZE
		avatar.size = _AVATAR_SIZE
		avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(avatar)
		_hud[i]["avatar"] = avatar
		_stage.add_child(holder)


## 脚下圈/变身光环(主花色变色): 旋转外环 + 辉光内环 + 8 向射线
func _draw_ring(ring: Control, is_aura: bool) -> void:
	if not ring.visible:
		return
	var idx: int = int(ring.get_meta("side", 0))
	var seat := _seat_at(idx)
	var col := AppTheme.GOLD if not is_aura else _suit_color(seat)
	var c := ring.size / 2.0
	var spin: float = float(_hud[idx].get(
			"aura_spin" if is_aura else "turn_ring_spin", 0.0))
	if is_aura:
		ring.draw_arc(c, 62.0, 0, TAU, 40, Color(col, 0.8), 3.0, true)
		ring.draw_arc(c, 55.0, 0, TAU, 40, Color(col, 0.35), 7.0, true)
		for i in 8:
			var a := TAU * i / 8.0 + spin
			ring.draw_line(c + Vector2.from_angle(a) * 68.0,
					c + Vector2.from_angle(a) * 76.0, Color(col, 0.85), 2.5, true)
	else:
		# 回合指示: 脚下扁椭圆(透视感)
		var pts := PackedVector2Array()
		for i in 32:
			var a := TAU * i / 32.0 + spin * 0.4
			pts.append(c + Vector2(0, 62) + Vector2(cos(a) * 58.0, sin(a) * 13.0))
		ring.draw_colored_polygon(pts, Color(col, 0.22))
		for i in 32:
			var a2 := TAU * i / 32.0 + spin * 0.4
			ring.draw_line(c + Vector2(0, 62)
					+ Vector2(cos(a2) * 58.0, sin(a2) * 13.0),
					c + Vector2(0, 62) + Vector2(cos(a2 + 0.22) * 58.0,
					sin(a2 + 0.22) * 13.0), Color(col, 0.75), 2.0, true)


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


## 中央舞台纵向定位: HUD 面板之下, 底部操作区(编成面板/行动行)之上。
## 底部高占用(编成中 254px)时头像整体上移, 保证完整可见不被遮挡。
func _layout_stage() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	var hud_w := minf(352.0, w * 0.30)
	var phase := str(view.get("phase", ""))
	var fighter: bool = not bool(view.get("spectator", true))
	# 编成面板只在"我还没编完"时满高占用; 已编成/战斗阶段按单行预留
	var bottom_h := 84.0
	if phase == "draft" and fighter \
			and not bool((view.get("my", {}) as Dictionary).get("done", true)):
		bottom_h = 254.0
	var panel_bottom: float = 86.0 \
			+ (_hud[0]["panel"] as Control).get_combined_minimum_size().y
	var top_limit: float = panel_bottom + 10.0
	var bottom_limit: float = h - bottom_h - _av_size.y - 6.0
	var av_y: float = clampf(maxf(panel_bottom + 10.0, h * 0.42),
			minf(top_limit, bottom_limit), maxf(top_limit, bottom_limit))
	_avatar_home[0] = Vector2(24.0 + hud_w * 0.5 - _av_size.x * 0.5, av_y)
	_avatar_home[1] = Vector2(w - 24.0 - hud_w * 0.5 - _av_size.x * 0.5, av_y)
	for i in 2:
		var holder: Control = _hud[i]["avatar"].get_parent()
		holder.position = _avatar_home[i]
	_vs_lbl.position = Vector2(w / 2.0 - 24.0, av_y + _av_size.y * 0.5 - 22.0)


func _relayout() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	leave_btn.position = Vector2(w - 140.0, 26)
	phase_lbl.position = Vector2(w / 2.0 - 150.0, 30)
	score_lbl.position = Vector2(w / 2.0 - 22.0, 60)
	spec_lbl.position = Vector2(w / 2.0 - 140.0, 88)
	_conn_lbl.position = Vector2(w / 2.0 - 150.0, 112)
	# ── 双角 HUD: 我方左上 / 对手右上(加宽到 384 配合调大后的卡槽,
	# 窄屏按 0.32 比例收窄, 给中央舞台让位) ──
	var hud_w := minf(384.0, w * 0.32)
	var bar_w := maxf(hud_w - 24.0, 140.0)
	for i in 2:
		var panel: PanelContainer = _hud[i]["panel"]
		panel.custom_minimum_size = Vector2(hud_w, 0)
		panel.size = Vector2(hud_w, 0)
		panel.position = Vector2(24.0 if i == 0 else w - hud_w - 24.0, 86.0)
		# 血条/怒气条/文案行宽度随面板(此前固定宽, 窄面板会溢出)
		(_hud[i]["hp_bg"] as ColorRect).custom_minimum_size = Vector2(bar_w, 18)
		(_hud[i]["fury_bg"] as ColorRect).custom_minimum_size = Vector2(bar_w, 11)
		(_hud[i]["hp_txt"] as Label).custom_minimum_size = Vector2(bar_w, 20)
		(_hud[i]["stats"] as Label).custom_minimum_size = Vector2(bar_w, 18)
	# ── 中央舞台: 大头像对峙 — 水平锚在各自面板中线下方(不再被面板遮挡) ──
	# 紧凑视口(手机)头像缩小一档: 底部操作行(h-84)之上留出净空
	_av_size = Vector2(120, 120) if h < 660.0 else Vector2(148, 148)
	for i in 2:
		var holder: Control = _hud[i]["avatar"].get_parent()
		holder.custom_minimum_size = _av_size
		for ch in holder.get_children():
			(ch as Control).size = _av_size
			(ch as Control).custom_minimum_size = _av_size
	_layout_stage()
	# 战斗日志移到顶部中央(原左下会压住我方头像与底部抽牌面板)
	log_lbl.position = Vector2(w / 2.0 - 170.0, 136.0)
	log_lbl.custom_minimum_size = Vector2(minf(340.0, w * 0.4), 88.0)
	log_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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


## ── 特效小控件 ──

## 技能弹道光球(带拖尾)
class _FXOrb extends Control:
	var color := Color("7ec8ff")
	var _trail: Array = []

	func _process(_d: float) -> void:
		_trail.append(position)
		if _trail.size() > 6:
			_trail.pop_front()
		queue_redraw()

	func _draw() -> void:
		for i in _trail.size():
			var t: float = float(i + 1) / _trail.size()
			draw_circle(size / 2.0 + (_trail[i] - position),
					6.0 * t, Color(color, 0.25 * t))
		draw_circle(size / 2.0, 8.0, Color(color, 0.9))
		draw_circle(size / 2.0, 4.0, Color(1, 1, 1, 0.9))


## 命中火花(放射线)
class _FXSpark extends Control:
	var color := Color("ffd166")

	func _draw() -> void:
		var c := size / 2.0
		for i in 10:
			var a := TAU * i / 10.0 + randf() * 0.4
			var r0 := size.x * (0.12 + randf() * 0.08)
			var r1 := size.x * (0.34 + randf() * 0.14)
			draw_line(c + Vector2.from_angle(a) * r0,
					c + Vector2.from_angle(a) * r1,
					Color(color, randf_range(0.6, 1.0)), 3.0, true)
		draw_circle(c, size.x * 0.10, Color(1, 1, 1, 0.9))


## 扩散光环(护盾/治疗/命中冲击)
class _FXRing extends Control:
	var color := Color("7ec8ff")

	func _draw() -> void:
		var c := size / 2.0
		draw_arc(c, size.x * 0.36, 0, TAU, 40, Color(color, 0.85), 4.0, true)
		draw_arc(c, size.x * 0.28, 0, TAU, 40, Color(color, 0.4), 8.0, true)
