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


func _ready() -> void:
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
	sfx.play_coin()
	# Small rumble on coin pickup
	Input.start_joy_vibration(0, 0.1, 0.0, 0.05)


func _on_obstacle_hit() -> void:
	score_manager.on_obstacle_hit()
	sfx.play_hit()


func _on_beat() -> void:
	# Subtle controller rumble on beat
	if audio_reactor.bass > 0.3:
		Input.start_joy_vibration(0, audio_reactor.bass * 0.3, 0.0, 0.08)
