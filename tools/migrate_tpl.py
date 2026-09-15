# 动态文案 tr() 迁移(一次性迁移脚本, 带逐条验证)
import io, re

BS = chr(92)   # 反斜杠
NL = chr(10)

def apply(path, pairs, regexes=None):
    s = io.open(path, encoding="utf-8").read()
    for old, new in pairs:
        assert old in s, "MISS in %s: %s" % (path, old[:60])
        s = s.replace(old, new, 1)
    for pat, rep in (regexes or []):
        s = re.sub(pat, rep, s)
    io.open(path, "w", encoding="utf-8", newline=NL).write(s)
    print("ok", path)

# ── fight_panel.gd ──
p = "src/client/ui/fight_panel.gd"
s = io.open(p, encoding="utf-8").read()
pairs = [
    ('+ "第 %d/%d 回合 · %s" % [fm.round_num, FightModeGd.ROUNDS,',
     '+ tr("第 %d/%d 回合 · %s") % [fm.round_num, FightModeGd.ROUNDS,'),
    ('_combo_lbl.text = "牌型 %s · %s" % [fm.combo["name"], fm.combo["desc"]]',
     '_combo_lbl.text = tr("牌型 %s · %s") % [tr(str(fm.combo["name"])), tr(str(fm.combo["desc"]))]'),
    ('\t\t_floater("装备 %s" % CardsGd.label(cand),',
     '\t\t_floater(tr("装备 %s") % CardsGd.label(cand),'),
    ('draft_title.text = "🟣 奇物已生效 — 补抽一张普通牌 (装备 %d/5)" % fm.slots.size()',
     'draft_title.text = tr("🟣 奇物已生效 — 补抽一张普通牌 (装备 %d/5)") % fm.slots.size()'),
    ('draft_title.text = "第 %d 回合 — 二选一 (装备 %d/5)%s" % [fm.round_num,',
     'draft_title.text = tr("第 %d 回合 — 二选一 (装备 %d/5)%s") % [fm.round_num,'),
    ('hint.text = "替换后 %s" % str(combo["name"])',
     'hint.text = tr("替换后 %s") % tr(str(combo["name"]))'),
    ('hint.text = "装备后 %s" % str(combo["name"])',
     'hint.text = tr("装备后 %s") % tr(str(combo["name"]))'),
    ('\tvar body := "通过 %d/5 回合 · 历史最佳第 %d 层' + BS + 'n奖励: %d 钻石 已入账" % [',
     '\tvar body := tr("通过 %d/5 回合 · 历史最佳第 %d 层' + BS + 'n奖励: %d 钻石 已入账") % ['),
    ('\tvar title := "试炼通关!" if fm.run_won else "试炼结束"',
     '\tvar title := (tr("每日挑战通关!") if fm.run_won else tr("每日挑战结束")) ' + BS + NL
     + '\t\t\tif daily else (tr("试炼通关!") if fm.run_won else tr("试炼结束"))'),
    ('e_intent.text = "意图: %s" % _intent_text()',
     'e_intent.text = tr("意图: %s") % _intent_text()'),
    ('\t\t\telse ("%s 冷却 %d" % [icon, cd])',
     '\t\t\telse (tr("%s 冷却 %d") % [icon, cd])'),
    ('var kind_txt: String = {"mob": "小怪", "elite": "精英怪",',
     'var kind_txt: String = {"mob": tr("小怪"), "elite": tr("精英怪"),'),
]
for old, new in pairs:
    assert old in s, "MISS in panel: " + old[:60]
    s = s.replace(old, new, 1)
s = re.sub(r'_floater\("([^%"]+)(-%d)" %', lambda m: '_floater(tr("%s%s") %%' % (m.group(1), m.group(2)), s)
s = re.sub(r'_floater\("(\+%d)" %', lambda m: '_floater(tr("%s") %%' % m.group(1), s)
s = s.replace('_floater("复活币生效!"', '_floater(tr("复活币生效!")')
s = s.replace('\t\tvar best_txt := ("通关! 剩余生命 %d%%" % int(d["best_hp"])) ' + BS,
              '\t\tvar best_txt := (tr("通关! 剩余生命 %d%%") % int(d["best_hp"])) ' + BS)
s = s.replace('\t\t\t\telse "到达第 %d 回合" % int(d["best_round"])',
              '\t\t\t\telse tr("到达第 %d 回合") % int(d["best_round"])')
s = s.replace('\t\tbody += "' + BS + 'n今日最佳: %s%s" % [best_txt,',
              '\t\tbody += "' + BS + 'n" + tr("今日最佳: %s%s") % [best_txt,')
s = s.replace('\t\t\t\t" (新纪录!)" if bool(d["better"]) else ""]',
              '\t\t\t\ttr(" (新纪录!)") if bool(d["better"]) else ""]')
io.open(p, "w", encoding="utf-8", newline=NL).write(s)
print("ok fight_panel")
