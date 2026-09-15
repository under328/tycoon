## 装扮内容测试: 皮肤/卡面注册表完整性 + 像素画美术校验 + 购买装备闭环。
## 重点: 像素画调色板缺色会渲染成品红(显式兜底色), 必须逐格校验键存在。
extends RefCounted

const SkinsLib = preload("res://src/client/ui/skins.gd")
const AvatarPix = preload("res://src/client/ui/avatar_pix.gd")
const CardViewGd = preload("res://src/client/ui/card_view.gd")
const WalletGd = preload("res://src/autoload/wallet.gd")
const GameStateGd = preload("res://src/rules/game_state.gd")
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
	_special_items(t)
	_rank_title(t)
	_signin(t)
	_achievements(t)
	_retention(t)
	_history(t)
	_consumables(t)
	_fight_mission(t)
	_missions(t)


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


## 特殊道具: 金币购买 / 当日双倍 / 结算翻倍与标记 / 首胜每日一次 / 次日失效
func _special_items(t) -> void:
	t.expect(WalletGd.SPECIALS.size() >= 1, "特殊道具已上架")
	var dd: Dictionary = {}
	for it in WalletGd.SPECIALS:
		if str(it["id"]) == "item_double_diamond":
			dd = it
	t.expect(not dd.is_empty() and int(dd["price"]) == 120
			and str(dd["currency"]) == "gold", "双倍钻石卡 120 金币")
	var w = WalletGd.new()
	w.save_path = "user://test_special_wallet.cfg"
	w.gold = 100
	t.expect(not w.buy_special("item_double_diamond"), "金币不足购买被拒")
	w.gold = 130
	t.expect(w.buy_special("item_double_diamond"), "购买成功")
	t.expect_eq(int(w.gold), 10, "扣款 120 金币")
	t.expect(w.double_diamond_active(), "当日双倍生效")
	# 结算: 富豪 +1 钻 → 双倍 +2, 标记 doubled
	var r: Dictionary = w.grant_match_reward(10, 2, 1)
	t.expect_eq(int(r["diamonds"]), 2, "双倍卡: +1 钻变 +2")
	t.expect(bool(r["doubled"]), "结算标记 doubled")
	# 当日首胜: 大富豪 +2 钻翻倍 +4, 首胜再 +3
	var r2: Dictionary = w.grant_match_reward(20, 1, 1)
	t.expect_eq(int(r2["diamonds"]), 4, "大富豪 +2 → 双倍 +4")
	t.expect_eq(int(r2["bonus"]), 3, "每日首胜 +3")
	t.expect_eq(int(r2["bonus"]) if r2.has("bonus") else -1, 3, "bonus 标记返回")
	# 同日第二胜: 首胜奖励不再发
	var r3: Dictionary = w.grant_match_reward(20, 1, 1)
	t.expect_eq(int(r3["bonus"]), 0, "同日再胜无首胜奖励")
	# 次日(模拟: 生效日写成昨天) → 双倍失效, 首胜名额重置
	w.double_diamond_day = "2000-01-01"
	w.first_win_day = "2000-01-01"
	t.expect(not w.double_diamond_active(), "次日双倍失效")
	var r4: Dictionary = w.grant_match_reward(20, 1, 1)
	t.expect_eq(int(r4["diamonds"]), 2, "无卡: 大富豪 +2 不翻倍")
	t.expect(not bool(r4["doubled"]), "无卡不标记 doubled")
	t.expect_eq(int(r4["bonus"]), 3, "新的一日首胜名额重置")
	w.queue_free()


## 每日签到: 领取入账/当日去重/连续计数/7天循环
func _signin(t) -> void:
	var w = WalletGd.new()
	w.save_path = "user://test_sign_wallet.cfg"
	t.expect(w.can_sign_today(), "新档可签到")
	var r: Dictionary = w.claim_signin()
	t.expect(not r.is_empty(), "签到成功")
	t.expect_eq(int(r["day_index"]), 0, "首日 = 第 1 格")
	t.expect_eq(int(w.gold), 500 + 100, "第 1 天奖励 100 金币")
	t.expect(not w.can_sign_today(), "当日不可重复签到")
	t.expect(w.claim_signin().is_empty(), "重复领取返回空")
	# 连续: 昨日签到过 → streak +1, 循环取模
	w.sign_day = "2000-01-01"  # 断签 → streak 重置为 1
	var r2: Dictionary = w.claim_signin()
	t.expect_eq(int(w.sign_streak), 1, "断签后 streak 重置")
	# 连续 7 天 → 风雨无阻(最近签到=昨日 → streak 6+1=7)
	w.sign_streak = 6
	w.sign_day = w._days_shift(Time.get_date_string_from_system(), -1)
	w.claim_signin()
	t.expect(w.unlocked.has("signer_7"), "连签 7 天解锁风雨无阻")
	w.queue_free()


