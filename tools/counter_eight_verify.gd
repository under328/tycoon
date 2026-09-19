## 记牌器 8 切计数专项验证: 本地局采样, 用服务器全量状态对拍
## _counter_played == 总数 - 全部手牌 - 死牌(即真实已出张数)。
## 8 切在服务端同事务打出+清桌, 客户端增量分支看不到 → 此前 8 必漏记;
## 修复后任何时刻逐点数都应精确相等。运行:
##   godot --headless --path . --script tools/counter_eight_verify.gd
extends SceneTree

const CardsGd = preload("res://src/rules/cards.gd")

var f := 0
var main = null
var checks := 0
var bad := 0
var cuts_seen := 0
var _last_field_n := -1


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	main = (load("res://src/client/main.tscn") as PackedScene).instantiate()
	root.add_child(main)


func _process(_d: float) -> bool:
	f += 1
	if f == 10:
		main._launch_new_local(false)
		return false
	var t = main.table
	if t == null:
		return false
	if f > 9000 or (checks >= 60 and cuts_seen > 0):
		_finish()
		return false
	var st = t.state
	# 逐帧跟踪清桌(8切/全过): 场上从有到无
	if st != null and not st.is_empty():
		var field_n: int = (st["field"] as Array).size()
		if _last_field_n > 0 and field_n == 0:
			cuts_seen += 1
		_last_field_n = field_n
	# 稀疏采样: 每 60 帧对拍一次
	if st == null or st.is_empty() or str(st.get("phase", "")) != "play":
		return false
	if int(t._counter_round) != int(st["round"]):
		return false   # 跨局重置帧跳过
	if f % 60 != 0:
		return false
	if checks >= 60:
		return false
	# 真值: 已出 = 总数 - 四家手牌 - 死牌
	var totals := {}
	for v in range(3, 16):
		totals[v] = 4
	totals[16] = 2 if bool(st["cfg"].get("with_joker", true)) else 0
	var in_hands := {}
	for s in 4:
		for c in st["hands"][s]:
			var v := CardsGd.value(int(c))
			in_hands[v] = int(in_hands.get(v, 0)) + 1
	var in_dead := {}
	for c in st.get("dead", []):
		var v2 := CardsGd.value(int(c))
		in_dead[v2] = int(in_dead.get(v2, 0)) + 1
	var ok := true
	for v3 in range(3, 17):
		var truth: int = int(totals.get(v3, 0)) - int(in_hands.get(v3, 0)) \
				- int(in_dead.get(v3, 0))
		var got: int = int(t._counter_played.get(v3, 0))
		if got != truth:
			ok = false
			print("[cut] MISMATCH v=%d played=%d truth=%d" % [v3, got, truth])
	# 记牌器显示文本亦对拍: left = 总数-已出-我手-死牌
	var hand0 := {}
	for c in st["hands"][0]:
		var v4 := CardsGd.value(int(c))
		hand0[v4] = int(hand0.get(v4, 0)) + 1
	for v5 in range(3, 17):
		var left_truth: int = int(totals.get(v5, 0)) \
				- int(t._counter_played.get(v5, 0)) - int(hand0.get(v5, 0)) \
				- int(in_dead.get(v5, 0))
		if left_truth <= 0:
			continue
		var shown := -1
		for part in t.counter_lbl.text.split("  "):
			if part.begins_with(CardsGd.rank_value_label(v5) + "×"):
				shown = int(part.split("×")[1])
		if shown != -1 and shown != left_truth:
			ok = false
			print("[cut] TEXT MISMATCH v=%d shown=%d left=%d" % [v5, shown, left_truth])
	checks += 1
	if not ok:
		bad += 1
	return false


func _finish() -> void:
	print("[cut] VERIFY_%s samples=%d clears=%d bad=%d" % [
			"OK" if bad == 0 and cuts_seen > 0 else "FAIL",
			checks, cuts_seen, bad])
	quit(0 if bad == 0 and cuts_seen > 0 else 1)
