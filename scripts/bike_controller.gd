extends Node3D
class_name BikeController
## Controls the player's motorcycle. Handles steering, speed, lane switching,
## jumping, boosting, and visual lean/tilt animations.

signal coin_collected(value: int)
signal obstacle_hit

# --- Tuning --- (dialed back: 15% of diff for calm, 50% for loud)
@export var base_speed: float = 28.5      # Dialed back: orig 30, prev 20 → 15%
@export var max_speed: float = 100.0      # Dialed back: orig 80, prev 120 → 50%
@export var steer_speed: float = 16.5     # Dialed back: orig 15, prev 18 → 50%
@export var lane_width: float = 3.5
@export var max_lanes_from_center: float = 2.0
@export var lean_angle: float = 27.5      # Dialed back: orig 25, prev 30 → 50%
@export var lean_speed: float = 9.0       # Dialed back: orig 8, prev 10 → 50%
@export var jump_force: float = 13.0      # Dialed back: orig 12, prev 14 → 50%
@export var gravity: float = 30.0
@export var boost_speed_bonus: float = 30.0  # Dialed back: orig 25, prev 35 → 50%
@export var boost_duration: float = 2.25
@export var boost_max: float = 100.0

# --- State ---
var current_speed: float = 0.0
var lateral_position: float = 0.0  # X position on the road
var vertical_velocity: float = 0.0
var is_grounded: bool = true
var is_boosting: bool = false
var boost_meter: float = 50.0
var _boost_timer: float = 0.0
var current_lean: float = 0.0
var invincible_timer: float = 0.0
var _spin_tween: Tween

# References
@onready var bike_mesh: Node3D = $BikeMesh
@onready var collision_area: Area3D = $CollisionArea
var audio_reactor: AudioReactor

# Road bounds (updated by road generator)
var road_half_width: float = 7.0


func _ready() -> void:
	current_speed = base_speed
	if collision_area:
		collision_area.area_entered.connect(_on_area_entered)


func _process(delta: float) -> void:
	_handle_input(delta)
	_update_speed(delta)
	_update_position(delta)
	_update_lean(delta)
	_update_boost(delta)
	_update_invincibility(delta)


func _handle_input(delta: float) -> void:
	# Steering (analog stick or keys)
	var steer_input := Input.get_axis("steer_left", "steer_right")
	lateral_position += steer_input * steer_speed * delta

	# Lane switching (quick snap)
	if Input.is_action_just_pressed("lane_switch_left"):
		lateral_position -= lane_width
	if Input.is_action_just_pressed("lane_switch_right"):
		lateral_position += lane_width

	# Clamp to road bounds
	var max_x := road_half_width - 1.0
	lateral_position = clampf(lateral_position, -max_x, max_x)

	# Jump
	if Input.is_action_just_pressed("jump") and is_grounded:
		vertical_velocity = jump_force
		is_grounded = false

	# Boost
	if Input.is_action_just_pressed("boost") and boost_meter >= 20.0 and not is_boosting:
		is_boosting = true
		_boost_timer = boost_duration
		boost_meter -= 20.0


func _update_speed(delta: float) -> void:
	# Base speed influenced by audio energy — balanced reactivity
	var target_speed := base_speed
	if audio_reactor:
		# Energy drives speed: dialed back from *70 to *45 (orig *20, 50% of diff)
		target_speed += audio_reactor.energy * 45.0

		# Bass hits give speed surges (orig 0, prev 15 → 50%)
		target_speed += audio_reactor.bass * 7.5

		# BPM influence — fast songs feel faster (dialed back 50%)
		target_speed += remap(audio_reactor.bpm, 60.0, 200.0, -7.5, 20.0)

		# Beat hits give speed kick (orig 0, prev 10 → 50%)
		if audio_reactor.is_beat:
			target_speed += 5.0

	# Accelerate / brake (dialed back 50%)
	if Input.is_action_pressed("accelerate"):
		target_speed += 17.5
	if Input.is_action_pressed("brake"):
		target_speed -= 25.0

	# Boost
	if is_boosting:
		target_speed += boost_speed_bonus

	target_speed = clampf(target_speed, 10.0, max_speed)
	# Speed lerp: dialed back from 8.0 to 5.5 (orig 3.0, 50% of diff)
	current_speed = lerp(current_speed, target_speed, 5.5 * delta)


func _update_position(delta: float) -> void:
	# Vertical movement (jump arc)
	if not is_grounded:
		vertical_velocity -= gravity * delta
		position.y += vertical_velocity * delta
		if position.y <= 0.0:
			position.y = 0.0
			vertical_velocity = 0.0
			is_grounded = true

	# Apply lateral position
	position.x = lateral_position

	# Forward movement is handled by the world scrolling toward us,
	# but we keep a Z reference for the camera
	# The bike stays at Z=0, the road moves toward it


func _update_lean(delta: float) -> void:
	# Visual lean based on steering input
	var steer_input := Input.get_axis("steer_left", "steer_right")
	var target_lean := -steer_input * lean_angle
	current_lean = lerp(current_lean, target_lean, lean_speed * delta)

	if bike_mesh:
		bike_mesh.rotation_degrees.z = current_lean
		# Slight forward pitch when accelerating
		var accel_input := Input.get_action_strength("accelerate")
		bike_mesh.rotation_degrees.x = lerp(bike_mesh.rotation_degrees.x, -accel_input * 5.0, 4.0 * delta)


func _update_boost(delta: float) -> void:
	if is_boosting:
		_boost_timer -= delta
		if _boost_timer <= 0.0:
			is_boosting = false

	# Passive boost recharge
	if not is_boosting:
		boost_meter = minf(boost_meter + 5.0 * delta, boost_max)

	# Audio beats give small boost charges
	if audio_reactor and audio_reactor.is_beat:
		boost_meter = minf(boost_meter + 2.0, boost_max)


func _update_invincibility(delta: float) -> void:
	if invincible_timer > 0.0:
		invincible_timer -= delta
		# Flash the bike mesh (blink on/off)
		if bike_mesh:
			bike_mesh.visible = fmod(invincible_timer, 0.2) > 0.1
		# When invincibility ends, ensure the bike is visible again
		if invincible_timer <= 0.0:
			invincible_timer = 0.0
			if bike_mesh:
				bike_mesh.visible = true


func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("coin"):
		var value := 10
		coin_collected.emit(value)
		area.queue_free()
	elif area.is_in_group("obstacle"):
		if invincible_timer <= 0.0:
			obstacle_hit.emit()
			invincible_timer = 2.0
			current_speed *= 0.5
			# Controller rumble
			Input.start_joy_vibration(0, 0.5, 0.8, 0.3)
			# 720-degree crash spin
			if bike_mesh:
				if _spin_tween and _spin_tween.is_valid():
					_spin_tween.kill()
				_spin_tween = create_tween()
				var start_y: float = bike_mesh.rotation.y
				_spin_tween.tween_property(bike_mesh, "rotation:y", start_y + PI * 4.0, 1.0) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				_spin_tween.tween_callback(func() -> void: bike_mesh.rotation.y = fmod(bike_mesh.rotation.y, TAU))


func get_speed_ratio() -> float:
	return current_speed / max_speed
