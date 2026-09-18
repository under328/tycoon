## 联机页点击目标审计: 手机档逻辑视口下枚举全部可见可点控件的矩形,
## 找出互相重叠的点击目标(误触根因)。
extends SceneTree

var f := 0
var lobby: Control = null


func _initialize() -> void:
	var scn: GDScript = load("res://src/client/scenes/lobby.gd")
	lobby = scn.new()
	lobby.size = Vector2(998, 461)   # 手机紧凑档逻辑视口
	root.add_child(lobby)


func _process(_d: float) -> bool:
	f += 1
	if f < 40:
		return false
	print("[tap] viewport=", root.get_visible_rect().size)
	_walk(lobby, 0)
	quit(0)
	return false


func _walk(n: Node, depth: int) -> void:
	for c in n.get_children():
		if c is Control and c.visible:
			var ct := c as Control
			if (ct is Button or ct is LineEdit) and ct.get_global_rect().size.x > 0:
				print("[tap] %s [%s] %s" % [ct.get_class(), str(ct).substr(0, 24),
						ct.get_global_rect()])
			if ct is OptionButton:
				print("[tap] OptionButton [%s] %s" % [str(ct).substr(0, 24), ct.get_global_rect()])
			_walk(c, depth + 1)
