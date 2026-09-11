## 终局演出面板（计划 GameEnd 场景的组件化）: 暗幕 + 勝利/敗北大字 + 四家结算。
## 用法: panel.setup(view, seat_namer); fx_layer.add_child(panel)
extends Control

const ScoringGd = preload("res://src/rules/scoring.gd")
const AppTheme = preload("res://src/client/theme/app_theme.gd")


func setup(view: Dictionary, seat_namer: Callable, reward: Dictionary = {}) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var my_rank := int(view["identities"][int(view["my_seat"])])
	Audio.play("win" if my_rank <= 1 else "lose")

	var dark := ColorRect.new()
	dark.color = Color(0, 0, 0, 0.0)
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dark)

	var big := AppTheme.make_label(96, AppTheme.GOLD if my_rank <= 1 else AppTheme.DIM)
	big.add_theme_font_override("font", AppTheme.title_font())
	big.text = "勝利" if my_rank <= 1 else "敗北"
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.set_anchors_preset(Control.PRESET_CENTER)
	big.position = Vector2(-200, -150)
	big.custom_minimum_size = Vector2(400, 130)
	big.pivot_offset = Vector2(200, 65)
	big.scale = Vector2(0.5, 0.5)
	add_child(big)

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
	detail.set_anchors_preset(Control.PRESET_CENTER)
	detail.position = Vector2(-260, -10)
	detail.custom_minimum_size = Vector2(520, 140)
	add_child(detail)

	if not reward.is_empty():
		var gain := AppTheme.make_label(24, AppTheme.GOLD)
		gain.text = "获得  💰+%d   💎+%d" % [int(reward.get("gold", 0)), int(reward.get("diamonds", 0))]
		gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gain.set_anchors_preset(Control.PRESET_CENTER)
		gain.position = Vector2(-200, 96)
		gain.custom_minimum_size = Vector2(400, 40)
		add_child(gain)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(dark, "color:a", 0.55, 0.4)
	tw.tween_property(big, "scale", Vector2.ONE, 0.45)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
