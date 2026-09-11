## 商城界面: 皮肤 / 卡片 两个分类, 钻石购买, 一键装备。计划 §12。
extends Control

signal closed

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const P5Header = preload("res://src/client/ui/p5_header.gd")
const SkinsLib = preload("res://src/client/ui/skins.gd")
const AvatarScript = preload("res://src/client/ui/avatar.gd")

const COLOR_BG := Color(0.94, 0.94, 0.96, 0.98)
const COLOR_PANEL_BG := Color("14142b")

var _tab := "skin"
var _balance_lbl: Label
var _toast: Label
var _grid: GridContainer
var _tab_skin_btn: Button
var _tab_card_btn: Button



func create_and_place(text: String, pos: Vector2, min_size: Vector2, font_size: int) -> Button:
	var b := AppTheme.make_button(text, min_size, font_size)
	b.position = pos
	add_child(b)
	return b

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(AppTheme.BG, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var header := P5Header.new()
	header.text = "商  城"
	header.position = Vector2(36, 22)
	header.custom_minimum_size = Vector2(300, 54)
	header.size = Vector2(300, 54)
	add_child(header)

	_balance_lbl = AppTheme.make_label(20, AppTheme.WHITE)
	_balance_lbl.position = Vector2(980, 30)
	add_child(_balance_lbl)

	var back := AppTheme.make_button("返 回", Vector2(100, 42), 17)
	back.position = Vector2(1150, 24)
	back.pressed.connect(func() -> void:
		Audio.play("click")
		_close())
	add_child(back)

	# 分类页签
	_tab_skin_btn = AppTheme.make_button("人 物 皮 肤", Vector2(200, 46), 18)
	_tab_skin_btn.position = Vector2(40, 110)
	_tab_skin_btn.toggle_mode = true
	_tab_skin_btn.pressed.connect(func() -> void: _set_tab("skin"))
	add_child(_tab_skin_btn)
	_tab_card_btn = AppTheme.make_button("卡 牌 面 貌", Vector2(200, 46), 18)
	_tab_card_btn.position = Vector2(255, 110)
	_tab_card_btn.toggle_mode = true
	_tab_card_btn.pressed.connect(func() -> void: _set_tab("card"))
	add_child(_tab_card_btn)

	# 商品网格
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 170)
	scroll.custom_minimum_size = Vector2(1200, 460)
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 18)
	scroll.add_child(_grid)

	_toast = AppTheme.make_label(16, AppTheme.RED)
	_toast.position = Vector2(40, 660)
	_toast.custom_minimum_size = Vector2(600, 30)
	add_child(_toast)

	Wallet.balance_changed.connect(_refresh)
	_set_tab("skin")


func _set_tab(tab: String) -> void:
	_tab = tab
	_tab_skin_btn.button_pressed = tab == "skin"
	_tab_card_btn.button_pressed = tab == "card"
	_refresh()


func _refresh() -> void:
	_balance_lbl.text = "💰 %d    💎 %d" % [Wallet.gold, Wallet.diamonds]
	for child in _grid.get_children():
		child.queue_free()
	var items: Array = SkinsLib.SKINS if _tab == "skin" else SkinsLib.CARDS
	for item in items:
		_grid.add_child(_item_panel(_tab, item))


func _item_panel(kind: String, item: Dictionary) -> Control:
	var id: String = str(item["id"])
	var price: int = int(item["price"])
	var owned: bool = Wallet.is_owned(kind, id)
	var equipped: bool = Wallet.is_equipped(kind, id)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 190)
	panel.add_theme_stylebox_override("panel", AppTheme.flat(
			Color(0.13, 0.13, 0.28), AppTheme.GOLD if equipped
					else Color(1, 1, 1, 0.15), 12, 2 if not equipped else 3))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var name_lbl := AppTheme.make_label(19, AppTheme.GOLD if equipped else AppTheme.WHITE)
	name_lbl.text = str(item["name"])
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_lbl)
	if equipped:
		var eq := AppTheme.make_label(14, AppTheme.GREEN)
		eq.text = "使用中"
		head.add_child(eq)

	# 预览
	var preview := Control.new()
	preview.custom_minimum_size = Vector2(0, 72)
	v.add_child(preview)
	if kind == "skin":
		var av := AvatarScript.new()
		av.skin_id = id
		av.set_anchors_preset(Control.PRESET_FULL_RECT)
		preview.add_child(av)
	else:
		var pal: Dictionary = SkinsLib.palette(id)
		var strip := HBoxContainer.new()
		strip.alignment = BoxContainer.ALIGNMENT_CENTER
		strip.add_theme_constant_override("separation", 10)
		preview.add_child(strip)
		for c: Color in [pal["face"], pal["red"], pal["black"], pal["back"]]:
			var sw := PanelContainer.new()
			sw.custom_minimum_size = Vector2(42, 60)
			sw.add_theme_stylebox_override("panel", AppTheme.flat(
					c, pal["border"], 6, 2))
			strip.add_child(sw)

	# 价格 + 操作按钮
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	v.add_child(foot)
	if owned:
		var act := AppTheme.make_button(
				"使用中" if equipped else "装 备", Vector2(120, 38), 15)
		act.disabled = equipped
		act.pressed.connect(func() -> void:
			Audio.play("click")
			Wallet.equip(kind, id)
			_refresh())
		foot.add_child(act)
	else:
		var price_lbl := AppTheme.make_label(16, AppTheme.WHITE)
		price_lbl.text = "💎 %d" % price
		price_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(price_lbl)
		var buy := AppTheme.make_button("购 买", Vector2(96, 38), 15)
		buy.disabled = Wallet.diamonds < price
		buy.pressed.connect(func() -> void:
			if Wallet.buy(kind, id, price):
				Wallet.equip(kind, id)
				Audio.play("win")
				_refresh()
				_toast_msg("购买成功, 已装备!")
			else:
				_toast_msg("钻石不足, 打几局赚钻石吧"))
		foot.add_child(buy)
	return panel


func _toast_msg(text: String) -> void:
	_toast.text = text
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_callback(func() -> void: _toast.text = "")



func _close() -> void:
	Audio.play("click")
	visible = false
	closed.emit()
