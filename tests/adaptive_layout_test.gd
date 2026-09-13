## 多设备自适应布局断言(无头)。PC/平板4:3/手机20:9/超宽 四档逻辑视口,
## 逐场景(主菜单/大厅/牌桌/商城/联机帮助/新手引导)校验关键控件:
## 不越界、右缘锚定、水平居中、底缘跟随。全部通过打印 ALL_PASS。
## 运行: godot --headless --path . --script tests/adaptive_layout_test.gd
extends SceneTree

## 场景用运行时 load(--script 模式下 const preload 早于 autoload 注册, 编译会找不到单例)
const SCENE_PATHS := [
	"res://src/client/scenes/main_menu.gd",
	"res://src/client/scenes/lobby.tscn",
	"res://src/client/scenes/table.tscn",
	"res://src/client/ui/shop.gd",
	"res://src/client/ui/lobby_help.gd",
	"res://src/client/scenes/tutorial.gd",
]

const PROFILES := [
	["pc", Vector2(1280, 720)],
	["pad4_3", Vector2(1280, 960)],
	["phone20_9", Vector2(1600, 720)],
	["ultrawide", Vector2(1770, 720)],
]

var checks := 0
var failed: Array = []
var cur: Control = null
var scene_idx := -1
var frames := 0
var prof_idx := 0
var prof_sub := 0   # 0=改窗口尺寸 1=传播 2=显式设场景尺寸(模拟 main._fit_safe_area) 3=传播 4=断言


func expect(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failed.append(msg)


func _in_rect(c: Control, w: float, h: float, tag: String) -> void:
	expect(c.position.x >= -2.0 and c.position.y >= -2.0
			and c.position.x + c.size.x <= w + 2.0
			and c.position.y + c.size.y <= h + 2.0,
			"%s 越界 pos=%s size=%s" % [tag, c.position, c.size])


func _make_scene(i: int) -> Control:
	var path: String = SCENE_PATHS[i]
	if path.ends_with(".tscn"):
		return (load(path) as PackedScene).instantiate()
	return (load(path) as GDScript).new()


func _check_scene(i: int, w: float, h: float) -> void:
	var s := cur
	match i:
		0:  # 主菜单
			expect(absf(s._title_group.position.x
					- clampf(w * 0.45, 500.0, w - 540.0)) <= 1.0,
					"menu 标题组未锚右半区 x=%s (w=%d)" % [s._title_group.position, w])
			expect(s._badge.position.x + s._badge.size.x <= w - 20.0,
					"menu 余额徽章越右缘 x=%s w=%d" % [s._badge.position, w])
			expect(absf(s._hint_lbl.position.x + s._hint_lbl.size.x / 2.0 - w / 2.0) <= 2.0,
					"menu 底部提示未水平居中")
			expect(s._ver_lbl.position.y >= h - 40.0, "menu 版本号未贴底缘")
			for child in s.get_children():
				var cs: Script = child.get_script()
				if cs != null and str(cs.resource_path).ends_with("slash_menu_item.gd"):
					_in_rect(child, w, h, "menu 菜单项")
		1:  # 大厅: 所有注册控件不越界 + 锚定公式正确
			var extra := maxf(w - 1280.0, 0.0)
			var eh := maxf(h - 720.0, 0.0)
			for e: Array in s._placed:
				_in_rect(e[0], w, h, "lobby %s" % e[0].name)
			expect(absf(s.port_edit.position.x - (1040.0 + extra)) <= 1.0,
					"lobby 端口输入未锚右缘 x=%s extra=%s" % [s.port_edit.position.x, extra])
			expect(absf(s._emoji_btns[0].position.y - (550.0 + eh)) <= 1.0,
					"lobby 表情栏未贴底缘 y=%s eh=%s" % [s._emoji_btns[0].position.y, eh])
			expect(absf(s.copy_btn.position.y - (470.0 + eh * 0.45)) <= 1.0,
					"lobby 操作行纵向分配错误 y=%s" % s.copy_btn.position.y)
		2:  # 牌桌
			expect(s.hand_box.position.x >= 0.0,
					"table 手牌区越左缘 x=%s" % s.hand_box.position.x)
			_in_rect(s.hand_box, w, h, "table 手牌区")
			expect(absf(s.field_panel.position.x + s.field_panel.size.x / 2.0 - w / 2.0) <= 2.0,
					"table 出牌区未水平居中")
			_in_rect(s.field_panel, w, h, "table 出牌区")
			_in_rect(s.self_panel, w, h, "table 自己面板")
			_in_rect(s.ops_row, w, h, "table 操作行")
			for sp in s._seat_panels:
				_in_rect(sp, w, h, "table 座位面板")
		3:  # 商城
			expect(s._back_btn.position.x + s._back_btn.size.x <= w - 20.0,
					"shop 返回按钮未锚右缘")
			expect(absf(s._scroll.size.x - (w - 80.0)) <= 1.0, "shop 商品区宽度未随窗口")
			expect(absf(s._scroll.size.y - (h - 236.0)) <= 1.0, "shop 商品区高度未随窗口")
			expect(absf(s._toast.position.y - (h - 60.0)) <= 1.0, "shop 提示未贴底缘")
		4:  # 联机帮助
			expect(absf(s._prev_btn.position.x - (w / 2.0 - 300.0)) <= 1.0,
					"help 上一页未居中左")
			expect(absf(s._next_btn.position.x - (w / 2.0 + 120.0)) <= 1.0,
					"help 下一页未居中右")
			expect(absf(s._close_lbl.position.x - (w - 110.0)) <= 1.0, "help 关闭未锚右缘")
		5:  # 新手引导
			expect(absf(s._fig.position.x - (w - 800.0) / 2.0) <= 1.0, "tutorial 图示未居中")
			expect(absf(s._close_lbl.position.x - (w - 110.0)) <= 1.0, "tutorial 关闭未锚右缘")
			expect(absf(s._next_btn.position.x - (w / 2.0 + 120.0)) <= 1.0, "tutorial 下一页未居中")


func _initialize() -> void:
	_next()


func _next() -> void:
	if cur != null:
		cur.queue_free()
		cur = null
	scene_idx += 1
	frames = 0
	if scene_idx >= 6:
		if not failed.is_empty():
			for f in failed:
				printerr("[adaptive] FAIL: " + str(f))
			print("ADAPTIVE LAYOUT  %d checks, %d failed" % [checks, failed.size()])
			quit(1)
			return
		print("ADAPTIVE LAYOUT  %d checks, 0 failed" % checks)
		print("ALL PASS")
		quit(0)
		return
	cur = _make_scene(scene_idx)
	cur.name = "AdaptiveCap%d" % scene_idx
	root.add_child(cur)


func _process(_d: float) -> bool:
	frames += 1
	if frames < 8:
		return false
	if scene_idx >= 0 and scene_idx < 6:
		match prof_sub:
			0:
				root.size = Vector2i(PROFILES[prof_idx][1])
				prof_sub = 1
			1:
				prof_sub = 2
			2:
				# 生产环境由 main._fit_safe_area 显式设场景根尺寸(安全区内缩),
				# 测试同样显式设置 — 裸 Control 不随窗口自动缩放
				cur.position = Vector2.ZERO
				cur.size = root.get_visible_rect().size
				prof_sub = 3
			3:
				prof_sub = 4  # 等一帧: resized→_relayout 在下一帧生效
			_:
				var vs: Vector2 = root.get_visible_rect().size
				_check_scene(scene_idx, vs.x, vs.y)
				prof_idx += 1
				prof_sub = 0
				if prof_idx >= PROFILES.size():
					prof_idx = 0
					_next()
	return false
