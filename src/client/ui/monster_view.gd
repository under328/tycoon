## 怪物像素画控件 v2: 形象由 monster_art.gd 程序化生成(32×32 画布,
## 原型骨架 + 主题三阶调色 + 描边), NEAREST 放大保持像素锐度。
## group 0..4 主题组 × kind mob/elite/boss × variant 换色变体。
extends Control

const MonsterArt = preload("res://src/client/ui/monster_art.gd")

var group := 0: set = _setv_group
var kind := "mob": set = _setv_kind
var variant := 0: set = _setv_variant

var _t := 0.0
var _frame := 0

func _setv_group(v: int) -> void:
	group = clampi(v, 0, 4)
	queue_redraw()


func _setv_kind(v: String) -> void:
	kind = v
	queue_redraw()


func _setv_variant(v: int) -> void:
	variant = v
	queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(120, 120)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	var nf := int(_t / 0.55) % 2   # 两帧待机呼吸(0.55s 一帧)
	if nf != _frame:
		_frame = nf
		queue_redraw()


func _draw() -> void:
	if size.x < 8:
		return
	var art: Dictionary = MonsterArt.build(group, kind, variant, _frame)
	draw_texture_rect(art["tex"], Rect2(Vector2.ZERO, size), false)
