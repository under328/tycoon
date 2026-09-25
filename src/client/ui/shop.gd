## 商城界面: 皮肤 / 卡片 两个分类, 钻石购买, 一键装备。计划 §12。
extends Control

signal closed

const AppTheme = preload("res://src/client/theme/app_theme.gd")
const P5Header = preload("res://src/client/ui/p5_header.gd")
const SkinsLib = preload("res://src/client/ui/skins.gd")
const CardViewScript = preload("res://src/client/ui/card_view.gd")
const AvatarScript = preload("res://src/client/ui/avatar.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")
const Icons = preload("res://src/client/ui/icons.gd")

const COLOR_BG := Color(0.94, 0.94, 0.96, 0.98)

var _tab := "skin"
var _bal_row: HBoxContainer
var _toast: Label
var _grid: GridContainer
var _tab_skin_btn: Button
var _tab_card_btn: Button
var _tab_item_btn: Button
var _back_btn: Button
var _scroll: ScrollContainer
var _header: Control
var _tabs: HBoxContainer



func _ready() -> void:
	# 父级是 Control(已按安全区内缩) → FULL_RECT 锚点自适应父级,
	# 不再手动赋视口尺寸(那会溢出父级边界, 手机上按钮超界)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 代码 new 出的 Control 挂 Control 父下锚点不自动求值(size 停留 0×0) → 显式铺满
	size = get_parent_area_size()
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = AppTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Responsive.page_bleed(self, AppTheme.BG)   # 避让条露出同色, 页面内外一致

	# 纵向主排布(容器化自适应: 头行 / 页签行 / 滚动商品区 / 提示行)
	var touch := Responsive.is_touch()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16 if touch else 30)
	margin.add_theme_constant_override("margin_right", 16 if touch else 30)
	margin.add_theme_constant_override("margin_top", 12 if touch else 18)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	# 顶行: 返回 + 标题(弹性占中) + 余额
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	_back_btn = AppTheme.make_button("返 回", Vector2(100, 42), 16)
	_back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_back_btn.pressed.connect(func() -> void:
		Audio.play("click")
		_close())
	top.add_child(_back_btn)
	_header = P5Header.new()
	_header.text = "商  城"
	_header.icon = "bag"
	_header.custom_minimum_size = Vector2(200, 54)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	_bal_row = Icons.CurrencyText.new(19)
	_bal_row.set_amounts(Wallet.gold, Wallet.diamonds, AppTheme.WHITE)
	_bal_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_bal_row)

	# 分类页签(居中)
	_tabs = HBoxContainer.new()
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabs.add_theme_constant_override("separation", 10)
	v.add_child(_tabs)
	_tab_skin_btn = AppTheme.make_button("人 物 皮 肤",
			Vector2(150, 46 if touch else 42), 15)
	_tab_skin_btn.toggle_mode = true
	_tab_skin_btn.pressed.connect(func() -> void: _set_tab("skin"))
	_tabs.add_child(_tab_skin_btn)
	_tab_card_btn = AppTheme.make_button("卡 牌 面 貌",
			Vector2(150, 46 if touch else 42), 15)
	_tab_card_btn.toggle_mode = true
	_tab_card_btn.pressed.connect(func() -> void: _set_tab("card"))
	_tabs.add_child(_tab_card_btn)
	_tab_item_btn = AppTheme.make_button("特 殊 道 具",
			Vector2(150, 46 if touch else 42), 15)
	_tab_item_btn.toggle_mode = true
	_tab_item_btn.pressed.connect(func() -> void: _set_tab("item"))
	_tabs.add_child(_tab_item_btn)

	# 商品网格(滚动区: 触摸滑动/滚轮; 网格列数随视口宽自适应)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不吃触屏拖动
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	_scroll.add_child(_grid)

	_toast = AppTheme.make_label(15, AppTheme.RED)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.custom_minimum_size = Vector2(0, 30)
	v.add_child(_toast)

	Wallet.balance_changed.connect(_refresh)
	Responsive.watch(self, _relayout)
	_relayout()   # 先按当前宽度定列数, 再建商品(网格最小宽度不膨胀)
	_set_tab("skin")


