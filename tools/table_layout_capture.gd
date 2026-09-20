## 牌桌布局截图验证: 本地普通(play 阶段: 顶栏三钮/座位面板) +
## 本地肉鸽(draft 阶段: 命运二选一横条; play 阶段: 命运横幅)。
## 用法: godot --path . --script tools/table_layout_capture.gd
extends SceneTree

var f := 0
var main = null
var stage := 0        # 0普通play 1肉鸽draft 2肉鸽play
var tries := 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_factor = 1.0


func _process(_d: float) -> bool:
	f += 1
	match f:
		10:
			main = (load("res://src/client/main.tscn") as PackedScene).instantiate()
			root.add_child(main)
		25:
			main._launch_new_local(false)
		160:
			if main.table != null \
					and str(main.table._current_view().get("phase", "")) == "play":
				root.get_viewport().get_texture().get_image() \
						.save_png("builds/layout_normal.png")
				print("[lay] normal saved")
				main._launch_new_local(true)
			else:
				_fallback()
		330:
			if main.table != null \
					and str(main.table._current_view().get("phase", "")) == "draft":
				root.get_viewport().get_texture().get_image() \
						.save_png("builds/layout_rogue_draft.png")
				print("[lay] rogue draft saved")
				# 天选者为玩家时选一张, 推进到 play 看横幅
				if main.table._rogue_dlg != null:
					for node in main.table._rogue_dlg.get_children():
						for b in node.get_children():
							if b is Button and "重抽" not in str(b.text):
								b.pressed.emit()
								break
			else:
				_fallback()
		420:
			# 关掉命运卡揭示弹窗 → play 阶段横幅可见
			if main.table != null and main.table._rogue_dlg != null \
					and is_instance_valid(main.table._rogue_dlg):
				main.table._close_rogue_reveal()
		460:
			# 无论处于何种阶段都截一张: 验证横幅/座位面板/顶栏布局
			root.get_viewport().get_texture().get_image() \
					.save_png("builds/layout_rogue_play.png")
			if main.table != null:
				print("[lay] rogue late phase=", str(main.table._current_view().get("phase", "")),
						" dlg=", main.table._rogue_dlg != null)
			print("[lay] rogue play saved (横幅应在信息框下方)")
		520:
			quit(0)
	return false


func _fallback() -> void:
	tries += 1
	if tries % 60 != 0:
		return
	# 阶段错位时重试推进: draft 由引擎自动轮转, 直接多等
	print("[lay] waiting phase... stage=", stage)
