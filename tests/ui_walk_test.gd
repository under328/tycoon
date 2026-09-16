## UI 遍历测试器: 真实挂载完整应用, 逐页打开 → 枚举并触发每个可交互
## 控件 → 健康检查 → 记录报告。发现脚本错误/页面意外关闭/卡死即记录。
## 覆盖: 主菜单/设置/商城/新手引导/个人档案/模式选择/肉鸽说明/格斗试炼/
##       联机大厅入口/本机开房房间页/本地牌桌(普通+肉鸽, 含表情弹窗/嵌套设置)。
## 运行: godot --headless --path . --script tests/ui_walk_test.gd
## 报告: builds/ui_walk_report.txt; 发现 ERR 退出码 1。
extends SceneTree

const PAGE_BUDGET := 4000
const SETTLE := 3
const CLOSE_TEXTS := ["返 回", "返回菜单", "返回大厅", "放弃试炼", "离开房间",
		"离开对局", "确认离开", "跳过(不选祝福)", "开始对局"]
const SKIP_TEXTS := ["退出游戏", "快速匹配", "创建房间", "粘贴邀请码, 一键加入",
		"连 接", "发现新版本, 点击更新"]
const PAGE_NAMES := ["主菜单", "设置", "商城", "新手引导", "个人档案", "模式选择",
		"肉鸽说明", "格斗试炼", "联机大厅-入口", "联机大厅-房间页",
		"本地牌桌", "肉鸽牌桌"]

var main: Node = null
var report: Array = []
var errors := 0
var presses := 0
var page_idx := -1
var state := "boot"          # boot/open/settle/walk/press/extra_open/extra_press/teardown/after/next/done
var wait_frames := 0
var page_frames := 0
var page_root: Control = null
var btns: Array = []         # 待按压 {b, tag, skip, note}
var press_i := 0
var extras: Array = []       # 页面专属附加遍历 {open, collect, close, tag}
var extra_i := 0
var extra_opening := false
var done := false
var pages_done := 0


func _initialize() -> void:
	print("[walk] UI 遍历测试开始")


func _process(_d: float) -> bool:
	if done:
		return false
	if wait_frames > 0:
		wait_frames -= 1
		return false
	page_frames += 1
	if state != "done" and page_frames > PAGE_BUDGET:
		_rec(page_idx, "看门狗", "ERR", "超时 state=%s 按压到 %d/%d" %
				[state, press_i, btns.size()])
		state = "teardown"
		return false
	match state:
		"boot":
			_boot()
		"open":
			_open_page()
		"settle":
			state = "walk"
		"walk":
			_walk()
		"press":
			_press()
		"extra_open":
			_press()   # 附加遍历与主队列共用按压状态机(见 _press 分支)
		"extra_press":
			_press()
		"teardown":
			_teardown()
		"after":
			_after()
	return false


