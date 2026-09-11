## 主菜单：本地游戏 / 联机游戏 / 设置 / 退出。动态背景见 menu_background.gd。
extends Control

const AppTheme = preload("res://src/client/theme/app_theme.gd")

signal local_game
signal online_game

const BGScript = preload("res://src/client/ui/menu_background.gd")
const SettingsPanelScript = preload("res://src/client/ui/settings_panel.gd")
const TutorialScript = preload("res://src/client/scenes/tutorial.gd")


var _settings: Control
var _tutorial_btn: Button


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
	var title := _label(92, AppTheme.GOLD)
	title.text = "大富豪"
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-160, 64)
	title.custom_minimum_size = Vector2(320, 110)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var sub := _label(20, AppTheme.DIM)
	sub.text = "T  Y  C  O  O  N"
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-160, 172)
	sub.custom_minimum_size = Vector2(320, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	# 朱印（和风落款）
	var seal := ColorRect.new()
	seal.color = AppTheme.RED
	seal.custom_minimum_size = Vector2(58, 58)
	seal.size = Vector2(58, 58)
	seal.position = Vector2(758, 78)
	seal.rotation = 0.08
	add_child(seal)
	var seal_char := _label(40, AppTheme.WHITE)
	seal_char.text = "富"
	seal_char.position = Vector2(10, 4)
	seal.add_child(seal_char)

	var ver := _label(13, AppTheme.DIM)
	ver.text = "v1.0.0"
	ver.position = Vector2(16, 690)
	add_child(ver)


func _build_menu() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-170, -95)
	box.custom_minimum_size = Vector2(340, 380)
	box.add_theme_constant_override("separation", 16)
	add_child(box)

	box.add_child(_menu_button("本地游戏", func() -> void:
		Audio.play("click")
		local_game.emit()))
	box.add_child(_menu_button("联机游戏", func() -> void:
		Audio.play("click")
		online_game.emit()))
	box.add_child(_menu_button("设  置", func() -> void:
		Audio.play("click")
		_settings.open()))
	_tutorial_btn = _menu_button("新手引导", func() -> void:
		Audio.play("click")
		_open_tutorial())
	box.add_child(_tutorial_btn)
	box.add_child(_menu_button("退出游戏", func() -> void:
		get_tree().quit()))
	_refresh_tutorial_badge()

	var hint := _label(13, AppTheme.DIM)
	hint.text = "和朋友开一局: 联机游戏 → 创建房间 → 把房间码发给朋友"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-300, -40)
	hint.custom_minimum_size = Vector2(600, 26)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)


func _refresh_tutorial_badge() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	var seen: bool = gs != null and bool(gs.tutorial_seen)
	_tutorial_btn.text = "新手引导" if seen else "新手引导 ★"


func _open_tutorial() -> void:
	var tut := TutorialScript.new()
	tut.closed.connect(_refresh_tutorial_badge)
	add_child(tut)


func _menu_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 58)
	b.add_theme_font_size_override("font_size", 22)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.10, 0.22, 0.88)
	normal.set_corner_radius_all(10)
	normal.set_border_width_all(2)
	normal.border_color = Color(AppTheme.GOLD, 0.55)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.16, 0.15, 0.34, 0.95)
	hover.border_color = AppTheme.GOLD
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.22, 0.12, 0.16, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(on_press)
	return b


func _build_settings() -> void:
	_settings = SettingsPanelScript.new()
	_settings.name = "Settings"
	add_child(_settings)


func _label(size: int, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", color)
	return lb
