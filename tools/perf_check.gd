## M4 验收证据: 本地对局性能采样(fps / 内存)。
## 用法: godot --path . --resolution 1280x720 --script tools/perf_check.gd
## 采样 90 秒: 人类座位由 AI 代理, 持续完整对局节奏。
extends SceneTree

const BotPlayerGd = preload("res://src/rules/ai/bot_player.gd")

var f := 0
var main
var frames := 0
var sample_t := 0.0
var fps_samples: Array = []
var mem_samples: Array = []


func _process(delta: float) -> bool:
	f += 1
	if f == 10:
		main = load("res://src/client/main.tscn").instantiate()
		root.add_child(main)
	if f == 25:
		main._start_local()
	if f > 30 and main.table != null and not main.table.state.is_empty():
		var st = main.table.state
		if str(st["phase"]) == "play" and int(st["turn"]) == 0:
			var act := BotPlayerGd.decide(st, 0)
			main.table._human_apply(act)
		elif str(st["phase"]) == "exchange":
			for e in st.get("exchange_returns", []):
				if int(e["seat"]) == 0:
					var hand: Array = st["hands"][0].duplicate()
					var CardsGd = load("res://src/rules/cards.gd")
					CardsGd.sort_cards(hand)
					main.table._human_apply({"t": "exchange_return", "seat": 0,
							"cards": hand.slice(0, int(e["n"]))})
					break
		sample_t += delta
		frames += 1
		if sample_t >= 1.0:
			fps_samples.append(frames / sample_t)
			mem_samples.append(OS.get_static_memory_usage() / 1048576.0)
			if int(f) % 1200 == 0:
				print("[perf] t=%ds fps=%.1f mem=%.1fMB" % [f / 60, fps_samples[-1], mem_samples[-1]])
			sample_t = 0.0
			frames = 0
		if f >= 5400:  # 90 秒
			var avg_fps := 0.0
			for v in fps_samples:
				avg_fps += v
			avg_fps /= maxf(fps_samples.size(), 1)
			var min_fps: float = fps_samples.min() if fps_samples.size() > 0 else 0.0
			var first_mem: float = mem_samples[0] if mem_samples.size() > 0 else 0.0
			var peak_mem: float = 0.0
			for v in mem_samples:
				peak_mem = maxf(peak_mem, v)
			print("[perf] RESULT samples=%d avg_fps=%.1f min_fps=%.1f mem_first=%.1fMB mem_peak=%.1fMB" % [
					fps_samples.size(), avg_fps, min_fps, first_mem, peak_mem])
			return true
	return false
