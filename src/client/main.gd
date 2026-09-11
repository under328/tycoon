## 客户端/服务器入口：按 AppMode 分发。
##   服务器: /root/Main/Net = net_node(服务器模式)
##   客户端: 主菜单 → (本地游戏|联机游戏→大厅→牌桌)；--client 跳过菜单直达大厅
##   本地默认: 主菜单 → 本地游戏 → 牌桌(人+3AI)
extends Node

const TableScene := preload("res://src/client/scenes/table.tscn")
const LobbyScene := preload("res://src/client/scenes/lobby.tscn")
const MainMenuScript := preload("res://src/client/scenes/main_menu.gd")
const NetNodeGd := preload("res://src/protocol/net_node.gd")

var menu = null
var lobby = null
var table = null
var net = null
var embed_server: Node = null   # 本机开房的内嵌服务器(非空=正在做主机)


func _ready() -> void:
	if AppMode.is_server:
		net = NetNodeGd.new()
		net.name = "Net"
		net.setup(true)
		add_child(net)
		return
	menu = MainMenuScript.new()
	menu.name = "Menu"
	add_child(menu)
	_fit_safe_area(menu)
	_apply_display_prefs()
	menu.local_game.connect(_start_local)
	menu.online_game.connect(_start_online)
	if AppMode.online_client:
		_start_online()  # --client 直达联机大厅


## 启动时应用持久化的显示偏好(用户在设置里保存过的才生效)
func _apply_display_prefs() -> void:
	if GameSettings.window_size != Vector2i.ZERO:
		DisplayServer.window_set_size(GameSettings.window_size)
	DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if GameSettings.vsync_enabled
			else DisplayServer.VSYNC_DISABLED)
	if GameSettings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## 刘海/圆角安全区: 把场景根整体移进系统安全区(桌面为全屏, 无变化)。
func _fit_safe_area(c: Control) -> void:
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


func _start_local() -> void:
	menu.visible = false
	table = TableScene.instantiate()
	table.name = "Table"
	table.mode = "local"
	add_child(table)
	_fit_safe_area(table)
	table.finished.connect(_back_to_menu, CONNECT_ONE_SHOT)


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
	var ts := _tailscale_ips()
	lobby.host_invite_ip = "" if ts.is_empty() else str(ts[0])
	lobby.auto_create_room = true  # 连上后自动创建房间, 房主直接复制邀请码
	if ts.is_empty():
		lobby.show_status("本机服务器已启动（端口 %d）\n未检测到 Tailscale IP。\n请先在所有设备上安装并登录 Tailscale（tailscale.com，免费），再重新点击本机开房。" % port,
				Color("ff6b6b"))
	else:
		lobby.show_status("本机服务器已启动, 正在自动创建房间…\n你的 Tailscale IP: %s\n房间建好后点【复制邀请码】发给朋友即可" % str(ts[0]))


func _stop_host() -> void:
	if embed_server != null:
		NetNodeGd.stop_embedded(self)
		embed_server = null


## Tailscale 虚拟网 IP(100.x.x.x): 跨网络联机的首选地址
func _tailscale_ips() -> Array:
	var out: Array = []
	for ip in IP.get_local_addresses():
		var s := str(ip)
		var parts := s.split(".")
		if parts.size() == 4 and int(parts[0]) == 100:
			out.append(s)
	return out


func _enter_table() -> void:
	if lobby != null:
		lobby.visible = false
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


func _back_to_menu() -> void:
	if table != null:
		table.queue_free()
		table = null
	if lobby != null:
		lobby.visible = false
	if menu != null:
		menu.visible = true
