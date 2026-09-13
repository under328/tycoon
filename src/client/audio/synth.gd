## 程序化音频合成（16-bit PCM WAV，运行时生成，无外部素材依赖）。
## 正式 BGM/SFX 素材到位后可整体替换 audio.gd 的库构建。
class_name SynthLib
extends RefCounted

const RATE := 22050


static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## 单音（正弦 + 可选二次泛音 + 指数衰减包络）
static func tone(dur: float, freq: float, vol := 0.5, decay := 6.0, harm := 0.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-decay * t)
		if t < 0.004:
			env *= t / 0.004  # 防爆音
		var s := sin(TAU * freq * t) + harm * sin(TAU * freq * 2.0 * t)
		out[i] = s / (1.0 + harm) * vol * env
	return out


## 噪声爆点（纸牌摩擦/拍击感）
static func snap(dur: float, vol := 0.4, decay := 30.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in n:
		var t := float(i) / RATE
		out[i] = (rng.randf() * 2.0 - 1.0) * vol * exp(-decay * t)
	return out


## 太鼓(低频扫频击)
static func drum(dur := 0.28, vol := 0.5) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(120.0, 42.0, minf(t / (dur * 0.7), 1.0))
		phase += TAU * f / RATE
		var env := exp(-9.0 * t)
		if t < 0.002:
			env *= t / 0.002
		out[i] = sin(phase) * vol * env
	return out


## 上扬扫频(革命预警)
static func riser(dur: float, f0: float, f1: float, vol := 0.22) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t * t)
		phase += TAU * f / RATE
		out[i] = sin(phase) * vol * (0.3 + 0.7 * t)
	return out


## 频率滑音
static func sweep(dur: float, f0: float, f1: float, vol := 0.35) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t)
		phase += TAU * f / RATE
		var env := sin(PI * t)  # 中间饱满两端归零
		out[i] = sin(phase) * vol * env
	return out


## 拼接多段
static func concat(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p)
	return out


## 叠加（短轨叠到长轨上, 起点 offset_sec）
static func mix_over(base: PackedFloat32Array, layer: PackedFloat32Array, offset_sec: float) -> PackedFloat32Array:
	var off := int(offset_sec * RATE)
	for i in layer.size():
		var idx := off + i
		if idx >= 0 and idx < base.size():
			base[idx] += layer[i]
	return base


static func wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	return _to_wav(samples)


# ---------------------------------------------------------------- BGM

## 五声音阶氛围垫（可变调式/密度）。16 秒无缝循环。drums=对局版加太鼓。
# ================================================================ 音乐升级 2.0

## 拨弦(古筝/琵琶): 基频+二三谐波, 快攻快衰
static func pluck(f: float, dur := 0.6, vol := 0.22) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-6.5 * t)
		if t < 0.003:
			env *= t / 0.003
		out[i] = (sin(TAU * f * t) + 0.45 * sin(TAU * f * 2 * t)
				+ 0.18 * sin(TAU * f * 3 * t)) / 1.63 * vol * env
	return out


## 笛(尺八风): 正弦 + 颤音 + 气声噪声, 缓起缓收
static func flute(f: float, dur: float, vol := 0.2) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f * 13)
	for i in n:
		var t := float(i) / RATE
		var env := minf(t / 0.09, 1.0) * minf(maxf((dur - t) / 0.18, 0.0), 1.0)
		var vib := sin(TAU * 5.2 * t) * 0.006
		var tone := sin(TAU * (f * (1.0 + vib)) * t)
		out[i] = (tone * 0.85 + (rng.randf() * 2 - 1) * 0.06) * vol * env
	return out


## 低音: 基频 + 三次谐波
static func bass_note(f: float, dur: float, vol := 0.16) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := sin(PI * t / dur) * 0.9 + 0.1
		out[i] = (sin(TAU * f * t) + 0.25 * sin(TAU * f * 2 * t)) / 1.25 * vol * env
	return out


## 铜钵: 非谐泛音簇, 长衰减
static func kane(vol := 0.2) -> PackedFloat32Array:
	var n := int(2.2 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-2.2 * t)
		if t < 0.002:
			env *= t / 0.002
		out[i] = (sin(TAU * 523.25 * t) + 0.6 * sin(TAU * 523.25 * 2.76 * t)
				+ 0.35 * sin(TAU * 523.25 * 5.4 * t)) / 1.95 * vol * env
	return out


