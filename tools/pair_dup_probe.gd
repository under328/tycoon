## 候选对重复探针: 大量种子自动推进 draft, 统计组内重复(同奇物/同候选值)
extends SceneTree

const FightGd = preload("res://src/rules/fight/fight_mode.gd")

const RUNS := 600
const MAX_ROUNDS := 40


func _initialize() -> void:
	var dup_sp := 0
	var dup_val := 0
	var pairs := 0
	var lock_cross_floor := 0
	for seed_i in RUNS:
		var fm = FightGd.new(seed_i)
		for r in MAX_ROUNDS:
			if fm.phase != "draft" or (fm.pair as Array).is_empty():
				break
			# 锁环跨层保留 + 奇物池每层重置 → 同奇物撞车监测
			var sps := []
			for c in fm.pair:
				if FightGd.is_sp(int(c)):
					sps.append(FightGd.sp_of(int(c)))
			if sps.size() >= 2 and sps[0] == sps[1]:
				dup_sp += 1
			var uniq := {}
			for c in fm.pair:
				uniq[int(c)] = true
			if uniq.size() < (fm.pair as Array).size():
				dup_val += 1
			if uniq.size() < (fm.pair as Array).size() and fm.floor_num > 1:
				lock_cross_floor += 1
			pairs += 1
			# 自动推进: 特殊牌直接选, 普通牌选 0 号(槽满时替换 0 槽)
			var cand: int = int(fm.pair[0])
			if FightGd.is_sp(cand):
				fm.draft_pick(cand)
			else:
				fm.draft_pick(cand, 0)
			# 每 3 回合强制换层: 触发奇物池重置 + 锁环保留的跨层撞车
			if r % 3 == 2:
				fm.start_next_floor()
	print("[probe] pairs=%d dup_same_sp=%d dup_value=%d (跨层撞车=%d)" % [
			pairs, dup_sp, dup_val, lock_cross_floor])
	quit(0 if dup_sp == 0 else 1)
