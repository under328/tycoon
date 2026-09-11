## 牌桌背景：弱化的和风夜景（与主菜单同一绘制库，强度调低保证牌面可读性）。
extends Control

const Wafu = preload("res://src/client/ui/wafu_paint.gd")
const AppTheme = preload("res://src/client/theme/app_theme.gd")

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
	Wafu.sky(self, sz, Color("191934"), Color("0d0d1c"))

	# 弱化红日(右上, 小)
	Wafu.sun(self, Vector2(sz.x * 0.86, sz.y * 0.14), 52.0, 0.45)

	# 远山(一层, 很暗)
	Wafu.mountains(self, sz, sz.y * 0.58, sz.y * 0.20, Color("101026"))

	# 青海波(底部, 缓慢流动)
	Wafu.seigaiha(self, sz, sz.y * 0.74, 4, 42.0, _t * 3.0,
			Color(Wafu.INDIGO, 0.40), Color(Wafu.GOLD, 0.10))

	# 中央场地柔光(聚焦牌面区)
	var c := Vector2(sz.x * 0.5, sz.y * 0.42)
	for i in 7:
		ci_glow(c, 200.0 + i * 34.0)

	Wafu.vignette(self, sz, 0.05)
	Wafu.frame(self, sz, Color(AppTheme.GOLD, 0.18))


func ci_glow(c: Vector2, r: float) -> void:
	draw_circle(c, r, Color(1.0, 0.95, 0.8, 0.010))