## 多设备自适应: 布局由容器承担, 这里只做网格列数随视口宽分档
## (≥1500 四列 / ≥960 三列 / ≥640 两列 / 更窄(手机竖屏)单列)。
func _relayout() -> void:
	var w := size.x
	if w < 100.0:
		return
	var cols := 4 if w >= 1500.0 else (3 if w >= 960.0 else (2 if w >= 640.0 else 1))
	if _grid.columns != cols:
		_grid.columns = cols
		# 列数变化必须重建商品, 且延迟一帧(queue_free 释放旧卡后)再算:
		# 网格最小宽度随新列数回落, 否则旧列布局的最小宽会把面板永久撑宽
		_refresh.call_deferred()
	# 窄屏收缩顶行/页签行: 装饰标题让位, 页签缩窄(最小宽不超视口)
	var narrow := w < 640.0
	if _header != null:
		_header.visible = not narrow
	_header.custom_minimum_size.x = 200.0 if not narrow else 120.0
	var tab_w := 126.0 if narrow else 150.0
	for tb: Button in [_tab_skin_btn, _tab_card_btn, _tab_item_btn]:
		tb.custom_minimum_size.x = tab_w
		tb.size.x = tab_w


func _set_tab(tab: String) -> void:
	_tab = tab
	_tab_skin_btn.button_pressed = tab == "skin"
	_tab_card_btn.button_pressed = tab == "card"
	_tab_item_btn.button_pressed = tab == "item"
	_refresh()


func _refresh() -> void:
	_bal_row.set_amounts(Wallet.gold, Wallet.diamonds, AppTheme.WHITE)
	for child in _grid.get_children():
		child.queue_free()
	var items: Array = SkinsLib.SKINS if _tab == "skin" else SkinsLib.CARDS
	if _tab == "item":
		items = Wallet.SPECIALS
	for item in items:
		_grid.add_child(_special_panel(item) if _tab == "item"
				else _item_panel(_tab, item))


