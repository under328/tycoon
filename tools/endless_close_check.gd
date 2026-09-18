## 无尽选择弹窗关闭回归: 点击「继续无尽挑战」后弹窗必须关闭并进入下一层
## (回归: 弹窗曾被局部变量遮蔽成员, _close_overlay 关不掉, 卡死界面)
extends SceneTree

var frames := 0
var panel: Control = null
var stage := 0
var go_btn: Button = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	panel = (load("res://src/client/ui/fight_panel.gd") as GDScript).new()
	panel.daily = false
	root.add_child(panel)
	panel.size = root.size


func _find_go(node: Node) -> Button:
	for c in node.get_children():
		if c is Button and str(c.text).contains("无尽"):
			return c
		var r := _find_go(c)
		if r != null:
			return r
	return null


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5 and stage == 0:
		stage = 1
		panel._show_endless_choice()
		print("[endless] 弹窗已建, overlay 成员=", panel.overlay != null)
	elif frames == 15 and stage == 1:
		stage = 2
		go_btn = _find_go(panel.overlay)
		if go_btn == null:
			print("[endless] FAIL 找不到继续按钮")
			quit(1)
			return false
		print("[endless] 模拟点击继续无尽挑战")
		go_btn.pressed.emit()
	elif frames == 17 and stage == 2:
		var member_cleared: bool = panel.overlay == null
		var still_valid: bool = is_instance_valid(go_btn) \
				and go_btn.is_inside_tree()
		var next_floor: bool = panel.fm.floor_num == 2 \
				and str(panel.fm.phase) == "draft" \
				and not bool(panel._busy)
		var ok := member_cleared and not still_valid and next_floor
		print("[endless] 成员清理=%s 旧弹窗离树=%s 下一层=%s → %s" % [
				member_cleared, not still_valid, next_floor,
				"CLOSE_OK" if ok else "CLOSE_FAIL"])
		quit(0 if ok else 1)
	return false
