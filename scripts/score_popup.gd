extends Node3D
class_name ScorePopup
## Floating 3D score text that pops above the bike on coin/near-miss pickup.
## Scales with combo — higher combos produce bigger, more colorful popups.
## Self-destructs after the animation completes.

var _label: Label3D


func setup(points: int, combo_count: int, spawn_position: Vector3) -> void:
	global_position = spawn_position
	scale = Vector3.ONE * 0.01  # Start nearly invisible

	_label = Label3D.new()
	_label.text = "+%d" % points
	_label.font_size = 72
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true  # Always visible on top
	_label.modulate = _color_for_combo(combo_count)
	_label.outline_modulate = Color(0, 0, 0, 0.8)
	_label.outline_size = 8
	add_child(_label)

	_animate(combo_count)


func _color_for_combo(combo_count: int) -> Color:
	if combo_count < 3:
		return Color(1, 1, 1, 1)       # White
	if combo_count < 10:
		return Color(1, 0.9, 0.2, 1)   # Gold
	if combo_count < 20:
		return Color(1, 0.5, 0.1, 1)   # Orange
	return Color(1, 0.2, 0.5, 1)       # Hot pink


func _animate(combo_count: int) -> void:
	# Peak scale grows with combo: 0.5 at combo 0, up to 2.0 at combo 25+
	var peak_scale := 0.5 + clampf(combo_count * 0.06, 0.0, 1.5)

	# Scale: pop in with overshoot, then shrink away
	var scale_tween := create_tween()
	scale_tween.tween_property(self, "scale", Vector3.ONE * peak_scale, 0.12) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	scale_tween.tween_property(self, "scale", Vector3.ONE * 0.1, 0.6) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	# Float upward
	var move_tween := create_tween()
	move_tween.tween_property(self, "position:y", position.y + 3.0, 0.8) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Fade out (delayed so it's fully visible at peak, then fades)
	var fade_tween := create_tween()
	fade_tween.tween_interval(0.25)
	fade_tween.tween_property(_label, "modulate:a", 0.0, 0.5)

	# Self-destruct after longest animation
	fade_tween.tween_callback(queue_free)


func setup_combo(combo_count: int, spawn_position: Vector3, _side: float) -> void:
	## Centered combo popup below the bike. Text grows aggressively with combo.
	global_position = spawn_position
	scale = Vector3.ONE * 0.01

	_label = Label3D.new()
	_label.text = "%dx Combo" % combo_count
	# Font size grows aggressively: 48 at combo 3, up to 200+ at high combos
	_label.font_size = 48 + combo_count * 8
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.modulate = _color_for_combo(combo_count)
	_label.outline_modulate = Color(0, 0, 0, 0.8)
	_label.outline_size = 12
	add_child(_label)

	_animate_combo(combo_count)


func _animate_combo(combo_count: int) -> void:
	## Pop in centered, scale aggressively with combo, float down slightly, fade out.
	# Peak scale grows much more with combo: 0.3 at combo 3, huge at combo 15+
	var peak_scale := 0.3 + clampf(combo_count * 0.08, 0.0, 2.5)

	# Scale: pop in with overshoot, then shrink
	var scale_tween := create_tween()
	scale_tween.tween_property(self, "scale", Vector3.ONE * peak_scale, 0.1) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	scale_tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.8) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	# Float downward slightly from spawn point
	var down_tween := create_tween()
	down_tween.tween_property(self, "position:y", position.y - 1.0, 0.9) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Fade out
	var fade_tween := create_tween()
	fade_tween.tween_interval(0.25)
	fade_tween.tween_property(_label, "modulate:a", 0.0, 0.65)
	fade_tween.tween_callback(queue_free)
