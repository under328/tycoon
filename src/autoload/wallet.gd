## 经济与装扮内核（autoload: Wallet）。
## 金币/钻石余额、皮肤与卡面的拥有/装备状态、本地战绩统计。
## 自动存档: 变更打脏标记 → 每 10s 周期保存; 退出/切后台时强制保存;
## 原子写入(tmp→rename) + .bak 备份回退, 防止存档损坏。
extends Node

signal balance_changed
signal equipped_changed

const SAVE_PATH := "user://wallet.cfg"
const AUTOSAVE_SEC := 10.0

## 本地对局奖励(按最终名次 1..4): [金币, 钻石]
const GOLD_PER_POINT := 2        # 1 积分 = 2 金币(再乘输赢倍率)

const FIRST_WIN_DIAMONDS := 3   # 每日首胜奖励钻石数

## 特殊道具(消耗型/限时增益, 非装扮): currency=购买所用货币
const SPECIALS := [
	{"id": "item_double_diamond", "name": "双倍钻石卡", "price": 120,
		"currency": "gold", "desc": "激活后至当日结束, 对局获得的钻石翻倍"},
]

var gold := 500       # 默认 500 金币
var diamonds := 0     # 默认 0 钻石
var owned_skins: Array = ["skin_default"]
var owned_cards: Array = ["card_washi"]
var equipped_skin := "skin_default"
var equipped_card := "card_washi"
var double_diamond_day := ""   # 双倍钻石卡生效日期(YYYY-MM-DD, 当地时区)
var first_win_day := ""        # 每日首胜已领取日期(空=今日未领)

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
## 双倍钻石卡生效中(当日)钻石翻倍; 当日首胜额外 +3 钻(每日首胜奖励)。
func grant_match_reward(points: int, rank: int, stakes: int = 1) -> Dictionary:
	var gold_delta := points * GOLD_PER_POINT * clampi(stakes, 1, 3)
	var dia_delta := 0
	match clampi(rank - 1, 0, 3):
		0:
			dia_delta = 2
		1:
			dia_delta = 1
	gold = maxi(gold + gold_delta, 0)
	var doubled := double_diamond_active()
	if doubled:
		dia_delta *= 2
	var bonus := 0
	if rank == 1 and first_win_day != _today():
		bonus = FIRST_WIN_DIAMONDS
		first_win_day = _today()
	diamonds += dia_delta + bonus
	local_matches += 1
	if rank == 1:
		local_wins += 1
	_mark_dirty()
	balance_changed.emit()
	return {"gold": gold_delta, "diamonds": dia_delta, "points": points,
			"stakes": stakes, "doubled": doubled, "bonus": bonus}


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
		_mark_dirty()
		balance_changed.emit()
		return true
	return false


## 称号随本地胜场晋升(留存成长线, 主菜单徽章展示)
func rank_title() -> String:
	if local_wins >= 30:
		return "大富豪"
	if local_wins >= 15:
		return "富豪"
	if local_wins >= 5:
		return "平民"
	return "新人"


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
