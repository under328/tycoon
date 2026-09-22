## 经济与装扮内核（autoload: Wallet）。
## 金币/钻石余额、皮肤与卡面的拥有/装备状态、本地战绩统计。
## 自动存档: 变更打脏标记 → 每 10s 周期保存; 退出/切后台时强制保存;
## 原子写入(tmp→rename) + .bak 备份回退, 防止存档损坏。
extends Node

signal balance_changed
signal equipped_changed
signal achievements_changed(newly: Array)

const SAVE_PATH := "user://wallet.cfg"
const AUTOSAVE_SEC := 10.0

## 本地对局奖励(按最终名次 1..4): [金币, 钻石]
const GOLD_PER_POINT := 1        # 1 积分 = 1 金币(再乘输赢倍率)

const FIRST_WIN_DIAMONDS := 2
const CODEX_TARGET := 11   # 命运卡图鉴全收集目标   # 每日首胜奖励钻石数
const HISTORY_MAX := 20         # 对局记录保留条数
const REPLAY_MAX := 10          # 对局回放保留场数
## 成就奖励: 每解锁 1 枚成就 +2 钻石; 集齐全部成就额外 +36 钻石
const ACH_REWARD_DIAMONDS := 2
const ACH_ALL_BONUS := 36

## 每日签到奖励(7 天一循环): streak = 连续签到天数, 取模循环
const SIGN_REWARDS := [
	{"gold": 60}, {"gold": 90}, {"diamonds": 1}, {"gold": 120},
	{"gold": 150}, {"diamonds": 2}, {"diamonds": 3},
]

## 每日任务(按日重置): target 达成后可领奖励
const MISSIONS := [
	{"id": "m_win", "name": "赢得一场胜利", "target": 1, "reward_diamonds": 2},
	{"id": "m_play", "name": "完成 2 场对局", "target": 2, "reward_gold": 100},
	{"id": "m_quad", "name": "打出一次四条(炸弹)", "target": 1, "reward_diamonds": 1},
	{"id": "m_fight", "name": "格斗试炼通过 1 层", "target": 1, "reward_diamonds": 1},
]

## 成就目录: cond 在 check_achievements 里按 id 求值(基于持久化统计)
const ACHIEVEMENTS := [
	{"id": "first_win", "name": "初阵告捷", "desc": "赢得第一场胜利"},
	{"id": "wins_10", "name": "渐入佳境", "desc": "累计获胜 10 场"},
	{"id": "wins_30", "name": "牌桌老手", "desc": "累计获胜 30 场"},
	{"id": "wins_50", "name": "所向披靡", "desc": "累计获胜 50 场"},
	{"id": "matches_30", "name": "常客", "desc": "完成 30 场对局"},
	{"id": "diamonds_50", "name": "小有积蓄", "desc": "累计获得 50 颗钻石"},
	{"id": "gold_1000", "name": "腰缠万贯", "desc": "金币持有量达到 1000"},
	{"id": "collector", "name": "收藏家", "desc": "拥有 8 件装扮(皮肤+卡面)"},
	{"id": "gambler", "name": "赌性坚强", "desc": "购入一张双倍钻石卡"},
	{"id": "signer_7", "name": "风雨无阻", "desc": "连续签到满 7 天"},
	{"id": "fight_1", "name": "初入试炼", "desc": "完成一次格斗试炼"},
	{"id": "fight_5", "name": "登塔者", "desc": "格斗试炼打进第 5 回合(BOSS 战)"},
	{"id": "fight_boss_3", "name": "屠龙勇士", "desc": "通关格斗试炼 3 次"},
	{"id": "shopper", "name": "大买家", "desc": "商城累计消费 5 次"},
	{"id": "revivor", "name": "向死而生", "desc": "使用复活币重返战场"},
	{"id": "fight_clear", "name": "试炼制霸", "desc": "通关格斗试炼(击败 BOSS)"},
	{"id": "fight_clear_5", "name": "试炼大师", "desc": "通关格斗试炼 5 次"},
	{"id": "daily_1", "name": "每日战士", "desc": "完成一次每日挑战"},
	{"id": "daily_3", "name": "持之以恒", "desc": "累计 3 天参与每日挑战"},
	{"id": "rogue_win_1", "name": "命运之子", "desc": "肉鸽模式取得 1 场胜利"},
	{"id": "rogue_win_10", "name": "命运主宰", "desc": "肉鸽模式取得 10 场胜利"},
	{"id": "codex_all", "name": "命运收藏家", "desc": "图鉴见齐全部 10 张命运卡"},
	{"id": "pvp_win_1", "name": "擂台新人", "desc": "联机格斗对战取得 1 场胜利"},
	{"id": "wins_100", "name": "百战王者", "desc": "累计获胜 100 场"},
	{"id": "diamonds_500", "name": "钻石大亨", "desc": "累计获得 500 颗钻石"},
	{"id": "gold_5000", "name": "富可敌国", "desc": "金币持有量达到 5000"},
	{"id": "quads_10", "name": "爆破专家", "desc": "累计打出 10 次四条(炸弹)"},
	{"id": "signer_30", "name": "签到达人", "desc": "累计签到 30 天"},
	{"id": "shopper_20", "name": "购物狂", "desc": "商城累计消费 20 次"},
	{"id": "fight_clear_10", "name": "试炼传说", "desc": "通关格斗试炼 10 次"},
	{"id": "endless_3", "name": "无尽远征", "desc": "无尽挑战到达第 3 层"},
	{"id": "rogue_win_30", "name": "命运之主", "desc": "肉鸽模式取得 30 场胜利"},
	{"id": "codex_take_30", "name": "与命运共舞", "desc": "命运卡累计选用 30 次"},
	{"id": "relics_all", "name": "奇物收藏家", "desc": "格斗奇物图鉴收集过半"},
	{"id": "daily_7", "name": "每日标兵", "desc": "累计 7 天参与每日挑战"},
	{"id": "pvp_win_10", "name": "擂台名将", "desc": "联机格斗对战取得 10 场胜利"},
]

