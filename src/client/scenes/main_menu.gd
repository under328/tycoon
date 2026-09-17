## 主菜单：本地游戏 / 联机游戏 / 设置 / 退出。动态背景见 menu_background.gd。
extends Control

const AppTheme = preload("res://src/client/theme/app_theme.gd")

signal local_game(mode: String)
signal online_game
signal fight_mode
signal fight_daily

const BGScript = preload("res://src/client/ui/menu_background.gd")
const SettingsPanelScript = preload("res://src/client/ui/settings_panel.gd")
const ShopScript = preload("res://src/client/ui/shop.gd")
const TutorialScript = preload("res://src/client/scenes/tutorial.gd")
const SlashItem = preload("res://src/client/ui/slash_menu_item.gd")
const Wafu = preload("res://src/client/ui/wafu_paint.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")
const Icons = preload("res://src/client/ui/icons.gd")
const CardViewScript = preload("res://src/client/ui/card_view.gd")
const SlashLine = preload("res://src/client/ui/slash_line.gd")
const SealStamp = preload("res://src/client/ui/seal_stamp.gd")
const AvatarScript = preload("res://src/client/ui/avatar.gd")


var _settings: Control
var _tutorial_item: Control
var _shop: Control
var _balance: Control          # CurrencyText 金额行
var _title_group: Control   # 标题/斩切线/副标/朱印 组容器(内部坐标固定, 整体锚定)
var _title_inner: Control   # 标题内层(呼吸浮动动画目标, 外层锚定不受影响)
var _slash_line: Control    # 刀斩切线(锥形笔触)
var _seal: Control          # 朱印
var _title_chars: Array = []   # 大/富/豪 分字标签(入场动画用)
var _profile: PanelContainer   # 左上角玩家头像卡
var _prof_avatar: Control
var _prof_name: Label
var _prof_rank: Label
var _badge: PanelContainer
var _mode_dlg: Control = null   # 模式选择弹窗
var _tutorial: Control = null   # 新手引导页(打开期间持有)
var _ver_lbl: Label
var _hint_lbl: Label
var _fan: Control             # 右下卡扇(展示已装备卡面)
var _bg: Control                # 菜单动态背景
var _menu_items: Array = []     # 斜切菜单项(位置由 _relayout 按屏高自适应)


func _ready() -> void:
	# 根 Control 由代码 new 出且父节点是普通 Node, 锚点不可靠 → 显式铺满视口
	set_anchors_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	theme = AppTheme.build_theme()

	_bg = BGScript.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 移动端: 菜单被安全区内缩, 背景描金边框会贴在分隔线上 → 隐藏
	add_child(_bg)

	_build_title()
	_build_menu()
	_build_fan()
	_build_profile()
	_build_settings()
	_settings.name = "Page"
	resized.connect(_sync_pages)
	Responsive.watch(self, _relayout)
	# 余额即时同步: 对局结算(后台托管打完也会结算)发放金币/钻石时首页立即刷新
	Wallet.balance_changed.connect(_refresh_balance)
	Audio.play_bgm("lobby")
	# 先同步收敛一次布局, 再录入场动画的起点/终点:
	# 否则入场 tween 会把菜单项带去过期的构建默认坐标(响应式位置被覆盖)
	_relayout()
	_play_entrance()
	# 布局二次收敛: 首帧绘制后 CurrencyText/称号等晚成型控件尺寸才稳定
	_relayout.call_deferred()


