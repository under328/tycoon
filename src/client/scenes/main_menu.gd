## 主菜单：本地游戏 / 联机游戏 / 设置 / 退出。动态背景见 menu_background.gd。
extends Control

signal local_game
signal online_game

const BGScript = preload("res://src/client/ui/menu_background.gd")

const COLOR_GOLD := Color("e0a83c")
const COLOR_RED := Color("e0503c")
const COLOR_WHITE := Color("f0f0f0")
const COLOR_DIM := Color("8a8ab0")
const COLOR_PANEL := Color(0.10, 0.10, 0.22, 0.92)

var _settings_panel: PanelContainer
var _nickname_edit: LineEdit


func _ready() -> void:
	# 根 Control 由代码 new 出且父节点是普通 Node, 锚点不可靠 → 显式铺满视口
	set_anchors_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	var theme_res := Theme.new()
	var sys_font := SystemFont.new()
	sys_font.font_names = PackedStringArray([
		"Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC", "SimHei", "Arial",
	])
	theme_res.default_font = sys_font
	theme_res.default_font_size = 18
	theme = theme_res

	var bg := BGScript.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_title()
	_build_menu()
	_build_settings()
	Audio.play_bgm("lobby")


func _build_title() -> void:
	var title := _label(92, COLOR_GOLD)
	title.text = "大富豪"
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-160, 64)
	title.custom_minimum_size = Vector2(320, 110)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var sub := _label(20, COLOR_DIM)
	sub.text = "T  Y  C  O  O  N"
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-160, 172)
	sub.custom_minimum_size = Vector2(320, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	# 朱印（和风落款）
	var seal := ColorRect.new()
	seal.color = COLOR_RED
	seal.custom_minimum_size = Vector2(58, 58)
	seal.size = Vector2(58, 58)
	seal.position = Vector2(758, 78)
	seal.rotation = 0.08
	add_child(seal)
	var seal_char := _label(40, COLOR_WHITE)
	seal_char.text = "富"
	seal_char.position = Vector2(10, 4)
	seal.add_child(seal_char)

	var ver := _label(13, COLOR_DIM)
	ver.text = "v1.0.0"
	ver.position = Vector2(16, 690)
	add_child(ver)


func _build_menu() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-170, -60)
	box.custom_minimum_size = Vector2(340, 300)
	box.add_theme_constant_override("separation", 18)
	add_child(box)

	box.add_child(_menu_button("本地游戏", func() -> void:
		Audio.play("click")
		local_game.emit()))
	box.add_child(_menu_button("联机游戏", func() -> void:
		Audio.play("click")
		online_game.emit()))
	box.add_child(_menu_button("设  置", func() -> void:
		Audio.play("click")
		_settings_panel.visible = not _settings_panel.visible))
	box.add_child(_menu_button("退出游戏", func() -> void:
		get_tree().quit()))

	var hint := _label(13, COLOR_DIM)
	hint.text = "和朋友开一局: 联机游戏 → 创建房间 → 把房间码发给朋友"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-300, -46)
	hint.custom_minimum_size = Vector2(600, 26)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)


func _menu_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 58)
	b.add_theme_font_size_override("font_size", 22)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.10, 0.22, 0.88)
	normal.set_corner_radius_all(10)
	normal.set_border_width_all(2)
	normal.border_color = Color(COLOR_GOLD, 0.55)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.16, 0.15, 0.34, 0.95)
	hover.border_color = COLOR_GOLD
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.22, 0.12, 0.16, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(on_press)
	return b


func _build_settings() -> void:
	_settings_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_PANEL
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = COLOR_GOLD
	_settings_panel.add_theme_stylebox_override("panel", sb)
	_settings_panel.set_anchors_preset(Control.PRESET_CENTER)
	_settings_panel.position = Vector2(-220, -170)
	_settings_panel.custom_minimum_size = Vector2(440, 340)
	_settings_panel.visible = false
	add_child(_settings_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_settings_panel.add_child(box)

	var title := _label(22, COLOR_GOLD)
	title.text = "设  置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var nick_row := HBoxContainer.new()
	nick_row.add_theme_constant_override("separation", 12)
	box.add_child(nick_row)
	var nick_lbl := _label(16, COLOR_WHITE)
	nick_lbl.text = "昵称"
	nick_lbl.custom_minimum_size = Vector2(60, 0)
	nick_row.add_child(nick_lbl)
	_nickname_edit = LineEdit.new()
	_nickname_edit.max_length = 12
	_nickname_edit.custom_minimum_size = Vector2(280, 38)
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		_nickname_edit.text = str(gs.nickname)
	_nickname_edit.text_changed.connect(func(t: String) -> void:
		var g := get_node_or_null("/root/GameSettings")
		if g != null:
			g.nickname = t.strip_edges()
			if g.nickname == "":
				g.nickname = "玩家"
			g.save_settings())
	nick_row.add_child(_nickname_edit)

	var bgm_row := HBoxContainer.new()
	bgm_row.add_theme_constant_override("separation", 12)
	box.add_child(bgm_row)
	var bgm_lbl := _label(16, COLOR_WHITE)
	bgm_lbl.text = "音乐"
	bgm_lbl.custom_minimum_size = Vector2(60, 0)
	bgm_row.add_child(bgm_lbl)
	var bgm_slider := HSlider.new()
	bgm_slider.max_value = 1.0
	bgm_slider.step = 0.05
	bgm_slider.custom_minimum_size = Vector2(280, 24)
	bgm_row.add_child(bgm_slider)

	var sfx_row := HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 12)
	box.add_child(sfx_row)
	var sfx_lbl := _label(16, COLOR_WHITE)
	sfx_lbl.text = "音效"
	sfx_lbl.custom_minimum_size = Vector2(60, 0)
	sfx_row.add_child(sfx_lbl)
	var sfx_slider := HSlider.new()
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	sfx_slider.custom_minimum_size = Vector2(280, 24)
	sfx_row.add_child(sfx_slider)

	var g2 := get_node_or_null("/root/GameSettings")
	if g2 != null:
		bgm_slider.value = float(g2.bgm_volume)
		sfx_slider.value = float(g2.sfx_volume)
	bgm_slider.value_changed.connect(func(v: float) -> void:
		var g := get_node_or_null("/root/GameSettings")
		if g != null:
			g.bgm_volume = v
			g.save_settings()
		Audio.apply_volumes())
	sfx_slider.value_changed.connect(func(v: float) -> void:
		var g := get_node_or_null("/root/GameSettings")
		if g != null:
			g.sfx_volume = v
			g.save_settings()
		Audio.apply_volumes()
		Audio.play("click"))

	var tip := _label(13, COLOR_DIM)
	tip.text = "设置会自动保存"
	box.add_child(tip)

	var close := Button.new()
	close.text = "关 闭"
	close.custom_minimum_size = Vector2(140, 42)
	close.add_theme_font_size_override("font_size", 17)
	close.pressed.connect(func() -> void:
		Audio.play("click")
		_settings_panel.visible = false)
	var center := CenterContainer.new()
	center.add_child(close)
	box.add_child(center)


func _label(size: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", color)
	return lb
