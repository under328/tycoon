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


var _settings: Control
var _tutorial_item: Control
var _shop: Control
var _balance_lbl: Label


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
	_build_settings()
	Audio.play_bgm("lobby")


func _build_title() -> void:
	# 巨型行书标题 + 阴影
	var title := AppTheme.make_label(170, Color("f2c14e"))
	title.add_theme_font_override("font", AppTheme.title_font())
	title.text = "大富豪"
	title.position = Vector2(580, 28)
	title.rotation = -0.06
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("shadow_offset_x", 5)
	title.add_theme_constant_override("shadow_offset_y", 5)
	add_child(title)

	# 红色斩切线
	var bar := ColorRect.new()
	bar.color = Color(AppTheme.RED, 0.85)
	bar.position = Vector2(570, 178)
	bar.size = Vector2(420, 10)
	bar.rotation = -0.06
	add_child(bar)

	# 英文副标
	var sub := AppTheme.make_label(22, AppTheme.DIM)
	sub.add_theme_font_override("font", AppTheme.display_font())
	sub.text = "T  Y  C  O  O  N"
	sub.position = Vector2(652, 216)
	sub.rotation = -0.06
	add_child(sub)

	# 朱印
	var seal := ColorRect.new()
	seal.color = Color(AppTheme.RED, 0.9)
	seal.custom_minimum_size = Vector2(56, 56)
	seal.size = Vector2(56, 56)
	seal.position = Vector2(1030, 72)
	seal.rotation = 0.10
	add_child(seal)
	var seal_char := AppTheme.make_label(38, AppTheme.WHITE)
	seal_char.add_theme_font_override("font", AppTheme.title_font())
	seal_char.text = "富"
	seal_char.position = Vector2(10, 2)
	seal.add_child(seal_char)

	# 余额徽章
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", AppTheme.flat(
			Color(0.08, 0.08, 0.18, 0.9), Color(AppTheme.GOLD, 0.6), 4, 0))
	badge.position = Vector2(1040, 30)
	badge.rotation = -0.03
	add_child(badge)
	_balance_lbl = AppTheme.make_label(19, AppTheme.WHITE)
	_balance_lbl.text = "💰 %d   💎 %d" % [Wallet.gold, Wallet.diamonds]
	badge.add_child(_balance_lbl)

	# 版本号
	var ver := AppTheme.make_label(13, AppTheme.DIM)
	ver.text = "v1.0.0"
	ver.position = Vector2(16, 690)
	add_child(ver)


func _build_menu() -> void:
	var items := [
		["本地游戏", func() -> void:
			local_game.emit(), ""],
		["联机游戏", func() -> void:
			online_game.emit(), ""],
		["商　城", func() -> void:
			_open_shop(), ""],
		["设　置", func() -> void:
			_settings.open(), ""],
		["新手引导", func() -> void:
			_open_tutorial(), _tutorial_badge()],
		["退出游戏", func() -> void:
			get_tree().quit(), ""],
	]
	for i in items.size():
		var item := SlashItem.new()
		item.text = str(items[i][0])
		item.badge = str(items[i][2])
		item.position = Vector2(90 + i * 28, 188 + i * 76)
		item.custom_minimum_size = Vector2(440, 62)
		item.size = Vector2(440, 62)
		var cb: Callable = items[i][1]
		item.pressed.connect(cb)
		if str(items[i][0]) == "新手引导":
			_tutorial_item = item
		add_child(item)

	var hint := AppTheme.make_label(14, AppTheme.DIM)
	hint.add_theme_font_override("font", AppTheme.accent_font())
	hint.text = "和朋友开一局: 联机游戏 → 创建房间 → 把房间码发给朋友"
	hint.position = Vector2(400, 700)
	add_child(hint)


func _tutorial_badge() -> String:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and not bool(gs.tutorial_seen):
		return "NEW"
	return ""


func _refresh_balance() -> void:
	if _balance_lbl != null:
		_balance_lbl.text = "💰 %d   💎 %d" % [Wallet.gold, Wallet.diamonds]


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
