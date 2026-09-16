## 多设备自适应布局断言(无头)。PC/平板4:3/手机20:9/超宽/手机紧凑 五档逻辑视口,
## 遍历全部页面(主菜单/大厅双视图/牌桌+离开确认框/商城/联机帮助/新手引导/
## 设置面板/结算面板), 每页跑三层通用断言:
##   ① 越界: 所有可见控件完整落在视口内(不截断)
##   ② 重叠: 交互控件(按钮/输入框/斜切菜单项)两两不相交
##   ③ 文本: 按钮与标签的实际文本按主题字体度量不超控件宽(不省略号截断);
##      自动换行标签按多行度量不超高
## 外加各页关键控件的锚定公式校验。全部通过打印 ALL PASS。
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
	"res://src/client/ui/settings_panel.gd",
	"res://src/client/ui/game_end_panel.gd",
	"res://src/client/ui/rogue_help.gd",
	"res://src/client/ui/profile_panel.gd",
	"res://src/client/ui/fight_panel.gd",
]

const PROFILES := [
	["pc", Vector2(1280, 720)],
	["pad4_3", Vector2(1280, 960)],
	["phone20_9", Vector2(1600, 720)],
	["ultrawide", Vector2(1770, 720)],
	["phone_compact", Vector2(1248, 576)],   # 手机触屏 csf1.25 后的逻辑视口
]

const TOL := 6.0   # 越界容差: 旋转卡牌的 AABB 天然略大于布局盒

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
	expect(c.position.x >= -TOL and c.position.y >= -TOL
			and c.position.x + c.size.x <= w + TOL
			and c.position.y + c.size.y <= h + TOL,
			"%s 越界 pos=%s size=%s" % [tag, c.position, c.size])


func _make_scene(i: int) -> Control:
	var path: String = SCENE_PATHS[i]
	if path.ends_with(".tscn"):
		return (load(path) as PackedScene).instantiate()
	return (load(path) as GDScript).new()


## 通用收集: 可见控件 → [越界检查集, 交互控件集, 文本检查集]
## ScrollContainer 的后代是容器裁剪管理(内容超出视口属正常滚动), 只查重叠与文本
func _collect(root_c: Control) -> Array:
	var bounds: Array = []
	var inters: Array = []
	var texts: Array = []
	_walk(root_c, false, bounds, inters, texts)
	return [bounds, inters, texts]


func _walk(c: Node, in_scroll: bool, bounds: Array, inters: Array, texts: Array) -> void:
	for ch in c.get_children():
		if not (ch is Control) or not ch.visible:
			continue
		var sc := in_scroll or ch is ScrollContainer
		var is_menu_item: bool = ch.get_script() != null and str(
				(ch.get_script() as Script).resource_path).ends_with("slash_menu_item.gd")
		if ch is Button or ch is LineEdit or is_menu_item:
			inters.append(ch)
		if not sc:
			bounds.append(ch)
		if (ch is Button or ch is Label) and str(ch.text) != "":
			texts.append(ch)
		_walk(ch, sc, bounds, inters, texts)


