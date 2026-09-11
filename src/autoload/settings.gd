extends Node
## 客户端偏好持久化（autoload: GameSettings）

const SAVE_PATH := "user://settings.cfg"
## 默认服务器: 本机(大厅可改; 没有官方 VPS 前保证"本机开房/局域网"开箱即用)
const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 24565
## 部署时改成实际下载页地址; 版本不符的客户端会收到此提示
const DOWNLOAD_URL := "https://tycoon.example.com/download"

var nickname := "玩家"
var bgm_volume := 0.8
var sfx_volume := 1.0
var client_id := ""      # 游客身份：首启随机生成，持久化
var tutorial_seen := false  # 是否已看过新手引导
var last_room_code := ""    # 最近加入的房间码(方便再次输入)
var host := "127.0.0.1"     # 联机服务器地址(大厅可改, 持久化)
var host_port := 24565      # 联机服务器端口(持久化)


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
		tutorial_seen = cf.get_value("player", "tutorial_seen", false)
		last_room_code = cf.get_value("player", "last_room_code", "")
		host = str(cf.get_value("net", "host", host))
		host_port = int(cf.get_value("net", "host_port", host_port))


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("player", "nickname", nickname)
	cf.set_value("audio", "bgm", bgm_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("player", "client_id", client_id)
	cf.set_value("player", "tutorial_seen", tutorial_seen)
	cf.set_value("net", "host", host)
	cf.set_value("net", "host_port", host_port)
	cf.save(SAVE_PATH)