## 多设备自适应(1280x720 设计基准): 标题组锚右半区并随高度下移,
## 余额徽章按屏宽比例边距锚右上, 菜单项按屏高自适应间距,
## 版本号左下, 底部提示居中, 卡扇贴右下——手机/平板/PC 通吃。
func _relayout() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	var margin := maxf(28.0, w * 0.025)   # 屏越宽边距越大(手机不再贴边)
	var tx := clampf(w * 0.45, 500.0, w - 540.0)
	if _title_group != null:
		# 组原点反向补偿标题组 PAD(14,16): 画面位置与设计基准一致
		_title_group.position = Vector2(tx, clampf(h * 0.17, 28.0, 170.0)) \
				- Vector2(14, 16)
		# 窄屏(逻辑宽 < 标题设计宽 560)整体等比缩小标题组: 朱印/切线不越右缘
		var ts := minf(1.0, (w - tx) / 560.0)
		_title_group.scale = Vector2(ts, ts)
	if _profile != null:
		_profile.position = Vector2(margin * 0.55, margin * 0.55)
	if _badge != null:
		_badge.position = Vector2(w - _badge.size.x - margin, 30)
	if _ver_lbl != null:
		_ver_lbl.position = Vector2(16, h - 30)
	if _hint_lbl != null:
		_hint_lbl.position = Vector2((w - _hint_lbl.size.x) / 2.0, h - 36)
	if _fan != null:
		# 矮屏(逻辑高 < 640): 卡扇下移到底缘上方并缩小, 让位给标题区
		var fs := clampf(h / 720.0, 0.78, 1.0)
		var fy := h * 0.60 if h >= 640.0 else h - 150.0
		_fan.scale = Vector2(fs, fs)
		_fan.position = Vector2(w - 356.0, fy)
	# 菜单项: 按可用高度自适应间距(手机紧凑视口也能放下全部六项)
	var y0 := clampf(h * 0.23, 110.0, 188.0)
	var spacing := clampf((h - y0 - 120.0) / 5.0, 52.0, 76.0)
	for i in _menu_items.size():
		var it: Control = _menu_items[i]
		it.position = Vector2(clampf(90.0 + i * 28.0, 40.0, w - 490.0), y0 + i * spacing)


## 标题「大富豪」v2: 三字分字排布(错落节奏, 中字放大) + 描边晕影,
## 下方刀斩切线(锥形笔触), 右上「富」字朱印; 入场动画见 _play_entrance。
func _build_title() -> void:
	# 巨型行书标题组: 内部坐标固定, _relayout 整体锚定到右半区(设计基准 x=576)
	_title_group = Control.new()
	_title_group.position = Vector2(576, 28)
	_title_group.custom_minimum_size = Vector2(520, 280)
	_title_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_group)
	# 内层: 呼吸浮动只动这里, 外层锚定不被覆盖
	_title_inner = Control.new()
	_title_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_group.add_child(_title_inner)

	# 分字: 大 / 富 / 豪 — 逐字独立旋转与高低错落(行书 rhythm), 中字放大提气
	# (行书字形视觉高度 ≈ 1.14×字号, 切线锚在字形底缘之下)
	# 子元素统一加 PAD: 切线左伸/中字上提的负偏移折进组原点(自适应断言要求
	# 局部坐标 ≥ -6), _relayout 中组位置反向补偿, 画面不变
	const PAD := Vector2(14, 16)
	var layout := [
		["大", Vector2(0, 10) + PAD, 150, -0.10],
		["富", Vector2(154, -12) + PAD, 166, -0.045],
		["豪", Vector2(326, 12) + PAD, 150, 0.0],
	]
	for spec: Array in layout:
		var ch := AppTheme.make_label(int(spec[2]), Color("f2c14e"))
		ch.add_theme_font_override("font", AppTheme.title_font())
		ch.text = str(spec[0])
		ch.position = spec[1]
		ch.rotation = float(spec[3])
		# 描边 + 晕影: 暖褐描边沉底, 黑晕右下, 字面亮金
		ch.add_theme_color_override("font_outline_color", Color(0.19, 0.09, 0.04, 0.92))
		ch.add_theme_constant_override("outline_size", int(spec[2]) * 0.055)
		ch.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
		ch.add_theme_constant_override("shadow_offset_x", 5)
		ch.add_theme_constant_override("shadow_offset_y", 6)
		_title_inner.add_child(ch)
		_title_chars.append(ch)

	# 刀斩切线(替代旧纯色矩形): 锥形笔触 + 金发丝线
	# (斜率压平 + 锚在字形底缘下: 右端上挑也不擦到「豪」的收笔)
	_slash_line = SlashLine.new()
	_slash_line.slope = -0.04
	_slash_line.position = Vector2(-14, 202) + PAD
	_slash_line.size = Vector2(470, 16)
	_title_inner.add_child(_slash_line)

	# 英文副标: 贴切线下方, 同斜率
	var sub := AppTheme.make_label(22, AppTheme.DIM)
	sub.add_theme_font_override("font", AppTheme.display_font())
	sub.text = "T  Y  C  O  O  N"
	sub.position = Vector2(72, 236) + PAD
	sub.rotation = -0.035
	_title_inner.add_child(sub)

	# 「富」字朱印: 落款位 — 切线末端右下(暗色山景上, 避开红日底色)
	_seal = SealStamp.new()
	_seal.position = Vector2(478, 196) + PAD
	_seal.size = Vector2(64, 64)
	_seal.rotation = 0.08
	_title_inner.add_child(_seal)


