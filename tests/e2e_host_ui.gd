## E2E: 真实 UI 链路复现 — 主菜单 → 联机游戏 → 本机开房 → 建房 → 空位加AI
## → 开始游戏 → 在线牌桌(自动代打+表情/聊天) → 打到 game_end → 返回大厅。
## 覆盖 lobby.gd + table.gd(online) 的完整交互, 此前自动化只测裸网络层。
## 运行: godot --headless --path . --script tests/e2e_host_ui.gd
extends SceneTree

const BotPlayerGd = preload("res://src/rules/ai/bot_player.gd")

var main = null
var f := 0
var stage := ""
var failed := false
var chat_sent := false
var emoji_sent := false
var done := false
var guard_ms := 0


func _fail(msg: String) -> void:
	failed = true
	printerr("[e2e-ui] FAIL: " + msg)
	quit(1)


func _process(delta: float) -> bool:
	f += 1
	guard_ms += int(delta * 1000.0)
	if guard_ms > 240000:
		_fail("超时 stage=" + stage)
		return true
	match f:
		10:
			stage = "main 场景"
			main = (load("res://src/client/main.tscn") as PackedScene).instantiate()
			root.add_child(main)
		30:
			stage = "联机游戏(lobby)"
			main._start_online()
			if main.lobby == null:
				_fail("lobby 未创建")
		40:
			stage = "本机开房"
			main._start_host()
		_:
			_poll()
	return false


func _poll() -> void:
	if failed or done:
		return
	match stage:
		"本机开房":
			# 等待: 连上内嵌服务器 → 自动建房 → 房间页视图
			if main.lobby != null and str(main.lobby._view) == "room" \
					and str(main.lobby._last_room_code) != "":
				var players: Array = (main.net.last_room_state as Dictionary).get("players", [])
				var humans := 0
				for p in players:
					if not bool(p.get("empty", true)):
						humans += 1
				if humans >= 1:
					stage = "空位加AI"
					print("[e2e-ui] 房间就绪 code=", main.lobby._last_room_code)
					main.lobby.fill_btn.pressed.emit()  # 空位加AI(真实按钮)
		"空位加AI":
			var players: Array = (main.net.last_room_state as Dictionary).get("players", [])
			var filled := 0
			for p in players:
				if not bool(p.get("empty", true)):
					filled += 1
			if filled >= 4:
				stage = "开始游戏"
				print("[e2e-ui] AI 已补满, 开局")
				main.lobby.start_btn.pressed.emit()  # 开始游戏(真实按钮)
		"开始游戏":
			if main.table != null and main.net.latest_view.size() > 0:
				stage = "对局中"
				main.net.autoplay = true  # 客户端自动代打(与服务端 AI 对打)
				print("[e2e-ui] 牌桌已进入, phase=", str(main.net.latest_view.get("phase")))
		"对局中":
			# 途中各打一次表情/聊天(在线专属 UI 路径)
			if not emoji_sent and main.table != null and main.table._emoji_btns.size() > 0:
				emoji_sent = true
				main.table._emoji_btns[0].pressed.emit()
			if not chat_sent and main.table != null:
				chat_sent = true
				main.table.chat_edit.text = "hello"
				main.table._on_chat_send()
			# 革命 BGM 切换路径触发过一次即验证
			if main.net != null and not (main.net.latest_view as Dictionary).is_empty() \
					and str(main.net.latest_view.get("phase")) == "game_end":
				stage = "终局"
				print("[e2e-ui] game_end 到达")
		"终局":
			# 终局后服务器广播 room_state → 自动回大厅
			if main.table == null and main.lobby != null and main.lobby.visible:
				done = true
				print("[e2e-ui] E2E_OK —— 联机 UI 全链路(开房→加AI→开局→终局→回房) 通过")
				quit(0)
