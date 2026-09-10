extends Node
## 启动模式判定（autoload: AppMode）
##   --server  服务器模式（headless 专用服务器）
##   --client  客户端联机模式（M2 接入）
##   默认      本地调试模式（人 + 3AI）

var is_server := false
var local_mode := true


func _ready() -> void:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for a: String in args:
		match a:
			"--server":
				is_server = true
			"--client":
				local_mode = false
			"--local":
				local_mode = true