## 特殊道具面板: 描述 + 价格(金币/钻石) + 购买/生效中/持有数量
func _special_panel(item: Dictionary) -> Control:
	var id := str(item["id"])
	var effect := str(item.get("effect", ""))
	var active := _item_active(id, effect)
	var count := Wallet.item_count(id)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 236)   # 仅锁高度, 宽度由网格列分
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不吃触屏拖动
	var sb := AppTheme.flat(
			Color(0.13, 0.13, 0.28), AppTheme.GOLD if active
					else Color(1, 1, 1, 0.15), 12, 2 if not active else 3)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var name_lbl := AppTheme.make_label(20, AppTheme.GOLD if active else AppTheme.WHITE)
	name_lbl.text = str(item["name"])
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(name_lbl)
	if active:
		var tag := AppTheme.make_label(13, AppTheme.GREEN)
		tag.text = "生效中·今日"
		head.add_child(tag)
	var well := PanelContainer.new()
	well.custom_minimum_size = Vector2(0, 84)
	var well_sb := AppTheme.flat(Color(0.07, 0.07, 0.17, 0.9), Color(1, 1, 1, 0.08), 8, 1)
	well_sb.content_margin_left = 12
	well_sb.content_margin_right = 12
	well_sb.content_margin_top = 8
	well_sb.content_margin_bottom = 8
	well.add_theme_stylebox_override("panel", well_sb)
	v.add_child(well)
	var well_center := CenterContainer.new()
	well.add_child(well_center)
	var art: HBoxContainer = Icons.CurrencyText.new(26)
	match effect:
		"dday":
			art.text("对局钻石 ", AppTheme.WHITE)
			art.amount("gem", "×2", AppTheme.GOLD)
		"tday":
			art.text("对局钻石 ", AppTheme.WHITE)
			art.amount("gem", "×3", AppTheme.GOLD)
		"revive":
			art.text("倒下时 ", AppTheme.WHITE)
			art.amount("coin", "原地复活", AppTheme.GOLD)
		"fdice":
			art.text("命运二选一 ", AppTheme.WHITE)
			art.amount("gem", "重抽", AppTheme.GOLD)
		"rticket":
			art.text("选牌重抽 ", AppTheme.WHITE)
			art.amount("coin", "+1", AppTheme.GOLD)
		"cday":
			art.text("当日记牌器 ", AppTheme.WHITE)
			art.amount("coin", tr("记牌器开放"), AppTheme.GOLD)
		"conce":
			art.text("单场记牌器 ", AppTheme.WHITE)
			art.amount("coin", "×1", AppTheme.GOLD)
		"clearr":
			art.text("战绩记录 ", AppTheme.WHITE)
			art.amount("gem", "一键清零", AppTheme.GOLD)
	well_center.add_child(art)
	var desc := AppTheme.make_label(14, AppTheme.DIM)
	desc.text = str(item["desc"])
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # 窄卡自动折行
	v.add_child(desc)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	v.add_child(foot)
	var price_row: HBoxContainer = Icons.CurrencyText.new(16)
	price_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	price_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if count > 0 and effect != "clearr":   # 即时生效道具不显示持有数
		price_row.amount("coin", "持有 %d" % count, AppTheme.WHITE)
	if str(item.get("currency", "gold")) == "gold":
		price_row.amount("coin", str(int(item["price"])), AppTheme.WHITE)
	else:
		price_row.amount("gem", str(int(item["price"])), AppTheme.WHITE)
	foot.add_child(price_row)
	var txt := "购 买"
	if effect == "clearr":
		txt = "清 空"
	var buy := AppTheme.make_button(txt, Vector2(112, 40), 15)
	if effect == "dday":
		buy.disabled = Wallet.double_diamond_active()
	elif effect == "tday":
		buy.disabled = Wallet.diamond_triple_active()
	else:
		# 按道具计价币种判定可负担
		buy.disabled = Wallet.diamonds < int(item["price"]) 				if str(item.get("currency", "gold")) == "diamonds" 				else Wallet.gold < int(item["price"])
	var armed := [false]   # 清空战绩二次确认(数组供闭包按引用读写)
	buy.pressed.connect(func() -> void:
		if effect == "clearr" and not armed[0]:
			armed[0] = true
			buy.text = "确认清空?"
			var tw := buy.create_tween()
			tw.tween_interval(3.0)
			tw.tween_callback(func() -> void:
				armed[0] = false
				if is_instance_valid(buy):
					buy.text = "清 空")
			return
		if Wallet.buy_item(id):
			Audio.play("buy")
			_refresh()
			_toast_msg("战绩已清空!" if effect == "clearr" else "购买成功, 已生效!")
			else:
				_toast_msg("余额不足, 先去赚一赚吧"))
	foot.add_child(buy)
	_touch_pass_through(panel)
	return panel


