## 音频管理（autoload: Audio）。BGM/SFX 双总线；音效库运行时程序化合成。
## 正式 AI 生成音乐素材就位后：替换 _build_library / _make_bgm 为文件加载即可。
extends Node

const Synth := preload("res://src/client/audio/synth.gd")

var bgm_player: AudioStreamPlayer
var _bgm_tracks := {}
var _bgm_current := ""
var _bgm_thread: Thread = null   # 对局曲后台预合成(避免进桌主线程卡顿)
var _table_synth_done := false   # 预合成结果已注册(主线程可见); 防兜底路径在
                                 # "线程已结束但 deferred 注册未跑"的一帧窗口内
                                 # 于主线程重复合成整轨(1-4s 冻结 → 手机 ANR)
var _sfx_players: Array = []
var _sfx_next := 0
var library := {}

# ── 语音播报(欢乐斗地主式): MP3 语音库 + 单播放器小队列 ──
const VOICE_DIR := "res://assets/voice/"
const VOICE_DEDUPE_MS := 1300   # 同一播报词的去重窗口(连续过牌/重复命中)
const VOICE_Q_MAX := 2          # 队列上限(旧播报让位新播报)
var _voice_player: AudioStreamPlayer
var _voice_q: Array = []        # [{key, pitch}]
var _voice_last_ms := {}        # key -> 上次播报时间(去重)
var _voice_missing := {}        # 加载失败的 key(测试环境/缺资产时静默跳过)


func _ready() -> void:
	_setup_buses()
	_build_library()
	# 首页曲启动即合成; 对局两曲较长 → 后台线程预合成(主线程整轨合成会冻结 1-4 秒)
	_bgm_tracks["lobby"] = Synth.bgm_lobby()
	_bgm_thread = Thread.new()
	if _bgm_thread.start(_synth_table_tracks) != OK:
		_bgm_thread = null
		_synth_table_tracks()  # 降级: 主线程合成(Thread.start 失败极罕见)
	apply_volumes()
	play_bgm("lobby")


func _synth_table_tracks() -> void:
	var koto := Synth.bgm_koto()
	var rev := Synth.bgm_koto_rev()
	var rogue := Synth.bgm_rogue()
	_register_table_tracks.call_deferred(koto, rev, rogue)


func _register_table_tracks(koto: AudioStreamWAV, rev: AudioStreamWAV,
		rogue: AudioStreamWAV) -> void:
	_bgm_tracks["table"] = koto
	_bgm_tracks["table_rev"] = rev
	_bgm_tracks["rogue"] = rogue
	_table_synth_done = true
	if _bgm_thread != null:
		_bgm_thread.wait_to_finish()
		_bgm_thread = null
	# 预合成期间有排队的重试请求 → 立即补播
	if (_bgm_current == "table" or _bgm_current == "table_rev") \
			and not bgm_player.playing:
		play_bgm(_bgm_current)


func _exit_tree() -> void:
	if _bgm_thread != null:
		_bgm_thread.wait_to_finish()
		_bgm_thread = null


func _notification(what: int) -> void:
	# 移动端切后台/桌面失焦时静音, 回前台恢复(避免后台出声被系统限制或打扰)
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_set_bus_volume("BGM", 0.0)
			_set_bus_volume("SFX", 0.0)
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			apply_volumes()


func _setup_buses() -> void:
	for bus_name in ["BGM", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	bgm_player = AudioStreamPlayer.new()
	bgm_player.bus = "BGM"
	add_child(bgm_player)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)
	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = "SFX"
	_voice_player.volume_db = 1.5   # 语音略高于音效: 播报是主要信息通道
	add_child(_voice_player)
	_voice_player.finished.connect(_on_voice_finished)


func _build_library() -> void:
	library["click"] = Synth.wav(Synth.tone(0.05, 1250.0, 0.30, 40.0))
	library["deal"] = Synth.wav(Synth.snap(0.05, 0.22, 46.0))
	library["play_card"] = Synth.wav(
			Synth.mix_over(Synth.snap(0.07, 0.34, 34.0),
			Synth.tone(0.06, 190.0, 0.20, 34.0), 0.0))
	library["pass"] = Synth.wav(Synth.tone(0.10, 235.0, 0.24, 22.0))
	library["clear"] = Synth.wav(Synth.sweep(0.30, 340.0, 90.0, 0.28))
	library["revolution"] = Synth.wav(Synth.concat([
		Synth.riser(0.40, 170.0, 860.0, 0.20),
		Synth.drum(0.32, 0.5),
		Synth.concat([
			Synth.tone(0.20, 659.25, 0.30, 8.0), Synth.tone(0.30, 880.0, 0.30, 6.0),
		]),
	]))
	library["exchange"] = Synth.wav(Synth.concat([
		Synth.tone(0.10, 587.33, 0.22, 12.0), Synth.tone(0.12, 783.99, 0.22, 12.0),
	]))
	library["win"] = Synth.wav(Synth.mix_over(Synth.concat([
		Synth.tone(0.13, 523.25, 0.30, 7.0), Synth.tone(0.13, 659.25, 0.30, 7.0),
		Synth.tone(0.13, 783.99, 0.30, 7.0), Synth.tone(0.34, 1046.5, 0.32, 5.0),
	]), Synth.tone(0.70, 130.81, 0.18, 2.0), 0.02))
	library["lose"] = Synth.wav(Synth.mix_over(Synth.concat([
		Synth.tone(0.16, 440.0, 0.26, 7.0), Synth.tone(0.16, 349.23, 0.26, 7.0),
		Synth.tone(0.30, 293.66, 0.26, 5.0),
	]), Synth.tone(0.62, 98.0, 0.16, 2.0), 0.02))
	library["pop"] = Synth.wav(Synth.tone(0.06, 880.0, 0.28, 26.0))
	library["tick"] = Synth.wav(Synth.tone(0.03, 1500.0, 0.18, 55.0))
	library["turn"] = Synth.wav(Synth.tone(0.08, 987.77, 0.20, 16.0))
	library["eight_cut"] = Synth.wav(Synth.concat([
		Synth.sweep(0.16, 1500.0, 260.0, 0.30), Synth.snap(0.12, 0.40, 30.0),
	]))
	library["fall"] = Synth.wav(Synth.sweep(0.55, 520.0, 70.0, 0.30))
	# 格斗专用: 命中/暴击/受击(短促冲击感, 与牌桌音效区分)
	library["hit"] = Synth.wav(Synth.mix_over(Synth.snap(0.07, 0.5, 55.0),
			Synth.tone(0.09, 130.0, 0.30, 30.0), 0.0))
	library["crit"] = Synth.wav(Synth.concat([
		Synth.snap(0.06, 0.55, 70.0), Synth.tone(0.16, 1318.5, 0.24, 9.0),
	]))
	library["hurt"] = Synth.wav(Synth.sweep(0.22, 320.0, 80.0, 0.32))
	library["result"] = Synth.result_fanfare()




