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
	menu.local_game.connect(_start_local)
	menu.online_game.connect(_start_online)
	if AppMode.online_client:
		_start_online()  # --client 直达联机大厅


func _start_local() -> void:
	menu.visible = false
	table = TableScene.instantiate()
	table.name = "Table"
	table.mode = "local"
	add_child(table)
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
		lobby.start_game.connect(_enter_table)
		lobby.back_to_menu.connect(_back_to_menu)
	lobby.visible = true


func _enter_table() -> void:
	if lobby != null:
		lobby.visible = false
	table = TableScene.instantiate()
	table.name = "Table"
	table.mode = "online"
	table.net = get_node("Net")
	add_child(table)
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
