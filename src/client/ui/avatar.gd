## 头像控件: 按 skin_id 程序化绘制人物徽章（商城预览与牌桌座位共用）。
extends Control

const SkinsLib = preload("res://src/client/ui/skins.gd")

var skin_id := "skin_default":
	set(v):
		skin_id = v
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(64, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if size.x < 8:
		return
	SkinsLib.draw_avatar(self, skin_id, size / 2.0, minf(size.x, size.y) / 2.0 - 2.0)
