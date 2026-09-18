## BGM 渲染体检: 每曲时长/峰值/响度检查(改曲后跑一遍防静音/削波/时长漂移)
extends SceneTree

const CASES := [
	["lobby", "bgm_lobby", 8, 112.0],
	["table", "bgm_koto", 8, 116.0],
	["table_rev", "bgm_koto_rev", 8, 138.0],
	["rogue", "bgm_rogue", 8, 128.0],
	["fight", "bgm_fight", 16, 132.0],
	["fanfare", "result_fanfare", 4, 140.0],
]


func _initialize() -> void:
	var synth: GDScript = load("res://src/client/audio/synth.gd")
	var fails := 0
	for c in CASES:
		var wav: AudioStreamWAV = synth.call(str(c[1]))
		var frames: int = wav.data.size() / 2
		var secs := float(frames) / 22050.0
		var want: float = float(c[2]) * 4.0 * 60.0 / float(c[3])
		var peak := 0.0
		var sum := 0.0
		for i in frames:
			var v: float = float(wav.data.decode_s16(i * 2)) / 32768.0
			peak = maxf(peak, absf(v))
			sum += v * v
		var rms := sqrt(sum / float(frames))
		var ok := absf(secs - want) < 0.05 and peak < 0.95 and rms > 0.03
		if not ok:
			fails += 1
		print("[BGM] %s dur=%.2fs(want %.2f) peak=%.3f rms=%.3f loop=%d %s" % [
				c[0], secs, want, peak, rms, wav.loop_mode, "OK" if ok else "FAIL"])
	print("[BGM] check done, fails=%d" % fails)
	quit(1 if fails > 0 else 0)
