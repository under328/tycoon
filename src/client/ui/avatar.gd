## 头像控件: 按 skin_id 程序化绘制人物徽章（商城预览与牌桌座位共用）。
## frameless=true 时只画人物本体不带徽章底盘/描金外环(战斗场景大形象用)。
extends Control

const SkinsLib = preload("res://src/client/ui/skins.gd")

var skin_id := "skin_default":
	set(v):
		if skin_id == v:
			return  # 联机每次视图刷新都会赋值: 同值早退避免像素网格重绘
		skin_id = v
		queue_redraw()

var frameless := false:
	set(v):
		if frameless == v:
			return
		frameless = v
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(64, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if size.x < 8:
		return
	SkinsLib.draw_avatar(self, skin_id, size / 2.0,
			minf(size.x, size.y) / 2.0 - 2.0, not frameless)
