extends Node3D
## Main game scene — wires together all game systems:
## AudioReactor, BikeController, RoadGenerator, ScoreManager, VisualReactor, HUD.

@onready var audio_reactor: AudioReactor = $AudioReactor
@onready var bike: BikeController = $Bike
@onready var road_generator: RoadGenerator = $RoadGenerator
@onready var score_manager: ScoreManager = $ScoreManager
@onready var visual_reactor: VisualReactor = $VisualReactor
@onready var chase_camera: ChaseCamera = $ChaseCamera
@onready var hud: HUD = $HUD
@onready var sfx: Node = $SfxManager

const ScorePopupScript := preload("res://scripts/score_popup.gd")

var _combo_popup_side: float = 1.0  # Alternates ±1 for left/right combo popups


func _ready() -> void:
	# Edge smoothing — MSAA removes geometry aliasing, FXAA catches the rest
	get_viewport().msaa_3d = Viewport.MSAA_4X
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA

	# Wire up references
	bike.audio_reactor = audio_reactor
	road_generator.audio_reactor = audio_reactor
	road_generator.bike = bike
	score_manager.audio_reactor = audio_reactor
	visual_reactor.audio_reactor = audio_reactor
	chase_camera.bike = bike
	chase_camera.audio_reactor = audio_reactor
	hud.audio_reactor = audio_reactor

	# Connect signals
	bike.coin_collected.connect(_on_coin_collected)
	bike.obstacle_hit.connect(_on_obstacle_hit)
	score_manager.score_changed.connect(hud.update_score)
	score_manager.multiplier_changed.connect(hud.update_multiplier)
	score_manager.combo_changed.connect(hud.update_combo)
	score_manager.combo_changed.connect(_on_combo_changed)
	score_manager.score_popup_requested.connect(_on_score_popup)

	# Controller rumble on beat
	audio_reactor.beat_detected.connect(_on_beat)

	print("=== DESERT PULSE ===")
	print("Ride the rhythm. Every song is a new road.")
	print("")
	print("Controls:")
	print("  A/D or Left Stick: Steer")
	print("  W/S or RT/LT: Accelerate/Brake")
	print("  Space or A button: Jump")
	print("  Shift or B button: Boost")
	print("  Q/E or LB/RB: Quick lane switch")
	print("")
	print("Music: Place .ogg or .wav files in res://music/ or user://music/")
	print("The game plays them and reacts to the audio in real time.")
	print("Check the spectrum visualizer (bottom-right) for audio status.")


func _process(_delta: float) -> void:
	# Update HUD with bike stats
	hud.update_boost(bike.boost_meter, bike.boost_max)
	hud.update_speed(bike.current_speed, bike.max_speed)


func _on_coin_collected(value: int) -> void:
	score_manager.add_coin_score(value)
	sfx.play_coin(score_manager.combo)
	# Small rumble on coin pickup
	Input.start_joy_vibration(0, 0.1, 0.0, 0.05)


func _on_obstacle_hit(obstacle_area: Area3D) -> void:
	score_manager.on_obstacle_hit()
	sfx.play_hit()
	# Break the obstacle apart if it's a real obstacle (not off-road null)
	if obstacle_area != null:
		_break_obstacle(obstacle_area)


func _on_combo_changed(combo_count: int) -> void:
	# Spawn 3D combo popup centered below the bike
	if combo_count > 2:
		var popup: Node3D = ScorePopupScript.new()
		add_child(popup)
		var spawn_pos := bike.global_position + Vector3(
			0.0,
			-0.5,
			-0.3
		)
		popup.setup_combo(combo_count, spawn_pos, 0.0)


func _on_score_popup(points: int, combo_count: int) -> void:
	var popup: Node3D = ScorePopupScript.new()
	add_child(popup)
	# Spawn above the bike with slight jitter to avoid perfect overlap
	var spawn_pos := bike.global_position + Vector3(
		randf_range(-0.3, 0.3),
		2.5 + combo_count * 0.02,
		-0.5
	)
	popup.setup(points, combo_count, spawn_pos)


func _break_obstacle(obstacle_area: Area3D) -> void:
	## Flash the obstacle bright and break it into flying/spinning/fading fragments.
	var obstacle_node: Node3D = obstacle_area.get_parent() as Node3D
	if obstacle_node == null:
		return

	# Find and hide the original mesh, disable collision
	var original_mesh: MeshInstance3D = null
	for child in obstacle_node.get_children():
		if child is MeshInstance3D:
			original_mesh = child
			child.visible = false
		if child is Area3D:
			child.monitoring = false
			child.monitorable = false

	var break_pos: Vector3 = obstacle_node.global_position
	if original_mesh == null:
		break_pos += Vector3(0, 0.5, 0)

	# Bright flash material for fragments
	var flash_mat := StandardMaterial3D.new()
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.albedo_color = Color(1.0, 0.9, 0.7, 1.0)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.6, 0.2)
	flash_mat.emission_energy_multiplier = 5.0

	# Spawn fragment boxes
	var fragment_count := 5
	for i in fragment_count:
		var frag := MeshInstance3D.new()
		var frag_box := BoxMesh.new()
		var frag_size := randf_range(0.2, 0.6)
		frag_box.size = Vector3(frag_size, frag_size * randf_range(0.5, 1.5), frag_size * randf_range(0.5, 1.5))
		frag_box.material = flash_mat
		frag.mesh = frag_box
		frag.global_position = break_pos + Vector3(
			randf_range(-0.5, 0.5),
			randf_range(0.0, 0.8),
			randf_range(-0.5, 0.5)
		)
		add_child(frag)

		# Fly outward + upward, then gravity drop
		var fly_dir := Vector3(
			randf_range(-3.0, 3.0),
			randf_range(2.0, 5.0),
			randf_range(-2.0, 2.0)
		)
		var end_pos := frag.global_position + fly_dir

		var move_tw := create_tween()
		move_tw.tween_property(frag, "global_position", end_pos, 0.4) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		# Gravity drop
		move_tw.tween_property(frag, "global_position:y", end_pos.y - 4.0, 0.4) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

		# Random spin
		var spin_tw := create_tween()
		var spin_axis := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var spin_amount := randf_range(PI * 2, PI * 6)
		spin_tw.tween_property(frag, "rotation", spin_axis * spin_amount, 0.8) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

		# Scale down to nothing
		var scale_tw := create_tween()
		scale_tw.tween_interval(0.3)
		scale_tw.tween_property(frag, "scale", Vector3.ONE * 0.05, 0.5)

		# Self-destruct fragment
		scale_tw.tween_callback(frag.queue_free)

	# Remove the original obstacle after fragments are done
	var cleanup_tw := create_tween()
	cleanup_tw.tween_interval(1.0)
	cleanup_tw.tween_callback(obstacle_node.queue_free)


func _on_beat() -> void:
	# Subtle controller rumble on beat
	if audio_reactor.bass > 0.3:
		Input.start_joy_vibration(0, audio_reactor.bass * 0.3, 0.0, 0.08)