## 左上角玩家头像卡: 皮肤头像 + 昵称 + 称号·战绩, 点击打开成就·战绩页。
## 换装(商城)后 equipped_changed 即时刷新头像。
func _build_profile() -> void:
	_profile = PanelContainer.new()
	var sb := AppTheme.flat(Color(0.06, 0.06, 0.14, 0.92), Color(AppTheme.GOLD, 0.6), 10, 2)
	sb.content_margin_left = 12
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 6
	_profile.add_theme_stylebox_override("panel", sb)
	_profile.mouse_filter = Control.MOUSE_FILTER_STOP
	_profile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_profile.tooltip_text = "查看成就与战绩"
	_profile.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			Audio.play("click")
			var pp: Control = (load("res://src/client/ui/profile_panel.gd") as GDScript).new()
			_mount_page(pp)
			pp.closed.connect(func() -> void:
				pp.queue_free()
				_refresh_profile()))
	add_child(_profile)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_profile.add_child(row)
	_prof_avatar = AvatarScript.new()
	_prof_avatar.custom_minimum_size = Vector2(48, 48)
	_prof_avatar.size = Vector2(48, 48)
	_prof_avatar.skin_id = Wallet.equipped_skin
	row.add_child(_prof_avatar)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	_prof_name = AppTheme.make_label(16, AppTheme.WHITE)
	_prof_name.text = str(GameSettings.nickname)
	col.add_child(_prof_name)
	_prof_rank = AppTheme.make_label(12, AppTheme.GOLD)
	_prof_rank.text = "%s · %d胜/%d场" % [Wallet.rank_title(),
			Wallet.local_wins, Wallet.local_matches]
	col.add_child(_prof_rank)
	Wallet.equipped_changed.connect(func() -> void:
		_prof_avatar.skin_id = Wallet.equipped_skin)


func _refresh_profile() -> void:
	if _prof_name == null:
		return
	_prof_name.text = str(GameSettings.nickname)
	_prof_rank.text = "%s · %d胜/%d场" % [Wallet.rank_title(),
			Wallet.local_wins, Wallet.local_matches]


