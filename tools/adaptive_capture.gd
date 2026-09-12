## 多设备自适应截图: 三档真实渲染视口(窗口尺寸=逻辑尺寸, 内容缩放恒为 1):
##   PC 1280x720 / 平板4:3 1280x960 / 手机20:9 1600x720
## 逐场景(主菜单/大厅/商城/联机帮助/新手引导)截帧到 builds/adaptive_*.png。
## 用法: godot --path . --script tools/adaptive_capture.gd  (非 headless, 需渲染)
extends SceneTree

const PROFILES := [
	["pc_720p", Vector2i(1280, 720)],
	["pad_4k3", Vector2i(1280, 960)],
	["phone_20x9", Vector2i(1600, 720)],
]
const SCENE_PATHS := [
	"res://src/client/scenes/main_menu.gd",
	"res://src/client/scenes/lobby.tscn",
	"res://src/client/ui/shop.gd",
	"res://src/client/ui/lobby_help.gd",
	"res://src/client/scenes/tutorial.gd",
]
const SCENE_NAMES := ["menu", "lobby", "shop", "help", "tutorial"]

var step := 0    # 分辨率档
var sidx := -1   # 场景序号
var cur: Control = null
var frames := 0


func _initialize() -> void:
	_next()


func _next() -> void:
	if cur != null:
		cur.queue_free()
		cur = null
	sidx += 1
	frames = 0
	if sidx >= SCENE_PATHS.size():
		sidx = 0
		step += 1
		if step >= PROFILES.size():
			print("[cap] DONE")
			quit(0)
			return
	var p: Array = PROFILES[step]
	root.size = Vector2i(p[1])
	var path: String = SCENE_PATHS[sidx]
	if path.ends_with(".tscn"):
		cur = (load(path) as PackedScene).instantiate()
	else:
		cur = (load(path) as GDScript).new()
	cur.name = "Cap%d%d" % [step, sidx]
	root.add_child(cur)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 12:
		var img := root.get_texture().get_image()
		var fname := "adaptive_%s_%s.png" % [PROFILES[step][0], SCENE_NAMES[sidx]]
		img.save_png("res://builds/" + fname)
		print("[cap] saved " + fname)
	if frames >= 14:
		_next()
	return false
