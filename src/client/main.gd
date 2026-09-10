## 客户端/服务器入口：按 AppMode 分发。
##   服务器: /root/Main/Net = net_server（RPC 路径两端必须一致）
##   联机客户端: /root/Main/Net = net_client + 大厅 ↔ 牌桌切换
##   本地模式: 直接进牌桌（人 + 3AI）
extends Node

const TableScene := preload("res://src/client/scenes/table.tscn")
const LobbyScene := preload("res://src/client/scenes/lobby.tscn")
const NetNodeGd := preload("res://src/protocol/net_node.gd")

var lobby = null
var table = null


func _ready() -> void:
	if AppMode.is_server:
		var net := NetNodeGd.new()
		net.name = "Net"
		net.setup(true)
		add_child(net)
	elif AppMode.online_client:
		var net := NetNodeGd.new()
		net.name = "Net"
		net.setup(false)
		add_child(net)
		lobby = LobbyScene.instantiate()
		lobby.name = "Lobby"
		add_child(lobby)
		lobby.setup(net)
		lobby.start_game.connect(_enter_table)
	else:
		table = TableScene.instantiate()
		table.name = "Table"
		add_child(table)


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
