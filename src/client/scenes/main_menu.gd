## 主菜单：本地游戏 / 联机游戏 / 设置 / 退出。动态背景见 menu_background.gd。
extends Control

const AppTheme = preload("res://src/client/theme/app_theme.gd")

signal local_game(mode: String)
signal online_game

const BGScript = preload("res://src/client/ui/menu_background.gd")
const SettingsPanelScript = preload("res://src/client/ui/settings_panel.gd")
const ShopScript = preload("res://src/client/ui/shop.gd")
const TutorialScript = preload("res://src/client/scenes/tutorial.gd")
const SlashItem = preload("res://src/client/ui/slash_menu_item.gd")
const Wafu = preload("res://src/client/ui/wafu_paint.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")
const Icons = preload("res://src/client/ui/icons.gd")
const CardViewScript = preload("res://src/client/ui/card_view.gd")


var _settings: Control
var _tutorial_item: Control
var _shop: Control
var _balance: Control          # CurrencyText 金额行
var _title_group: Control   # 标题/斩切线/副标/朱印 组容器(内部坐标固定, 整体锚定)
var _badge: PanelContainer
var _rank_lbl: Label
var _mode_dlg: Control = null   # 模式选择弹窗
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
	_bg.frame_visible = not Responsive.is_touch()
	add_child(_bg)

	_build_title()
	_build_menu()
	_build_fan()
	_build_settings()
	Responsive.watch(self, _relayout)
	# 余额即时同步: 对局结算(后台托管打完也会结算)发放金币/钻石时首页立即刷新
	Wallet.balance_changed.connect(_refresh_balance)
	Audio.play_bgm("lobby")


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
		_title_group.position = Vector2(tx, clampf(h * 0.17, 28.0, 170.0))
	if _badge != null:
		_badge.position = Vector2(w - _badge.size.x - margin, 30)
	if _ver_lbl != null:
		_ver_lbl.position = Vector2(16, h - 30)
	if _hint_lbl != null:
		_hint_lbl.position = Vector2((w - _hint_lbl.size.x) / 2.0, h - 36)
	if _fan != null:
		_fan.position = Vector2(w - 340.0, clampf(h * 0.60, 300.0, h - 300.0))
	# 菜单项: 按可用高度自适应间距(手机紧凑视口也能放下全部六项)
	var y0 := clampf(h * 0.23, 110.0, 188.0)
	var spacing := clampf((h - y0 - 120.0) / 5.0, 52.0, 76.0)
	for i in _menu_items.size():
		var it: Control = _menu_items[i]
		it.position = Vector2(clampf(90.0 + i * 28.0, 40.0, w - 490.0), y0 + i * spacing)


