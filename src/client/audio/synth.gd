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


## 单音（正弦 + 指数衰减包络）
static func tone(dur: float, freq: float, vol := 0.5, decay := 6.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-decay * t)
		if t < 0.004:
			env *= t / 0.004  # 防爆音
		out[i] = sin(TAU * freq * t) * vol * env
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


static func silence(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	return out


static func wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	return _to_wav(samples)


# ---------------------------------------------------------------- BGM

## 五声音阶氛围垫（可变调式/密度）。16 秒无缝循环。
static func _bgm_base(roots: Array, pluck_seed: int, pluck_min: float, pluck_max: float) -> AudioStreamWAV:
	var dur := 16.0
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for ci in roots.size():
		var start: float = ci * (dur / roots.size())
		for half in 2:
			var f: float = roots[ci][half]
			var s0 := int(start * RATE)
			var len := int((dur / roots.size()) * RATE)
			for i in len:
				var t := float(i) / RATE
				var env := sin(PI * t / (dur / roots.size())) * 0.10
				out[s0 + i] += sin(TAU * f * t) * env
	var rng := RandomNumberGenerator.new()
	rng.seed = pluck_seed
	var t := 0.4
	while t < dur - 0.5:
		var f: float = roots[rng.randi_range(0, roots.size() - 1)][rng.randi_range(0, 1)]
		# 拨弦音高在其邻域五度内跳动
		f *= [0.5, 0.75, 1.0, 1.5][rng.randi_range(0, 3)]
		var vol := rng.randf_range(0.10, 0.18)
		var pluck := tone(0.9, f, vol, 5.0)
		out = mix_over(out, pluck, t)  # PackedArray 值语义, 必须接返回值
		t += rng.randf_range(pluck_min, pluck_max)
	return _to_wav(out)


## 对局 BGM: A 羽调式, 舒缓
static func bgm_koto() -> AudioStreamWAV:
	return _bgm_base([
		[220.0, 329.63],   # A + E
		[261.63, 392.0],   # C + G
		[293.66, 440.0],   # D + A
		[220.0, 329.63],
	], 20260911, 0.5, 1.1)


## 大厅 BGM: D 羽调式, 稍快更轻快
static func bgm_lobby() -> AudioStreamWAV:
	return _bgm_base([
		[293.66, 440.0],   # D + A
		[349.23, 523.25],  # F + C
		[392.0, 587.33],   # G + D
		[293.66, 440.0],
	], 20260912, 0.35, 0.8)
