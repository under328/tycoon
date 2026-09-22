## 头像控件: 优先加载像素美术资产(assets/avatars/<skin>_64.png, 64×64),
## 缺资产时回退程序化像素绘制(avatar_pix 32×32 合成器)。
## frameless=true 时只画人物本体不带徽章底盘/描金外环(战斗场景大形象用)。
extends Control

const SkinsLib = preload("res://src/client/ui/skins.gd")

var skin_id := "skin_default":
	set(v):
		if skin_id == v:
			return  # 联机每次视图刷新都会赋值: 同值早退避免像素网格重绘
		skin_id = v
		_tex = _texture_for(v)
		queue_redraw()

var frameless := false:
	set(v):
		if frameless == v:
			return
		frameless = v
		queue_redraw()

var _tex: Texture2D = null

## 纹理缓存(所有头像控件共享)
static var _tex_cache := {}


static func _texture_for(skin_id: String) -> Texture2D:
	if _tex_cache.has(skin_id):
		return _tex_cache[skin_id]
	var path := "res://assets/avatars/%s_64.png" % skin_id
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[skin_id] = tex
	return tex


func _ready() -> void:
	custom_minimum_size = Vector2(64, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tex = _texture_for(skin_id)


func _draw() -> void:
	if size.x < 8:
		return
	if _tex != null:
		# 像素资产: 有框模式留出珠纹/描金空间, 无框铺满
		var r := minf(size.x, size.y) / 2.0 - 2.0
		var theme := SkinsLib._skin_theme(skin_id)
		if not frameless:
			draw_circle(size / 2.0, r, theme["bg"])
			for i in 12:
				var ang := TAU * i / 12.0
				draw_circle(size / 2.0 + Vector2.from_angle(ang) * r * 0.86,
						r * 0.045, Color(SkinsLib.GOLD, 0.5))
		var inner := r * (1.94 if frameless else 1.80)
		var dst := Rect2(size / 2.0 - Vector2.ONE * inner * 0.5,
				Vector2.ONE * inner)
		draw_texture_rect(_tex, dst, false)
		if not frameless:
			draw_arc(size / 2.0, r * 0.97, 0, TAU, 40, Color(SkinsLib.GOLD, 0.75),
					r * 0.06, true)
		return
	# 回退: 程序化像素画
	SkinsLib.draw_avatar(self, skin_id, size / 2.0,
			minf(size.x, size.y) / 2.0 - 2.0, not frameless)
