extends Node
## 客户端偏好持久化（autoload: GameSettings）

const SAVE_PATH := "user://settings.cfg"
## 默认服务器: 本机(大厅可改; 没有官方 VPS 前保证"本机开房/局域网"开箱即用)
const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 24565
## 版本更新的兜底地址(仅在客户端没有主机信息时使用)。
## 正式分发建议用主机内置下载服务: 把新版安装包放到服务器 download/ 文件夹,
## 客户端"发现新版本"会直接从联机主机获取(国内友好, 无需外部站点)。
const DOWNLOAD_URL := "https://tycoon.example.com/download"

var nickname := "玩家"
var bgm_volume := 0.8
var sfx_volume := 1.0
var client_id := ""      # 游客身份：首启随机生成，持久化
var tutorial_seen := false  # 是否已看过新手引导
var host: String = DEFAULT_HOST  # 联机服务器地址(大厅可改, 持久化)
var host_port := 24565      # 联机服务器端口(持久化)
var fullscreen := false         # 显示偏好: 全屏(持久化)
var vsync_enabled := true       # 显示偏好: 垂直同步(持久化)
var window_size := Vector2i.ZERO  # 显示偏好: 窗口尺寸(ZERO=不改)
var vibration := true           # 触感偏好: 震动反馈(移动端)
var ai_level := "normal"        # 本地 AI 难度: easy/normal
var card_counter := true        # 记牌器 HUD 开关


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
		host = str(cf.get_value("net", "host", host))
		host_port = int(cf.get_value("net", "host_port", host_port))
		var lv := str(cf.get_value("game", "ai_level", ai_level))
		ai_level = lv if lv in ["easy", "normal"] else "normal"
		card_counter = bool(cf.get_value("game", "card_counter", card_counter))
		fullscreen = bool(cf.get_value("display", "fullscreen", fullscreen))
		vsync_enabled = bool(cf.get_value("display", "vsync", vsync_enabled))
		vibration = bool(cf.get_value("haptics", "vibration", true))
		window_size = Vector2i(cf.get_value("display", "window_size_x", 0),
				cf.get_value("display", "window_size_y", 0))


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("player", "nickname", nickname)
	cf.set_value("audio", "bgm", bgm_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("player", "client_id", client_id)
	cf.set_value("player", "tutorial_seen", tutorial_seen)
	cf.set_value("net", "host", host)
	cf.set_value("net", "host_port", host_port)
	cf.set_value("game", "ai_level", ai_level)
	cf.set_value("game", "card_counter", card_counter)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("display", "vsync", vsync_enabled)
	cf.set_value("display", "window_size_x", window_size.x)
	cf.set_value("display", "window_size_y", window_size.y)
	cf.set_value("haptics", "vibration", vibration)
	cf.save(SAVE_PATH)