## 触屏滑动修复: 卡片内除按钮外全部放行拖动 — PanelContainer/容器默认 STOP
## 会吃掉 ScrollContainer 的触摸滑动手势, 手机上表现为"卡片上滑不动、
## 卡间空隙能滑"的不一致。按钮保留 STOP 以正常点击。
func _touch_pass_through(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			continue
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_touch_pass_through(child)


func _item_active(id: String, effect: String) -> bool:
	match effect:
		"dday":
			return Wallet.double_diamond_active()
		"tday":
			return Wallet.diamond_triple_active()
		"revive":
			return Wallet.item_count(id) > 0
		"fdice":
			return Wallet.item_count(id) > 0
		"rticket":
			return Wallet.item_count(id) > 0
		"cday":
			return Wallet.counter_day_today()
	return false


func _item_panel(kind: String, item: Dictionary) -> Control:
	var id: String = str(item["id"])
	var price: int = int(item["price"])
	var owned: bool = Wallet.is_owned(kind, id)
	var equipped: bool = Wallet.is_equipped(kind, id)

	# 卡片外框: 留足内边距, 装备中金框高亮
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 236)   # 仅锁高度, 宽度由网格列分
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不吃触屏拖动
	var sb := AppTheme.flat(
			Color(0.13, 0.13, 0.28), AppTheme.GOLD if equipped
					else Color(1, 1, 1, 0.15), 12, 2 if not equipped else 3)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	# 头行: 名称 + 状态徽标
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var name_lbl := AppTheme.make_label(20, AppTheme.GOLD if equipped else AppTheme.WHITE)
	name_lbl.text = str(item["name"])
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(name_lbl)
	if equipped:
		var tag_sb := AppTheme.flat(Color(AppTheme.GREEN, 0.16), AppTheme.GREEN, 6, 1)
		tag_sb.content_margin_left = 10
		tag_sb.content_margin_right = 10
		tag_sb.content_margin_top = 3
		tag_sb.content_margin_bottom = 3
		var tag := PanelContainer.new()
		tag.add_theme_stylebox_override("panel", tag_sb)
		var tag_lbl := AppTheme.make_label(13, AppTheme.GREEN)
		tag_lbl.text = "使用中"
		tag.add_child(tag_lbl)
		head.add_child(tag)

	# 预览井: 内嵌暗色衬底把预览框起来, 上下留呼吸感
	var well := PanelContainer.new()
	well.custom_minimum_size = Vector2(0, 100)
	var well_sb := AppTheme.flat(Color(0.07, 0.07, 0.17, 0.9), Color(1, 1, 1, 0.08), 8, 1)
	well_sb.content_margin_left = 12
	well_sb.content_margin_right = 12
	well_sb.content_margin_top = 8
	well_sb.content_margin_bottom = 8
	well.add_theme_stylebox_override("panel", well_sb)
	v.add_child(well)
	var well_center := CenterContainer.new()
	well.add_child(well_center)
	if kind == "skin":
		var av := AvatarScript.new()
		av.skin_id = id
		av.custom_minimum_size = Vector2(84, 84)
		well_center.add_child(av)
	else:
		# 迷你实卡预览: 牌背 + ♠5(纹环) + JOKER(像素画), 展示整套卡面美术
		var strip := HBoxContainer.new()
		strip.alignment = BoxContainer.ALIGNMENT_CENTER
		strip.add_theme_constant_override("separation", 14)
		well_center.add_child(strip)
		for card_id: int in [-1, 4, 53]:
			var cv := CardViewScript.new(card_id)
			cv.palette_id = id
			cv.face_down = card_id < 0
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.custom_minimum_size = Vector2(42, 60)
			cv.size = Vector2(42, 60)
			strip.add_child(cv)

	# 底行: 价格在左, 操作按钮在右
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	v.add_child(foot)
	if owned:
		var price_lbl := AppTheme.make_label(16, AppTheme.DIM)
		price_lbl.text = "已拥有"
		price_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		price_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		foot.add_child(price_lbl)
		var act := AppTheme.make_button(
				"使用中" if equipped else "装 备", Vector2(128, 40), 15)
		act.disabled = equipped
		act.pressed.connect(func() -> void:
			Audio.play("select")
			Wallet.equip(kind, id)
			_refresh())
		foot.add_child(act)
	else:
		var price_row: HBoxContainer = Icons.CurrencyText.new(16)
		price_row.alignment = BoxContainer.ALIGNMENT_BEGIN
		price_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		price_row.amount("gem", str(price), AppTheme.WHITE)
		foot.add_child(price_row)
		var buy := AppTheme.make_button("购 买", Vector2(112, 40), 15)
		buy.disabled = Wallet.diamonds < price
		buy.pressed.connect(func() -> void:
			if Wallet.buy(kind, id, price):
				Wallet.equip(kind, id)
				Audio.play("buy")
				_refresh()
				_toast_msg("购买成功, 已装备!")
			else:
				_toast_msg("钻石不足, 打几局赚钻石吧"))
		foot.add_child(buy)
	_touch_pass_through(panel)
	return panel


func _toast_msg(text: String) -> void:
	_toast.text = text
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_callback(func() -> void: _toast.text = "")



func _close() -> void:
	Audio.play("click")
	visible = false
	closed.emit()