## 特殊道具: effect 决定生效方式
##   dday=当日对局钻石×2  tday=×3(覆盖双倍)  revive=格斗死亡自动复活
##   fdice=肉鸽命运二选一可重抽候选  rticket=格斗选牌额外重抽
##   clearr=购买即清空全部战绩(不可逆, 面板二次确认)
##   stack=true 的道具按库存计数、随用随消耗
## 定价锚点: 钻石收入约 2-6/场(身份奖励+格斗楼层), 金币约 15-50/场;
##   钻石消耗品 25-40 ≈ 数场积攒, 金币日增益卡 100-260 ≈ 数场内可得
const SPECIALS := [
	{"id": "item_double_diamond", "name": "双倍钻石卡", "price": 150,
		"currency": "gold", "effect": "dday", "stack": false,
		"desc": "激活后至当日结束, 对局获得的钻石 ×2"},
	{"id": "item_triple_diamond", "name": "三倍钻石卡", "price": 350,
		"currency": "gold", "effect": "tday", "stack": false,
		"desc": "激活后至当日结束, 对局获得的钻石 ×3 (覆盖双倍卡)"},
	{"id": "item_revive_coin", "name": "复活币", "price": 160,
		"currency": "gold", "effect": "revive", "stack": true,
		"desc": "格斗试炼倒下时自动消耗 1 枚, 以 60% 生命原地复活"},
	{"id": "item_fate_dice", "name": "命运骰", "price": 60,
		"currency": "diamonds", "effect": "fdice", "stack": true,
		"desc": "肉鸽命运二选一界面可掷骰重抽候选(每次消耗 1 枚)"},
	{"id": "item_reroll_ticket", "name": "重抽券", "price": 35,
		"currency": "diamonds", "effect": "rticket", "stack": true,
		"desc": "格斗选牌界面额外重抽次数 +1 (每次消耗 1 张)"},
	{"id": "item_clear_record", "name": "清空战绩", "price": 80,
		"currency": "diamonds", "effect": "clearr", "stack": false,
		"desc": "立即清空全部对局记录、胜负统计与各模式战绩(不可逆)"},
	{"id": "item_counter_day", "name": "记牌器·日卡", "price": 40,
		"currency": "diamonds", "effect": "cday", "stack": false,
		"desc": "激活后至当日结束, 本机所有对局均可使用记牌器"},
	{"id": "item_counter_once", "name": "记牌器·次卡", "price": 80,
		"currency": "gold", "effect": "conce", "stack": true,
		"desc": "1 张 = 1 场对局的记牌器使用权, 开局自动消耗 1 张"},
]

var gold := 500       # 默认 500 金币
var diamonds := 0     # 默认 0 钻石
var owned_skins: Array = ["skin_default"]
var owned_cards: Array = ["card_washi"]
var equipped_skin := "skin_default"
var equipped_card := "card_washi"
var double_diamond_day := ""   # 双倍钻石卡生效日期(YYYY-MM-DD, 当地时区)
var first_win_day := ""        # 每日首胜已领取日期(空=今日未领)
var sign_day := ""             # 最近一次签到日期
var sign_streak := 0           # 连续签到天数(7 天一循环)
var win_streak := 0            # 对局连胜场次(结算加成, 输即清零)
var sign_total := 0            # 累计签到天数
var diamonds_earned := 0       # 累计获得钻石(成就统计)
var special_bought := 0        # 累计购入特殊道具数(成就统计)
var unlocked: Array = []       # 已解锁成就 id
var history: Array = []        # 对局记录(最近 HISTORY_MAX 条)
var replays: Array = []        # 对局回放(最近 REPLAY_MAX 场: {v,rogue,seed,actions,day,mode})
var fight_best := 0            # 格斗试炼历史最远回合(1-5)
var fight_runs := 0            # 累计格斗局数
var fight_bosses := 0          # 累计击败 Boss 数
var fight_clears := 0          # 格斗试炼通关次数
var rogue_runs := 0            # 肉鸽模式局数
var rogue_wins := 0            # 肉鸽模式胜场
var pvp_wins := 0              # 联机格斗对战胜场
var daily_day := ""            # 每日挑战最近参与日期
var daily_best_round := 0      # 当日最佳到达回合(0-5)
var daily_best_hp := 0         # 当日最佳剩余生命百分比(0-100)
var daily_days := 0            # 累计参与每日挑战天数
var mod_seen := {}             # 命运卡图鉴: mod_id → 出现次数
var mod_taken := {}            # 命运卡图鉴: mod_id → 选用次数
var relic_seen := {}           # 格斗奇物图鉴: sp_id → 获得次数
var purchases := 0             # 累计商城消费次数
var revives := 0               # 累计使用复活币次数
var inventory := {}            # 消耗品库存: id -> 数量
var diamond_mult_day := ""     # 三倍钻石生效日期
var diamond_mult := 1          # 当前钻石倍率
var mission_day := ""          # 任务所属日期
var mission_progress := {}     # id -> 进度
var mission_claimed := {}      # id -> true(已领取)
var quads := 0                 # 累计打出四条次数(成就统计)
var endless_best := 0          # 无尽挑战历史最高层(成就统计)
var counter_day := ""          # 记牌器·日卡生效日期(空=未激活)
var all_ach_bonus := false     # 集齐全部成就的 +36 钻奖励是否已发放

## 本地战绩统计
var local_matches := 0
var local_wins := 0

var save_path := SAVE_PATH   # 测试可覆盖
var _dirty := false
var _save_timer := 0.0


func _ready() -> void:
	load_wallet()


func _process(delta: float) -> void:
	_save_timer += delta
	if _dirty and _save_timer >= 1.0:
		_save_timer = 0.0
		save_wallet()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, \
		NOTIFICATION_APPLICATION_PAUSED, \
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if _dirty:
				save_wallet()
				_dirty = false


