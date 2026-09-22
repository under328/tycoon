# -*- coding: utf-8 -*-
"""语音播报清单: key -> 中文播报词。
欢乐斗地主式: 短促、口语、带感叹号。生成器 tools/voice_gen.py 按此合成。
key 约定:
  v_<点数>  单张(3..15, 15=2);  v_wang=大王  v_s3=黑桃3(最强单张)
  p_<点数>  对子 3..15
  t_<点数>  三条 3..15
  其余语义 key 见下表
"""

RANKS = []  # (点数, 中文, 牌面字符)
_cn = {"3": "三", "4": "四", "5": "五", "6": "六", "7": "七", "8": "八",
       "9": "九", "10": "十", "11": "J", "12": "Q", "13": "K", "14": "A",
       "15": "二"}
for v in range(3, 16):
    RANKS.append((v, _cn[str(v)], _cn[str(v)]))

MANIFEST = {}

# ── 单张(14) ──
for v, cn, _ in RANKS:
    MANIFEST["v_%d" % v] = cn
MANIFEST["v_wang"] = "大王!"
MANIFEST["v_s3"] = "黑桃三!"

# ── 对子(13) ──
for v, cn, _ in RANKS:
    MANIFEST["p_%d" % v] = "对%s!" % cn

# ── 三条(13) ──
for v, cn, _ in RANKS:
    MANIFEST["t_%d" % v] = "三个%s!" % cn

# ── 牌局通用 ──
MANIFEST.update({
    "pass": "不要",
    "eight_cut": "八切!",
    "revolution": "革命!",
    "v_dafuhao": "大富豪!",
    "v_r2": "富豪!",
    "v_r3": "贫民~",
    "v_r4": "大贫民…",
    "v_last_one": "只剩一张啦!",
    "victory": "胜利!",
    "defeat": "惜败!",
})

# ── 肉鸽模式: 命运卡 ──
MANIFEST.update({
    "rogue_choice": "命运二选一!",
    "rogue_legend": "传说命运卡!",
    "rogue_epic": "史诗命运卡!",
    "rogue_common": "命运卡生效!",
})

# ── 格斗试炼 / 联机格斗对战 ──
MANIFEST.update({
    "f_draft": "选择装备!",
    "battle_start": "战斗开始!",
    "f_boss": "BOSS来袭!",
    "f_attack": "攻击!",
    "f_skill": "技能!",
    "f_defend": "防御!",
    "f_ult": "奥义!",
    "f_parry": "完美格挡!",
    "f_crit": "暴击!",
    "f_kill": "击败!",
    "f_fury": "怒气已满!",
    "f_combo": "连击!",
    "f_rare": "稀有卡!",
    "f_relic": "获得奇物!",
    "f_clear": "通关!",
    "f_transform": "变身!",
    "f_boss_skill": "看招!",
    "daily_start": "每日挑战, 开始!",
    "f_round_win": "得分!",
    "f_round_lose": "失分!",
    "f_vs": "对决!",
})

# ── 风趣变体(<key>_f1.._f3): 播报时随机替换原声, 让重复台词更活泼 ──
MANIFEST.update({
    "pass_f1": "过!",
    "pass_f2": "不出!",
    "pass_f3": "要不起咯~",
    "eight_cut_f1": "八切! 接好啦!",
    "eight_cut_f2": "八切咯~ 都别想要!",
    "revolution_f1": "革命! 变天啦!",
    "revolution_f2": "革命啦! 翻盘喽!",
    "victory_f1": "赢啦! 太棒了!",
    "victory_f2": "漂亮! 这把稳了!",
    "defeat_f1": "差一点点…",
    "defeat_f2": "唉, 下把再来!",
    "v_dafuhao_f1": "哈哈, 我是大富豪!",
    "v_last_one_f1": "只剩一张咯, 紧张!",
    "v_wang_f1": "大王驾到!",
    "v_s3_f1": "黑桃三, 无敌!",
    "v_15_f1": "二! 见谁压谁!",
    "f_kill_f1": "解决! 下一个!",
    "f_kill_f2": "再见啦你!",
    "f_crit_f1": "会心一击!",
    "f_crit_f2": "太疼了吧!",
    "f_parry_f1": "格挡成功, 反击!",
    "f_ult_f1": "吃我终极奥义!",
    "f_fury_f1": "怒气满格! 冲!",
    "f_rare_f1": "金光闪闪的稀有卡!",
    "f_relic_f1": "奇物到手!",
    "f_clear_f1": "全部通关! 厉害!",
    "f_vs_f1": "巅峰对决!",
    "daily_start_f1": "每日挑战, 冲鸭!",
    "rogue_legend_f1": "传说命运卡! 走运了!",
    "rogue_choice_f1": "命运二选一, 手气来了!",
})
