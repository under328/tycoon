extends Node
## 客户端偏好持久化（autoload: GameSettings）

const SAVE_PATH := "user://settings.cfg"
## 部署时改成实际下载页地址; 版本不符的客户端会收到此提示
const DOWNLOAD_URL := "https://tycoon.example.com/download"

var nickname := "玩家"
var bgm_volume := 0.8
var sfx_volume := 1.0
var client_id := ""      # 游客身份：首启随机生成，持久化


func _ready() -> void:
	load_settings()
	if client_id == "":
		client_id = "%08x%08x" % [randi(), randi()]
		save_settings()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		nickname = cf.get_value("player", "nickname", nickname)
		bgm_volume = cf.get_value("audio", "bgm", bgm_volume)
		sfx_volume = cf.get_value("audio", "sfx", sfx_volume)
		client_id = cf.get_value("player", "client_id", "")


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("player", "nickname", nickname)
	cf.set_value("audio", "bgm", bgm_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("player", "client_id", client_id)
	cf.save(SAVE_PATH)
