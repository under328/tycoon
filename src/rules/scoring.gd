## 身份结算与单局积分。契约见 docs/规则规格.md §6。
class_name Scoring
extends RefCounted

const IDENTITY_NAMES := ["大富豪", "富豪", "平民", "乞丐"]
const IDENTITY_POINTS := [2, 1, -1, -2]


## finish_order: 出完顺序（前 3 人）；remaining_seat: 局终未出完者。
## 返回长度 4 数组，索引=座位，值=身份 rank（0 大富豪 … 3 乞丐）。
static func identities(finish_order: Array, remaining_seat: int) -> Array:
	var ids := [0, 0, 0, 0]
	for rank in finish_order.size():
		ids[int(finish_order[rank])] = rank
	ids[remaining_seat] = 3
	return ids


static func round_delta(identity: int) -> int:
	return IDENTITY_POINTS[identity]
