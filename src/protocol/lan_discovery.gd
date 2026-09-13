## 局域网发现协议(同 WiFi/局域网一键加入):
## 客户端 UDP 广播 QUERY → 主机(游戏端口+2)回 REPLY(房间概览+游戏端口)。
## 无 Tailscale 也能联机: 大厅自动列出附近主机, 点击即加。
## 本文件全部为纯函数(无 socket), 可零依赖单测。
extends RefCounted

const MAGIC_Q := "TYCOONQ1"
const MAGIC_R := "TYCOONR1"
const PORT_OFFSET := 2   # 发现端口 = 游戏端口+2 (健康检查占用 +1)
const TTL_MS := 12000    # 客户端: 超过此时长未见回包则从列表移除该主机


static func make_query() -> PackedByteArray:
	return MAGIC_Q.to_utf8_buffer()


static func is_query(data: PackedByteArray) -> bool:
	return data.get_string_from_utf8() == MAGIC_Q


## rooms: RoomManager.discovery_snapshot() 输出; port: 游戏端口(客户端直连用,
## 主机可能改过端口, 广播里带上才不用猜)
static func make_reply(rooms: Array, port: int) -> PackedByteArray:
	return (MAGIC_R + JSON.stringify({"port": port, "rooms": rooms})).to_utf8_buffer()


## 返回 {port:int, rooms:[{code,players,cap,open}]} 或 {}(非本协议/损坏数据)
static func parse_reply(data: PackedByteArray) -> Dictionary:
	var s := data.get_string_from_utf8()
	if not s.begins_with(MAGIC_R):
		return {}
	var parsed = JSON.parse_string(s.substr(MAGIC_R.length()))
	if not (parsed is Dictionary):
		return {}
	var port := int(parsed.get("port", 0))
	if port < 1 or port > 65535 or not (parsed.get("rooms") is Array):
		return {}
	var rooms: Array = []
	for r in parsed["rooms"]:
		if r is Dictionary and str(r.get("code", "")) != "":
			rooms.append({
				"code": str(r["code"]),
				"players": int(r.get("players", 0)),
				"cap": int(r.get("cap", 4)),
				"open": bool(r.get("open", false)),
			})
	return {"port": port, "rooms": rooms}