## ③ 文本适配: ""=通过, 否则返回原因
func _text_issue(c: Control) -> String:
	var f: Font = c.get_theme_font("font")
	var fs: int = c.get_theme_font_size("font_size")  # 主题项名是 font_size
	if f == null:
		return ""
	if fs <= 0:
		fs = 16
	# 自动换行标签: 按当前宽度做多行度量, 高度必须装得下
	if c is Label and c.autowrap_mode != TextServer.AUTOWRAP_OFF:
		var need: Vector2 = f.get_multiline_string_size(c.text,
				HORIZONTAL_ALIGNMENT_LEFT, c.size.x, fs)
		if need.y > c.size.y + 4.0:
			return "文本超高 need=%.0f have=%.0f text=%s" % [need.y, c.size.y,
					str(c.text).left(20)]
		return ""
	# 单行(按钮/普通标签): 最长行宽 + 水平内容边距 必须装得下
	var lines := str(c.text).split("\n")
	var wmax := 0.0
	for ln in lines:
		wmax = maxf(wmax, f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var sb: StyleBox = c.get_theme_stylebox("normal")
	var m := 0.0
	if sb != null:
		m = sb.get_content_margin(SIDE_LEFT) + sb.get_content_margin(SIDE_RIGHT)
	if wmax + m > c.size.x + 3.0:
		return "文本超宽 need=%.0f have=%.0f text=%s" % [wmax + m, c.size.x,
				str(c.text).left(20)]
	return ""


## ①越界 ②重叠 ③文本 — 每页每档分辨率通用断言
func _sweep(i: int, w: float, h: float) -> void:
	var coll := _collect(cur)
	var bounds: Array = coll[0]
	var inters: Array = coll[1]
	var texts: Array = coll[2]
	for c in bounds:
		_in_rect(c, w, h, "%s %s" % [SCENE_PATHS[i].get_file(), c.name])
	for a_idx in inters.size():
		for b_idx in range(a_idx + 1, inters.size()):
			var a: Control = inters[a_idx]
			var b: Control = inters[b_idx]
			expect(not a.get_global_rect().intersects(b.get_global_rect()),
					"%s 交互控件重叠 %s(%s) × %s(%s)" % [
						SCENE_PATHS[i].get_file(), a.name, a.get_global_rect(),
						b.name, b.get_global_rect()])
	for c in texts:
		var issue := _text_issue(c)
		expect(issue == "", "%s %s %s" % [SCENE_PATHS[i].get_file(), c.name, issue])


func _check_scene(i: int, w: float, h: float) -> void:
	var s := cur
	match i:
		0:  # 主菜单
			# 标题组原点含 PAD(14,16) 补偿(切线左伸/中字上提的负偏移折进组内)
			expect(absf(s._title_group.position.x + 14.0
					- clampf(w * 0.45, 500.0, w - 540.0)) <= 1.0,
					"menu 标题组未锚右半区 x=%s (w=%d)" % [s._title_group.position, w])
			expect(s._badge.position.x + s._badge.size.x <= w - 20.0,
					"menu 余额徽章越右缘 x=%s w=%d" % [s._badge.position, w])
			expect(absf(s._hint_lbl.position.x + s._hint_lbl.size.x / 2.0 - w / 2.0) <= 2.0,
					"menu 底部提示未水平居中")
			expect(s._ver_lbl.position.y >= h - 40.0, "menu 版本号未贴底缘")
		1:  # 大厅: 双视图锚定(入口页/房间页) + 公式正确
			var extra := maxf(w - 1280.0, 0.0)
			var eh := maxf(h - 720.0, 0.0)
			s._apply_view("entry")
			for n in s._layouts:
				if (s._layouts[n] as Dictionary).has("entry"):
					_in_rect(n, w, h, "lobby entry %s" % n.name)
			expect(absf(s.port_edit.position.x - (1040.0 + extra)) <= 1.0,
					"lobby 端口输入未锚右缘 x=%s extra=%s" % [s.port_edit.position.x, extra])
			expect(s.code_edit.visible and not s.room_title_lbl.visible,
					"入口页显隐错误")
			# 房间页(独立子页面): 切视图后断言
			s._apply_view("room")
			for n in s._layouts:
				if (s._layouts[n] as Dictionary).has("room"):
					_in_rect(n, w, h, "lobby room %s" % n.name)
			expect(absf(s._emoji_btns[0].position.y - (662.0 + eh)) <= 1.0,
					"lobby 房间页表情未贴底缘 y=%s eh=%s" % [s._emoji_btns[0].position.y, eh])
			expect(absf(s._seat_cards[0]["panel"].position.x - (150.0 + extra * 0.45)) <= 1.0,
					"lobby 座位卡未随宽漂移 x=%s" % s._seat_cards[0]["panel"].position.x)
			expect(s.room_title_lbl.visible and not s.code_edit.visible,
					"房间页显隐错误")
			expect(not s.quick_btn.visible and not s.host_edit.visible,
					"房间页仍显示入口控件")
			s._apply_view("entry")
		2:  # 牌桌 + 离开确认框(模态层一并对入遍历)
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
			# 手牌卡底不压操作行; 出牌区不压手牌区(紧凑/标准档都要成立)
			var ops_top: float = s.ops_row.position.y
			expect(ops_top >= s.hand_box.position.y + s.hand_box.size.y - 6.0,
					"table 手牌与操作行重叠 hand=%s ops=%s" % [
						s.hand_box.position.y + s.hand_box.size.y, ops_top])
			expect(s.field_panel.position.y + s.field_panel.size.y
					<= s.hand_box.position.y + 14.0,
					"table 出牌区压手牌区 field_bottom=%s hand_top=%s" % [
						s.field_panel.position.y + s.field_panel.size.y,
						s.hand_box.position.y + 14.0])
			# 聊天发送钮与操作行同排时不得重叠
			if absf(s.chat_btn.position.y - s.ops_row.position.y) < 30.0:
				expect(s.chat_btn.position.x + s.chat_btn.size.x
						<= s.ops_row.position.x + 1.0,
						"table 聊天发送钮压操作行 chat_end=%s ops_x=%s" % [
							s.chat_btn.position.x + s.chat_btn.size.x,
							s.ops_row.position.x])
			if s._leave_dlg != null:
				s._leave_dlg.size = s.size  # 换档后随牌桌尺寸
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
			var col_w: float = minf(w - 80.0, 900.0)
			expect(absf(s._fig.position.x - (w - col_w) / 2.0) <= 1.0, "tutorial 图示未居中")
			expect(absf(s._fig.size.x - col_w) <= 1.0, "tutorial 内容列宽未自适应")
			expect(absf(s._close_lbl.position.x - (w - 110.0)) <= 1.0, "tutorial 关闭未锚右缘")
			expect(absf(s._next_btn.position.x - (w / 2.0 + 120.0)) <= 1.0, "tutorial 下一页未居中")
		6:  # 设置面板(纯容器布局, 交给通用断言)
			expect(s.get_global_rect().size == Vector2(w, h), "settings 面板未铺满视口")
		7:  # 结算面板(纯容器布局, 交给通用断言)
			expect(s.get_global_rect().size == Vector2(w, h), "结算面板未铺满视口")
		8:  # 肉鸽规则说明(翻页框)
			expect(absf(s._prev_btn.position.x - (w / 2.0 - 300.0)) <= 1.0,
					"rogue_help 上一页未居中左")
			expect(absf(s._next_btn.position.x - (w / 2.0 + 120.0)) <= 1.0,
					"rogue_help 下一页未居中右")
			expect(absf(s._close_lbl.position.x - (w - 110.0)) <= 1.0,
					"rogue_help 关闭未锚右缘")
		9:  # 个人档案(页签/返回/滚动区)
			expect(s._scroll.size.x == w - 80.0, "profile 商品区宽度未随窗口")
			expect(s._back_btn.position.x + s._back_btn.size.x <= w - 20.0,
					"profile 返回按钮未锚右缘")
			expect(s._tab_ach_btn.visible and s._tab_hist_btn.visible,
					"profile 双页签可见")


func _initialize() -> void:
	_next()


func _next() -> void:
	if cur != null:
		cur.queue_free()
		cur = null
	scene_idx += 1
	frames = 0
	if scene_idx >= SCENE_PATHS.size():
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
	if cur == null:
		printerr("[adaptive] FAIL: 场景加载失败 %s" % SCENE_PATHS[scene_idx])
		quit(1)
		return
	cur.name = "AdaptiveCap%d" % scene_idx
	root.add_child(cur)
	if scene_idx == 7:
		cur.setup({
			"identities": [2, 3, 0, 1],
			"my_seat": 0,
			"last_points": [35, 5, -10, -30],
			"scores": [35, 5, -10, -30],
		}, func(seat: int) -> String: return "玩家%d" % (seat + 1),
				{"points": 35, "stakes": 1, "gold": 45, "diamonds": 1,
				"wallet_gold": 545, "wallet_diamonds": 3})


func _process(_d: float) -> bool:
	frames += 1
	if frames < 8:
		return false
	if scene_idx >= 0 and scene_idx < SCENE_PATHS.size():
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
				if scene_idx == 2 and cur._leave_dlg == null:
					cur._show_leave_dialog()  # 提前一帧开框: 容器布局完成后再断言
				if scene_idx == 6 and not cur.visible:
					cur.open()  # 设置页默认隐藏(open 后容器才排序), 打开后再断言
				prof_sub = 3
			3:
				prof_sub = 4  # 等一帧: resized→_relayout 在下一帧生效
			_:
				var vs: Vector2 = root.get_visible_rect().size
				_check_scene(scene_idx, vs.x, vs.y)
				_sweep(scene_idx, vs.x, vs.y)
				prof_idx += 1
				prof_sub = 0
				if prof_idx >= PROFILES.size():
					prof_idx = 0
					_next()
	return false
