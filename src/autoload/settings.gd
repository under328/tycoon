extends Node
## 客户端偏好持久化（autoload: GameSettings）

const SAVE_PATH := "user://settings.cfg"

var nickname := "玩家"
var bgm_volume := 0.8
var sfx_volume := 1.0


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		nickname = cf.get_value("player", "nickname", nickname)
		bgm_volume = cf.get_value("audio", "bgm", bgm_volume)
		sfx_volume = cf.get_value("audio", "sfx", sfx_volume)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("player", "nickname", nickname)
	cf.set_value("audio", "bgm", bgm_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.save(SAVE_PATH)
