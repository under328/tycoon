## 按座位裁剪"可见信息"（防作弊核心：除本人 hand 外不得出现他人具体牌）。
## 结构契约见 docs/协议.md §5。
class_name View
extends RefCounted


static func build(st: Dictionary, seat: int) -> Dictionary:
	return {
		"phase": st["phase"],
		"round": st["round"],
		"rounds_total": int(st["cfg"]["rounds"]),
		"rules": st["cfg"].duplicate(),
		"my_seat": seat,
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
		"must_include": st["must_include"],
	}