func _reset_defaults() -> void:
	gold = 500
	diamonds = 0
	owned_skins = ["skin_default"]
	owned_cards = ["card_washi"]
	equipped_skin = "skin_default"
	equipped_card = "card_washi"
	double_diamond_day = ""
	first_win_day = ""
	sign_day = ""
	sign_streak = 0
	sign_total = 0
	diamonds_earned = 0
	special_bought = 0
	unlocked = []
	history = []
	fight_best = 0
	fight_runs = 0
	fight_bosses = 0
	fight_clears = 0
	rogue_runs = 0
	rogue_wins = 0
	pvp_wins = 0
	daily_day = ""
	daily_best_round = 0
	daily_best_hp = 0
	daily_days = 0
	mod_seen = {}
	mod_taken = {}
	relic_seen = {}
	purchases = 0
	revives = 0
	inventory = {}
	diamond_mult_day = ""
	diamond_mult = 1
	mission_day = ""
	mission_progress = {}
	mission_claimed = {}
	quads = 0
	endless_best = 0
	counter_day = ""
	all_ach_bonus = false
	local_matches = 0
	local_wins = 0


func load_wallet() -> void:
	_reset_defaults()
	# 主存档优先; 损坏/缺失时回退 .bak 备份
	if _read_into(save_path):
		return
	_read_into(save_path + ".bak")


