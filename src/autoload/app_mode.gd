extends Node
## 启动模式与命令行参数（autoload: AppMode）
##   --server            服务器模式（headless 专用服务器）
##   --client            客户端联机模式（大厅）
##   --local             本地调试模式（人 + 3AI，默认）
##   --port N            服务器/客户端端口（默认 24565）
##   --address A         客户端连接地址（默认 127.0.0.1）
##   --ai-delay MS       服务器 AI/托管出牌延迟（默认 600）
##   --phase-delay MS    服务器阶段过渡延迟（默认 2200）

var is_server := false
var local_mode := true
var online_client := false
var port := 24565
var address := "127.0.0.1"
var ai_delay_ms := 600
var phase_delay_ms := 2200


func _ready() -> void:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	var i := 0
	while i < args.size():
		var a: String = str(args[i])
		match a:
			"--server":
				is_server = true
			"--client":
				online_client = true
				local_mode = false
			"--local":
				local_mode = true
				online_client = false
			"--port":
				if i + 1 < args.size():
					port = int(args[i + 1])
					i += 1
			"--address":
				if i + 1 < args.size():
					address = str(args[i + 1])
					i += 1
			"--ai-delay":
				if i + 1 < args.size():
					ai_delay_ms = maxi(1, int(args[i + 1]))
					i += 1
			"--phase-delay":
				if i + 1 < args.size():
					phase_delay_ms = maxi(1, int(args[i + 1]))
					i += 1
		i += 1
