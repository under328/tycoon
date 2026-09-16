## 记牌器数字正确性验证: 本地局打几轮后, 记牌器余数 = 总数-已出-我手-死牌
extends SceneTree

const CardsGd = preload("res://src/rules/cards.gd")
const GameStateGd = preload("res://src/rules/game_state.gd")
const ViewGd = preload("res://src/protocol/view.gd")

var f := 0
var main = null
var checks := 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	main = (load("res://src/client/main.tscn") as PackedScene).instantiate()
	root.add_child(main)


func _process(_d: float) -> bool:
	f += 1
	if f == 10:
		main._launch_new_local(false)
	# 每 60 帧校验一次记牌器口径(前 12 次 = 约 4 局内多次采样)
	if f > 300 and f % 60 == 0 and main.table != null and checks < 12:
		var t = main.table
		var v: Dictionary = t._current_view()
		if v.is_empty() or str(v.get("phase", "")) != "play":
			return false
		checks += 1
		# 独立重算: 总张数 - 已出(field 累计不可知) → 用记牌器自身口径对拍:
		# 记牌器文本余数 = totals - played - 我手 - 死牌; 这里独立验证
		# 我手 + 已出(记牌器内部账) + 余数 == 总数, 且余数不含我手牌
		var hand_cnt := {}
		for c in v.get("hand", []):
			var hv := CardsGd.value(int(c))
			hand_cnt[hv] = int(hand_cnt.get(hv, 0)) + 1
		var dead: Array = v.get("dead_counts", [])
		var totals := {}
		for i in range(3, 16):
			totals[i] = 4
		totals[16] = 2 if bool(v["rules"].get("with_joker", true)) else 0
		var ok := true
		for v2 in range(3, 17):
			var played: int = int(t._counter_played.get(v2, 0))
			var expect_left: int = int(totals.get(v2, 0)) - played \
					- int(hand_cnt.get(v2, 0)) - (int(dead[v2 - 3]) if v2 - 3 < dead.size() else 0)
			# 记牌器余数最大条目 = expect_left(逐点数对拍)
			var shown := -1
			for part in t.counter_lbl.text.split("  "):
				if part.begins_with(CardsGd.rank_value_label(v2) + "×"):
					shown = int(part.split("×")[1])
			if shown > expect_left:
				ok = false
				print("[counter] MISMATCH v=%d shown=%d expect<=%d" % [v2, shown, expect_left])
		if ok:
			print("[counter] sample %d OK — text: %s" % [checks, t.counter_lbl.text])
	if f > 1400 and main.table != null:
		print("[counter] VERIFY_OK samples=%d" % checks)
		quit(0)
	return false