# ---------------------------------------------------------------- API

func play(sfx_name: String) -> void:
	if not library.has(sfx_name) or _sfx_players.is_empty():
		return
	var p: AudioStreamPlayer = _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = library[sfx_name]
	p.play()


## 语音播报(欢乐斗地主式): key 为 assets/voice/<key>.mp3。
## pitch 做座位差异化变调(1.0 原声); interrupt=true 清队列立即播(革命/胜负
## 等关键时刻)。同 key 去重窗口内只播一次; 队列上限 2 旧让新; 走 SFX 总线
## 受音效音量控制, 且受 GameSettings.voice_on 开关。
func say(key: String, pitch := 1.0, interrupt := false) -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and not bool(gs.voice_on):
		return
	if _voice_player == null:
		return
	var now := Time.get_ticks_msec()
	if int(_voice_last_ms.get(key, -100000)) + VOICE_DEDUPE_MS > now:
		return
	_voice_last_ms[key] = now
	if interrupt:
		_voice_q.clear()
		_voice_player.stop()
	while _voice_q.size() >= VOICE_Q_MAX:
		_voice_q.pop_front()
	_voice_q.append({"key": key, "pitch": pitch})
	_pump_voice()


func _pump_voice() -> void:
	if _voice_player.playing or (_voice_q as Array).is_empty():
		return
	var item: Dictionary = _voice_q.pop_front()
	var stream := _voice_stream(str(item["key"]))
	if stream == null:
		_pump_voice()   # 缺资产(测试环境): 跳过继续
		return
	_voice_player.stream = stream
	_voice_player.pitch_scale = float(item.get("pitch", 1.0))
	_voice_player.play()


func _voice_stream(key: String) -> AudioStream:
	var cache_key := "voice_" + key
	if _voice_missing.has(key) or library.has(cache_key):
		return library.get(cache_key)
	var path := VOICE_DIR + key + ".mp3"
	if not ResourceLoader.exists(path):
		_voice_missing[key] = true
		return null
	var stream: AudioStream = load(path)
	if stream == null:
		_voice_missing[key] = true
	return stream


func _on_voice_finished() -> void:
	if not is_inside_tree():
		return   # 退出期不再排程
	get_tree().create_timer(0.08).timeout.connect(_pump_voice)


## 切换 BGM 轨道（"lobby"/"table"/"table_rev"）；同轨不重启。
## 对局曲后台预合成中 → 定时重试(绝不主线程合成卡顿); 兜底同步合成。
func play_bgm(track: String = "lobby") -> void:
	if bgm_player == null:
		return
	if not _bgm_tracks.has(track):
		match track:
			"table", "table_rev", "rogue":
				# 合成未注册(线程仍在跑, 或已结束但 deferred 注册未到) → 只重试,
				# 不在主线程兜底合成 — 兜底路径在手机上冻结 1-4 秒即 ANR
				if _bgm_thread != null or not _table_synth_done:
					get_tree().create_timer(0.25).timeout.connect(
							play_bgm.bind(track))
					return
				_bgm_tracks[track] = Synth.bgm_koto() if track == "table" \
						else (Synth.bgm_rogue() if track == "rogue" \
						else Synth.bgm_fight())
			_:
				return
	if _bgm_current == track and bgm_player.playing:
		return
	_bgm_current = track
	bgm_player.stream = _bgm_tracks[track]
	bgm_player.play()


func apply_volumes() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	var bgm_v := 0.8
	var sfx_v := 1.0
	if gs != null:
		bgm_v = float(gs.bgm_volume)
		sfx_v = float(gs.sfx_volume)
	_set_bus_volume("BGM", bgm_v)
	_set_bus_volume("SFX", sfx_v)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))
		AudioServer.set_bus_mute(idx, linear <= 0.001)
