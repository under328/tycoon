## 客户端/服务器入口：按 AppMode 分发。
##   服务器: /root/Main/Net = net_node(服务器模式)
##   客户端: 主菜单 → (本地游戏|联机游戏→大厅→牌桌)；--client 跳过菜单直达大厅
##   本地默认: 主菜单 → 本地游戏 → 牌桌(人+3AI)
extends Node

const TableScene := preload("res://src/client/scenes/table.tscn")
const LobbyScene := preload("res://src/client/scenes/lobby.tscn")
const MainMenuScript := preload("res://src/client/scenes/main_menu.gd")
const NetNodeGd := preload("res://src/protocol/net_node.gd")
const AppTheme = preload("res://src/client/theme/app_theme.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")

var menu = null
var lobby = null
var table = null
var net = null
var embed_server: Node = null   # 本机开房的内嵌服务器(非空=正在做主机)
var _fit_target: Control = null # 最近一次做过安全区适配的可见场景
var _resume_dlg: Control = null # "返回上一局?"确认框
var _bleed_bg: ColorRect = null # 全屏铺底色(填充刘海/挖孔避让条, 消除异色边)


func _ready() -> void:
	if AppMode.is_server:
		net = NetNodeGd.new()
		net.name = "Net"
		net.setup(true)
		add_child(net)
		return
	_bleed_bg = ColorRect.new()
	_bleed_bg.color = AppTheme.BG
	_bleed_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bleed_bg)  # 第一个子节点 = 所有场景之下
	_refit_bleed_bg()
	# 触屏全局放大: 逻辑视口收小 → 牌/按钮物理尺寸 +25%(配合触屏加大尺寸)
	get_window().content_scale_factor = Responsive.ui_scale()
	# 移动端锁 60fps: 高刷屏全速渲染徒增发热耗电
	if Responsive.is_touch():
		Engine.max_fps = 60
	menu = MainMenuScript.new()
	menu.name = "Menu"
	add_child(menu)
	_fit_safe_area(menu)
	_apply_display_prefs()
	get_viewport().size_changed.connect(_refit_safe_area)
	menu.local_game.connect(_start_local)
	menu.online_game.connect(_start_online)
	if AppMode.online_client:
		_start_online()  # --client 直达联机大厅


## 底色铺满整个视口(含安全区外的刘海/挖孔条); 场景根被 _fit_safe_area
## 内缩后, 露出的条带与场景背景同色, 视觉上无缝
func _refit_bleed_bg() -> void:
	if _bleed_bg != null:
		_bleed_bg.position = Vector2.ZERO
		_bleed_bg.size = get_viewport().get_visible_rect().size
		# 条带颜色跟随当前场景的背景顶色(菜单天空/牌桌夜空/大厅深靛),
		# 让安全区外的露出条带与场景无缝衔接
		var p: String = ""
		if _fit_target != null and is_instance_valid(_fit_target) 				and _fit_target.get_script() != null:
			p = str(_fit_target.get_script().resource_path)
		if p.ends_with("main_menu.gd"):
			_bleed_bg.color = Color("232348")
		elif p.ends_with("table.gd"):
			_bleed_bg.color = Color("191934")
		else:
			_bleed_bg.color = AppTheme.BG


## 窗口尺寸/设备旋转变化后重算安全区(手机横屏翻转时刘海换边)
func _refit_safe_area() -> void:
	_refit_bleed_bg()
	if _fit_target != null and is_instance_valid(_fit_target) and _fit_target.visible:
		_fit_safe_area(_fit_target)


## 启动时应用持久化的显示偏好(用户在设置里保存过的才生效)
## 触屏设备跳过窗口尺寸/垂直同步(移动端由系统全屏管理)
func _apply_display_prefs() -> void:
	if Responsive.is_touch():
		return
	if GameSettings.window_size != Vector2i.ZERO:
		DisplayServer.window_set_size(GameSettings.window_size)
	DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if GameSettings.vsync_enabled
			else DisplayServer.VSYNC_DISABLED)
	if GameSettings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## 刘海/圆角安全区: 把场景根整体移进系统安全区(桌面为全屏, 无变化)。
