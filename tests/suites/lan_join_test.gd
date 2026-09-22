## 局域网联机: 地址分类 / 邀请码多地址解析 / 发现协议编解码 / 房间概览快照。
extends RefCounted

const Responsive = preload("res://src/client/theme/responsive.gd")
const LanDisc = preload("res://src/protocol/lan_discovery.gd")
const LobbyScript = preload("res://src/client/scenes/lobby.gd")
const RoomManagerGd = preload("res://src/server/room_manager.gd")


func run(t) -> void:
	_parse_invite(t)
	_discovery_codec(t)
	_ip_classify(t)
	_snapshot(t)


func _parse_invite(t) -> void:
	# 多地址: 局域网 + Tailscale
	var inv := LobbyScript.parse_invite("TC|192.168.1.5,100.64.0.3|24565|AB12")
	t.expect_eq((inv["ips"] as Array).size(), 2, "多地址全部解析")
	t.expect_eq(str(inv["ip"]), "192.168.1.5", "首个地址=局域网")
	t.expect_eq(int(inv["port"]), 24565, "端口解析")
	t.expect_eq(str(inv["code"]), "AB12", "房间码解析")
	# 单地址向后兼容(旧版邀请码)
	var one := LobbyScript.parse_invite("TC|100.64.0.9||XYZ9")
	t.expect_eq((one["ips"] as Array).size(), 1, "单地址兼容")
	t.expect_eq(int(one["port"]), 24565, "缺省端口=24565")
	# 去重与空白容忍
	var dup := LobbyScript.parse_invite("TC|192.168.0.1, 192.168.0.1 ,10.0.0.2|24565|C")
	t.expect_eq((dup["ips"] as Array).size(), 2, "重复地址去重")
	# 无效输入
	t.expect(LobbyScript.parse_invite("TC||24565|X").is_empty(), "空地址拒绝")
	t.expect(LobbyScript.parse_invite("TC|192.168.0.1|99999|X").is_empty(), "非法端口拒绝")
	t.expect(LobbyScript.parse_invite("hello world").is_empty(), "非邀请码拒绝")
	t.expect(LobbyScript.parse_invite("TC|192.168.0.1|24565|X|extra").is_empty(), "段数不符拒绝")


func _discovery_codec(t) -> void:
	var q := LanDisc.make_query()
	t.expect(LanDisc.is_query(q), "查询编解码往返")
	t.expect(not LanDisc.is_query("TYCOONQ2".to_utf8_buffer()), "版本不符不认")
	t.expect(not LanDisc.is_query(PackedByteArray()), "空包不认")
	var rooms: Array = [{"code": "AB12", "players": 2, "cap": 4, "open": true}]
	var reply := LanDisc.make_reply(rooms, 24565)
	var r := LanDisc.parse_reply(reply)
	t.expect(not r.is_empty(), "应答可解析")
	t.expect_eq(int(r["port"]), 24565, "应答端口往返")
	t.expect_eq((r["rooms"] as Array).size(), 1, "应答房间数往返")
	var r0: Dictionary = r["rooms"][0]
	t.expect_eq(str(r0["code"]), "AB12", "房间码往返")
	t.expect(bool(r0["open"]), "open 标志往返")
	# 损坏/伪造数据一律返回空(客户端丢弃)
	t.expect(LanDisc.parse_reply("garbage".to_utf8_buffer()).is_empty(), "非协议数据拒绝")
	t.expect(LanDisc.parse_reply("TYCOONR1{broken".to_utf8_buffer()).is_empty(), "损坏 JSON 拒绝")
	t.expect(LanDisc.parse_reply((LanDisc.MAGIC_R + "{\"port\":0,\"rooms\":[]}").to_utf8_buffer()).is_empty(),
			"非法端口拒绝")
	t.expect(LanDisc.parse_reply((LanDisc.MAGIC_R + "{\"port\":1,\"rooms\":{}}").to_utf8_buffer()).is_empty(),
			"房间非数组拒绝")


func _ip_classify(t) -> void:
	var d := Responsive.local_ips()
	t.expect(d.has("lan") and d.has("ts"), "分类返回 lan/ts 两组")
	var all: Array = d["lan"] + d["ts"]
	var host: Array = Responsive.host_ips()
	t.expect_eq(host.size(), all.size(), "host_ips=全部联机地址")
	var ok_order := true  # 局域网必须排在 Tailscale 前
	var seen_ts := false
	for ip in host:
		var s := str(ip)
		var p := s.split(".")
		if p.size() != 4:
			ok_order = false
		if str(s).begins_with("100.") and p.size() == 4 \
				and int(p[1]) >= 64 and int(p[1]) <= 127:
			seen_ts = true
		elif seen_ts:
			ok_order = false
	t.expect(ok_order, "host_ips 全为合法 IPv4 且局域网在前")
	t.expect(not host.has("127.0.0.1"), "回环地址不参与联机")
	# 已知样例分类(注入式验证: 直接构造字符串走同样的分支逻辑不可行,
	# 用分类不变式覆盖: lan 全为私网段)
	var lan_ok := true
	for ip in d["lan"]:
		var p: PackedStringArray = str(ip).split(".")
		var is_priv: bool = p[0] == "10" or (p[0] == "192" and p[1] == "168") \
				or (p[0] == "172" and int(p[1]) >= 16 and int(p[1]) <= 31)
		if not is_priv:
			lan_ok = false
	t.expect(lan_ok, "lan 组全为私网段")


func _snapshot(t) -> void:
	var m := RoomManagerGd.new()
	var out: Array = m.create_room(1000, "房主", {}, "cid-1000")
	t.expect(_count(out, "s_room_state") == 1, "建房成功")
	var snap: Array = m.discovery_snapshot()
	t.expect_eq(snap.size(), 1, "快照含 1 个房间")
	if snap.size() == 1:
		t.expect_eq(int(snap[0]["players"]), 1, "人数=1")
		t.expect(bool(snap[0]["open"]), "未开局 open=true")
	var j: Array = m.join_room(1001, "朋友", str(snap[0]["code"]), "cid-1001")
	t.expect(_count(j, "s_room_state") >= 1, "第二人加入(加入者+房内广播)")
	t.expect_eq(int(m.discovery_snapshot()[0]["players"]), 2, "人数=2")
	# 房主补 1 个 AI: 发现页人数只计真人(任务反馈)
	m.rooms[str(snap[0]["code"])].sit_bot()
	var snap_bots: Array = m.discovery_snapshot()
	t.expect_eq(snap_bots.size(), 1, "AI 补位后仍有空位则公开")
	t.expect_eq(int(snap_bots[0]["players"]), 2, "人数不含 AI(=2)")
	# 满员房间不公开
	var full_code := str(snap[0]["code"])
	for peer in range(1002, 1005):
		m.join_room(peer, "p%d" % peer, full_code, "cid-%d" % peer)
	t.expect_eq(m.discovery_snapshot().size(), 0, "满员房间不公开")
	# 压测房间不公开
	var soak: Array = m.create_room(2000, "压测", {}, "cid-2000")
	t.expect(_count(soak, "s_room_state") == 1, "压测房创建")
	for c in m.rooms:
		m.rooms[c].soak = true
	t.expect_eq(m.discovery_snapshot().size(), 0, "压测房间不公开")


func _count(out: Array, event: String) -> int:
	var n := 0
	for m in out:
		if str(m["event"]) == event:
			n += 1
	return n
