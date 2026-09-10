## 客户端/服务器入口：按 AppMode 分发。
extends Node

const TableScene := preload("res://src/client/scenes/table.tscn")
const RoomManagerGd = preload("res://src/server/room_manager.gd")


func _ready() -> void:
	if AppMode.is_server:
		var server := RoomManagerGd.new()
		server.name = "RoomManager"
		add_child(server)
	else:
		add_child(TableScene.instantiate())