## 军鼓式噪声击
static func snare(vol := 0.2) -> PackedFloat32Array:
	var n := int(0.14 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i in n:
		var t := float(i) / RATE
		out[i] = (rng.randf() * 2 - 1) * vol * exp(-18.0 * t)
	return out


## 音序器: 按 BPM 渲染音符事件列表为 BGM 流(无缝循环)。
## event: {t: 起始拍, len: 拍数, kind: "pluck/flute/bass/taiko/kane/snare", f: 频率, v: 音量}
static func render_track(bars: int, bpm: float, events: Array, loop := true) -> AudioStreamWAV:
	var spb := 60.0 / bpm
	var dur := bars * 4 * spb
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	for e in events:
		var s0 := int(float(e["t"]) * spb * RATE)
		var buf: PackedFloat32Array
		match str(e["kind"]):
			"pluck":
				buf = pluck(float(e["f"]), float(e["len"]) * spb, float(e.get("v", 0.2)))
			"flute":
				buf = flute(float(e["f"]), float(e["len"]) * spb, float(e.get("v", 0.18)))
			"bass":
				buf = bass_note(float(e["f"]), float(e["len"]) * spb, float(e.get("v", 0.15)))
			"taiko":
				buf = drum(0.28, float(e.get("v", 0.4)))
			"kane":
				buf = kane(float(e.get("v", 0.2)))
			"snare":
				buf = snare(float(e.get("v", 0.16)))
			_:
				continue
		for i in buf.size():
			var idx := s0 + i
			if idx >= out.size():
				break
			out[idx] += buf[i]
	var wav := _to_wav(out)
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = out.size()
	return wav


## 音符事件辅助
static func _n(t: float, len: float, kind: String, f: float, v: float) -> Dictionary:
	return {"t": t, "len": len, "kind": kind, "f": f, "v": v}


## 大厅 BGM: C 大调五声 112BPM 明亮欢快(笛主旋律 + 拨弦琶音 + 律动低音 + 反拍军鼓),
## 与对局 BGM 同一音乐语汇(和风×流行圈进行), 首页不再有阴翳感。
static func bgm_lobby() -> AudioStreamWAV:
	var ev := []
	# 笛主旋律(拍, 长拍, 频率): 两句 16 拍, 末句解决到 C5 无缝循环
	var C4 := 261.63
	var A4 := 440.0
	var B4 := 493.88
	var C5 := 523.25
	var D5 := 587.33
	var E5 := 659.26
	var mel := [
		# A 句: C-Am-F-G
		[0, .5, 392.0], [.5, .5, A4], [1, 1, C5], [2, .5, C5], [2.5, .5, D5], [3, 1, E5],
		[4, 1, E5], [5, .5, E5], [5.5, .5, D5], [6, 1, C5], [7, 1, A4],
		[8, .5, A4], [8.5, .5, C5], [9, 1, D5], [10, .5, D5], [10.5, .5, E5], [11, 1, D5],
		[12, 1, D5], [13, .5, E5], [13.5, .5, D5], [14, 1, B4], [15, 1, 392.0],
		# B 句(变奏): 末尾 B4→C5 半解决, 循环进 C 和弦
		[16, .5, 392.0], [16.5, .5, A4], [17, 1, C5], [18, .5, C5], [18.5, .5, D5], [19, 1, E5],
		[20, .5, E5], [20.5, .5, D5], [21, 1, C5], [22, 1, A4], [23, 1, C5],
		[24, 1, D5], [25, .5, E5], [25.5, .5, D5], [26, 1, C5], [27, 1, A4],
		[28, .5, 392.0], [28.5, .5, A4], [29, .5, B4], [29.5, .5, C5], [30, 2, C5],
	]
	for m in mel:
		ev.append(_n(float(m[0]), float(m[1]), "flute", float(m[2]), 0.16))
	# 拨弦琶音(每半拍, 和弦音下行使声部低于旋律)
	var chord_arps := [
		[C4, 329.63, 392.0, 329.63],        # C: 1-3-5-3
		[220.0, C4, 329.63, C4],            # Am
		[174.61, 220.0, C4, 220.0],         # F
		[196.0, 246.94, 293.66, 246.94],    # G
	]
	for rep in 2:
		for bi in 4:
			var arp: Array = chord_arps[bi]
			for k in 8:
				ev.append(_n(rep * 16 + bi * 4 + k * 0.5, 0.5, "pluck",
						float(arp[k % arp.size()]), 0.10))
	# 律动低音: 每小节 根音(2拍) + 五音(2拍)
	var bass_pairs := [
		[65.41, 98.0],     # C2 → G2
		[110.0, 82.41],    # A2 → E2
		[87.31, 65.41],    # F2 → C2
		[98.0, 73.42],     # G2 → D2
	]
	for rep in 2:
		for bi in 4:
			var pair: Array = bass_pairs[bi]
			ev.append(_n(rep * 16 + bi * 4, 2, "bass", float(pair[0]), 0.14))
			ev.append(_n(rep * 16 + bi * 4 + 2, 2, "bass", float(pair[1]), 0.12))
	# 打击: 太鼓每小节头, 军鼓反拍(第3拍), 钹标句读
	for rep in 2:
		for bi in 4:
			ev.append(_n(rep * 16 + bi * 4, 1, "taiko", 0, 0.22))
			ev.append(_n(rep * 16 + bi * 4 + 2, 1, "snare", 0, 0.09))
	ev.append(_n(0, 1, "kane", 523.25, 0.12))
	ev.append(_n(16, 1, "kane", 523.25, 0.10))
	return render_track(8, 112, ev)


## 对局 BGM: G 大调 116BPM 欢快(笛主旋律 + 拨弦琶音 + 弹跳低音 + 反拍军鼓)
static func bgm_koto() -> AudioStreamWAV:
	var ev := []
	# G 大调欢快跳跃音型
	var mel := [
		[0,.5,783.99],[.5,.5,987.77],[1,1,1174.66],[1.5,.5,880],
		[2,1,783.99],[3,.5,659.26],[4,1,587.33],[4.5,.5,659.26],
		[5,1,783.99],[5.5,.5,880],[6,1,1174.66],[6.5,1,1567.98],
		[7,.5,1318.51],[7.5,.5,1174.66],[8,1,987.77],[8.5,.5,880],
		[9,1,783.99],[9.5,.5,659.26],[10,1,587.33],[10.5,.5,493.88],
		[11,1,587.33],[11.5,.5,493.88],[12,1,440],[12.5,.5,392],
	]
	var t := 0.0
	for n in mel:
		ev.append(_n(t, float(n[1]), "flute", float(n[2]), 0.16))
		t += float(n[1])
	var chord_roots := [196.0, 164.81, 130.81, 146.83]
	var chord_arps := [
		[392, 493.88, 587.33, 493.88],
		[329.63, 392, 493.88, 392],
		[261.63, 329.63, 392, 329.63],
		[293.66, 369.99, 440, 369.99],
	]
	for rep in 2:
		for bi in 4:
			var t0: float = rep * 12 + bi * 4
			var arp: Array = chord_arps[bi]
			ev.append(_n(t0, 4, "bass", float(chord_roots[bi]), 0.15))
			for e8 in 8:
				ev.append(_n(t0 + e8 * 0.5, 0.45, "pluck", float(arp[e8 % arp.size()]), 0.09))
			ev.append(_n(t0, 1, "taiko", 0, 0.25))
			ev.append(_n(t0 + 2, 1, "snare", 0, 0.10))
	return render_track(8, 116, ev)

static func bgm_koto_rev() -> AudioStreamWAV:
	var ev := []
	var riff := [[110.0, 0.5], [110.0, 0.5], [130.81, 0.5], [164.81, 0.5],
			[146.83, 1.0], [130.81, 0.5], [146.83, 0.5]]
	var bars := [[220.0, 130.81], [220.0, 146.83], [196.0, 110.0], [164.81, 196.0]]
	for bi in 8:
		var pair: Array = bars[bi % 4]
		var base := 0.0
		for note in riff:
			var f: float = float(note[0])
			if base > 0.0:
				f = float(pair[0]) if f < 150.0 else float(pair[1])
			ev.append(_n(bi * 8 + base, float(note[1]), "pluck", f, 0.2))
			base += float(note[1])
		ev.append(_n(bi * 8, 1, "taiko", 0.0, 0.5))
		ev.append(_n(bi * 8 + 1.5, 1, "taiko", 0.0, 0.3))
		ev.append(_n(bi * 8 + 2.5, 1, "taiko", 0.0, 0.34))
		ev.append(_n(bi * 8 + 3, 1, "snare", 0.0, 0.12))
		ev.append(_n(bi * 8 + 4, 1, "kane", 523.25, 0.14))
		ev.append(_n(bi * 8 + 4, 2, "flute", 440.0, 0.14))
	return render_track(8, 138, ev)


## 终局凯旋短句(一次性, 140BPM 4 小节)
static func result_fanfare() -> AudioStreamWAV:
	var ev := []
	var fanfare := [[0, 0.5, 587.33], [0.5, 0.5, 739.99], [1, 1, 880.0], [2, 2.5, 1174.66]]
	for n in fanfare:
		ev.append(_n(float(n[0]), float(n[1]), "flute", float(n[2]), 0.22))
		ev.append(_n(float(n[0]), float(n[1]), "pluck", float(n[2]) / 2.0, 0.16))
	for i in 8:
		ev.append(_n(i * 0.25, 0.25, "taiko", 0.0, 0.3 - i * 0.02))
	ev.append(_n(2, 1, "taiko", 0.0, 0.5))
	ev.append(_n(2, 1, "kane", 523.25, 0.2))
	return render_track(4, 140, ev, false)
