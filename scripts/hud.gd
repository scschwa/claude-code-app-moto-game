extends CanvasLayer
class_name HUD
## Heads-up display showing score, multiplier, combo, boost meter,
## spectrum visualizer, and audio-reactive visual feedback.

@onready var score_label: Label = $ScoreLabel
@onready var multiplier_label: Label = $MultiplierLabel
@onready var combo_label: Label = $ComboLabel
@onready var boost_bar: ProgressBar = $BoostBar
@onready var speed_label: Label = $SpeedLabel
@onready var bpm_label: Label = $BPMLabel
@onready var beat_flash: ColorRect = $BeatFlash
@onready var spectrum_visualizer: SpectrumVisualizer = $SpectrumVisualizer

var _beat_flash_alpha: float = 0.0
var audio_reactor: AudioReactor


func _ready() -> void:
	if beat_flash:
		beat_flash.color = Color(1.0, 1.0, 1.0, 0.0)

	# Alarm-clock style monospace font for score display
	if score_label:
		var mono_font := SystemFont.new()
		mono_font.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console"])
		mono_font.antialiasing = TextServer.FONT_ANTIALIASING_LCD
		score_label.add_theme_font_override("font", mono_font)

	# Wire the visualizer to the audio reactor (deferred so audio_reactor is set by main.gd)
	_wire_visualizer.call_deferred()


func _wire_visualizer() -> void:
	if spectrum_visualizer and audio_reactor:
		spectrum_visualizer.audio_reactor = audio_reactor


func _process(delta: float) -> void:
	# Beat flash decay
	_beat_flash_alpha = maxf(_beat_flash_alpha - delta * 4.0, 0.0)
	if beat_flash:
		beat_flash.color.a = _beat_flash_alpha

	# BPM display
	if audio_reactor and bpm_label:
		bpm_label.text = "%d BPM" % int(audio_reactor.bpm)

	# Flash on beat — halved for less screen wash
	if audio_reactor and audio_reactor.is_beat:
		_beat_flash_alpha = 0.075


func update_score(value: int) -> void:
	if score_label:
		score_label.text = "Total Score: %d" % value
		var tween := create_tween()
		tween.tween_property(score_label, "scale", Vector2(1.3, 1.3), 0.05)
		tween.tween_property(score_label, "scale", Vector2(1.0, 1.0), 0.15)


func update_multiplier(value: float) -> void:
	if multiplier_label:
		if value > 1.0:
			multiplier_label.text = "x%.1f" % value
			multiplier_label.visible = true
			var t := remap(value, 1.0, 8.0, 0.0, 1.0)
			multiplier_label.modulate = Color(1.0, 1.0 - t * 0.5, 1.0 - t, 1.0)
		else:
			multiplier_label.visible = false


func update_combo(_value: int) -> void:
	# Combo display is now handled by 3D world-space popups from main.gd
	if combo_label:
		combo_label.visible = false


func update_boost(value: float, max_value: float) -> void:
	if boost_bar:
		boost_bar.value = value
		boost_bar.max_value = max_value
		var ratio := value / max_value
		var bar_style := boost_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if bar_style:
			bar_style.bg_color = Color(1.0 - ratio, ratio * 0.9, ratio)


func update_speed(speed: float, max_speed: float) -> void:
	if speed_label:
		var display_speed := int(speed * 3.6)
		speed_label.text = "%d km/h" % display_speed
