# profile_panel.gd 动态文案 tr() 迁移
import io

NL = chr(10)
p = "src/client/ui/profile_panel.gd"
s = io.open(p, encoding="utf-8").read()
pairs = [
    ('["🂡 大富豪", "场次 %d · 胜 %d · 胜率 %d%%" % [Wallet.local_matches,',
     '["🂡 大富豪", tr("场次 %d · 胜 %d · 胜率 %d%%") % [Wallet.local_matches,'),
    ('["🎲 肉鸽模式", "场次 %d · 胜 %d" % [Wallet.rogue_runs, Wallet.rogue_wins]],',
     '["🎲 肉鸽模式", tr("场次 %d · 胜 %d") % [Wallet.rogue_runs, Wallet.rogue_wins]],'),
    ('["⚔ 格斗试炼", "局数 %d · 通关 %d · 最远第 %d 回合 · 击破 BOSS %d" % [',
     '["⚔ 格斗试炼", tr("局数 %d · 通关 %d · 最远第 %d 回合 · 击破 BOSS %d") % ['),
    ('["🥊 联机格斗对战", "胜场 %d" % Wallet.pvp_wins],',
     '["🥊 联机格斗对战", tr("胜场 %d") % Wallet.pvp_wins],'),
    ('["📅 每日挑战", "%s · 累计参与 %d 天" % [_daily_text(), Wallet.daily_days]],',
     '["📅 每日挑战", "%s · " + tr("累计参与 %d 天") % Wallet.daily_days],'),
    ('["📕 命运卡图鉴", "已见 %d / %d 种" % [Wallet.mod_seen.size(),',
     '["📕 命运卡图鉴", tr("已见 %d / %d 种") % [Wallet.mod_seen.size(),'),
    ('		return "今日未挑战"',
     '		return tr("今日未挑战")'),
    ('		return "今日已通关(剩余生命 %d%%)" % Wallet.daily_best_hp',
     '		return tr("今日已通关(剩余生命 %d%%)") % Wallet.daily_best_hp'),
    ('	return "今日最佳: 到达第 %d 回合" % Wallet.daily_best_round',
     '	return tr("今日最佳: 到达第 %d 回合") % Wallet.daily_best_round'),
    ('	head.text = "共 %d 场 · 胜 %d 场 · 胜率 %d%% · 称号 %s" % [total, wins,',
     '	head.text = tr("共 %d 场 · 胜 %d 场 · 胜率 %d%% · 称号 %s") % [total, wins,'),
    ('	fight.text = "⚔ 格斗试炼最高纪录: 第 %d 层" % Wallet.fight_best',
     '	fight.text = tr("⚔ 格斗试炼最高纪录: 第 %d 回合") % Wallet.fight_best'),
    ('	head.text = "已解锁 %d / %d" % [done, WalletGd.ACHIEVEMENTS.size()]',
     '	head.text = tr("已解锁 %d / %d") % [done, WalletGd.ACHIEVEMENTS.size()]'),
]
for old, new in pairs:
    assert old in s, "MISS profile: " + old[:60]
    s = s.replace(old, new, 1)
io.open(p, "w", encoding="utf-8", newline=NL).write(s)
print("ok profile")