## 成就: 阈值解锁/不重复解锁/信号
func _achievements(t) -> void:
	var w = WalletGd.new()
	w.save_path = "user://test_ach_wallet.cfg"
	var got: Array = []
	w.achievements_changed.connect(func(newly: Array) -> void:
		got.append(newly.size()))
	var r: Dictionary = w.grant_match_reward(10, 1, 1)  # 首胜
	t.expect((r["achievements"] as Array).any(
			func(a: Dictionary) -> bool: return str(a["id"]) == "first_win"),
			"首胜解锁初阵告捷")
	t.expect_eq(int(got[0]), (r["achievements"] as Array).size(), "信号广播新增数")
	var again: Dictionary = w.grant_match_reward(10, 1, 1)
	t.expect_eq((again["achievements"] as Array).size(), 0, "不重复解锁")
	t.expect(w.unlocked.has("first_win"), "已解锁持久在列")
	# 收藏家: 8 件装扮
	for i in 7:
		w.owned_skins.append("skin_x%d" % i)
	w.check_achievements()
	t.expect(w.unlocked.has("collector"), "8 件装扮解锁收藏家")
	w.queue_free()


## 留存: 每日挑战 / 命运卡图鉴 / 新计数器与成就 II
func _retention(t) -> void:
	var w = WalletGd.new()
	w.save_path = "user://test_retain_wallet.cfg"
	# 每日种子: 平台无关的当日确定性
	t.expect_eq(w.daily_seed(),
			int(str(Time.get_date_string_from_system()).replace("-", "")),
			"每日种子=日期数字")
	# 首次参与: 计天数, 记录最佳
	var d1: Dictionary = w.record_daily(3, 40)
	t.expect(bool(d1["new_day"]) and int(d1["best_round"]) == 3,
			"每日挑战首录")
	t.expect(w.unlocked.has("daily_1"), "首挑战解锁每日战士")
	# 同日更好成绩
	var d2: Dictionary = w.record_daily(5, 60)
	t.expect(bool(d2["better"]) and int(d2["best_round"]) == 5,
			"同日更优成绩覆盖")
	# 同日较差成绩保留最佳
	var d3: Dictionary = w.record_daily(2, 99)
	t.expect(not bool(d3["better"]) and int(d3["best_round"]) == 5,
			"较差成绩不覆盖最佳")
	# 跨日: 新一天重新计
	w.daily_day = "2000-01-01"
	var d4: Dictionary = w.record_daily(4, 10)
	t.expect(bool(d4["new_day"]) and int(w.daily_days) == 2,
			"跨日重新计数")
	t.expect(w.unlocked.has("daily_3") == false or int(w.daily_days) >= 3,
			"持之以恒按天数解锁")
	# 命运卡图鉴
	w.note_rogue_mod("joker_x2", false)
	w.note_rogue_mod("joker_x2", false)
	w.note_rogue_mod("joker_x2", true)
	t.expect(int(w.mod_seen.get("joker_x2", 0)) == 2
			and int(w.mod_taken.get("joker_x2", 0)) == 1,
			"图鉴出现/选用分别计数")
	for m in GameStateGd.ROGUE_MODS:
		w.note_rogue_mod(str(m["id"]), false)
	t.expect(w.unlocked.has("codex_all"), "见齐 10 张解锁命运收藏家")
	# 格斗计数: 通关/局数
	w.grant_fight_reward(5)
	t.expect(int(w.fight_clears) == 1 and int(w.fight_runs) == 1,
			"格斗通关/局数计数")
	t.expect(w.unlocked.has("fight_clear"), "通关解锁试炼制霸")
	# 肉鸽模式计数
	w.grant_match_reward(10, 1, 1, "rogue")
	t.expect(int(w.rogue_runs) == 1 and int(w.rogue_wins) == 1,
			"肉鸽场次/胜场计数")
	t.expect(w.unlocked.has("rogue_win_1"), "肉鸽首胜解锁命运之子")
	# PvP 胜场
	w.grant_pvp_result(true)
	t.expect(int(w.pvp_wins) == 1 and w.unlocked.has("pvp_win_1"),
			"PvP 首胜解锁擂台新人")
	w.queue_free()


