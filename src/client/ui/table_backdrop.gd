## 牌桌弱化和风夜景背景(与主菜单同一绘制库, 强度调低保证牌面可读性)。
extends Control

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const Wafu = preload("res://src/client/ui/wafu_paint.gd")

var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var sz := size
	if sz.x < 10 or sz.y < 10:
		return
	WafuPaint.sky(self, sz, Color("191934"), Color("0d0d1c"))
	# 弱化红日(右上, 小)
	WafuPaint.sun(self, Vector2(sz.x * 0.86, sz.y * 0.14), 52.0, 0.45)
	# 远山(一层, 很暗)
	WafuPaint.mountains(self, sz, sz.y * 0.58, sz.y * 0.20, Color("101026"))
	# 青海波(底部, 缓慢流动)
	WafuPaint.seigaiha(self, sz, sz.y * 0.74, 4, 42.0, _t * 3.0,
			Color(Wafu.INDIGO, 0.40), Color(Wafu.GOLD, 0.10))
	# 描金边框
	WafuPaint.frame(self, sz, Color(AppTheme.GOLD, 0.18))
