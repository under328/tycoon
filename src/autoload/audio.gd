## 音频管理（autoload: Audio）。BGM/SFX 双总线；音效库运行时程序化合成。
## 正式 AI 生成音乐素材就位后：替换 _build_library / _make_bgm 为文件加载即可。
extends Node

const Synth := preload("res://src/client/audio/synth.gd")

var bgm_player: AudioStreamPlayer
var _bgm_tracks := {}
var _bgm_current := ""
var _sfx_players: Array = []
var _sfx_next := 0
var library := {}


func _ready() -> void:
	_setup_buses()
	_build_library()
	_bgm_tracks["table"] = Synth.bgm_koto()
	_bgm_tracks["table_rev"] = Synth.bgm_koto_rev()
	_bgm_tracks["lobby"] = Synth.bgm_lobby()
	apply_volumes()
	play_bgm("lobby")


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
	library["result"] = Synth.wav(Synth.concat([
		Synth.tone(0.12, 523.25, 0.28, 6.0), Synth.tone(0.12, 659.25, 0.28, 6.0),
		Synth.tone(0.12, 783.99, 0.28, 5.0),
		Synth.concat([
			Synth.tone(0.42, 1046.5, 0.30, 4.0), Synth.tone(0.42, 1318.5, 0.18, 4.0),
		]),
	]))




# ---------------------------------------------------------------- API

func play(sfx_name: String) -> void:
	if not library.has(sfx_name):
		return
	var p: AudioStreamPlayer = _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = library[sfx_name]
	p.play()


## 切换 BGM 轨道（"lobby"/"table"）；同轨不重启。
func play_bgm(track: String = "lobby") -> void:
	if not _bgm_tracks.has(track):
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
