## 格斗精灵动画控件: 播放 assets/fight/<skin>/<action>.png 精灵表
## (256×256/帧, 纵向排列)。缺资产时回退程序化头像(Avatar)。
## 动作: idle / attack / skill_fire / skill_frost / skill_light /
##       defend / ult / transform / hit
extends Control

signal animation_finished(action: String)

const ACTIONS_FPS := {
	"idle": 8, "attack": 11, "skill_fire": 10, "skill_frost": 10,
	"skill_light": 10, "defend": 6, "ult": 10, "transform": 9, "hit": 8,
}

var skin_id := "skin_default":
	set(v):
		if skin_id == v:
			return
		skin_id = v
		_reload()

var action := "idle":
	set(v):
		if action == v:
			return
		action = v
		_reload()

var loop := true:
	set(v):
		if loop == v:
			return
		loop = v
		if not loop and _frame >= _frames:
			_frame = 0

var flip_h := false:
	set(v):
		if flip_h == v:
			return
		flip_h = v
		queue_redraw()

var _tex: Texture2D = null
var _frames := 1
var _frame := 0
var _t := 0.0
var _fallback: Control = null   # 缺精灵表时的程序化头像回退

static var _sheet_cache := {}


func _ready() -> void:
	custom_minimum_size = Vector2(128, 128)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 256 资产在 <256 控件上缩小时取最近 mip(≈128 级), 保持像素干净不闪烁
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_reload()


func _reload() -> void:
	_frame = 0
	_t = 0.0
	var key := "%s/%s" % [skin_id, action]
	_tex = _sheet_cache.get(key)
	if _tex == null and not _sheet_cache.has(key):
		var path := "res://assets/fight/%s/%s.png" % [skin_id, action]
		if ResourceLoader.exists(path):
			_tex = load(path)
		_sheet_cache[key] = _tex
	if _tex != null:
		# 帧边长取纹理宽(方形帧, 256 资产; 异常纹理也不越界)
		var fw := maxi(int(_tex.get_width()), 1)
		_frames = maxi(int(_tex.get_height()) / fw, 1)
		if _fallback != null:
			_fallback.queue_free()
			_fallback = null
	else:
		_frames = 1
		if _fallback == null:
			var AvatarScript = preload("res://src/client/ui/avatar.gd")
			_fallback = AvatarScript.new()
			_fallback.frameless = true
			_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
			add_child(_fallback)
	_fallback_set_skin()
	queue_redraw()


func _fallback_set_skin() -> void:
	if _fallback != null:
		(_fallback as Control).set("skin_id", skin_id)


## 单次播放某动作(播完自动回 base); base 为空则停在最后一帧
func play_once(p_action: String, base := "idle") -> void:
	action = p_action
	loop = false
	set_meta("base", base)


func back_to(base := "idle") -> void:
	action = base
	loop = true


func _process(delta: float) -> void:
	if _tex == null or _frames <= 1:
		return
	_t += delta * float(ACTIONS_FPS.get(action, 8))
	if _t >= 1.0:
		_t -= 1.0
		_frame += 1
		if _frame >= _frames:
			if loop:
				_frame = 0
			else:
				_frame = _frames - 1
				var base := str(get_meta("base", "idle"))
				animation_finished.emit(action)
				back_to(base)
		queue_redraw()


func _draw() -> void:
	if _tex == null:
		return   # 回退头像子控件负责显示
	var fw := maxi(int(_tex.get_width()), 1)
	var dst := Rect2(Vector2.ZERO, size)
	var src := Rect2(0.0, float(_frame) * fw, fw, fw)
	if flip_h:
		draw_texture_rect_region(_tex, dst, src, Color.WHITE, true)
	else:
		draw_texture_rect_region(_tex, dst, src)