## 入场编排: 三字依次落定(错落旋转回正) → 切线自左描绘 → 朱印钤落
## → 副标浮现 → 菜单项左移滑入。全部短促(≤1.6s), 不阻塞点击。
func _play_entrance() -> void:
	# 标题三字
	for i in _title_chars.size():
		var ch: Label = _title_chars[i]
		var target := ch.rotation
		ch.modulate.a = 0.0
		ch.rotation = target - 0.22
		ch.position.y += 34
		var tw := create_tween()
		tw.tween_interval(0.10 + i * 0.12)
		tw.set_parallel(true)
		tw.tween_property(ch, "modulate:a", 1.0, 0.34).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(ch, "rotation", target, 0.44) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(ch, "position:y", ch.position.y - 34.0, 0.44) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 切线描绘
	_slash_line.draw_t = 0.0
	var tw2 := create_tween()
	tw2.tween_interval(0.42)
	tw2.tween_property(_slash_line, "draw_t", 1.0, 0.38) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 朱印钤落
	_seal.pivot_offset = _seal.size / 2.0
	_seal.modulate.a = 0.0
	_seal.scale = Vector2(1.7, 1.7)
	(_seal as SealStamp).stamp_t = 0.0
	var tw3 := create_tween()
	tw3.tween_interval(0.55)
	tw3.set_parallel(true)
	tw3.tween_property(_seal, "modulate:a", 1.0, 0.16)
	tw3.tween_property(_seal, "stamp_t", 1.0, 0.30)
	tw3.tween_property(_seal, "scale", Vector2.ONE, 0.34) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 副标浮现
	for c in _title_inner.get_children():
		if c is Label and str((c as Label).text) == "T  Y  C  O  O  N":
			c.modulate.a = 0.0
			var tw4 := create_tween()
			tw4.tween_interval(0.75)
			tw4.tween_property(c, "modulate:a", 1.0, 0.4)
	# 菜单项左移滑入(错峰)
	for i in _menu_items.size():
		var it: Control = _menu_items[i]
		var home := it.position
		it.modulate.a = 0.0
		it.position = home + Vector2(-46, 0)
		var tw5 := create_tween()
		tw5.tween_interval(0.18 + i * 0.055)
		tw5.set_parallel(true)
		tw5.tween_property(it, "modulate:a", 1.0, 0.3)
		tw5.tween_property(it, "position", home, 0.36) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 标题组呼吸浮动(循环, 只动内层)
	var bob := create_tween().set_loops()
	bob.tween_property(_title_inner, "position:y", 4.0, 1.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(_title_inner, "position:y", 0.0, 1.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 资产面板(锚右上): 双层金框 · 无倾斜 · 三行(货币/称号/操作按钮)
	_badge = PanelContainer.new()
	var b_outer := AppTheme.flat(Color(0.06, 0.06, 0.14, 0.92),
			Color(AppTheme.GOLD, 0.75), 6, 2)
	b_outer.content_margin_left = 14
	b_outer.content_margin_right = 14
	b_outer.content_margin_top = 10
	b_outer.content_margin_bottom = 10
	b_outer.shadow_color = Color(0, 0, 0, 0.5)
	b_outer.shadow_size = 8
	_badge.add_theme_stylebox_override("panel", b_outer)
	_badge.position = Vector2(1040, 30)
	add_child(_badge)
	var badge_box := VBoxContainer.new()
	badge_box.add_theme_constant_override("separation", 4)
	_badge.add_child(badge_box)

	# ── 第一行: 金币/钻石(图标+数值, 等宽对齐) ──
	_balance = Icons.CurrencyText.new(19)
	_balance.set_amounts(Wallet.gold, Wallet.diamonds, AppTheme.WHITE)
	badge_box.add_child(_balance)

	# ── 金色分隔线 ──
	var div := ColorRect.new()
	div.color = Color(AppTheme.GOLD, 0.30)
	div.custom_minimum_size = Vector2(0, 1)
	badge_box.add_child(div)

	# ── 第二行: 签到 + 成就·战绩 按钮行(战绩展示已移至左上角头像卡) ──
	var ops := HBoxContainer.new()
	ops.add_theme_constant_override("separation", 6)
	badge_box.add_child(ops)
	var sign_btn := AppTheme.make_button("签到", Vector2(64, 30), 14)
	sign_btn.visible = Wallet.can_sign_today()
	sign_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_show_signin(sign_btn))
	ops.add_child(sign_btn)
	var prof_btn := AppTheme.make_button("成就·战绩", Vector2(120, 30), 14)
	prof_btn.pressed.connect(func() -> void:
		Audio.play("click")
		var pp: Control = (load("res://src/client/ui/profile_panel.gd") as GDScript).new()
		_mount_page(pp)
		pp.closed.connect(func() -> void:
			pp.queue_free()
			_refresh_balance()))
	ops.add_child(prof_btn)

	# 版本号(锚左下)
	_ver_lbl = AppTheme.make_label(13, AppTheme.DIM)
	_ver_lbl.text = "v" + str(ProjectSettings.get_setting("application/config/version", "1.0.0"))
	_ver_lbl.reset_size()  # 文本晚于创建 → 刷新尺寸(避免居中锚定/绘制用旧宽度)
	_ver_lbl.position = Vector2(16, 690)
	add_child(_ver_lbl)


func _build_menu() -> void:
	var items := [
		["本地游戏", func() -> void:
			_show_mode_select(), "", "card"],
		["联机游戏", func() -> void:
			online_game.emit(), "", "net"],
		["商　城", func() -> void:
			_open_shop(), "", "bag"],
		["设　置", func() -> void:
			_settings.open(), "", "gear"],
		["新手引导", func() -> void:
			_open_tutorial(), _tutorial_badge(), "scroll"],
		["退出游戏", func() -> void:
			get_tree().quit(), "", "exit"],
	]
	for i in items.size():
		var item := SlashItem.new()
		item.text = str(items[i][0])
		item.badge = str(items[i][2])
		item.icon = str(items[i][3])
		item.position = Vector2(90 + i * 28, 188 + i * 76)
		item.custom_minimum_size = Vector2(440, 62)
		item.size = Vector2(440, 62)
		_menu_items.append(item)
		var cb: Callable = items[i][1]
		item.pressed.connect(cb)
		if str(items[i][0]) == "新手引导":
			_tutorial_item = item
		add_child(item)

	_hint_lbl = AppTheme.make_label(14, AppTheme.DIM)
	_hint_lbl.add_theme_font_override("font", AppTheme.accent_font())
	_hint_lbl.text = "和朋友开一局: 联机游戏 → 创建房间 → 把房间码发给朋友"
	_hint_lbl.reset_size()  # 文本晚于创建 → 刷新尺寸, _relayout 才能算准居中
	_hint_lbl.position = Vector2(400, 700)
	add_child(_hint_lbl)


## 右下卡扇: 展示已装备卡面(♠A + 大王像素画 + 牌背纹样), 商城换卡实时刷新
func _build_fan() -> void:
	_fan = Control.new()
	_fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 缩放锚在视觉中心偏右: _relayout 缩放卡扇时右缘位置不动
	_fan.pivot_offset = Vector2(150, 60)
	add_child(_fan)
	for info: Array in [[-1, -16.0], [53, 0.0], [44, 16.0]]:  # 牌背(底) → 大王 → ♠A(顶)
		var cv: Control = CardViewScript.new(int(info[0]))
		cv.face_down = int(info[0]) < 0
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.custom_minimum_size = Vector2(88, 122)
		cv.size = Vector2(88, 122)
		cv.pivot_offset = Vector2(44, 112)
		cv.rotation_degrees = float(info[1])
		_fan.add_child(cv)
	Wallet.equipped_changed.connect(_refresh_fan_palette)


func _refresh_fan_palette() -> void:
	if _fan == null:
		return
	for cv in _fan.get_children():
		cv._refresh_palette()
		cv.queue_redraw()


func _tutorial_badge() -> String:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and not bool(gs.tutorial_seen):
		return "NEW"
	return ""


## 模式选择弹窗: 普通(现行规则) / 肉鸽(命运卡); 右上 ? 打开图像化规则说明
func _show_mode_select() -> void:
	if _mode_dlg != null and is_instance_valid(_mode_dlg):
		_mode_dlg.queue_free()
	var dlg := Control.new()
	dlg.mouse_filter = Control.MOUSE_FILTER_STOP
	dlg.theme = AppTheme.build_theme()
	dlg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close_mode_select())
	dlg.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg.add_child(center)
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(AppTheme.PANEL, AppTheme.GOLD, 16, 2)
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 26
	sb.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	# 标题(右上 ? 已移除: 各模式方块右上角有独立的圆包 ? 帮助钮)
	var title := AppTheme.make_label(28, AppTheme.GOLD)
	title.text = "选择游戏模式"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	# AI 难度行(本地两种模式共用)
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 10)
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(diff_row)
	var diff_lbl := AppTheme.make_label(16, AppTheme.WHITE)
	diff_lbl.text = "AI 难度"
	diff_lbl.custom_minimum_size = Vector2(70, 0)
	diff_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	diff_row.add_child(diff_lbl)
	var diff_btns: Array = []
	for lv: Array in [["简单", "easy"], ["普通", "normal"]]:
		var b := AppTheme.make_button(str(lv[0]), Vector2(120, 40), 16)
		b.toggle_mode = true
		b.button_pressed = GameSettings.ai_level == str(lv[1])
		b.pressed.connect(func() -> void:
			Audio.play("click")
			GameSettings.ai_level = str(lv[1])
			GameSettings.save_settings()
			for other: Button in diff_btns:  # 单选互斥
				if other != b:
					other.set_pressed_no_signal(false))
		diff_btns.append(b)
		diff_row.add_child(b)
	# 四模式 2×2 方块: 图标 + 名称 + 描述 + 方块内右上角圆包 ? 帮助钮
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	box.add_child(grid)
	var modes := [
		["普通模式", "经典大富豪: 换牌 / 革命 / 8切, 回合制排名结算",
			"local_game", "normal", "normal_help.gd", "normal"],
		["肉鸽模式", "每局『命运二选一』定规则: 10 种命运卡随机登场",
			"local_game", "rogue", "rogue_help.gd", "rogue"],
		["格斗试炼", "化身头像人物, 五回合二选一编成 5 张装备, 决战 BOSS",
			"fight_mode", "fight", "fight_help.gd", "fight"],
		["每日挑战", "全设备同一天同一布局, 冲击今日最佳成绩",
			"fight_daily", "daily", "fight_help.gd", "daily"],
	]
	for m: Array in modes:
		grid.add_child(_build_mode_card(m))
	_mode_dlg = dlg
	add_child(dlg)


