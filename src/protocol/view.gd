## 按座位裁剪"可见信息"（防作弊核心：除本人 hand 外不得出现他人具体牌）。
## 结构契约见 docs/协议.md §5。
class_name View
extends RefCounted

const GameStateGd = preload("res://src/rules/game_state.gd")
const CardsGd = preload("res://src/rules/cards.gd")


static func build(st: Dictionary, seat: int) -> Dictionary:
	return {
		"phase": st["phase"],
		"round": st["round"],
		"rounds_total": int(st["cfg"]["rounds"]),
		"rules": st["cfg"].duplicate(),
		"my_seat": seat,
		# 死牌按点数聚合(只给数量不给具体牌): 记牌器剔除死牌用
		"dead_counts": _dead_counts(st),
		"hand": (st["hands"][seat] as Array).duplicate(),
		"counts": [
			(st["hands"][0] as Array).size(),
			(st["hands"][1] as Array).size(),
			(st["hands"][2] as Array).size(),
			(st["hands"][3] as Array).size(),
		],
		"finished": (st["finish_order"] as Array).duplicate(),
		"turn": st["turn"],
		"lead": (st["lead"] as Dictionary).duplicate(true),
		"field": (st["field"] as Array).duplicate(true),
		"revolution": st["revolution"],
		"scores": (st["scores"] as Array).duplicate(),
		"identities": (st["identities"] as Array).duplicate(),
		"last_points": (st["last_points"] as Array).duplicate(),
		"exchange": (st["exchange"] as Array).duplicate(true),
		"exchange_return": _pending_return(st),
		"must_include": st["must_include"],
		"rogue_mod": str(st["cfg"].get("rogue_mod", "")),
		"rogue_choices": (st.get("rogue_choices", []) as Array).duplicate(),
		"rogue_rar": _rogue_rar(st),
	}


## 候选命运卡的稀有度(与 rogue_choices 一一对应)
static func _rogue_rar(st: Dictionary) -> Array:
	var out: Array = []
	for cid in st.get("rogue_choices", []):
		var rar := "common"
		for m in GameStateGd.ROGUE_MODS:
			if str(m["id"]) == str(cid):
				rar = str(m.get("rar", "common"))
		out.append(rar)
	return out


## 死牌按点数聚合: 索引 = 点数-3 (3..15 各 4 张基准, 16=王)
static func _dead_counts(st: Dictionary) -> Array:
	var counts := {}
	for c in st.get("dead", []):
		var v := CardsGd.value(int(c))
		counts[v] = int(counts.get(v, 0)) + 1
	var out: Array = []
	for v in range(3, 17):
		out.append(int(counts.get(v, 0)))
	return out


static func _pending_return(st: Dictionary) -> Dictionary:
	var pend: Array = st.get("exchange_returns", [])
	if pend.is_empty():
		return {}
	var cur: Dictionary = pend[0]
	return {"seat": int(cur["seat"]), "n": int(cur["n"]), "to": int(cur["to"])}