func _read_into(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return false
	# 损坏/截断的文件会"成功加载"但内容为空 → 校验必需键
	if not cf.has_section_key("wallet", "gold"):
		return false
	gold = int(cf.get_value("wallet", "gold", 500))
	diamonds = int(cf.get_value("wallet", "diamonds", 0))
	var skins: Array = cf.get_value("wallet", "owned_skins", ["skin_default"])
	if skins.is_empty():
		skins = ["skin_default"]
	owned_skins = skins
	var cards: Array = cf.get_value("wallet", "owned_cards", ["card_washi"])
	if cards.is_empty():
		cards = ["card_washi"]
	owned_cards = cards
	equipped_skin = str(cf.get_value("wallet", "equipped_skin", "skin_default"))
	equipped_card = str(cf.get_value("wallet", "equipped_card", "card_washi"))
	local_matches = int(cf.get_value("wallet", "local_matches", 0))
	local_wins = int(cf.get_value("wallet", "local_wins", 0))
	double_diamond_day = str(cf.get_value("wallet", "dd_day", ""))
	first_win_day = str(cf.get_value("wallet", "fw_day", ""))
	sign_day = str(cf.get_value("wallet", "sign_day", ""))
	sign_streak = int(cf.get_value("wallet", "sign_streak", 0))
	sign_total = int(cf.get_value("wallet", "sign_total", 0))
	diamonds_earned = int(cf.get_value("wallet", "diamonds_earned", 0))
	special_bought = int(cf.get_value("wallet", "special_bought", 0))
	var ul: Array = cf.get_value("wallet", "unlocked", [])
	unlocked = ul
	var hs: Array = cf.get_value("wallet", "history", [])
	history = hs
	var rps: Array = cf.get_value("wallet", "replays", [])
	replays = rps
	fight_best = int(cf.get_value("wallet", "fight_best", 0))
	fight_runs = int(cf.get_value("wallet", "fight_runs", 0))
	fight_bosses = int(cf.get_value("wallet", "fight_bosses", 0))
	fight_clears = int(cf.get_value("wallet", "fight_clears", 0))
	rogue_runs = int(cf.get_value("wallet", "rogue_runs", 0))
	rogue_wins = int(cf.get_value("wallet", "rogue_wins", 0))
	pvp_wins = int(cf.get_value("wallet", "pvp_wins", 0))
	daily_day = str(cf.get_value("wallet", "daily_day", ""))
	daily_best_round = int(cf.get_value("wallet", "daily_best_round", 0))
	daily_best_hp = int(cf.get_value("wallet", "daily_best_hp", 0))
	daily_days = int(cf.get_value("wallet", "daily_days", 0))
	var ms = cf.get_value("wallet", "mod_seen", {})
	mod_seen = ms if ms is Dictionary else {}
	var mt = cf.get_value("wallet", "mod_taken", {})
	mod_taken = mt if mt is Dictionary else {}
	var rs = cf.get_value("wallet", "relic_seen", {})
	relic_seen = rs if rs is Dictionary else {}
	purchases = int(cf.get_value("wallet", "purchases", 0))
	revives = int(cf.get_value("wallet", "revives", 0))
	var inv = cf.get_value("wallet", "inventory", {})
	inventory = inv if inv is Dictionary else {}
	diamond_mult_day = str(cf.get_value("wallet", "dm_day", ""))
	diamond_mult = int(cf.get_value("wallet", "dm_mult", 1))
	mission_day = str(cf.get_value("wallet", "mission_day", ""))
	var mp = cf.get_value("wallet", "mission_progress", {})
	mission_progress = mp if mp is Dictionary else {}
	var mc = cf.get_value("wallet", "mission_claimed", {})
	mission_claimed = mc if mc is Dictionary else {}
	quads = int(cf.get_value("wallet", "quads", 0))
	endless_best = int(cf.get_value("wallet", "endless_best", 0))
	counter_day = str(cf.get_value("wallet", "counter_day", ""))
	all_ach_bonus = bool(cf.get_value("wallet", "all_ach_bonus", false))
	return true


## 原子写入: 先写临时文件再改名, 避免写入中断导致存档损坏。
func save_wallet() -> void:
	var tmp := save_path + ".tmp"
	var cf := ConfigFile.new()
	cf.set_value("wallet", "gold", gold)
	cf.set_value("wallet", "diamonds", diamonds)
	cf.set_value("wallet", "owned_skins", owned_skins)
	cf.set_value("wallet", "owned_cards", owned_cards)
	cf.set_value("wallet", "equipped_skin", equipped_skin)
	cf.set_value("wallet", "equipped_card", equipped_card)
	cf.set_value("wallet", "local_matches", local_matches)
	cf.set_value("wallet", "local_wins", local_wins)
	cf.set_value("wallet", "dd_day", double_diamond_day)
	cf.set_value("wallet", "fw_day", first_win_day)
	cf.set_value("wallet", "sign_day", sign_day)
	cf.set_value("wallet", "sign_streak", sign_streak)
	cf.set_value("wallet", "sign_total", sign_total)
	cf.set_value("wallet", "diamonds_earned", diamonds_earned)
	cf.set_value("wallet", "special_bought", special_bought)
	cf.set_value("wallet", "unlocked", unlocked)
	cf.set_value("wallet", "history", history)
	cf.set_value("wallet", "replays", replays)
	cf.set_value("wallet", "fight_best", fight_best)
	cf.set_value("wallet", "fight_runs", fight_runs)
	cf.set_value("wallet", "fight_bosses", fight_bosses)
	cf.set_value("wallet", "fight_clears", fight_clears)
	cf.set_value("wallet", "rogue_runs", rogue_runs)
	cf.set_value("wallet", "rogue_wins", rogue_wins)
	cf.set_value("wallet", "pvp_wins", pvp_wins)
	cf.set_value("wallet", "daily_day", daily_day)
	cf.set_value("wallet", "daily_best_round", daily_best_round)
	cf.set_value("wallet", "daily_best_hp", daily_best_hp)
	cf.set_value("wallet", "daily_days", daily_days)
	cf.set_value("wallet", "mod_seen", mod_seen)
	cf.set_value("wallet", "mod_taken", mod_taken)
	cf.set_value("wallet", "relic_seen", relic_seen)
	cf.set_value("wallet", "purchases", purchases)
	cf.set_value("wallet", "revives", revives)
	cf.set_value("wallet", "inventory", inventory)
	cf.set_value("wallet", "dm_day", diamond_mult_day)
	cf.set_value("wallet", "dm_mult", diamond_mult)
	cf.set_value("wallet", "mission_day", mission_day)
	cf.set_value("wallet", "mission_progress", mission_progress)
	cf.set_value("wallet", "mission_claimed", mission_claimed)
	cf.set_value("wallet", "quads", quads)
	cf.set_value("wallet", "endless_best", endless_best)
	cf.set_value("wallet", "counter_day", counter_day)
	cf.set_value("wallet", "all_ach_bonus", all_ach_bonus)
	if cf.save(tmp) == OK:
		DirAccess.rename_absolute(
				ProjectSettings.globalize_path(tmp),
				ProjectSettings.globalize_path(save_path))
	# 保留一份 .bak(上一版), 供损坏回退
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(
				ProjectSettings.globalize_path(save_path),
				ProjectSettings.globalize_path(save_path + ".bak"))
	_dirty = false


## 本地对局结算发放(名次 1..4)。返回 {gold, diamonds, doubled, bonus}。
## 场次结算: 金币 = 总积分 × 2 × 输赢倍率(可为负, 钱包下限 0);
## 钻石按最终身份: 大富豪 +2, 富豪 +1, 其余 +0。rank 1=大富豪…4=大贫民。
## 双倍钻石卡生效中(当日)钻石翻倍; 当日首胜额外 +2 钻(每日首胜奖励)。
func grant_match_reward(points: int, rank: int, stakes: int = 1,
		mode: String = "normal") -> Dictionary:
	var gold_delta := points * GOLD_PER_POINT * clampi(stakes, 1, 3)
	var dia_delta := 0
	match clampi(rank - 1, 0, 3):
		0:
			dia_delta = 1
		1:
			dia_delta = 1
	# 连胜奖励: 第 2 胜起每连胜 +10 金(封顶 +40)。钻石结算保持原口径。
	var streak_gold := 0
	if rank == 1:
		win_streak += 1
		streak_gold = 10 * mini(win_streak - 1, 4)
	else:
		win_streak = 0
	gold_delta += streak_gold
	gold = maxi(gold + gold_delta, 0)
	var doubled := double_diamond_active()
	if doubled:
		dia_delta *= 2
	var bonus := 0
	if rank == 1 and first_win_day != _today():
		bonus = FIRST_WIN_DIAMONDS
		first_win_day = _today()
	diamonds += dia_delta + bonus
	diamonds_earned += dia_delta + bonus
	local_matches += 1
	if mode == "rogue":
		rogue_runs += 1
		if rank == 1:
			rogue_wins += 1
	if rank == 1:
		local_wins += 1
	_mission_add("m_play", 1)
	if rank == 1:
		_mission_add("m_win", 1)
	var newly := check_achievements()
	_mark_dirty()
	balance_changed.emit()
	return {"gold": gold_delta, "diamonds": dia_delta, "points": points,
			"stakes": stakes, "doubled": doubled, "bonus": bonus,
			"streak": win_streak, "streak_gold": streak_gold,
			"achievements": newly}


## 购买: 成功扣钻石并加入拥有, 返回 true。
func buy(kind: String, item_id: String, price: int) -> bool:
	if is_owned(kind, item_id):
		return false
	if diamonds < price:
		return false
	diamonds -= price
	if kind == "skin":
		owned_skins.append(item_id)
	elif kind == "card":
		owned_cards.append(item_id)
	_mark_dirty()
	balance_changed.emit()
	return true


## 购买特殊道具(金币计价, 消耗/限时增益)。成功返回 true。
func buy_special(item_id: String) -> bool:
	for it in SPECIALS:
		if str(it["id"]) != item_id:
			continue
		var price := int(it["price"])
		if gold < price:
			return false
		gold -= price
		double_diamond_day = _today()  # 双倍钻石卡: 当日起效
		special_bought += 1
		check_achievements()
		_mark_dirty()
		balance_changed.emit()
		return true
	return false


## ── 格斗试炼 ──

## 通关/终局发放: 胜者层数越高钻石越多(1 + 层数); 记录历史最高层。
## daily=每日挑战(每日一次, 全额); 格斗试炼可重复, 奖励为其一半。
## 失败(won=false): 不发放钻石, 金币 -15(下限 0)。
func grant_fight_reward(floor_num: int, bosses: int = 0, daily: bool = false,
		won: bool = true) -> Dictionary:
	fight_runs += 1
	if floor_num >= 5:
		fight_clears += 1
	fight_bosses += maxi(bosses, 0)
	var d := 0
	var g := 0
	var mult := 1   # 函数级作用域: 返回值携带 mult, 不能声明在分支内
	if won:
		if diamond_triple_active():
			mult = 3
		elif double_diamond_active():
			mult = 2
		d = (1 + floor_num) * mult
		if not daily:
			d = maxi(int(d * 0.5), 1)   # 格斗试炼: 每日挑战奖励的一半
	else:
		g = -15   # 失败惩罚
	gold = maxi(gold + g, 0)
	diamonds += d
	diamonds_earned += d
	var best := maxi(fight_best, floor_num)
	var new_record := best != fight_best
	fight_best = best
	var newly := check_achievements()
	_mark_dirty()
	balance_changed.emit()
	return {"diamonds": d, "gold": g, "best": best, "new_record": new_record,
			"mult": mult, "achievements": newly}


## 联机格斗对战结算(客户端本地入账, 与联机大富豪同策略):
## 胜 +25 金币 +1 钻石, 败 -10 金币(下限 0); 计入场次/胜负/每日任务。
func grant_pvp_result(win: bool) -> Dictionary:
	var g := 25 if win else -10
	var d := 1 if win else 0
	gold = maxi(gold + g, 0)
	diamonds += d
	diamonds_earned += d
	local_matches += 1
	if win:
		local_wins += 1
		pvp_wins += 1
		_mission_add("m_win", 1)
	_mission_add("m_play", 1)
	var newly := check_achievements()
	push_history({
		"day": Time.get_date_string_from_system(),
		"mode": "格斗对战", "floor": 0, "rank": 1 if win else 2,
		"points": 0, "gold": g, "diamonds": d,
	})
	_mark_dirty()
	balance_changed.emit()
	return {"gold": g, "diamonds": d, "achievements": newly}


## ── 每日挑战(格斗试炼) ──

## 当日固定种子: 全设备同一天同一开局布局(日期数字, 平台无关)
func daily_seed() -> int:
	return int(str(_today()).replace("-", ""))


## 每日挑战每日一次: 今日是否已参与(参与即登记, 当日不可再开新局)
func daily_played_today() -> bool:
	return daily_day == _today()


## 登记今日参与(开局时调用): 占用当日名额并重置当日最佳
func mark_daily_played() -> void:
	if daily_played_today():
		return
	daily_day = _today()
	daily_best_round = 0
	daily_best_hp = 0
	daily_days += 1
	_mark_dirty()


## 每日挑战结算: 记录当日最佳(回合优先, 同回合比剩余生命%);
## 跨日首次参与计入天数。返回 {new_day, better, best_round, best_hp}
func record_daily(rounds: int, hp_pct: int) -> Dictionary:
	var today := _today()
	var new_day: bool = daily_day != today
	if new_day:   # 兜底: 正常流程开局已 mark_daily_played, 这里仅异常路径生效
		daily_day = today
		daily_best_round = 0
		daily_best_hp = 0
		daily_days += 1
	var better: bool = rounds > daily_best_round 			or (rounds == daily_best_round and hp_pct > daily_best_hp)
	if better:
		daily_best_round = maxi(rounds, 0)
		daily_best_hp = clampi(hp_pct, 0, 100)
	var newly := check_achievements()
	_mark_dirty()
	return {"new_day": new_day, "better": better,
			"best_round": daily_best_round, "best_hp": daily_best_hp,
			"achievements": newly}


## 命运卡图鉴计数(出现/选用)
func note_rogue_mod(mod_id: String, taken: bool) -> void:
	var id := str(mod_id)
	if taken:
		mod_taken[id] = int(mod_taken.get(id, 0)) + 1
		# 选用隐含出现过: 图鉴未见则补记一次(不重复计)
		if int(mod_seen.get(id, 0)) == 0:
			mod_seen[id] = 1
	else:
		mod_seen[id] = int(mod_seen.get(id, 0)) + 1
	_mark_dirty()
	check_achievements()   # 图鉴收集成就即时解锁(不等下局结算)


## 格斗奇物图鉴计数(本地/联机拾取都记)
func note_relic(sp_id: int) -> void:
	relic_seen[int(sp_id)] = int(relic_seen.get(int(sp_id), 0)) + 1
	_mark_dirty()
	check_achievements()   # 奇物收藏家成就即时解锁


## ── 每日任务 ──

## 跨日重置任务(惰性)
func _ensure_mission_day() -> void:
	if mission_day != _today():
		mission_day = _today()
		mission_progress = {}
		mission_claimed = {}
		_mark_dirty()


## 推进任务进度(封顶 target)
func _mission_add(id: String, n: int) -> void:
	_ensure_mission_day()
	var cur := int(mission_progress.get(id, 0))
	for m in MISSIONS:
		if str(m["id"]) == id:
			mission_progress[id] = mini(cur + n, int(m["target"]))
	_mark_dirty()


## 外部事件推进(如打出一枚四条)
func note_mission(id: String, n: int = 1) -> void:
	_mission_add(id, n)


func mission_state(id: String) -> Dictionary:
	_ensure_mission_day()
	var m := {}
	for it in MISSIONS:
		if str(it["id"]) == id:
			m = it
	return {"meta": m, "progress": int(mission_progress.get(id, 0)),
			"claimed": bool(mission_claimed.get(id, false))}


## 领取任务奖励(进度满且未领)。返回 {gold, diamonds} 或 {}
func claim_mission(id: String) -> Dictionary:
	_ensure_mission_day()
	if bool(mission_claimed.get(id, false)):
		return {}
	var meta := {}
	for m in MISSIONS:
		if str(m["id"]) == id:
			meta = m
	if meta.is_empty() or int(mission_progress.get(id, 0)) < int(meta["target"]):
		return {}
	mission_claimed[id] = true
	var g := int(meta.get("reward_gold", 0))
	var d := int(meta.get("reward_diamonds", 0))
	gold += g
	diamonds += d
	diamonds_earned += d
	check_achievements()
	_mark_dirty()
	balance_changed.emit()
	return {"gold": g, "diamonds": d}


## ── 每日签到(7 天一循环) ──

func can_sign_today() -> bool:
	return sign_day != _today()


## 领取今日签到: 奖励入账, 连续/累计计数推进, 返回 {day_index, gold, diamonds}
func claim_signin() -> Dictionary:
	if not can_sign_today():
		return {}
	var yesterday := _days_shift(_today(), -1)
	sign_streak = sign_streak + 1 if sign_day == yesterday else 1
	sign_day = _today()
	sign_total += 1
	var idx := (sign_streak - 1) % SIGN_REWARDS.size()
	var rw: Dictionary = SIGN_REWARDS[idx]
	var g := int(rw.get("gold", 0))
	var d := int(rw.get("diamonds", 0))
	gold += g
	diamonds += d
	diamonds_earned += d
	var newly := check_achievements()  # 签到可解锁『风雨无阻』
	_mark_dirty()
	balance_changed.emit()
	return {"day_index": idx, "gold": g, "diamonds": d, "achievements": newly}


func _days_shift(day: String, delta: int) -> String:
	# 昨日/明日日期串(本地时区): 直接用当前日推算, 与 _today() 同基准
	var now := Time.get_unix_time_from_system() as int
	var offset := int(Time.get_time_zone_from_system().get("offset", 0))
	return Time.get_date_string_from_unix_time(now + offset + delta * 86400)


## ── 成就 ──

## 按当前统计求值全部成就, 新解锁的入列并广播; 返回本次新解锁列表。
## 奖励: 每枚成就解锁 +2 钻石; 集齐全部成就额外 +36 钻石(一次性)。
func check_achievements() -> Array:
	var stats := {
		"wins": local_wins, "matches": local_matches,
		"diamonds_earned": diamonds_earned, "gold": gold,
		"skins": owned_skins.size(), "cards": owned_cards.size(),
		"special_bought": special_bought, "sign_streak": sign_streak,
		"fight_best": fight_best, "fight_runs": fight_runs,
		"fight_bosses": fight_bosses, "purchases": purchases,
		"revives": revives, "fight_clears": fight_clears,
		"rogue_wins": rogue_wins, "pvp_wins": pvp_wins,
		"daily_days": daily_days, "codex_seen": mod_seen.size(),
		"quads": quads, "endless_best": endless_best,
		"sign_total": sign_total, "codex_taken": _codex_taken_total(),
		"relic_seen": relic_seen.size(),
	}
	var newly: Array = []
	for a in ACHIEVEMENTS:
		var id := str(a["id"])
		if unlocked.has(id):
			continue
		if _ach_met(str(id), stats):
			unlocked.append(id)
			newly.append(a)
	if not newly.is_empty():
		diamonds += newly.size() * ACH_REWARD_DIAMONDS
		diamonds_earned += newly.size() * ACH_REWARD_DIAMONDS
		# 集齐全部成就: 一次性发放 +36 钻
		if not all_ach_bonus and unlocked.size() >= ACHIEVEMENTS.size():
			all_ach_bonus = true
			diamonds += ACH_ALL_BONUS
			diamonds_earned += ACH_ALL_BONUS
		_mark_dirty()
		achievements_changed.emit(newly)
	return newly


func _codex_taken_total() -> int:
	var n := 0
	for k in mod_taken:
		n += int(mod_taken[k])
	return n


func _ach_met(id: String, s: Dictionary) -> bool:
	match id:
		"first_win": return int(s["wins"]) >= 1
		"wins_10": return int(s["wins"]) >= 10
		"wins_30": return int(s["wins"]) >= 30
		"wins_50": return int(s["wins"]) >= 50
		"matches_30": return int(s["matches"]) >= 30
		"diamonds_50": return int(s["diamonds_earned"]) >= 50
		"gold_1000": return int(s["gold"]) >= 1000
		"collector": return int(s["skins"]) + int(s["cards"]) >= 8
		"gambler": return int(s["special_bought"]) >= 1
		"signer_7": return int(s["sign_streak"]) >= 7
		"fight_5": return int(s["fight_best"]) >= 5
		"fight_1": return int(s["fight_runs"]) >= 1
		"fight_boss_3": return int(s.get("fight_clears", 0)) >= 3
		"shopper": return int(s.get("purchases", 0)) >= 5
		"revivor": return int(s.get("revives", 0)) >= 1
		"fight_clear": return int(s.get("fight_clears", 0)) >= 1
		"fight_clear_5": return int(s.get("fight_clears", 0)) >= 5
		"daily_1": return int(s.get("daily_days", 0)) >= 1
		"daily_3": return int(s.get("daily_days", 0)) >= 3
		"rogue_win_1": return int(s.get("rogue_wins", 0)) >= 1
		"rogue_win_10": return int(s.get("rogue_wins", 0)) >= 10
		"codex_all": return int(s.get("codex_seen", 0)) >= CODEX_TARGET
		"pvp_win_1": return int(s.get("pvp_wins", 0)) >= 1
		"wins_100": return int(s.get("wins", 0)) >= 100
		"diamonds_500": return int(s.get("diamonds_earned", 0)) >= 500
		"gold_5000": return int(s.get("gold", 0)) >= 5000
		"quads_10": return int(s.get("quads", 0)) >= 10
		"signer_30": return int(s.get("sign_total", 0)) >= 30
		"shopper_20": return int(s.get("purchases", 0)) >= 20
		"fight_clear_10": return int(s.get("fight_clears", 0)) >= 10
		"endless_3": return int(s.get("endless_best", 0)) >= 3
		"rogue_win_30": return int(s.get("rogue_wins", 0)) >= 30
		"codex_take_30": return int(s.get("codex_taken", 0)) >= 30
		"relics_all": return int(s.get("relic_seen", 0)) >= 8
		"daily_7": return int(s.get("daily_days", 0)) >= 7
		"pvp_win_10": return int(s.get("pvp_wins", 0)) >= 10
	return false


## ── 对局记录 ──

## 追加一条本地对局记录(只留最近 HISTORY_MAX 条)
func push_history(entry: Dictionary) -> void:
	history.append(entry)
	while history.size() > HISTORY_MAX:
		history.pop_front()
	_mark_dirty()


## 追加一场对局回放(只留最近 REPLAY_MAX 场, 新的在前)
func push_replay(entry: Dictionary) -> void:
	replays.push_front(entry)
	while replays.size() > REPLAY_MAX:
		replays.pop_back()
	_mark_dirty()


## 删除一场对局回放(档案页回放列表): 越界静默忽略
func delete_replay(idx: int) -> void:
	if idx < 0 or idx >= replays.size():
		return
	replays.remove_at(idx)
	_mark_dirty()


## 称号随本地胜场晋升(留存成长线, 主菜单徽章展示)
func rank_title() -> String:
	if local_wins >= 30:
		return "大富豪"
	if local_wins >= 15:
		return "富豪"
	if local_wins >= 5:
		return "平民"
	return "新人"


## ── 消耗品道具 ──

func item_count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


## 购买消耗品: 扣费入库存, 成功返回 true
func buy_item(item_id: String) -> bool:
	for it in SPECIALS:
		if str(it["id"]) != item_id:
			continue
		var price := int(it["price"])
		if str(it["currency"]) == "gold":
			if gold < price:
				return false
			gold -= price
		else:
			if diamonds < price:
				return false
			diamonds -= price
		inventory[item_id] = item_count(item_id) + 1
		match str(it.get("effect", "")):
			"dday":
				double_diamond_day = _today()
			"tday":
				diamond_mult_day = _today()
				diamond_mult = 3
				double_diamond_day = _today()  # 三倍覆盖双倍(同日只留一条记录)
			"cday":
				counter_day = _today()
			"clearr":
				clear_records()
			"conce":
				pass   # 次卡: 入库存按次消耗(开局时 consume_counter_use)
		purchases += 1
		check_achievements()
		_mark_dirty()
		balance_changed.emit()
		return true
	return false


## 清空战绩: 对局记录/胜负统计/称号/各模式战绩与每日最佳清零。
## 不影响 货币/成就/每日任务/命运卡图鉴/消耗品库存(清空战绩道具生效入口)。
func clear_records() -> void:
	local_matches = 0
	local_wins = 0
	history = []
	fight_best = 0
	fight_runs = 0
	fight_bosses = 0
	fight_clears = 0
	rogue_runs = 0
	rogue_wins = 0
	pvp_wins = 0
	daily_day = ""
	daily_best_round = 0
	daily_best_hp = 0
	daily_days = 0
	_mark_dirty()


## ── 记牌器道具(日卡 40 钻 / 次卡 80 金, 购买后才能使用) ──

## 记牌器当前是否可用: 日卡当日生效, 或持有次卡
func counter_active() -> bool:
	return counter_day == _today() or item_count("item_counter_once") > 0


## 开局占用记牌器: 日卡当日不限次; 否则消耗 1 张次卡。无可用返回 false。
func consume_counter_use() -> bool:
	if counter_day == _today():
		return true
	return consume_item("item_counter_once")


## 记录一次四条(成就统计; 我方打出时由牌桌调用)
func note_quad() -> void:
	quads += 1
	check_achievements()
	_mark_dirty()


## 记录无尽挑战到达层数(成就统计; 格斗页开新层时调用)
func note_endless(floor_num: int) -> void:
	if floor_num > endless_best:
		endless_best = floor_num
		check_achievements()
		_mark_dirty()


## ── 对局回放 ──

## 清空全部回放(档案页"删除所有回放"按钮)
func clear_replays() -> void:
	replays = []
	_mark_dirty()


## ── 钱包备份码(P1 阶段一) ──
## 导出: 持久化字段 → JSON → zlib 压缩 → base64 + 校验和(防手改)。
## 校验和为休闲级防篡改, 非加密签名。跨设备迁移: 导出码在另一设备导入。

const BACKUP_SALT := "TB1::daifugo::v1::9f27c41b"
const BACKUP_PREFIX := "TB1-"

## 全部持久化字段的紧凑载荷(短键压缩体积)
func _backup_payload() -> Dictionary:
	return {
		"v": 1,
		"g": gold, "d": diamonds,
		"os": owned_skins, "oc": owned_cards,
		"es": equipped_skin, "ec": equipped_card,
		"lm": local_matches, "lw": local_wins,
		"ul": unlocked, "hs": history,
		"fb": fight_best, "fr": fight_runs, "fb3": fight_bosses,
		"fc": fight_clears, "rr": rogue_runs, "rw": rogue_wins,
		"pw": pvp_wins,
		"ddy": daily_day, "dbr": daily_best_round, "dbh": daily_best_hp,
		"ddy2": daily_days,
		"ms": mod_seen, "mt": mod_taken, "rs": relic_seen,
		"nk": GameSettings.nickname, "cid": GameSettings.client_id,
		"pu": purchases, "rv": revives, "iv": inventory,
		"dmd": diamond_mult_day, "dm": diamond_mult,
		"sdy": sign_day, "sst": sign_streak, "sto": sign_total, "wst": win_streak,
		"de": diamonds_earned, "sb": special_bought,
		"fw": first_win_day, "ddd": double_diamond_day,
		"mdy": mission_day, "mp": mission_progress, "mc": mission_claimed,
	}


## 导出备份码(含校验和)。格式: TB1-校验8-解压尺寸-base64载荷
func export_backup() -> String:
	var json := JSON.stringify(_backup_payload())
	var raw := json.to_utf8_buffer()
	var sum := (json + BACKUP_SALT).sha256_text().substr(0, 8)
	var b64 := Marshalls.raw_to_base64(raw.compress())
	return "%s%s-%d-%s" % [BACKUP_PREFIX, sum, raw.size(), b64]


## 导入备份码: 校验通过则覆盖恢复并落盘。
## 返回 {gold, diamonds} 或 {error: 原因}。
func import_backup(code: String) -> Dictionary:
	var t := code.strip_edges().replace(" ", "").replace("
", "").replace("
", "")
	if not t.begins_with(BACKUP_PREFIX):
		return {"error": "不是有效的备份码"}
	var rest := t.substr(BACKUP_PREFIX.length())
	var parts := rest.split("-")
	if parts.size() != 3:
		return {"error": "备份码格式不完整"}
	var sum_in := parts[0]
	var size_in := int(parts[1])
	var compressed := Marshalls.base64_to_raw(parts[2])
	if compressed.is_empty() or size_in <= 0 or size_in > 1 << 20:
		return {"error": "备份码内容无法读取"}
	var raw := compressed.decompress(size_in)
	if raw.is_empty():
		return {"error": "备份码解压失败"}
	var json := raw.get_string_from_utf8()
	if (json + BACKUP_SALT).sha256_text().substr(0, 8) != sum_in:
		return {"error": "备份码校验不符(可能被改动)"}
	var parsed = JSON.parse_string(json)
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("v", 0)) != 1:
		return {"error": "备份码版本不受支持"}
	# 覆盖恢复(与 save_wallet 字段一一对应)
	gold = maxi(int(parsed.get("g", 0)), 0)
	diamonds = maxi(int(parsed.get("d", 0)), 0)
	owned_skins = parsed.get("os", ["skin_default"])
	owned_cards = parsed.get("oc", ["card_washi"])
	equipped_skin = str(parsed.get("es", "skin_default"))
	equipped_card = str(parsed.get("ec", "card_washi"))
	local_matches = maxi(int(parsed.get("lm", 0)), 0)
	local_wins = maxi(int(parsed.get("lw", 0)), 0)
	unlocked = parsed.get("ul", [])
	history = parsed.get("hs", [])
	fight_best = maxi(int(parsed.get("fb", 0)), 0)
	fight_runs = maxi(int(parsed.get("fr", 0)), 0)
	fight_bosses = maxi(int(parsed.get("fb3", 0)), 0)
	fight_clears = maxi(int(parsed.get("fc", 0)), 0)
	rogue_runs = maxi(int(parsed.get("rr", 0)), 0)
	rogue_wins = maxi(int(parsed.get("rw", 0)), 0)
	pvp_wins = maxi(int(parsed.get("pw", 0)), 0)
	daily_day = str(parsed.get("ddy", ""))
	daily_best_round = maxi(int(parsed.get("dbr", 0)), 0)
	daily_best_hp = clampi(int(parsed.get("dbh", 0)), 0, 100)
	daily_days = maxi(int(parsed.get("ddy2", 0)), 0)
	mod_seen = parsed.get("ms", {})
	# 身份恢复: 昵称 + 游客id(重装设备导入备份码即找回身份)
	GameSettings.nickname = str(parsed.get("nk", GameSettings.nickname))
	if GameSettings.nickname.strip_edges() == "":
		GameSettings.nickname = "玩家"
	GameSettings.client_id = str(parsed.get("cid", GameSettings.client_id))
	GameSettings.save_settings()
	relic_seen = parsed.get("rs", {})
	if relic_seen is not Dictionary:
		relic_seen = {}
	else:
		# JSON 往返会把 int 键字符串化 — 归一回 int
		var rs_norm := {}
		for k in relic_seen:
			rs_norm[int(k)] = int(relic_seen[k])
		relic_seen = rs_norm
	mod_taken = parsed.get("mt", {})
	purchases = maxi(int(parsed.get("pu", 0)), 0)
	revives = maxi(int(parsed.get("rv", 0)), 0)
	inventory = parsed.get("iv", {})
	diamond_mult_day = str(parsed.get("dmd", ""))
	diamond_mult = maxi(int(parsed.get("dm", 1)), 1)
	sign_day = str(parsed.get("sdy", ""))
	sign_streak = maxi(int(parsed.get("sst", 0)), 0)
	win_streak = maxi(int(parsed.get("wst", 0)), 0)
	sign_total = maxi(int(parsed.get("sto", 0)), 0)
	diamonds_earned = maxi(int(parsed.get("de", 0)), 0)
	special_bought = maxi(int(parsed.get("sb", 0)), 0)
	first_win_day = str(parsed.get("fw", ""))
	double_diamond_day = str(parsed.get("ddd", ""))
	mission_day = str(parsed.get("mdy", ""))
	mission_progress = parsed.get("mp", {})
	mission_claimed = parsed.get("mc", {})
	save_wallet()
	balance_changed.emit()
	return {"gold": gold, "diamonds": diamonds}


## 复活币: 有库存则消耗并复活
func try_consume_revive() -> bool:
	if item_count("item_revive_coin") > 0 and consume_item("item_revive_coin"):
		revives += 1
		check_achievements()
		return true
	return false


## 三倍钻石卡生效中
func diamond_triple_active() -> bool:
	return diamond_mult_day == _today() and diamond_mult >= 3


## 消耗一枚道具
func consume_item(item_id: String) -> bool:
	if item_count(item_id) <= 0:
		return false
	inventory[item_id] = item_count(item_id) - 1
	_mark_dirty()
	balance_changed.emit()
	return true


## 复活币: 有库存则消耗并复活
func double_diamond_active() -> bool:
	return double_diamond_day == _today()


func _today() -> String:
	return Time.get_date_string_from_system()


func is_owned(kind: String, item_id: String) -> bool:
	var list: Array = owned_skins if kind == "skin" else owned_cards
	return list.has(item_id)


func is_equipped(kind: String, item_id: String) -> bool:
	return equipped_skin == item_id if kind == "skin" else equipped_card == item_id


func equip(kind: String, item_id: String) -> void:
	if kind == "skin":
		if not owned_skins.has(item_id):
			return
		equipped_skin = item_id
	elif kind == "card":
		if not owned_cards.has(item_id):
			return
		equipped_card = item_id
	_mark_dirty()
	equipped_changed.emit()


func _mark_dirty() -> void:
	_dirty = true
	_save_timer = AUTOSAVE_SEC  # 尽快触发下一轮周期保存(≤1 帧)