## 模式方块(2×2 网格格子): 点击进模式; 右上角圆包 ? 打开图文说明
func _build_mode_card(m: Array) -> Button:
	var card := AppTheme.make_button("", Vector2(336, 116), 16)
	card.name = "mode_%s" % str(m[3])   # 空文本按钮需显式命名(引擎拒绝空名)
	# 模式图标(方块前方)
	var icon := Icons.ModeIconView.new(str(m[5]))
	icon.position = Vector2(18, 30)
	icon.size = Vector2(56, 56)
	card.add_child(icon)
	# 名称 + 描述
	var name_lb := AppTheme.make_label(20, AppTheme.GOLD)
	name_lb.text = str(m[0])
	name_lb.position = Vector2(88, 16)
	card.add_child(name_lb)
	var desc := AppTheme.make_label(13, AppTheme.DIM)
	desc.text = str(m[1])
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size = Vector2(234, 58)
	desc.position = Vector2(88, 50)
	card.add_child(desc)
	# 圆包 ? 帮助钮(方块内右上角, 小巧不抢视觉)
	var help := AppTheme.make_button("?", Vector2(28, 28), 15)
	var circle := StyleBoxFlat.new()
	circle.bg_color = Color(0.16, 0.15, 0.32)
	circle.set_corner_radius_all(14)
	circle.set_border_width_all(1)
	circle.border_color = Color(AppTheme.GOLD, 0.7)
	help.add_theme_stylebox_override("normal", circle)
	var circle_h: StyleBoxFlat = circle.duplicate()
	circle_h.bg_color = Color(0.26, 0.24, 0.48)
	circle_h.set_border_width_all(2)
	help.add_theme_stylebox_override("hover", circle_h)
	help.add_theme_stylebox_override("pressed", circle_h)
	help.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	help.position = Vector2(336 - 38, 8)
	help.tooltip_text = "查看 %s 玩法说明" % str(m[0])
	var help_script := str(m[4])
	help.pressed.connect(func() -> void:
		Audio.play("click")
		_open_mode_help(help_script))
	card.add_child(help)
	# 点击方块主体 → 进入模式(子级 ? 钮自吸收点击, 不误触)
	var mmode := str(m[3])
	var msig := str(m[2])
	if msig == "fight_daily" and Wallet.daily_played_today():
		card.disabled = true   # 每日挑战每日一次: 已参与当日置灰
		desc.text = str(m[1]) + "
