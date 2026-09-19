## 奇物图鉴页截图验证: 实例化 fight_help, 直接跳到图鉴页(末页)截图 —
## 验证 8 枚奇物芯片排布与"未获得置灰/已获得点亮"两种状态。
extends SceneTree

var frames := 0
var help: Control = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_factor = 1.0


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		help = (load("res://src/client/ui/fight_help.gd") as GDScript).new()
		root.add_child(help)
		help.size = root.size
		# 预置 2 枚已获得(其余保持置灰); --script 模式下 autoload 用节点查找
		var wallet = root.get_node("Wallet")
		wallet.note_relic(2)
		wallet.note_relic(5)
	elif frames == 25:
		help._show(help.PAGES.size() - 1)   # 跳到奇物图鉴页
	elif frames == 45:
		root.get_viewport().get_texture().get_image() \
				.save_png("builds/fight_help_codex.png")
		print("[help-cap] saved")
	elif frames == 55:
		quit(0)
	return false