func _fit_safe_area(c: Control) -> void:
	_fit_target = c
	var canvas := get_viewport().get_visible_rect().size
	var wsize := Vector2(DisplayServer.window_get_size())
	if canvas.x <= 0.0 or canvas.y <= 0.0 or wsize.x <= 0.0 or wsize.y <= 0.0:
		return
	# 系统返回的是屏幕坐标, 先换算到窗口本地像素
	var dsa := DisplayServer.get_display_safe_area()
	var sa := Rect2(Vector2(dsa.position) - Vector2(DisplayServer.window_get_position()),
			Vector2(dsa.size))
	sa = sa.intersection(Rect2(Vector2.ZERO, wsize))
	if sa.size.x <= 0.0 or sa.size.y <= 0.0 \
			or (sa.position == Vector2.ZERO and sa.size == wsize):
		return  # 无安全区约束
	var sx := wsize.x / canvas.x
	var sy := wsize.y / canvas.y
	var left := sa.position.x / sx
	var top := sa.position.y / sy
	var right := (wsize.x - sa.end.x) / sx
	var bottom := (wsize.y - sa.end.y) / sy
	c.position = Vector2(left, top)
	c.size = canvas - Vector2(left + right, top + bottom)


## ESC 关闭"返回上一局"确认框
func _unhandled_input(event: InputEvent) -> void:
	if _resume_dlg != null and event is InputEventKey and event.pressed \
			and event.keycode == KEY_ESCAPE:
		_close_resume_dialog()


## Android 返回手势/返回键(WM_GO_BACK_REQUEST, 不走 ESC 键路径):
## 按当前界面路由 — 牌桌=返回菜单 / 大厅=回首页 / 首页=退出应用
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_android_back()


func _handle_android_back() -> void:
	if _resume_dlg != null and is_instance_valid(_resume_dlg):
		_close_resume_dialog()
		return
	if table != null and is_instance_valid(table) and table.visible:
		table._on_leave_pressed()
		return
	if lobby != null and is_instance_valid(lobby) and lobby.visible:
		lobby.go_back()
		return
	get_tree().quit()  # 首页按返回 = 退出应用


func _start_local(mode: String = "normal") -> void:
	# 上一场本地局仍在后台托管进行中 → 弹窗让玩家选: 回局继续 / 开新局
	if table != null and table.mode == "local" \
			and not table.state.is_empty() \
			and str(table.state["phase"]) != "game_end":
		_show_resume_dialog()
		return
	_launch_new_local(mode == "rogue")


func _launch_new_local(rogue: bool = false) -> void:
	if table != null:
		table.queue_free()
		table = null
	menu.visible = false
	table = TableScene.instantiate()
	table.name = "Table"
	table.mode = "local"
	table.rogue = rogue  # add_child 前置: _ready 即开新局
	add_child(table)
	_fit_safe_area(table)
	table.finished.connect(_back_to_menu, CONNECT_ONE_SHOT)


## 后台对局仍在进行: 询问返回上一局还是开新局
func _show_resume_dialog() -> void:
	if _resume_dlg != null:
		return
	var dlg := Control.new()
	dlg.mouse_filter = Control.MOUSE_FILTER_STOP
	dlg.theme = AppTheme.build_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(center)
	var panel := PanelContainer.new()
	var sb := AppTheme.flat(AppTheme.PANEL, AppTheme.GOLD, 14, 2)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := AppTheme.make_label(22, AppTheme.GOLD)
	title.text = "返回上一局？"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var desc := AppTheme.make_label(15, AppTheme.DIM)
	desc.text = "上一局仍在后台进行中（AI 托管代打）"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(desc)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var go := AppTheme.make_button("返回上一局", Vector2(150, 46), 17)
	go.pressed.connect(func() -> void:
		Audio.play("click")
		_close_resume_dialog()
		_resume_local_game())
	row.add_child(go)
	var new_btn := AppTheme.make_button("开始新游戏", Vector2(150, 46), 17)
	new_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_close_resume_dialog()
		menu._show_mode_select())
	row.add_child(new_btn)
	var cancel := AppTheme.make_button("取消", Vector2(96, 46), 15)
	cancel.pressed.connect(func() -> void:
		Audio.play("click")
		_close_resume_dialog())
	row.add_child(cancel)
	_resume_dlg = dlg
	add_child(dlg)
	# 父节点是普通 Node, 锚点不可靠 → 入树后显式铺满视口(同主菜单做法)
	dlg.position = Vector2.ZERO
	dlg.size = get_viewport().get_visible_rect().size