今日已参与, 明天再来 — 格斗试炼奖励不受限"
	if msig == "fight_daily" and not Wallet.daily_played_today():
		desc.text = str(m[1]) + "
每日一次, 奖励为格斗试炼的两倍"
	card.pressed.connect(func() -> void:
		Audio.play("click")
		_close_mode_select()
		if msig == "fight_mode":
			fight_mode.emit()
		elif msig == "fight_daily":
			fight_daily.emit()
		else:
			local_game.emit(mmode))
	return card


## 打开模式说明页(图文), 关闭后回到模式选择弹窗
func _open_mode_help(script_name: String) -> void:
	var h: Control = (load("res://src/client/ui/" + script_name) as GDScript).new()
	h.closed.connect(func() -> void: h.queue_free())
	add_child(h)


## 每日签到弹窗: 7 天奖励轨道 + 今日领取
func _show_signin(sign_btn: Button) -> void:
	if not Wallet.can_sign_today():
		return
	var dlg := Control.new()
	dlg.mouse_filter = Control.MOUSE_FILTER_STOP
	dlg.theme = AppTheme.build_theme()
	dlg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg.add_child(center)
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(AppTheme.PANEL, AppTheme.GOLD, 16, 2)
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 24
	sb.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title := AppTheme.make_label(26, AppTheme.GOLD)
	title.text = "每日签到 · 连续 %d 天" % Wallet.sign_streak
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	# 7 天轨道(高亮今日可领的那格)
	var track := HBoxContainer.new()
	track.add_theme_constant_override("separation", 8)
	track.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(track)
	var next_idx := Wallet.sign_streak % Wallet.SIGN_REWARDS.size()
	for i in Wallet.SIGN_REWARDS.size():
		var rw: Dictionary = Wallet.SIGN_REWARDS[i]
		var txt := "第%d天
