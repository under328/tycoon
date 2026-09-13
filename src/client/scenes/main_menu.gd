## 主菜单：本地游戏 / 联机游戏 / 设置 / 退出。动态背景见 menu_background.gd。
extends Control

const AppTheme = preload("res://src/client/theme/app_theme.gd")

signal local_game
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
var _ver_lbl: Label
var _hint_lbl: Label
var _fan: Control             # 右下卡扇(展示已装备卡面)


func _ready() -> void:
	# 根 Control 由代码 new 出且父节点是普通 Node, 锚点不可靠 → 显式铺满视口
	set_anchors_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	theme = AppTheme.build_theme()

	var bg := BGScript.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_title()
	_build_menu()
	_build_fan()
	_build_settings()
	Responsive.watch(self, _relayout)
	# 余额即时同步: 对局结算(后台托管打完也会结算)发放金币/钻石时首页立即刷新
	Wallet.balance_changed.connect(_refresh_balance)
	Audio.play_bgm("lobby")


## 多设备自适应(1280x720 设计基准): 标题组锚右半区并随高度下移,
## 余额徽章锚右上, 版本号左下, 底部提示居中, 卡扇贴右下——手机/平板/PC 通吃。
func _relayout() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	var tx := clampf(w * 0.45, 500.0, w - 540.0)
	if _title_group != null:
		_title_group.position = Vector2(tx, clampf(h * 0.17, 28.0, 170.0))
	if _badge != null:
		_badge.position = Vector2(w - _badge.size.x - 28.0, 30)
	if _ver_lbl != null:
		_ver_lbl.position = Vector2(16, h - 30)
	if _hint_lbl != null:
		_hint_lbl.position = Vector2((w - _hint_lbl.size.x) / 2.0, h - 36)
	if _fan != null:
		_fan.position = Vector2(w - 340.0, h * 0.60)


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

	# 余额徽章(锚右上): 铜钱/宝石图标 + 数字
	_badge = PanelContainer.new()
	_badge.add_theme_stylebox_override("panel", AppTheme.flat(
			Color(0.08, 0.08, 0.18, 0.9), Color(AppTheme.GOLD, 0.6), 4, 0))
	_badge.position = Vector2(1040, 30)
	_badge.rotation = -0.03
	add_child(_badge)
	_balance = Icons.CurrencyText.new(19)
	_balance.set_amounts(Wallet.gold, Wallet.diamonds, AppTheme.WHITE)
	_badge.add_child(_balance)

	# 版本号(锚左下)
	_ver_lbl = AppTheme.make_label(13, AppTheme.DIM)
	_ver_lbl.text = "v1.0.0"
	_ver_lbl.position = Vector2(16, 690)
	add_child(_ver_lbl)


func _build_menu() -> void:
	var items := [
		["本地游戏", func() -> void:
			local_game.emit(), "", "card"],
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
		var cb: Callable = items[i][1]
		item.pressed.connect(cb)
		if str(items[i][0]) == "新手引导":
			_tutorial_item = item
		add_child(item)

	_hint_lbl = AppTheme.make_label(14, AppTheme.DIM)
	_hint_lbl.add_theme_font_override("font", AppTheme.accent_font())
	_hint_lbl.text = "和朋友开一局: 联机游戏 → 创建房间 → 把房间码发给朋友"
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


func _refresh_balance() -> void:
	if _balance != null:
		_balance.set_amounts(Wallet.gold, Wallet.diamonds, AppTheme.WHITE)


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
