## 设置面板（居中弹窗）: 昵称 + 音量 + 语言 + 触感 + 图像，自动保存。
## 弹窗居中显示, 内容可滚动(手机触摸滑动), 点击遮罩或关闭按钮关闭。
## 用法: add_child(SettingsPanelScript.new()); 需要时调用 open()；closed 信号通知关闭。
extends Control

signal closed

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")

var _nickname_edit: LineEdit
var _bgm_slider: HSlider
var _sfx_slider: HSlider
var _display_ctrls: Array = []
var _fullscreen_btn: CheckButton
var _vsync_btn: CheckButton
var _resolution_btn: OptionButton
var _lang_btn: OptionButton
var _toast: Label
var _scroll: ScrollContainer
var _panel: PanelContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = get_parent_area_size()
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 半透明遮罩(点击关闭)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_save_all()
			_close())
	add_child(dim)

	# 居中容器
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# 弹窗面板
	_panel = PanelContainer.new()
	var sb := AppTheme.flat(AppTheme.PANEL, AppTheme.GOLD, 16, 2)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	# PanelContainer 会把每个子控件拉伸铺满整个面板 → 标题行与滚动区
	# 必须包进同一个 VBox, 否则 ✕ 关闭按钮被拉成整列盖住右侧内容
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	_panel.add_child(page)

	# 标题 + 关闭
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	page.add_child(head)
	var title := AppTheme.make_label(24, AppTheme.GOLD)
	title.text = tr("设  置")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	var close_btn := AppTheme.make_button("✕", Vector2(40, 40), 20)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	close_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_save_all()
		_close())
	head.add_child(close_btn)

	# 滚动内容
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(440, 0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(box)

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

	# ── 语言(16 种, 即时切换) ──
	box.add_child(_section("语言"))
	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 12)
	box.add_child(lang_row)
	_lang_btn = OptionButton.new()
	_lang_btn.custom_minimum_size = Vector2(220, 38)
	var cur_lang := 0
	var i18n := get_node_or_null("/root/I18n")
	for i in I18n.LANGUAGES.size():
		var l: Dictionary = I18n.LANGUAGES[i]
		_lang_btn.add_item(str(l["name"]))
		_lang_btn.set_item_metadata(i, str(l["code"]))
		if str(l["code"]) == str(I18n.language()):
			cur_lang = i
	_lang_btn.select(cur_lang)
	_lang_btn.item_selected.connect(_on_language)
	lang_row.add_child(_lang_btn)
	var lang_hint := AppTheme.make_label(13, AppTheme.DIM)
	lang_hint.text = tr("切换后全界面即时生效")
	lang_row.add_child(lang_hint)

	# ── 触感(触屏专属) ──
	if Responsive.is_touch():
		box.add_child(_section("触感"))
		var vib := CheckButton.new()
		vib.text = tr("震动反馈(轮到你/结算)")
		vib.button_pressed = bool(gs_vibration())
		vib.toggled.connect(func(on: bool) -> void:
			var g := get_node_or_null("/root/GameSettings")
			if g != null:
				g.vibration = on
				g.save_settings())
		box.add_child(vib)

	# ── 图像(桌面专属) ──
	var sec_img := _section("图像")
	box.add_child(sec_img)
	_display_ctrls.append(sec_img)
	_fullscreen_btn = CheckButton.new()
	_fullscreen_btn.text = tr("全屏")
	_fullscreen_btn.button_pressed = _is_fullscreen()
	_fullscreen_btn.toggled.connect(_on_fullscreen)
	box.add_child(_fullscreen_btn)
	_display_ctrls.append(_fullscreen_btn)

	_vsync_btn = CheckButton.new()
	_vsync_btn.text = tr("垂直同步")
	_vsync_btn.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	_vsync_btn.toggled.connect(_on_vsync)
	box.add_child(_vsync_btn)
	_display_ctrls.append(_vsync_btn)

	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 12)
	box.add_child(res_row)
	_display_ctrls.append(res_row)
	var res_lbl := AppTheme.make_label(16, AppTheme.WHITE)
	res_lbl.text = tr("分辨率")
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

	var apply_btn := AppTheme.make_button(tr("应用分辨率"), Vector2(0, 0), 15)
	apply_btn.custom_minimum_size = Vector2(200, 36)
	apply_btn.pressed.connect(_on_apply_resolution)
	box.add_child(apply_btn)
	_display_ctrls.append(apply_btn)
	if Responsive.is_touch():
		for c: Control in _display_ctrls:
			c.visible = false

	# ── 关闭 ──
	box.add_child(HSeparator.new())
	var cc := CenterContainer.new()
	var close := AppTheme.make_button(tr("保存并关闭"), Vector2(200, 42), 17)
	close.pressed.connect(func() -> void:
		Audio.play("click")
		_save_all()
		_close())
	cc.add_child(close)
	box.add_child(cc)

	_toast = AppTheme.make_label(14, AppTheme.DIM)
	_toast.text = ""
	box.add_child(_toast)

	Responsive.watch(self, _relayout)
	visible = false
	_load_settings()


## 弹窗高度约束: 滚动区不超过视口 70%
func _relayout() -> void:
	var vh := get_viewport().get_visible_rect().size.y
	if vh < 100:
		return
	_scroll.custom_minimum_size.y = minf(vh * 0.65, 560.0)


## 打开面板: 重新读取当前设置并置顶显示
func open() -> void:
	_load_settings()
	visible = true
	move_to_front()


func _section(text: String) -> Label:
	var lb := AppTheme.make_label(16, AppTheme.GOLD)
	lb.text = "── " + tr(text)
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
	pass


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


func _on_language(idx: int) -> void:
	Audio.play("click")
	var code := str(_lang_btn.get_item_metadata(idx))
	I18n.set_language(code)
	_toast.text = "Language: %s" % I18n.LANGUAGES[idx]["name"]


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


func gs_vibration() -> bool:
	var g := get_node_or_null("/root/GameSettings")
	return bool(g.vibration) if g != null else true


func _close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed \
			and event.keycode == KEY_ESCAPE:
		_save_all()
		_close()