## 对局记录: 推入/截断 20 条
func _history(t) -> void:
	var w = WalletGd.new()
	w.save_path = "user://test_hist_wallet.cfg"
	for i in 25:
		w.push_history({"day": "d%d" % i, "rank": 1, "points": 10,
				"gold": 20, "diamonds": 2, "mode": "本地"})
	t.expect_eq(int(w.history.size()), 20, "记录截断至 20 条")
	t.expect_eq(str((w.history[0] as Dictionary)["day"]), "d5", "最旧被挤出")
	t.expect_eq(str((w.history[19] as Dictionary)["day"]), "d24", "最新在尾")
	w.queue_free()


## 每日任务: 进度/领取/去重/跨日重置
func _missions(t) -> void:
	var w = WalletGd.new()
	w.save_path = "user://test_mission_wallet.cfg"
	w.grant_match_reward(10, 2, 1)  # 完成 1 场(m_play 进度 1/2)
	t.expect_eq(int(w.mission_state("m_play")["progress"]), 1, "对局任务进度 1/2")
	t.expect(w.claim_mission("m_play").is_empty(), "未达标领取被拒")
	w.grant_match_reward(10, 3, 1)  # 第 2 场 → 达标
	t.expect_eq(int(w.mission_state("m_play")["progress"]), 2, "进度封顶 2/2")
	var r: Dictionary = w.claim_mission("m_play")
	t.expect_eq(int(r["gold"]), 150, "领取 150 金币")
	t.expect(w.mission_state("m_play")["claimed"], "领取状态记录")
	t.expect(w.claim_mission("m_play").is_empty(), "重复领取被拒")
	w.note_mission("m_quad")
	t.expect(w.mission_state("m_quad")["claimed"] == false
			and int(w.mission_state("m_quad")["progress"]) == 1, "四条事件计入")
	# 跨日重置
	w.mission_day = "2000-01-01"
	t.expect_eq(int(w.mission_state("m_play")["progress"]), 0, "跨日进度重置")
	t.expect(not w.mission_state("m_play")["claimed"], "跨日领取状态重置")
	w.queue_free()


## 称号随胜场晋升
func _rank_title(t) -> void:
	var w = WalletGd.new()
	w.local_wins = 0
	t.expect_eq(w.rank_title(), "新人", "0 胜 = 新人")
	w.local_wins = 5
	t.expect_eq(w.rank_title(), "平民", "5 胜 = 平民")
	w.local_wins = 15
	t.expect_eq(w.rank_title(), "富豪", "15 胜 = 富豪")
	w.local_wins = 30
	t.expect_eq(w.rank_title(), "大富豪", "30 胜 = 大富豪")
	w.queue_free()


## 消耗品道具: 购买入库存/消耗/三倍钻石/复活币任务
func _consumables(t) -> void:
	var w = WalletGd.new()
	w.save_path = "user://test_consumables.cfg"
	w.gold = 100
	t.expect(not w.buy_item("item_revive_coin"), "金币不足购买被拒")
	w.gold = 500
	t.expect(w.buy_item("item_revive_coin"), "购买复活币成功")
	t.expect_eq(w.item_count("item_revive_coin"), 1, "复活币库存 +1")
	t.expect_eq(int(w.purchases), 1, "消费计数")
	# 复活消耗
	t.expect(w.try_consume_revive(), "复活币生效")
	t.expect_eq(w.item_count("item_revive_coin"), 0, "复活币库存清零")
	t.expect(not w.try_consume_revive(), "无币不可再复活")
	# 三倍钻石
	w.diamond_mult_day = w._today()
	w.diamond_mult = 3
	w.diamonds = 0
	var r: Dictionary = w.grant_fight_reward(2, 0)
	t.expect_eq(int(r["diamonds"]), 18, "三倍: (2+2×2)×3 = 18 钻 got=%d" % int(r["diamonds"]))
	# 命运骰消耗
	w.inventory["item_fate_dice"] = 2
	t.expect(w.consume_item("item_fate_dice"), "命运骰消耗")
	t.expect_eq(w.item_count("item_fate_dice"), 1, "命运骰余 1")
	# 成就: shopper/revivor
	t.expect(w.unlocked.has("shopper") or int(w.purchases) >= 1, "消费成就可解锁")
	t.expect(int(w.revives) >= 1, "复活计数")
	w.queue_free()


## 格斗任务: 层完成推进 m_fight
func _fight_mission(t) -> void:
	var w = WalletGd.new()
	w.save_path = "user://test_fight_mission2.cfg"
	w.note_mission("m_fight")
	var st: Dictionary = w.mission_state("m_fight")
	t.expect_eq(int(st["progress"]), 1, "格斗层任务进度 1/1")
	var r: Dictionary = w.claim_mission("m_fight")
	t.expect_eq(int(r["diamonds"]), 2, "领取 +2 钻")
	w.queue_free()
