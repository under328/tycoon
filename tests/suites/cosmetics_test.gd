## 装扮内容测试: 皮肤/卡面注册表完整性 + 像素画美术校验 + 购买装备闭环。
## 重点: 像素画调色板缺色会渲染成品红(显式兜底色), 必须逐格校验键存在。
extends RefCounted

const SkinsLib = preload("res://src/client/ui/skins.gd")
const AvatarPix = preload("res://src/client/ui/avatar_pix.gd")
const CardViewGd = preload("res://src/client/ui/card_view.gd")
const WalletGd = preload("res://src/autoload/wallet.gd")
const RoomManagerGd = preload("res://src/server/room_manager.gd")

const NEW_SKINS := ["skin_dball", "skin_ninja", "skin_rx"]
const NEW_CARDS := ["card_dball", "card_ninja", "card_rx"]
const KNOWN_MOTIFS := ["washi", "sumi", "hi", "umi", "wukong", "cyber",
		"dball", "ninja", "rx"]


func run(t) -> void:
	_registry(t)
	_pixel_avatars(t)
	_joker_pixel_art(t)
	_buy_flow(t)
	_server_pool(t)


func _registry(t) -> void:
	var skin_ids: Array = []
	for s in SkinsLib.SKINS:
		skin_ids.append(str(s["id"]))
	for id in NEW_SKINS:
		t.expect(skin_ids.has(id), "新皮肤 %s 已上架" % id)
		for s in SkinsLib.SKINS:
			if str(s["id"]) == id:
				t.expect_eq(int(s["price"]), 100, "%s 定价 100 钻" % id)
	var card_ids: Array = []
	for c in SkinsLib.CARDS:
		card_ids.append(str(c["id"]))
		for key in ["id", "motif", "name", "price", "face", "border", "red",
				"black", "shadow", "back", "speckle"]:
			t.expect((c as Dictionary).has(key), "卡面 %s 缺字段 %s" % [c["id"], key])
		t.expect(KNOWN_MOTIFS.has(str(c["motif"])), "卡面 %s motif 已实现" % c["id"])
	for id in NEW_CARDS:
		t.expect(card_ids.has(id), "新卡面 %s 已上架" % id)
		var pal: Dictionary = SkinsLib.palette(id)
		t.expect_eq(str(pal["id"]), id, "卡面 %s 可查得调色板" % id)
		t.expect_eq(int(pal["price"]), 100, "%s 定价 100 钻" % id)


func _pixel_avatars(t) -> void:
	for s in SkinsLib.SKINS:
		var id := str(s["id"])
		t.expect(AvatarPix.ART_IDS.has(id), "皮肤 %s 有像素头像" % id)
		var pal: Dictionary = AvatarPix.PALETTES[id]
		var g: Dictionary = AvatarPix._grid(id)
		t.expect(g.size() > 200, "皮肤 %s 像素画有内容(%d 格)" % [id, g.size()])
		var missing := {}
		for cell in g:
			if not pal.has(str(g[cell])):
				missing[str(g[cell])] = true
		t.expect(missing.is_empty(),
				"皮肤 %s 无缺色调色键 %s" % [id, str(missing.keys())])
		var outlined := g.has(Vector2i(0, 0)) or g.has(Vector2i(31, 31))
		t.expect(not outlined, "皮肤 %s 画幅未顶满画布(留描边空间)" % id)


func _joker_pixel_art(t) -> void:
	var scr = load("res://src/client/ui/card_view.gd")  # 常量表在脚本资源上取
	var consts: Dictionary = scr.get_script_constant_map()
	var art_names := ["PIX_DBALL", "PIX_NINJA", "PIX_RX"]
	for name in art_names:
		t.expect(consts.has(name), "JOKER 像素画 %s 存在" % name)
		if not consts.has(name):
			continue
		var art: Array = consts[name]
		t.expect_eq(art.size(), 12, "%s 12 行" % name)
		var w := (art[0] as String).length()
		var uniform := true
		for row in art:
			if (row as String).length() != w:
				uniform = false
		t.expect(uniform, "%s 行宽一致" % name)


func _buy_flow(t) -> void:
	var w = WalletGd.new()
	w.save_path = "user://test_cosmetics_wallet.cfg"
	w.diamonds = 0
	t.expect(not w.buy("skin", "skin_dball", 100), "钻石不足购买被拒")
	t.expect(not w.is_owned("skin", "skin_dball"), "未购得皮肤")
	w.diamonds = 100
	t.expect(w.buy("skin", "skin_dball", 100), "足额购买皮肤成功")
	t.expect_eq(int(w.diamonds), 0, "扣款 100 钻")
	t.expect(w.is_owned("skin", "skin_dball"), "皮肤已拥有")
	w.equip("skin", "skin_dball")
	t.expect(w.is_equipped("skin", "skin_dball"), "皮肤可装备")
	t.expect(not w.buy("skin", "skin_dball", 100), "重复购买被拒")
	w.diamonds = 100
	t.expect(w.buy("card", "card_rx", 100), "足额购买卡面成功")
	w.equip("card", "card_rx")
	t.expect(w.is_equipped("card", "card_rx"), "卡面可装备")
	w.queue_free()


func _server_pool(t) -> void:
	for id in NEW_SKINS:
		t.expect(RoomManagerGd.SKINS.has(id), "服务端 AI 皮肤池含 %s" % id)