func _build_title() -> void:
	# 巨型行书标题组: 内部坐标固定, _relayout 整体锚定到右半区(设计基准 x=576)
	_title_group = Control.new()
	_title_group.position = Vector2(576, 28)
	_title_group.custom_minimum_size = Vector2(520, 240)
	_title_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_group)

	var title := AppTheme.make_label(170, Color("f2c14e"))
	title.add_theme_font_override("font", AppTheme.title_font())
	title.text = "大富豪"
	title.position = Vector2(4, 0)
	title.rotation = -0.06
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("shadow_offset_x", 5)
	title.add_theme_constant_override("shadow_offset_y", 5)
	_title_group.add_child(title)

	# 红色斩切线
	var bar := ColorRect.new()
	bar.color = Color(AppTheme.RED, 0.85)
	bar.position = Vector2(-6, 150)
	bar.size = Vector2(420, 10)
	bar.rotation = -0.06
	_title_group.add_child(bar)

	# 英文副标
	var sub := AppTheme.make_label(22, AppTheme.DIM)
	sub.add_theme_font_override("font", AppTheme.display_font())
	sub.text = "T  Y  C  O  O  N"
	sub.position = Vector2(76, 188)
	sub.rotation = -0.06
	_title_group.add_child(sub)

	# 朱印
	var seal := ColorRect.new()
	seal.color = Color(AppTheme.RED, 0.9)
	seal.custom_minimum_size = Vector2(56, 56)
	seal.size = Vector2(56, 56)
	seal.position = Vector2(454, 44)
	seal.rotation = 0.10
	_title_group.add_child(seal)
	var seal_char := AppTheme.make_label(38, AppTheme.WHITE)
	seal_char.add_theme_font_override("font", AppTheme.title_font())
	seal_char.text = "富"
	seal_char.position = Vector2(10, 2)
	seal.add_child(seal_char)

	# 余额徽章(锚右上): 铜钱/宝石图标 + 数字 + 称号/战绩行(随胜场晋升)
	_badge = PanelContainer.new()
	_badge.add_theme_stylebox_override("panel", AppTheme.flat(
			Color(0.08, 0.08, 0.18, 0.9), Color(AppTheme.GOLD, 0.6), 4, 0))
	_badge.position = Vector2(1040, 30)
	_badge.rotation = -0.03
	add_child(_badge)
	var badge_box := VBoxContainer.new()
	badge_box.add_theme_constant_override("separation", 2)
	_badge.add_child(badge_box)
	_balance = Icons.CurrencyText.new(19)
	_balance.set_amounts(Wallet.gold, Wallet.diamonds, AppTheme.WHITE)
	badge_box.add_child(_balance)
	_rank_lbl = AppTheme.make_label(13, AppTheme.GOLD)
	_rank_lbl.text = "称号 %s · %d胜/%d场" % [Wallet.rank_title(),
			Wallet.local_wins, Wallet.local_matches]
	_rank_lbl.reset_size()
	badge_box.add_child(_rank_lbl)
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
		pp.closed.connect(func() -> void:
			pp.queue_free()
			_refresh_balance())
		add_child(pp))
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
	# 标题行 + 右上 ?
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	var title := AppTheme.make_label(28, AppTheme.GOLD)
	title.text = "选择游戏模式"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	var help := AppTheme.make_button("?", Vector2(40, 40), 20)
	help.pressed.connect(func() -> void:
		Audio.play("click")
		var rh: Control = (load("res://src/client/ui/rogue_help.gd") as GDScript).new()
		rh.closed.connect(func() -> void: rh.queue_free())
		add_child(rh))
	head.add_child(help)
	# AI 难度行(本地两种模式共用)
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 10)
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
	# 普通模式
	var normal := AppTheme.make_button("普通模式", Vector2(420, 64), 22)
	normal.pressed.connect(func() -> void:
		Audio.play("click")
		_close_mode_select()
		local_game.emit("normal"))
	box.add_child(normal)
	var d1 := AppTheme.make_label(14, AppTheme.DIM)
	d1.text = "经典大富豪: 换牌 / 革命 / 8切, 回合制排名结算"
	box.add_child(d1)
	# 肉鸽模式
	var rogue := AppTheme.make_button("肉鸽模式", Vector2(420, 64), 22)
	rogue.pressed.connect(func() -> void:
		Audio.play("click")
		_close_mode_select()
		local_game.emit("rogue"))
	box.add_child(rogue)
	var d2 := AppTheme.make_label(14, AppTheme.DIM)
	d2.text = "每局随机一张『命运卡』增强随机性, 规则主体与普通一致"
	d2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(d2)
	_mode_dlg = dlg
	add_child(dlg)


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
	if _rank_lbl != null:
		_rank_lbl.text = "称号 %s · %d胜/%d场" % [Wallet.rank_title(),
				Wallet.local_wins, Wallet.local_matches]
		_rank_lbl.reset_size()


func _open_shop() -> void:
	if _shop != null:
		return
	_shop = ShopScript.new()
	_shop.name = "Shop"
	add_child(_shop)
	_shop.closed.connect(func() -> void:
		_shop.queue_free()
		_shop = null
		_refresh_balance())


func _open_tutorial() -> void:
	var tut := TutorialScript.new()
	tut.closed.connect(func() -> void: _tutorial_item.badge = _tutorial_badge())
	add_child(tut)


func _build_settings() -> void:
	_settings = SettingsPanelScript.new()
	_settings.name = "Settings"
	add_child(_settings)


func _label(size: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", color)
	return lb