func _close_resume_dialog() -> void:
	if _resume_dlg != null and is_instance_valid(_resume_dlg):
		_resume_dlg.queue_free()
	_resume_dlg = null


## 回到后台托管中的对局: 重新接管自己的座位
func _resume_local_game() -> void:
	_close_resume_dialog()
	if table == null or not is_instance_valid(table):
		menu._show_mode_select()
		return
	table.auto_pilot = false  # 重新接管自己的座位
	table.advancing = false   # 后台驱动循环由代际机制自动让位
	menu.visible = false
	table.visible = true
	table._refresh()
	Audio.play_bgm("table")
	table._advance()
	table.finished.connect(_back_to_menu, CONNECT_ONE_SHOT)  # 重连一次性信号


func _start_online() -> void:
	menu.visible = false
	if net == null:
		net = NetNodeGd.new()
		net.name = "Net"
		net.setup(false)
		add_child(net)
	if lobby == null:
		lobby = LobbyScene.instantiate()
		lobby.name = "Lobby"
		lobby.setup(net)   # ★ 必须在 add_child 之前注入(_ready 依赖)
		add_child(lobby)
		_fit_safe_area(lobby)
		lobby.start_game.connect(_enter_table)
		lobby.back_to_menu.connect(_back_to_menu)
		lobby.host_requested.connect(_start_host)
	lobby.visible = true


## 本机开房: 内嵌专用服务器 + 本机客户端自动连入; 朋友在大厅填本机 IP 直连。
func _start_host() -> void:
	_stop_host()
	var port: int = GameSettings.host_port
	embed_server = NetNodeGd.start_embedded(self, port)
	if embed_server == null:
		lobby.show_status("本机服务器启动失败（端口 %d 被占用？）" % port,
				Color("ff6b6b"))
		return
	net.disconnect_all()
	net.auto_reconnect = true
	net.connect_to("127.0.0.1", port)
	lobby.auto_create_room = true  # 连上后自动创建房间, 房主直接复制邀请码
	# 全部对外地址(局域网优先+Tailscale 兜底): 同 WiFi 朋友可直接一键加入
	lobby.show_host_panel(Responsive.host_ips())


func _stop_host() -> void:
	if embed_server != null:
		NetNodeGd.stop_embedded(self)
		embed_server = null


func _enter_table() -> void:
	if lobby != null:
		lobby.visible = false
	# 守卫: 大厅的 view_changed 在每个服务器广播都会触发 start_game,
	# 已有牌桌时绝不再实例化(否则牌桌叠罗汉: 特效闪烁/卡顿/操作多次)
	if table != null and is_instance_valid(table):
		table.visible = true
		_fit_safe_area(table)
		return
	table = TableScene.instantiate()
	table.name = "Table"
	table.mode = "online"
	table.net = get_node("Net")
	add_child(table)
	_fit_safe_area(table)
	table.finished.connect(_leave_table, CONNECT_ONE_SHOT)


func _leave_table() -> void:
	if table != null:
		table.queue_free()
		table = null
	if lobby != null:
		lobby.visible = true
		_fit_safe_area(lobby)
	Audio.play_bgm("lobby")


func _back_to_menu() -> void:
	if table != null:
		# 本地局托管中(返回菜单自动托管) → 保留牌桌后台继续, 重新进入可继续
		if table.mode == "local" and table.auto_pilot:
			table.visible = false
		else:
			table.queue_free()
			table = null
	if lobby != null:
		lobby.visible = false
	if menu != null:
		menu.visible = true
		_fit_safe_area(menu)
	Audio.play_bgm("lobby")  # 菜单 _ready 只跑一次, 回首页需手动切回首页音乐
