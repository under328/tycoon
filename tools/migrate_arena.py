# fight_arena.gd 动态文案 tr() 迁移
import io

NL = chr(10)
p = "src/client/ui/fight_arena.gd"
s = io.open(p, encoding="utf-8").read()
pairs = [
    ('"draft": "第 %d/%d 回合 — 二选一编成" % [int(v.get("round_num", 1)),',
     '"draft": tr("第 %d/%d 回合 — 二选一编成") % [int(v.get("round_num", 1)),'),
    ('"battle": "第 %d 回合 — 对战!" % int(v.get("round_num", 1)),',
     '"battle": tr("第 %d 回合 — 对战!") % int(v.get("round_num", 1)),'),
    ('"round_end": "第 %d 回合 结束" % int(v.get("round_num", 1)),',
     '"round_end": tr("第 %d 回合 结束") % int(v.get("round_num", 1)),'),
    ('(p["score"] as Label).text = "回合胜 %d" % int(sc.get(seat, 0))',
     '(p["score"] as Label).text = tr("回合胜 %d") % int(sc.get(seat, 0))'),
    ('(p["prog"] as Label).text = "装备 %d/5 · 奇物 %d" % [',
     '(p["prog"] as Label).text = tr("装备 %d/5 · 奇物 %d") % ['),
    ('title.text = ("🟣 奇物生效! 补抽一张普通牌" if bool(my.get("comp", false))',
     'title.text = (tr("🟣 奇物生效! 补抽一张普通牌") if bool(my.get("comp", false))'),
    ('else "二选一 — 点选 1 张 (装备 %d/5%s)" % [',
     'else tr("二选一 — 点选 1 张 (装备 %d/5%s)") % ['),
    ('_status_line(row, "等待 %s 行动…" % nm)',
     '_status_line(row, tr("等待 %s 行动…") % nm)'),
    ('_status_line(row, "%s 拿下本回合 — 即将进入下一回合…" % nm)',
     '_status_line(row, tr("%s 拿下本回合 — 即将进入下一回合…") % nm)'),
    ('\tvar body := "比分 %d : %d — 胜者 %s" % [',
     '\tvar body := tr("比分 %d : %d — 胜者 %s") % ['),
    ('\t\tbody += "' + chr(92) + 'n奖励: %+d 金币 %+d 钻石 已入账" % [int(r["gold"]),',
     '\t\tbody += "' + chr(92) + 'n" + tr("奖励: %+d 金币 %+d 钻石 已入账") % [int(r["gold"]),'),
]
for old, new in pairs:
    assert old in s, "MISS arena: " + old[:60]
    s = s.replace(old, new, 1)
io.open(p, "w", encoding="utf-8", newline=NL).write(s)
print("ok fight_arena")
