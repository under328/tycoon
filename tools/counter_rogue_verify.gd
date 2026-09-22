## 记牌器 × 肉鸽命运卡专项验证: 锁定各命运卡开局, 校验记牌器基数随卡重算 —
##   王者归来(joker_x2) → 王×4 / 无王之地(joker_ban) → 无王条目 /
##   缩牌·疾风(手牌数变化) / 八喜临门 → 基数不变但口径与真实牌堆一致。
## 对拍口径: _counter_totals[v] == 全量牌堆(4 手牌 + 死牌)中 v 的真实张数。
## 运行: godot --headless --path . --script tools/counter_rogue_verify.gd
extends SceneTree

const CardsGd = preload("res://src/rules/cards.gd")
const GameStateGd = preload("res://src/rules/game_state.gd")

const MODS := ["joker_x2", "joker_ban", "short_hands", "blitz", "eight_gift",
		"revolution_start"]

var f := 0
var main = null
var mod_idx := 0
var picked := false
var results: Array = []
var cur_mod := ""
var _wait := 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	main = (load("res://src/client/main.tscn") as PackedScene).instantiate()
	root.add_child(main)


func _process(_d: float) -> bool:
	f += 1
	if mod_idx >= MODS.size():
		_finish()
		return false
	var t = main.table
	if t == null or t.state == null or t.state.is_empty():
		if _wait <= 0:
			_wait = 30
			_launch()
		else:
			_wait -= 1
		return false
	var st: Dictionary = t.state
	if str(st.get("phase", "")) == "draft" and not picked:
		cur_mod = str(MODS[mod_idx])
		st["cfg"]["rogue_mod_lock"] = cur_mod
		st["rogue_choices"] = [cur_mod, cur_mod]
		picked = true
		return false
	if picked and str(st.get("phase", "")) == "draft":
		# 命运二选一: 锁定后两张相同 → 选 0
		var rr = GameStateGd.apply(st, {"t": "rogue_pick", "idx": 0, "seat": 0})
		if bool(rr["ok"]):
			t.state = rr["state"]
			t._show_rogue_reveal(0)
			t._close_rogue_reveal()
		return false
	if str(st.get("phase", "")) == "play":
		_verify(t)
		_next()
	return false


func _launch() -> void:
	picked = false
	main._launch_new_local(true)


func _verify(t) -> void:
	var st: Dictionary = t.state
	# 真实牌堆 = 全部手牌 + 死牌
	var truth := {}
	for hand in st["hands"]:
		for c in hand:
			truth[CardsGd.value(int(c))] = int(truth.get(CardsGd.value(int(c)), 0)) + 1
	for c in st["dead"]:
		truth[CardsGd.value(int(c))] = int(truth.get(CardsGd.value(int(c)), 0)) + 1
	var ok := true
	var detail := ""
	for v in range(3, 17):
		var total: int = int(t._counter_totals.get(v, 0))
		var real: int = int(truth.get(v, 0))
		if total != real:
			ok = false
			detail += " %s:%d!=%d" % [CardsGd.rank_value_label(v), total, real]
	# 命运卡基数随卡重算: 记牌器归属 mod == 当前 mod
	var mod_ok: bool = str(t._counter_mod) == cur_mod
	results.append({"mod": cur_mod, "totals_ok": ok, "mod_ok": mod_ok,
			"detail": detail})


func _next() -> void:
	mod_idx += 1
	picked = false
	# 清场(结束托管中的旧局)再开下一张卡
	if main.table != null:
		main.table.queue_free()
		main.table = null
	_wait = 0
	_launch()


func _finish() -> void:
	var bad := 0
	for r in results:
		var line := "[counter-rogue] %s → totals %s, mod 归属 %s%s" % [
			str(r["mod"]),
			"OK" if bool(r["totals_ok"]) else "FAIL",
			"OK" if bool(r["mod_ok"]) else "FAIL",
			str(r["detail"]) if not bool(r["totals_ok"]) else ""]
		print(line)
		if not bool(r["totals_ok"]) or not bool(r["mod_ok"]):
			bad += 1
	print("[counter-rogue] %d/%d mods OK" % [results.size() - bad, results.size()])
	quit(1 if bad > 0 or results.size() < MODS.size() else 0)
