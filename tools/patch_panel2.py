# fight_panel.gd: 连击大字 + 怒气条 + 奥义按钮 + 稀有金框 + 事件音效
import io

NL = chr(10)
p = "src/client/ui/fight_panel.gd"
s = io.open(p, encoding="utf-8").read()
pairs = []

# 成员
pairs.append((
    'var overlay: CenterContainer = null   # 结算弹窗(成员持有, 关闭可靠)',
    'var overlay: CenterContainer = null   # 结算弹窗(成员持有, 关闭可靠)'
    + NL + 'var fury_bar: ColorRect' + NL + 'var fury_fg: ColorRect'
    + NL + 'var hits_lbl: Label' + NL + 'var act_ult: Button'))

# 怒气条创建(追加在 battle_box 末尾, 不影响既有子节点索引)
pairs.append((
    '\tfloaters = Control.new()',
    '\t# 怒气条(奥义能量, 金色)' + NL
    + '\tfury_bar = ColorRect.new()' + NL
    + '\tfury_bar.color = Color(0, 0, 0, 0.45)' + NL
    + '\tfury_bar.size = Vector2(240, 8)' + NL
    + '\tbattle_box.add_child(fury_bar)' + NL
    + '\tfury_fg = ColorRect.new()' + NL
    + '\tfury_fg.color = Color("ffd166")' + NL
    + '\tfury_bar.add_child(fury_fg)' + NL
    + '\t# 连击大字(中央)' + NL
    + '\thits_lbl = _label(44, Color("ffd166"))' + NL
    + '\thits_lbl.visible = false' + NL
    + '\thits_lbl.z_index = 15' + NL
    + '\tbattle_box.add_child(hits_lbl)' + NL
    + '\tfloaters = Control.new()'))

# 奥义按钮
pairs.append((
    '\tact_def = AppTheme.make_button("🛡 防御", Vector2(160, 56), 18)',
    '\tact_def = AppTheme.make_button("🛡 防御", Vector2(160, 56), 18)' + NL
    + '\tact_ult = AppTheme.make_button("⚡ 奥义", Vector2(160, 56), 18)'
    + NL + '\tact_ult.disabled = true'))
pairs.append((
    '\tact_row.add_child(act_def)',
    '\tact_row.add_child(act_def)' + NL + '\tact_row.add_child(act_ult)'))
pairs.append((
    '\tact_def.pressed.connect(func() -> void: _on_action("defend"))',
    '\tact_def.pressed.connect(func() -> void: _on_action("defend"))' + NL
    + '\tact_ult.pressed.connect(func() -> void: _on_action("ult"))'))

# 奥义事件演出
pairs.append((
    '\t\t"chilled":' + NL
    + '\t\t\t_floater("❄ 冻结", _px(0.68), _py(0.36), Color("9fd8ff"))',
    '\t\t"ult":' + NL
    + '\t\t\t_floater(tr("奥义 -%d") % v, _px(0.68), _py(0.30), AppTheme.GOLD)'
    + NL + '\t\t\t_shake(12.0)' + NL
    + '\t\t\t_sfx("crit")' + NL
    + '\t\t"parry":' + NL
    + '\t\t\t_floater(tr("完美格挡! 反击 -%d") % v, _px(0.68), _py(0.36),'
    + ' Color("7ec8ff"))' + NL
    + '\t\t\t_sfx("crit")' + NL
    + '\t\t"combo":' + NL
    + '\t\t\t_update_hits()   # 连击大字刷新' + NL
    + '\t\t\t_sfx("tick")' + NL
    + '\t\t"chilled":' + NL
    + '\t\t\t_floater("❄ 冻结", _px(0.68), _py(0.36), Color("9fd8ff"))'))