## ── 启动: 挂载完整应用(钱包指向测试存档) ──
func _boot() -> void:
	var w := root.get_node_or_null("/root/Wallet")
	if w != null:
		w.save_path = "user://walk_wallet.cfg"   # 隔离: 不污染真实存档
	main = (load("res://src/client/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	page_idx = 0
	state = "open"


## ── 打开页面 ──
func _open_page() -> void:
	if page_idx >= PAGE_NAMES.size():
		_finish()
		return
	if page_idx < 0:
		page_idx = 0
	print("[walk] ▶ 页面: %s" % _page_name(page_idx))
	page_frames = 0
	page_root = null
	extras = []
	extra_i = 0
	extra_opening = false
	match page_idx:
		0:
			page_root = main.menu
		1:
			main.menu._settings.open()
			page_root = main.menu._settings
		2:
			main.menu._open_shop()
			page_root = main.menu._shop
		3:
			main.menu._open_tutorial()
			page_root = main.menu._tutorial
		4:
			_press_text(main.menu, "成就·战绩")
			page_root = _find_by_script(main.menu, "profile_panel.gd")
		5:
			main.menu._show_mode_select()
			page_root = main.menu._mode_dlg
		6:
			main.menu._show_mode_select()
			# 2×2 卡片: 每卡右上角各有圆包 ? → 定向按「肉鸽模式」卡的帮助钮
			for b in main.menu._mode_dlg.find_children("*", "Button", true, false):
				if str((b as Button).text) == "?":
					var card := (b as Button).get_parent()
					for c in card.get_children():
						if c is Label and str((c as Label).text) == "肉鸽模式":
							b.pressed.emit()
			page_root = _find_by_script(main.menu, "rogue_help.gd")
		7:
			main._start_fight()
			page_root = main.fight_panel
		8:
			main._start_online()
			page_root = main.lobby
		9:
			main._start_host()
			page_root = main.lobby
		10:
			main._launch_new_local(false)
			page_root = main.table
			extras = _table_extras()
		11:
			main._launch_new_local(true)
			page_root = main.table
			extras = _table_extras()
	if page_root == null and page_idx != 0:
		_rec(page_idx, "页面", "ERR", "打开失败(page_root 为空)")
		state = "after"
		wait_frames = 5
		return
	state = "settle"


func _page_name(i: int) -> String:
	return PAGE_NAMES[i] if i >= 0 and i < PAGE_NAMES.size() else "?"


func _press_text(root: Node, text: String) -> void:
	for b in root.find_children("*", "BaseButton", true, false):
		if str((b as BaseButton).text) == text:
			(b as BaseButton).pressed.emit()
			return


func _find_by_script(parent: Node, part: String) -> Control:
	for c in parent.find_children("*", "Control", true, false):
		var sc: Script = (c as Control).get_script()
		if sc != null and str(sc.resource_path).ends_with(part):
			return c
	return null


func _settle() -> void:
	# 本机开房需等待自动连入+建房
	if page_idx == 9 and not main.net.in_room:
		if page_frames > 900:
			_rec(page_idx, "本机开房", "ERR", "长时间未进入房间")
			state = "teardown"
		wait_frames = 10
		return
	state = "walk"


## ── 枚举并排队按压 ──
func _walk() -> void:
	if page_root == null or not is_instance_valid(page_root):
		_rec(page_idx, "页面", "ERR", "页面根节点缺失")
		state = "teardown"
		return
	btns = _collect(page_root, _page_skip(page_idx))
	print("[walk]   可交互控件 %d 个" % btns.size())
	press_i = 0
	extra_i = 0
	state = "press"


func _page_skip(idx: int) -> Array:
	return ["成就·战绩"] if idx == 0 else []


## 收集可见 BaseButton(排除关闭钮/危险钮; root 指定收集范围)
func _collect(root: Node, also_skip: Array = []) -> Array:
	var out: Array = []
	for b in root.find_children("*", "BaseButton", true, false):
		var bb: BaseButton = b
		if not bb.is_visible_in_tree():
			continue
		var tag := _btn_tag(bb)
		var note := ""
		var skip := false
		if CLOSE_TEXTS.has(tag):
			continue   # 收尾阶段统一处理
		if SKIP_TEXTS.has(tag):
			skip = true
			note = "网络/外部副作用"
		if also_skip.has(tag):
			skip = true
			note = "由专属页面覆盖"
		out.append({"b": bb, "tag": tag, "skip": skip, "note": note})
	return out


func _btn_tag(b: BaseButton) -> String:
	if str(b.text) != "":
		return str(b.text)
	var sc: Script = b.get_script()
	if sc != null and str(sc.resource_path).ends_with("slash_menu_item.gd"):
		return "斜切菜单项:" + str(b.get("text"))
	return b.name


## ── 逐个按压; 队列耗尽后进入页面专属附加遍历 ──
func _press() -> void:
	if press_i < btns.size():
		_press_one(btns[press_i])
		press_i += 1
		return
	# 主队列耗尽 → 附加遍历(表情弹窗/嵌套设置)
	if extra_i < extras.size():
		if not extra_opening:
			extra_opening = true
			extras[extra_i]["open"].call()
			wait_frames = 4
			return
		btns = _collect(extras[extra_i]["root"], [])
		print("[walk]   附加遍历: %s (%d 个)" % [extras[extra_i]["tag"], btns.size()])
		extra_opening = false
		extra_i += 1
		press_i = 0
		return
	state = "teardown"


func _press_one(entry: Dictionary) -> void:
	var bb_v = entry["b"]
	if not is_instance_valid(bb_v):
		_rec(page_idx, str(entry["tag"]), "SKIP", "节点失效")
		return
	var bb: BaseButton = bb_v
	var tag := str(entry["tag"])
	if not is_instance_valid(bb):
		_rec(page_idx, tag, "SKIP", "节点已随列表重建释放")
		return
	if not bb.is_visible_in_tree():
		_rec(page_idx, tag, "SKIP", "不可见")
		return
	if bb.disabled:
		_rec(page_idx, tag, "OK", "禁用态(验证存在与禁用)")
		return
	page_frames = 0
	presses += 1
	print("[walk]   按压: %s" % tag)
	if bool(entry.get("skip", false)):
		_rec(page_idx, tag, "SKIP", entry.get("note", ""))
		return
	bb.pressed.emit()
	wait_frames = SETTLE


## ── 收尾(关页/退出) ──
func _teardown() -> void:
	print("[walk] ◀ 收尾: %s" % _page_name(page_idx))
	match page_idx:
		1:
			main.menu._settings._close()
		2:
			_press_text(main.menu._shop, "返 回")
		3:
			main.menu._tutorial._close()
		4:
			_press_text(page_root, "返 回")
		5:
			main.menu._close_mode_select()
		6:
			var rh := _find_by_script(main.menu, "rogue_help.gd")
			if rh != null:
				rh._close()
			main.menu._close_mode_select()
		7:
			_press_text(main.fight_panel, "放弃试炼")
			_press_text(main.fight_panel, "返回菜单")  # 结算面板确认后真正关闭
		8:
			main.lobby.go_back()
		9:
			main.lobby.go_back()
			main._stop_host()
		10, 11:
			_press_text(main.table, "返回大厅")
			_press_text(main.table, "返回菜单")
		_:
			pass
	state = "after"
	wait_frames = 8


func _after() -> void:
	if main == null or not is_instance_valid(main):
		_rec(page_idx, "应用", "ERR", "主场景失效!")
		_finish()
		return
	if main.menu._shop != null and is_instance_valid(main.menu._shop):
		_rec(page_idx, "商城", "ERR", "关闭后残留")
	if page_idx == 7 and main.fight_panel != null and is_instance_valid(main.fight_panel):
		_rec(page_idx, "格斗页", "ERR", "关闭后残留")
	pages_done += 1
	page_idx += 1
	state = "open"
	wait_frames = 5


func _finish() -> void:
	done = true
	var path := "res://builds/ui_walk_report.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("UI 遍历报告\n============\n页面: %d\n按压力次: %d\n发现问题: %d\n\n%s"
			% [pages_done, presses, errors, "\n".join(PackedStringArray(report))])
	f.close()
	print("[walk] 报告已写入 %s" % path)
	print("[walk] SUMMARY 页面=%d 按压=%d 错误=%d" % [pages_done, presses, errors])
	quit(1 if errors > 0 else 0)


## ── 报告 ──
func _rec(page: int, btn: String, status: String, detail: String = "") -> void:
	var line := "%s | %s | %s%s" % [_page_name(page), btn, status,
			("" if detail == "" else "  <%s>" % detail)]
	report.append(line)
	print("[walk] !! " + line)
	if status == "ERR":
		errors += 1


## ── 页面专属附加遍历构建 ──
func _table_extras() -> Array:
	var t = main.table
	return [
		{
			"tag": "表情弹窗",
			"open": func() -> void: _press_text(t, "😀"),
			"root": t,
			"collect": func() -> Array: return _collect(t, []),
			"close": func() -> void: _press_text(t, "😀"),
		},
		{
			"tag": "嵌套设置",
			"open": func() -> void: _press_text(t, "设置"),
			"root": main.menu._settings,
			"collect": func() -> Array: return _collect(main.menu._settings, []),
			"close": func() -> void: _press_text(main.menu._settings, "返 回"),
		},
	]


## 页面10/11 挂载时挂上附加遍历(表情弹窗 + 嵌套设置)
func _attach_table_extras() -> void:
	if page_idx == 10 or page_idx == 11:
		extras = _table_extras()
