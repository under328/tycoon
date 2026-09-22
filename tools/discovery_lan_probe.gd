## 双进程发现探针: 扫描进程向本机真实局域网 IP 的发现端口发 QUERY,
## 独立服务器进程应答 → 验证跨进程 UDP 发现链路(非回环)。
extends SceneTree

const NetNodeGd = preload("res://src/protocol/net_node.gd")
const LanDisc = preload("res://src/protocol/lan_discovery.gd")
const Responsive = preload("res://src/client/theme/responsive.gd")

var f := 0
var disc: PacketPeerUDP = null
var ok := false


func _process(_d: float) -> bool:
	f += 1
	if f == 5:
		var lans: Array = Responsive.local_ips()["lan"]
		print("[disc2] 本机局域网 IP: ", lans)
		if lans.is_empty():
			print("[disc2] FAIL 无局域网 IP")
			quit(1)
			return true
		disc = PacketPeerUDP.new()
		if disc.bind(0) != OK:
			print("[disc2] FAIL 绑定失败")
			quit(1)
			return true
		disc.set_broadcast_enabled(true)
	if f % 30 == 0 and f > 10 and f < 300:
		var dport: int = 24575 + LanDisc.PORT_OFFSET
		disc.set_dest_address("255.255.255.255", dport)
		disc.put_packet(LanDisc.make_query())
		for ip in Responsive.local_ips()["lan"]:
			var p: PackedStringArray = str(ip).split(".")
			if p.size() != 4:
				continue
			# 定向广播 + 网段首地址(服务器通常占 .1-.254 之一)
			disc.set_dest_address("%s.%s.%s.255" % [p[0], p[1], p[2]], dport)
			disc.put_packet(LanDisc.make_query())
			disc.set_dest_address(ip, dport)
			disc.put_packet(LanDisc.make_query())
	while disc != null and disc.get_available_packet_count() > 0:
		var r := LanDisc.parse_reply(disc.get_packet())
		if not r.is_empty():
			ok = true
			print("[disc2] DISC2_OK — 收到应答: ", r["rooms"])
			quit(0)
			return true
	if f > 300:
		print("[disc2] FAIL 无应答")
		quit(1)
		return true
	return false
