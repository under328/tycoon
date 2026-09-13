## 房间规则配置（变体开关）。契约见 docs/规则规格.md。
class_name RulesConfig
extends RefCounted


static func defaults() -> Dictionary:
	return {
		"with_joker": true,
		"revolution": true,
		
		"eight_cut": true,
		"rounds": 3,
		"turn_seconds": 20,
		"exchange_seconds": 15,
		"stakes": 1,
	}


## 用输入覆盖默认值并夹紧合法范围。
static func normalize(cfg: Dictionary) -> Dictionary:
	var out := defaults()
	for k in out.keys():
		if cfg.has(k):
			out[k] = cfg[k]
	out["eight_cut"] = true  # rule.md: 8切为基础规则, 不可关闭
	# 回合制: 一回合 = 3 局; 开房可选 一/三/五回合(3/9/15 局)
	out["rounds"] = clampi(int(out["rounds"]), 1, 15)
	out["turn_seconds"] = clampi(int(out["turn_seconds"]), 5, 120)
	out["exchange_seconds"] = clampi(int(out["exchange_seconds"]), 5, 60)
	out["stakes"] = clampi(int(out["stakes"]), 1, 3)
	return out
