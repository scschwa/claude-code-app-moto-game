extends Control
class_name SpectrumVisualizer
## Draws a real-time spectrum analyzer / waveform visualization.
## Shows frequency bars with color coding (bass=magenta, mids=cyan, highs=white)
## and an energy waveform history. Also displays whether audio is live or synthetic.

var audio_reactor: AudioReactor

# Waveform history (rolling graph of overall energy)
var _energy_history: PackedFloat32Array
const HISTORY_LENGTH := 120  # frames of history

# Beat flash
var _beat_flash: float = 0.0

# Colors
const COLOR_BASS := Color(1.0, 0.2, 0.6)       # Hot pink
const COLOR_MIDS := Color(0.0, 0.85, 1.0)       # Cyan
const COLOR_HIGHS := Color(1.0, 1.0, 1.0, 0.9)  # White
const COLOR_BG := Color(0.0, 0.0, 0.0, 0.4)     # Semi-transparent black
const COLOR_BORDER := Color(1.0, 1.0, 1.0, 0.15)
const COLOR_WAVEFORM := Color(1.0, 0.4, 0.2, 0.8)  # Orange
const COLOR_SYNTHETIC := Color(1.0, 0.8, 0.0, 0.7)  # Yellow warning
const COLOR_LIVE := Color(0.0, 1.0, 0.5, 0.7)       # Green


func _ready() -> void:
	_energy_history.resize(HISTORY_LENGTH)
	_energy_history.fill(0.0)


func _process(delta: float) -> void:
	if audio_reactor == null:
		return

	# Push energy to history
	# Shift left
	for i in range(HISTORY_LENGTH - 1):
		_energy_history[i] = _energy_history[i + 1]
	_energy_history[HISTORY_LENGTH - 1] = audio_reactor.energy

	# Beat flash
	if audio_reactor.is_beat:
		_beat_flash = 1.0
	_beat_flash = maxf(_beat_flash - delta * 6.0, 0.0)

	# Trigger redraw every frame
	queue_redraw()


func _draw() -> void:
	if audio_reactor == null:
		return

	var rect := get_rect()
	var w := rect.size.x
	var h := rect.size.y

	# Background
	var bg_color := COLOR_BG
	if _beat_flash > 0.0:
		bg_color = bg_color.lerp(Color(0.3, 0.1, 0.2, 0.5), _beat_flash * 0.3)
	draw_rect(Rect2(Vector2.ZERO, rect.size), bg_color)
	draw_rect(Rect2(Vector2.ZERO, rect.size), COLOR_BORDER, false, 1.0)

	# --- Spectrum bars (bottom 60% of the widget) ---
	var bar_area_h := h * 0.55
	var bar_area_y := h - bar_area_h
	var band_count := audio_reactor.VISUALIZER_BANDS
	var bar_width := (w - 4.0) / float(band_count)
	var gap := 1.0

	for i in band_count:
		var value: float = audio_reactor.spectrum_data[i]
		var bar_h := value * bar_area_h
		var x := 2.0 + i * bar_width
		var y := h - bar_h

		# Color: blend from bass (pink) through mids (cyan) to highs (white)
		var t := float(i) / float(band_count)
		var bar_color: Color
		if t < 0.33:
			bar_color = COLOR_BASS.lerp(COLOR_MIDS, t / 0.33)
		else:
			bar_color = COLOR_MIDS.lerp(COLOR_HIGHS, (t - 0.33) / 0.67)

		# Brighten on beat
		if _beat_flash > 0.0:
			bar_color = bar_color.lerp(Color.WHITE, _beat_flash * 0.3)

		draw_rect(Rect2(Vector2(x, y), Vector2(bar_width - gap, bar_h)), bar_color)

	# --- Energy waveform (top 35% of the widget) ---
	var wave_area_h := h * 0.30
	var wave_area_y := 4.0
	var points := PackedVector2Array()

	for i in HISTORY_LENGTH:
		var x := 2.0 + (float(i) / float(HISTORY_LENGTH - 1)) * (w - 4.0)
		var y := wave_area_y + wave_area_h - _energy_history[i] * wave_area_h
		points.append(Vector2(x, y))

	if points.size() > 1:
		draw_polyline(points, COLOR_WAVEFORM, 1.5, true)

	# --- Status indicator ---
	var status_color: Color
	var status_text: String
	match audio_reactor.audio_mode:
		"music_file":
			status_color = COLOR_LIVE
			status_text = "MUSIC"
		"mic_loopback":
			status_color = Color(0.3, 0.7, 1.0, 0.7)  # Blue
			status_text = "MIC"
		_:
			status_color = COLOR_SYNTHETIC
			status_text = "SYNTHETIC"

	# Draw status dot and label
	var dot_pos := Vector2(8.0, wave_area_y + wave_area_h + 8.0)
	draw_circle(dot_pos, 4.0, status_color)

	var font := ThemeDB.fallback_font
	if font:
		var font_size := 11
		draw_string(font, dot_pos + Vector2(10.0, 4.0), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, status_color)

		# Show track name if playing a music file
		if audio_reactor.audio_mode == "music_file" and audio_reactor.current_track_name != "":
			var track_text := audio_reactor.current_track_name
			if track_text.length() > 28:
				track_text = track_text.left(25) + "..."
			draw_string(font, dot_pos + Vector2(70.0, 4.0), track_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.5))
		elif audio_reactor.audio_mode == "synthetic":
			draw_string(font, dot_pos + Vector2(85.0, 4.0), "No audio input", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.8, 0, 0.4))

		# Draw band labels
		var bass_label_x := 2.0 + (0.1 * band_count) * bar_width
		var mid_label_x := 2.0 + (0.4 * band_count) * bar_width
		var high_label_x := 2.0 + (0.75 * band_count) * bar_width
		var label_y := h - 2.0

		draw_string(font, Vector2(bass_label_x, label_y), "BASS", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLOR_BASS * Color(1, 1, 1, 0.6))
		draw_string(font, Vector2(mid_label_x, label_y), "MID", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLOR_MIDS * Color(1, 1, 1, 0.6))
		draw_string(font, Vector2(high_label_x, label_y), "HIGH", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLOR_HIGHS * Color(1, 1, 1, 0.6))
