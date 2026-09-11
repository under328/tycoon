## 经济与装扮内核（autoload: Wallet）。
## 金币/钻石余额、皮肤与卡面的拥有/装备状态，持久化 user://wallet.cfg。
## 全部为装饰内容，不影响规则判定。
extends Node

signal balance_changed
signal equipped_changed

const SAVE_PATH := "user://wallet.cfg"

## 本地对局奖励(按最终名次 1..4): [金币, 钻石]
const MATCH_REWARDS := [
	[300, 6], [180, 4], [120, 3], [60, 2],
]

var gold := 500       # 默认 500 金币
var diamonds := 0     # 默认 0 钻石
var owned_skins: Array = ["skin_default"]
var owned_cards: Array = ["card_washi"]
var equipped_skin := "skin_default"
var equipped_card := "card_washi"


func _ready() -> void:
	load_wallet()


func load_wallet() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		gold = int(cf.get_value("wallet", "gold", 500))
		diamonds = int(cf.get_value("wallet", "diamonds", 0))
		owned_skins = cf.get_value("wallet", "owned_skins", ["skin_default"])
		owned_cards = cf.get_value("wallet", "owned_cards", ["card_washi"])
		equipped_skin = str(cf.get_value("wallet", "equipped_skin", "skin_default"))
		equipped_card = str(cf.get_value("wallet", "equipped_card", "card_washi"))


func save_wallet() -> void:
	var cf := ConfigFile.new()
	cf.set_value("wallet", "gold", gold)
	cf.set_value("wallet", "diamonds", diamonds)
	cf.set_value("wallet", "owned_skins", owned_skins)
	cf.set_value("wallet", "owned_cards", owned_cards)
	cf.set_value("wallet", "equipped_skin", equipped_skin)
	cf.set_value("wallet", "equipped_card", equipped_card)
	cf.save(SAVE_PATH)


## 本地对局结算发放(名次 1..4)。返回 {gold, diamonds}。
func grant_match_reward(rank: int) -> Dictionary:
	var idx := clampi(rank - 1, 0, MATCH_REWARDS.size() - 1)
	var reward: Array = MATCH_REWARDS[idx]
	gold += int(reward[0])
	diamonds += int(reward[1])
	save_wallet()
	balance_changed.emit()
	return {"gold": int(reward[0]), "diamonds": int(reward[1])}


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
	save_wallet()
	balance_changed.emit()
	return true


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
	save_wallet()
	equipped_changed.emit()
