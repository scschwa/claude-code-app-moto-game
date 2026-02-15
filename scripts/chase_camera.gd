extends Camera3D
class_name ChaseCamera
## Third-person camera that follows the bike with smooth lag,
## FOV changes based on speed, and subtle shake on beats.
## Camera sits BEHIND the bike (+Z) and looks FORWARD (-Z).

@export var follow_offset := Vector3(0, 4.0, 8.0)
@export var look_ahead := Vector3(0, 1.5, -10.0)
@export var follow_speed := 5.0
@export var fov_min := 64.0     # Dialed back: orig 65, prev 60 → 15% of diff
@export var fov_max := 97.5     # Dialed back: orig 90, prev 105 → 50% of diff

var bike: BikeController
var audio_reactor: AudioReactor

var _shake_amount: float = 0.0
var _shake_decay: float = 8.0


func _process(delta: float) -> void:
	if bike == null:
		return

	# Target position: behind and above the bike (+Z is behind in forward=-Z convention)
	var target_pos := bike.global_position + follow_offset
	# Offset laterally to follow bike's steering slightly
	target_pos.x = lerp(global_position.x, bike.lateral_position * 0.5 + follow_offset.x, 2.0 * delta)

	global_position = global_position.lerp(target_pos, follow_speed * delta)

	# Look at a point ahead of the bike (into -Z)
	var look_target := bike.global_position + look_ahead
	look_target.x = bike.lateral_position * 0.3
	look_at(look_target, Vector3.UP)

	# FOV shifts with speed — balanced range and response
	var speed_ratio := bike.get_speed_ratio() if bike else 0.0
	var target_fov := remap(speed_ratio, 0.0, 1.0, fov_min, fov_max)

	# Energy pushes FOV wider — baseline -20%
	if audio_reactor:
		target_fov += audio_reactor.energy * 4.0

	# Beat FOV kick — baseline -20%
	if audio_reactor and audio_reactor.is_beat:
		target_fov += audio_reactor.bass * 2.0

	target_fov = clampf(target_fov, fov_min, fov_max + 5.0)
	fov = lerp(fov, target_fov, 4.5 * delta)  # Dialed back: orig 3.0, prev 6.0 → 50%

	# Beat shake — baseline -20%
	if audio_reactor and audio_reactor.is_beat:
		_shake_amount = audio_reactor.bass * 0.22

	if _shake_amount > 0.001:
		var shake_offset := Vector3(
			randf_range(-_shake_amount, _shake_amount),
			randf_range(-_shake_amount, _shake_amount) * 0.7,
			randf_range(-_shake_amount, _shake_amount) * 0.3
		)
		global_position += shake_offset
		_shake_amount = lerp(_shake_amount, 0.0, _shake_decay * delta)
