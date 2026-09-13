## 多设备自适应布局助手: PC / 手机 / 平板横屏统一适配。
## 拉伸模式 canvas_items+expand(设计分辨率 1280x720)下, 逻辑视口恒有 宽>=1280、高>=720:
##   4:3 平板横屏 = 1280x960(多高度) · 20:9 手机横屏 = 1600x720(多宽度) · PC = 任意窗形。
## 因此布局不按设备型号分支, 只按几何锚定:
##   左栏固定 · 中栏随多余宽度按比例右移 · 右栏锚住右缘 · 底部内容锚住底缘。
extends RefCounted


## 触控设备(安卓/iOS 及其 Web 导出): 按钮热区下限 44px
static func is_touch() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") \
			or OS.has_feature("web_ios")


## 触屏内容缩放: >1 = 逻辑视口更小 = 一切元素物理尺寸放大。
## 1.25 → 20:9 手机(2340x1080)逻辑视口 1248x576, 牌/按钮物理 +25%,
## 配合牌桌紧凑布局与触屏加大尺寸(牌 96x134)合计 +67%。
static func ui_scale() -> float:
	return 1.25 if is_touch() else 1.0


## 本机地址分类: lan=私网 IPv4(192.168/10./172.16-31, 含手机热点/USB共享),
## ts=Tailscale(CGNAT); 回环与 IPv6 不参与联机, 一律排除。
static func local_ips() -> Dictionary:
	var lan: Array = []
	var ts: Array = []
	for ip in IP.get_local_addresses():
		var s := str(ip)
		var p := s.split(".")
		if p.size() != 4:
			continue
		if p[0] == "100" and int(p[1]) >= 64 and int(p[1]) <= 127:
			ts.append(s)
		elif p[0] == "10" or (p[0] == "192" and p[1] == "168") \
				or (p[0] == "172" and int(p[1]) >= 16 and int(p[1]) <= 31):
			lan.append(s)
	return {"lan": lan, "ts": ts}


## Tailscale 虚拟网 IP(CGNAT 段 100.64.0.0/10, 而非任意 100.x 公网地址)
static func tailscale_ips() -> Array:
	return local_ips()["ts"]


## 邀请码/主机面板的地址候选: 局域网优先(同 WiFi 延迟最低), Tailscale 兜底(跨网)
static func host_ips() -> Array:
	var d := local_ips()
	return d["lan"] + d["ts"]


## 当前设备的 Tailscale 下载直达页
## (Android 不用 Play 商店——国内无法访问; 大厅按钮会用运行时解析的 APK 直链)
static func tailscale_url() -> String:
	if OS.has_feature("android"):
		return "https://pkgs.tailscale.com/stable/#android"
	if OS.has_feature("ios"):
		return "https://apps.apple.com/app/tailscale/id1475387142"
	if OS.has_feature("macos"):
		return "https://tailscale.com/download/mac"
	if OS.has_feature("windows"):
		return "https://tailscale.com/download/windows"
	if OS.has_feature("linux"):
		return "https://tailscale.com/download/linux"
	return "https://tailscale.com/download"


## 平台名(下载按钮文案用)
static func platform_label() -> String:
	if OS.has_feature("android"):
		return "Android"
	if OS.has_feature("ios"):
		return "iPhone/iPad"
	if OS.has_feature("macos"):
		return "macOS"
	if OS.has_feature("windows"):
		return "Windows"
	if OS.has_feature("linux"):
		return "Linux"
	return "当前平台"


## 控件尺寸变化(窗口缩放/安全区收缩)时触发重排; 首帧延迟执行一次。
## 用法: Responsive.watch(self, _relayout)
static func watch(c: Control, fn: Callable) -> void:
	c.resized.connect(fn)
	fn.call_deferred()
