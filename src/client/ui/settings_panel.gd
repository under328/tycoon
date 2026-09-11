## 设置面板（模态居中弹窗）: 昵称 + 音乐/音效音量 + 图像设置，自动保存。
## 用法: add_child(SettingsPanelScript.new()); 需要时调用 open()；closed 信号通知关闭。
extends Control

signal closed

const AppTheme = preload("res://src/client/theme/app_theme.gd")

var _nickname_edit: LineEdit
var _bgm_slider: HSlider
var _sfx_slider: HSlider
var _fullscreen_btn: CheckButton
var _vsync_btn: CheckButton
var _resolution_btn: OptionButton
var _toast: Label


func _ready() -> void:
	# 全屏模态层
	set_anchors_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var sb := AppTheme.flat(AppTheme.PANEL, AppTheme.GOLD, 14, 2)
	sb.content_margin_left = 32
	sb.content_margin_right = 32
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	# 标题
	var title := AppTheme.make_label(24, AppTheme.GOLD)
	title.text = "设  置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(HSeparator.new())

	# ── 昵称 ──
	box.add_child(_section("昵称"))
	_nickname_edit = LineEdit.new()
	_nickname_edit.max_length = 12
	_nickname_edit.custom_minimum_size = Vector2(340, 38)
	_nickname_edit.text_changed.connect(func(t: String) -> void:
		var g := get_node_or_null("/root/GameSettings")
		if g != null:
			g.nickname = t.strip_edges()
			if g.nickname == "":
				g.nickname = "玩家"
			g.save_settings())
	box.add_child(_nickname_edit)

	# ── 音量 ──
	box.add_child(_section("音量"))
	_bgm_slider = _slider(box, "音乐", _on_bgm_changed)
	_sfx_slider = _slider(box, "音效", _on_sfx_changed)

	# ── 图像 ──
	box.add_child(_section("图像"))
	_fullscreen_btn = CheckButton.new()
	_fullscreen_btn.text = "全屏"
	_fullscreen_btn.button_pressed = _is_fullscreen()
	_fullscreen_btn.toggled.connect(_on_fullscreen)
	box.add_child(_fullscreen_btn)

	_vsync_btn = CheckButton.new()
	_vsync_btn.text = "垂直同步"
	_vsync_btn.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	_vsync_btn.toggled.connect(_on_vsync)
	box.add_child(_vsync_btn)

	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 12)
	box.add_child(res_row)
	var res_lbl := AppTheme.make_label(16, AppTheme.WHITE)
	res_lbl.text = "分辨率"
	res_lbl.custom_minimum_size = Vector2(100, 0)
	res_row.add_child(res_lbl)
	_resolution_btn = OptionButton.new()
	_resolution_btn.custom_minimum_size = Vector2(200, 34)
	for r: Vector2i in [
		Vector2i(1280, 720), Vector2i(1600, 900),
		Vector2i(1920, 1080), Vector2i(2560, 1440),
	]:
		_resolution_btn.add_item("%d × %d" % [r.x, r.y])
		_resolution_btn.set_item_metadata(_resolution_btn.item_count - 1, r)
	_resolution_btn.select(0)
	_resolution_btn.item_selected.connect(_on_resolution)
	res_row.add_child(_resolution_btn)

	var apply_btn := AppTheme.make_button("应用分辨率", Vector2(0, 0), 15)
	apply_btn.custom_minimum_size = Vector2(200, 36)
	apply_btn.pressed.connect(_on_apply_resolution)
	box.add_child(apply_btn)

	# ── 关闭 ──
	box.add_child(HSeparator.new())
	var cc := CenterContainer.new()
	var close := AppTheme.make_button("保存并关闭", Vector2(200, 42), 17)
	close.pressed.connect(func() -> void:
		Audio.play("click")
		_save_all()
		_close())
	cc.add_child(close)
	box.add_child(cc)

	# toast
	_toast = AppTheme.make_label(14, AppTheme.DIM)
	_toast.text = ""
	box.add_child(_toast)

	visible = false
	_load_settings()


## 打开面板: 重新读取当前设置并置顶显示
func open() -> void:
	_load_settings()
	visible = true
	move_to_front()


func _section(text: String) -> Label:
	var lb := AppTheme.make_label(16, AppTheme.GOLD)
	lb.text = "── " + text
	return lb


func _slider(box: VBoxContainer, text: String, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var lbl := AppTheme.make_label(16, AppTheme.WHITE)
	lbl.text = text
	lbl.custom_minimum_size = Vector2(100, 0)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(280, 24)
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	return slider


func _save_all() -> void:
	var g := get_node_or_null("/root/GameSettings")
	if g != null:
		g.save_settings()


func _load_settings() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		_nickname_edit.text = str(gs.nickname)
		_bgm_slider.set_value_no_signal(float(gs.bgm_volume))
		_sfx_slider.set_value_no_signal(float(gs.sfx_volume))
		_fullscreen_btn.set_pressed_no_signal(bool(gs.fullscreen))
		_vsync_btn.set_pressed_no_signal(bool(gs.vsync_enabled))
		var want: Vector2i = gs.window_size
		for i in _resolution_btn.item_count:
			if _resolution_btn.get_item_metadata(i) == want:
				_resolution_btn.select(i)
				break


func _on_fullscreen(toggled: bool) -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if toggled else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	_save_display(toggled, null, Vector2i.ZERO)


func _on_vsync(toggled: bool) -> void:
	DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if toggled else DisplayServer.VSYNC_DISABLED)
	_save_display(null, toggled, Vector2i.ZERO)


func _on_resolution(index: int) -> void:
	pass  # 由 _on_apply_resolution 统一处理


func _on_apply_resolution() -> void:
	var idx := _resolution_btn.selected
	var r: Vector2i = _resolution_btn.get_item_metadata(idx)
	DisplayServer.window_set_size(r)
	if not _fullscreen_btn.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_save_display(null, null, r)


func _save_display(fullscreen, vsync, res: Vector2i) -> void:
	var g := get_node_or_null("/root/GameSettings")
	if g == null:
		return
	if fullscreen != null:
		g.fullscreen = fullscreen
	if vsync != null:
		g.vsync_enabled = vsync
	if res != Vector2i.ZERO:
		g.window_size = res
	g.save_settings()


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


func _is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() >= DisplayServer.WINDOW_MODE_FULLSCREEN


func _close() -> void:
	Audio.play("click")
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed \
			and event.keycode == KEY_ESCAPE:
		_close()
