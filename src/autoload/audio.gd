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
						else Synth.bgm_koto_rev()
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