%s" % [i + 1, _signin_reward_text(rw)]
		var cell := AppTheme.make_label(14,
				AppTheme.GOLD if i == next_idx else AppTheme.DIM)
		cell.text = txt
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.custom_minimum_size = Vector2(76, 52)
		var wrap := PanelContainer.new()
		wrap.add_theme_stylebox_override("panel", AppTheme.flat(
				Color(0.10, 0.10, 0.22) if i == next_idx else Color(0.07, 0.07, 0.16),
				AppTheme.GOLD if i == next_idx else Color(1, 1, 1, 0.1), 8, 1))
		wrap.add_child(cell)
		track.add_child(wrap)
	var claim := AppTheme.make_button("签 到 领 取", Vector2(240, 50), 19)
	claim.pressed.connect(func() -> void:
		var r: Dictionary = Wallet.claim_signin()
		if r.is_empty():
			return
		Audio.play("win")
		_refresh_balance()
		sign_btn.visible = false
		dlg.queue_free()
		_toast_msg("签到成功: %+d金币 %+d钻石" % [int(r["gold"]), int(r["diamonds"])])
	)
	var wrap2 := CenterContainer.new()
	wrap2.add_child(claim)
	box.add_child(wrap2)
	add_child(dlg)


func _signin_reward_text(rw: Dictionary) -> String:
	var parts: Array = []
	if int(rw.get("gold", 0)) > 0:
		parts.append("%d金币" % int(rw["gold"]))
	if int(rw.get("diamonds", 0)) > 0:
		parts.append("%d钻石" % int(rw["diamonds"]))
	return " ".join(PackedStringArray(parts))


func _toast_msg(text: String) -> void:
	# 复用底部提示行(临时浮现)
	if _hint_lbl == null:
		return
	var prev := _hint_lbl.text
	var prev_color := _hint_lbl.get_theme_color("font_color")
	_hint_lbl.text = text
	_hint_lbl.add_theme_color_override("font_color", AppTheme.GOLD)
	_hint_lbl.reset_size()
	_hint_lbl.position = Vector2((size.x - _hint_lbl.size.x) / 2.0, size.y - 36)
	var tw := create_tween()
	tw.tween_interval(2.4)
	tw.tween_callback(func() -> void:
		_hint_lbl.text = prev
		_hint_lbl.add_theme_color_override("font_color", prev_color)
		_hint_lbl.reset_size()
		_hint_lbl.position = Vector2((size.x - _hint_lbl.size.x) / 2.0, size.y - 36))


func _close_mode_select() -> void:
	if _mode_dlg != null and is_instance_valid(_mode_dlg):
		_mode_dlg.queue_free()
	_mode_dlg = null


func _refresh_balance() -> void:
	if _balance != null:
		_balance.set_amounts(Wallet.gold, Wallet.diamonds, AppTheme.WHITE)
	if _badge != null and size.x > 100.0:
		# 金额文本晚成型会撑宽徽章: 刷新时按新尺寸重锚右上
		_badge.position = Vector2(size.x - _badge.size.x - maxf(28.0, size.x * 0.025), 30)
	_refresh_profile()


## 全屏页统一挂载: 显式铺满父级(锚点对代码 new 的 Control 不自动求值),
## 并在菜单尺寸变化(窗口拉伸/安全区变化)时同步所有已挂载页面
func _mount_page(page: Control) -> void:
	page.name = "Page"
	add_child(page)
	page.position = Vector2.ZERO
	page.size = size


func _sync_pages() -> void:
	for c in get_children():
		if c is Control and str(c.name) == "Page":
			(c as Control).size = size


func _open_shop() -> void:
	if _shop != null:
		return
	_shop = ShopScript.new()
	_mount_page(_shop)
	_shop.closed.connect(func() -> void:
		_shop.queue_free()
		_shop = null
		_refresh_balance())


func _open_tutorial() -> void:
	var tut := TutorialScript.new()
	_mount_page(tut)
	_tutorial = tut
	tut.closed.connect(func() -> void:
		_tutorial = null
		_tutorial_item.badge = _tutorial_badge())


func _build_settings() -> void:
	_settings = SettingsPanelScript.new()
	_settings.name = "Settings"
	add_child(_settings)


func _label(size: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", color)
	return lb