# 受击音效已有 hurt; 连击大字刷新函数 + 渲染更新
pairs.append((
    '## ── 总渲染: 按引擎 phase 切换可见区 ──',
    '''func _update_hits() -> void:
\tif fm != null and fm.phase == "battle" and fm.hits >= 2:
\t\thits_lbl.visible = true
\t\thits_lbl.text = "COMBO x%d" % fm.hits
\t\thits_lbl.position = Vector2(_px(0.5) - 90.0, _py(0.16))
\t\tvar tw := create_tween()
\t\thits_lbl.scale = Vector2(1.25, 1.25)
\t\ttw.tween_property(hits_lbl, "scale", Vector2.ONE, 0.12)
\telse:
\t\thits_lbl.visible = false


## ── 总渲染: 按引擎 phase 切换可见区 ──'''))

for old, new in pairs:
    assert old in s, "MISS panel2: " + old[:70]
    s = s.replace(old, new, 1)

# _render: 连击显示同步 + 隐藏
s = s.replace('\t_refresh_slots()\n\t_refresh_bars()\n\tvar is_battle',
              '\t_refresh_slots()\n\t_refresh_bars()\n\t_update_hits()\n\tvar is_battle', 1)

# _refresh_bars: 怒气填充
s = s.replace('''	fury_fg''', '''	fury_fg''', 1) if False else s
s = s.replace('''	php_txt.text = "HP %d / %d" % [maxi(fm.hp, 0), mh]''',
              '''	php_txt.text = "HP %d / %d" % [maxi(fm.hp, 0), mh]
	if fury_fg != null:
		fury_fg.size = Vector2(236.0 * float(fm.fury) / 100.0, 8)''', 1)

# 奥义可用性
s = s.replace('''	act_skill.disabled = cd > 0''',
              '''	act_skill.disabled = cd > 0
	act_ult.disabled = fm.fury < 100''', 1)

# _layout_bars: 怒气条位置(玩家血条下方)
s = s.replace('''		var shield_bar: Control = kids[4]
		shield_bar.position = php_bar.position + Vector2(0.0, 40.0)''',
              '''		var shield_bar: Control = kids[4]
		shield_bar.position = php_bar.position + Vector2(0.0, 40.0)
		fury_bar.position = php_bar.position + Vector2(0.0, 50.0)
		fury_fg.size = Vector2(maxf(fury_bar.size.x * float(fm.fury) / 100.0, 0.0), 8)''', 1)

# 候选稀有金框(_build_normal_card): cand >= 200 → 剥离显示 + 金框 + 稀有标签
s = s.replace('''func _build_normal_card(card: int) -> Control:''',
              '''func _build_normal_card(card: int) -> Control:
	var rare := card >= 200
	if rare:
		card = card - 200   # 稀有普通牌: 显示剥离后的卡面''', 1)
s = s.replace('''	var sb := AppTheme.flat(Color(0.10, 0.10, 0.22), Color(1, 1, 1, 0.2), 10, 1)
	wrap.add_theme_stylebox_override("panel", sb)
	var vbox := VBoxContainer.new()''',
              '''	var sb := AppTheme.flat(Color(0.10, 0.10, 0.22),
			AppTheme.GOLD if rare else Color(1, 1, 1, 0.2), 10, 2 if rare else 1)
	wrap.add_theme_stylebox_override("panel", sb)
	var vbox := VBoxContainer.new()''', 1)
s = s.replace('''	var hint := _label(11, Color("c9b06a"))
	hint.text = ("替换后 %s" if slots.size() >= 5 else "装备后 %s") \\
			% str(combo["name"])''',
              '''	var hint := _label(11, Color("ffd166") if rare else Color("c9b06a"))
	hint.text = (tr("稀有!") if rare else "") + ("替换后 %s" if slots.size() >= 5
			else "装备后 %s") % tr(str(combo["name"]))''')

# 候选稀有飘字(_on_candidate)
s = s.replace('''	var r: Dictionary = fm.draft_pick(cand)
	if not bool(r["ok"]):
		return
	if cand >= 100:''',
              '''	var r: Dictionary = fm.draft_pick(cand)
	if not bool(r["ok"]):
		return
	if cand >= 200:
		_floater(tr("稀有卡! 生命上限 +8%"), _px(0.5), _py(0.30),
				Color("ffd166"))
	if cand >= 100:''')

io.open(p, "w", encoding="utf-8", newline=NL).write(s)
print("ok panel fury/combo/rare")
