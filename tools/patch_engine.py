# fight_mode.gd: 连击/怒气/奥义/完美格挡 引擎改造(精确锚点)
import io

NL = chr(10)
BS = chr(92)
p = "src/rules/fight/fight_mode.gd"
s = io.open(p, encoding="utf-8").read()
pairs = []

# step 入口: 奥义怒气守卫
pairs.append((
    '\tif phase != "battle":' + NL + '\t\treturn evs',
    '\tif phase != "battle":' + NL + '\t\treturn evs' + NL
    + '\tif action == "ult" and fury < 100:' + NL
    + '\t\treturn evs   # 怒气未满, 奥义不可用'))

# _start_battle: 重置连击
pairs.append((
    '\t_skill_cd = 0' + NL + '\t_battle_round = 0' + NL + '\t_first_used = false',
    '\t_skill_cd = 0' + NL + '\t_battle_round = 0' + NL + '\t_first_used = false'
    + NL + '\tcombo = 0'))

# 攻击: 连击计数 + 连击伤害加成 + 怒气 + 连击事件
pairs.append((
    '\t\t"attack":' + NL
    + '\t\t\tvar crit: bool = rng.randf() < float(stats["crit_rate"])',
    '\t\t"attack":' + NL
    + '\t\t\tcombo = mini(combo + 1, 11)' + NL
    + '\t\t\tvar crit: bool = rng.randf() < float(stats["crit_rate"])'))
pairs.append((
    '\t\t\tdmg = maxi(dmg - 2, 1)',
    '\t\t\tdmg = int(dmg * (1.0 + 0.06 * mini(maxi(combo - 1, 0), 10)))   # 连击伤害加成'
    + NL + '\t\t\tdmg = maxi(dmg - 2, 1)'))
pairs.append((
    '\t\t\tenemy["hp"] = int(enemy["hp"]) - dmg' + NL
    + '\t\t\tev' + 's.append({"who": "p", "kind": "crit" if crit else "dmg", "v": dmg})',
    '\t\t\tenemy["hp"] = int(enemy["hp"]) - dmg' + NL
    + '\t\t\tfury = mini(fury + 12, 100)' + NL
    + '\t\t\tev' + 's.append({"who": "p", "kind": "crit" if crit else "dmg", "v": dmg})'
    + NL + '\t\t\tif combo >= 2:' + NL
    + '\t\t\t\tev' + 's.append({"who": "p", "kind": "combo", "v": combo})'))

# 技能: 连击 + 怒气
pairs.append((
    '\t\t\tev' + 's.append({"who": "p", "kind": "skill", "v": dmg,'
    + NL + '\t\t\t\t\t"skill_kind": kind_name})' + NL
    + '\t\t\t_vamp_heal(evs, dmg)' + NL + '\t\t\t_skill_cd = 2',
    '\t\t\tev' + 's.append({"who": "p", "kind": "skill", "v": dmg,'
    + NL + '\t\t\t\t\t"skill_kind": kind_name})' + NL
    + '\t\t\t_vamp_heal(evs, dmg)' + NL
    + '\t\t\tcombo = mini(combo + 1, 11)' + NL
    + '\t\t\tfury = mini(fury + 8, 100)' + NL
    + '\t\t\tif combo >= 2:' + NL
    + '\t\t\t\tev' + 's.append({"who": "p", "kind": "combo", "v": combo})' + NL
    + '\t\t\t_skill_cd = 2'))

# 防御后追加奥义分支
pairs.append((
    '\t\t"defend":' + NL
    + '\t\t\tvar heal := maxi(int(stats["max_hp"]) / 25, 3)' + NL
    + '\t\t\thp = mini(hp + heal, int(stats["max_hp"]))' + NL
    + '\t\t\tev' + 's.append({"who": "p", "kind": "defend", "v": heal})',
    '\t\t"defend":' + NL
    + '\t\t\tvar heal := maxi(int(stats["max_hp"]) / 25, 3)' + NL
    + '\t\t\thp = mini(hp + heal, int(stats["max_hp"]))' + NL
    + '\t\t\tev' + 's.append({"who": "p", "kind": "defend", "v": heal})' + NL
    + '\t\t"ult":' + NL
    + '\t\t\t# 奥义: 2.5 倍攻击必中 + 回复 20% 生命, 怒气清零' + NL
    + '\t\t\tvar udmg := maxi(int(float(stats["atk"]) * 2.5), 1)' + NL
    + '\t\t\tenemy["hp"] = int(enemy["hp"]) - udmg' + NL
    + '\t\t\tfury = 0' + NL
    + '\t\t\tcombo = mini(combo + 1, 11)' + NL
    + '\t\t\tvar uhl := maxi(int(int(stats["max_hp"]) * 0.2), 1)' + NL
    + '\t\t\thp = mini(hp + uhl, int(stats["max_hp"]))' + NL
    + '\t\t\tev' + 's.append({"who": "p", "kind": "ult", "v": udmg})' + NL
    + '\t\t\tev' + 's.append({"who": "p", "kind": "heal", "v": uhl})' + NL
    + '\t\t\t_vamp_heal(evs, udmg)'))

# 顺子追击: 奥义不触发
pairs.append((
    '\tif action != "defend" and bool(stats.get("straight", false)) ' + BS,
    '\tif action != "defend" and action != "ult" '
    + 'and bool(stats.get("straight", false)) ' + BS))

# 敌人行动: 完美格挡(预读重击防御) + 被击中清连击/积怒气
pairs.append((
    '\tif action == "defend":' + NL
    + '\t\tedmg = int(edmg * 0.4)',
    '\tif action == "defend" and intent == "heavy":' + NL
    + '\t\t# 完美格挡: 零伤害 + 反击, 重读意图的奖励' + NL
    + '\t\tvar counter := maxi(int(float(stats["atk"]) * 1.0), 1)' + NL
    + '\t\tenemy["hp"] = int(enemy["hp"]) - counter' + NL
    + '\t\tfury = mini(fury + 25, 100)' + NL
    + '\t\tev' + 's.append({"who": "p", "kind": "parry", "v": counter})' + NL
    + '\t\t_choose_intent()' + NL
    + '\t\tif int(enemy["hp"]) <= 0:' + NL
    + '\t\t\tenemy["hp"] = 0' + NL
    + '\t\t\tev' + 's.append({"who": "e", "kind": "die", "v": 0})' + NL
    + '\t\t\t_win_round()' + NL
    + '\t\treturn evs' + NL
    + '\tif action == "defend":' + NL
    + '\t\tedmg = int(edmg * 0.4)'))

# 玩家受击: 清连击 + 积怒气(在 _damage_player 调用后)
pairs.append((
    '\tedmg = maxi(edmg, 1)' + NL
    + '\t_damage_player(edmg)',
    '\tedmg = maxi(edmg, 1)' + NL
    + '\t_damage_player(edmg)' + NL
    + '\tcombo = 0' + NL
    + '\tfury = mini(fury + 8, 100)'))

for old, new in pairs:
    assert old in s, "MISS: " + old[:70]
    s = s.replace(old, new, 1)

# 击破奖励怒气(_win_round 内)
old = '\tvar heal := int(int(stats["max_hp"]) * 0.25)'
assert old in s
s = s.replace(old, '\tfury = mini(fury + 30, 100)' + NL + old, 1)

io.open(p, "w", encoding="utf-8", newline=NL).write(s)
print("ok fight_mode engine")
