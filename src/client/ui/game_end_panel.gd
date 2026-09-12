## 终局演出面板: 暗幕 + 勝利/敗北大字 + 四家结算 + 金币/钻石结算明细。
## 用法: panel.setup(view, seat_namer, reward); fx_layer.add_child(panel)
## 重开一局时由牌桌清空 fx_layer 关闭本面板。
extends Control

const ScoringGd = preload("res://src/rules/scoring.gd")
const Wallet = preload("res://src/autoload/wallet.gd")
const AppTheme = preload("res://src/client/theme/app_theme.gd")


func setup(view: Dictionary, seat_namer: Callable, reward: Dictionary = {}) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var my_rank := int(view["identities"][int(view["my_seat"])])
	Audio.play("win" if my_rank <= 1 else "lose")

	# 暗幕
	var dark := ColorRect.new()
	dark.color = Color(0, 0, 0, 0.0)
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dark)

	# 居中竖排: 勝利/敗北 → 四家结算 → 金币/钻石明细
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	center.add_child(box)

	var big := AppTheme.make_label(96, AppTheme.GOLD if my_rank <= 1 else AppTheme.DIM)
	big.add_theme_font_override("font", AppTheme.title_font())
	big.text = "勝利" if my_rank <= 1 else "敗北"
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.custom_minimum_size = Vector2(400, 130)
	big.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(big)

	var ids: Array = view["identities"]
	var pts: Array = view["last_points"]
	var scores: Array = view["scores"]
	var lines: Array = []
	for s in 4:
		lines.append("%s  %s  %+d 分（总 %d）" % [
			str(seat_namer.call(s)), ScoringGd.IDENTITY_NAMES[int(ids[s])],
			int(pts[s]), int(scores[s]),
		])
	var detail := AppTheme.make_label(19, AppTheme.WHITE)
	detail.text = "\n".join(lines)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(detail)

	if not reward.is_empty():
		var gain := AppTheme.make_label(24, AppTheme.GOLD)
		gain.text = "结算: 积分 %+d × %d  =  💰 %+d" % [
				int(reward.get("points", 0)), int(reward.get("stakes", 1)),
				int(reward.get("gold", 0))]
		gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gain.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(gain)
		var dia := AppTheme.make_label(19, AppTheme.WHITE)
		dia.text = "💎 +%d    钱包: 💰 %d · 💎 %d" % [
				int(reward.get("diamonds", 0)),
				int(reward.get("wallet_gold", 0)), int(reward.get("wallet_diamonds", 0))]
		dia.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dia.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(dia)

	# 演出: 暗幕淡入 + 大字弹入 + 内容淡入
	big.pivot_offset = Vector2(200, 65)
	big.scale = Vector2(0.5, 0.5)
	box.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(dark, "color:a", 0.55, 0.4)
	tw.tween_property(big, "scale", Vector2.ONE, 0.45)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "modulate:a", 1.0, 0.35)
