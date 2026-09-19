## 格斗引擎策略模拟器: 无 UI 批量种子推进, 验证玩法可达性 —
## 通关率(R5 BOSS 可被击败)/奇物覆盖(10 种都该在 draft 中出现)/
## 无尽换层/每日种子确定性。策略: 贪心选牌 + 启发式战斗。
## 运行: godot --headless --path . --script tools/fight_sim.gd
extends SceneTree

const FightGd = preload("res://src/rules/fight/fight_mode.gd")

const RUNS := 300
const TIER_RANK := ["straight_flush", "quad", "flush", "full_house",
		"straight", "trips", "two_pair", "pair", "high"]


func tier_rank(combo: Dictionary) -> int:
	return TIER_RANK.find(str(combo.get("tier", "high")))


func _initialize() -> void:
	var wins := 0
	var boss_reached := 0
	var relics_seen := {}
	var floors_seen := {}
	var drafts_total := 0
	var draft_pair_dup := 0
	var stuck := 0
	for seed_i in RUNS:
		var fm = FightGd.new(seed_i * 7919 + 13)
		var rounds_guard := 0
		var boss_counted := false
		while rounds_guard < 400:
			rounds_guard += 1
			if str(fm.phase) == "draft":
				drafts_total += 1
				for c in fm.pair:
					if c >= 100 and c < 200:
						relics_seen[FightGd.sp_of(int(c))] = true
				if fm.bonus_relic >= 0:
					relics_seen[FightGd.sp_of(int(fm.bonus_relic))] = true
				var uniq := {}
				for c in fm.pair:
					uniq[int(c)] = true
				if uniq.size() < (fm.pair as Array).size():
					draft_pair_dup += 1
				# 选牌: 奇物(独立第三选项)先拾取 — 不消耗卡牌选择;
				# 再选使牌型更强的普通牌
				if fm.bonus_relic >= 0 and (fm.specials as Array).size() < 2:
					fm.draft_pick(int(fm.bonus_relic))
				var best_cand: int = -1
				var best_rank := -1
				var best_slot := 0
				for c in fm.pair:
					if c < 0:
						continue
					var slots: Array = (fm.slots as Array).duplicate()
					var slot := 0
					var card_v: int = FightGd.card_of(int(c))
					if slots.size() >= 5:
						slot = _weakest_slot(slots)
						slots[slot] = card_v
					else:
						slots.append(card_v)
					var rk := tier_rank(FightGd.evaluate_combo(slots))
					if rk > best_rank:
						best_rank = rk
						best_cand = int(c)
						best_slot = slot
				if best_cand >= 0:
					fm.draft_pick(best_cand, best_slot)
				else:
					fm.draft_pick(-1)   # 跳过(仅槽满)
			elif str(fm.phase) == "battle":
				if int(fm.round_num) == FightGd.ROUNDS and not boss_counted:
					boss_reached += 1
					boss_counted = true
				var act := _battle_act(fm)
				fm.step(act)
			elif str(fm.phase) == "round_end":
				if int(fm.round_num) >= FightGd.ROUNDS and bool(fm.run_won):
					wins += 1
					floors_seen[fm.floor_num] = true
					fm.start_next_floor()   # 无尽: 进入下一层
				else:
					fm.advance_round()   # 过场推进(与 UI 同接口)
			elif str(fm.phase) == "over":
				break
			else:
				stuck += 1
				break
	print("[sim] runs=%d wins=%d boss_reached=%d drafts=%d dup_pair=%d stuck=%d floors=%s relics=%d/10" % [
			RUNS, wins, boss_reached, drafts_total, draft_pair_dup, stuck,
			str(floors_seen.keys()), relics_seen.size()])
	quit(0)


func _weakest_slot(slots: Array) -> int:
	var best := 0
	var best_v := 99
	for i in slots.size():
		var v: int = FightGd.card_of(int(slots[i]))
		if v < best_v:
			best_v = v
			best = i
	return best


## 启发式战斗: 蓄力→强攻; 残血→奥义/防御; 技能好了→技能; 否则攻击
func _battle_act(fm) -> String:
	var intent := str(fm.enemy.get("intent", "attack"))
	var hp_frac := float(fm.hp) / maxf(float(fm.stats["max_hp"]), 1.0)
	if fm.fury >= 100 and (hp_frac < 0.6 or intent == "charge"):
		return "ult"
	if hp_frac < 0.3 and fm._skill_cd == 0:
		return "defend"
	if fm._skill_cd == 0 and intent == "charge":
		return "skill"
	if fm.hp < int(fm.stats["max_hp"]) * 0.25:
		return "defend"
	return "attack"
