## 房间规则配置（变体开关）。契约见 docs/规则规格.md。
class_name RulesConfig
extends RefCounted


static func defaults() -> Dictionary:
	return {
		"with_joker": true,
		"revolution": true,
		"stairs": true,
		"eight_cut": false,
		"rounds": 3,
		"turn_seconds": 20,
		"exchange_seconds": 15,
	}


## 用输入覆盖默认值并夹紧合法范围。
static func normalize(cfg: Dictionary) -> Dictionary:
	var out := defaults()
	for k in out.keys():
		if cfg.has(k):
			out[k] = cfg[k]
	out["rounds"] = clampi(int(out["rounds"]), 1, 5)
	out["turn_seconds"] = clampi(int(out["turn_seconds"]), 5, 120)
	out["exchange_seconds"] = clampi(int(out["exchange_seconds"]), 5, 60)
	return out
