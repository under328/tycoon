## 设置面板组件（计划 Settings 场景的组件化）: 昵称 + 音乐/音效音量，自动保存。
## 用法: add_child(SettingsPanelScript.new()); 面板.open() 显示, closed 信号通知关闭。
extends PanelContainer

signal closed

const AppTheme = preload("res://src/client/theme/app_theme.gd")

var _nickname_edit: LineEdit
var _bgm_slider: HSlider
var _sfx_slider: HSlider


func _ready() -> void:
	add_theme_stylebox_override("panel", AppTheme.flat(
			AppTheme.PANEL, AppTheme.GOLD, 14, 2))
	custom_minimum_size = Vector2(440, 340)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	var title := AppTheme.make_label(22, AppTheme.GOLD)
	title.text = "设  置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var nick_row := HBoxContainer.new()
	nick_row.add_theme_constant_override("separation", 12)
	box.add_child(nick_row)
	var nick_lbl := AppTheme.make_label(16, AppTheme.WHITE)
	nick_lbl.text = "昵称"
	nick_lbl.custom_minimum_size = Vector2(60, 0)
	nick_row.add_child(nick_lbl)
	_nickname_edit = LineEdit.new()
	_nickname_edit.max_length = 12
	_nickname_edit.custom_minimum_size = Vector2(280, 38)
	nick_row.add_child(_nickname_edit)

	_bgm_slider = _volume_row(box, "音乐", _on_bgm_changed)
	_sfx_slider = _volume_row(box, "音效", _on_sfx_changed)

	var tip := AppTheme.make_label(13, AppTheme.DIM)
	tip.text = "设置会自动保存"
	box.add_child(tip)

	var close := AppTheme.make_button("关 闭", Vector2(140, 42), 17)
	close.pressed.connect(func() -> void:
		Audio.play("click")
		visible = false
		closed.emit())
	var center := CenterContainer.new()
	center.add_child(close)
	box.add_child(center)

	visible = false


## 打开并刷新控件值（昵称/音量读自存档）。
func open() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		_nickname_edit.text = str(gs.nickname)
		_bgm_slider.set_value_no_signal(float(gs.bgm_volume))
		_sfx_slider.set_value_no_signal(float(gs.sfx_volume))
	visible = true


func _volume_row(box: VBoxContainer, text: String, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var lbl := AppTheme.make_label(16, AppTheme.WHITE)
	lbl.text = text
	lbl.custom_minimum_size = Vector2(60, 0)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(280, 24)
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	return slider


func _on_bgm_changed(v: float) -> void:
	var g := get_node_or_null("/root/GameSettings")
	if g != null:
		g.bgm_volume = v
		g.save_settings()
	Audio.apply_volumes()


func _on_sfx_changed(v: float) -> void:
	var g := get_node_or_null("/root/GameSettings")
	if g != null:
		g.sfx_volume = v
		g.save_settings()
	Audio.apply_volumes()
	Audio.play("click")
