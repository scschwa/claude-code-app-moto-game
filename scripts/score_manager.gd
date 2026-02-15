extends Node
class_name ScoreManager
## Tracks score, multipliers, combos, and near-miss bonuses.

signal score_changed(new_score: int)
signal multiplier_changed(new_multiplier: float)
signal combo_changed(new_combo: int)
signal score_popup_requested(points: int, combo_count: int)

var score: int = 0
var multiplier: float = 1.0
var combo: int = 0
var high_score: int = 0

# Quiet zone multiplier: builds during calm sections, applied during intense ones
var quiet_bonus: float = 0.0

# Combo timing
var _combo_timer: float = 0.0
const COMBO_TIMEOUT := 2.0
const MAX_MULTIPLIER := 8.0

var audio_reactor: AudioReactor


func _process(delta: float) -> void:
	# Combo decay
	if combo > 0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_break_combo()

	# Quiet zone bonus: builds when energy is low
	if audio_reactor and audio_reactor.energy < 0.2:
		quiet_bonus = minf(quiet_bonus + delta * 0.5, 3.0)

	# Update multiplier based on combo
	var target_mult := 1.0 + combo * 0.5 + quiet_bonus
	target_mult = minf(target_mult, MAX_MULTIPLIER)
	if absf(multiplier - target_mult) > 0.01:
		multiplier = target_mult
		multiplier_changed.emit(multiplier)


func add_coin_score(base_value: int) -> void:
	# On-beat bonus
	var beat_bonus := 1.0
	if audio_reactor and audio_reactor.is_beat:
		beat_bonus = 2.0

	var points := int(base_value * multiplier * beat_bonus)
	score += points
	combo += 1
	_combo_timer = COMBO_TIMEOUT

	# Consume quiet bonus on first coin in an intense section
	if audio_reactor and audio_reactor.energy > 0.5 and quiet_bonus > 0.0:
		var quiet_points := int(base_value * quiet_bonus)
		score += quiet_points
		points += quiet_points
		quiet_bonus = 0.0

	score_changed.emit(score)
	combo_changed.emit(combo)
	multiplier_changed.emit(multiplier)
	score_popup_requested.emit(points, combo)


func add_near_miss_score() -> void:
	var points := int(25 * multiplier)
	score += points
	combo += 1
	_combo_timer = COMBO_TIMEOUT
	score_changed.emit(score)
	combo_changed.emit(combo)
	score_popup_requested.emit(points, combo)


func on_obstacle_hit() -> void:
	_break_combo()
	quiet_bonus = 0.0


func _break_combo() -> void:
	if combo > 0:
		combo = 0
		multiplier = 1.0
		combo_changed.emit(combo)
		multiplier_changed.emit(multiplier)
