extends Node
class_name AudioReactor
## Real-time audio analysis engine for Desert Pulse.
##
## TWO audio modes:
##   1. MUSIC FILE — plays an .ogg/.mp3/.wav from res://music/ or user://music/
##      through the Master bus. The spectrum analyzer on Master captures it.
##   2. MIC LOOPBACK — captures system audio via AudioStreamMicrophone on a
##      separate bus (requires Stereo Mix enabled in Windows).
##
## The game tries music files first. If none are found, it falls back to mic
## capture. If that also produces silence, it enters synthetic fallback mode.
##
## Provides both LIVE values (for visuals/HUD) and DELAYED values (for terrain
## generation), giving the player time to react to rhythm changes.

signal beat_detected
signal intensity_changed(value: float)
signal track_changed(track_name: String)

# --- Exposed LIVE reactive values (used by visuals, HUD, camera) ---
var energy: float = 0.0
var bass: float = 0.0
var mids: float = 0.0
var highs: float = 0.0
var bpm: float = 120.0
var is_beat: bool = false
var spectral_flux: float = 0.0
var onset_density: float = 0.0
var is_synthetic: bool = false

# --- Exposed DELAYED reactive values (used by terrain/road generation) ---
var delayed_energy: float = 0.0
var delayed_bass: float = 0.0
var delayed_mids: float = 0.0
var delayed_highs: float = 0.0
var delayed_onset_density: float = 0.0
var delayed_spectral_flux: float = 0.0

@export var delay_seconds: float = 5.0

# --- Spectrum band data for visualizer (live, 32 bands) ---
const VISUALIZER_BANDS := 32
var spectrum_data: PackedFloat32Array

# --- Current track info ---
var current_track_name: String = ""
var audio_mode: String = "none"  # "music_file", "mic_loopback", "synthetic"

# --- Audio capture ---
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _music_player: AudioStreamPlayer
var _mic_player: AudioStreamPlayer
var _track_list: PackedStringArray
var _current_track_index: int = 0

# --- Analysis state ---
var _prev_magnitudes: PackedFloat32Array
var _energy_history: PackedFloat32Array
var _beat_history: Array[float] = []
var _onset_times: Array[float] = []
var _flux_threshold: float = 0.08  # Dialed back: orig 0.15, prev 0.005
var _energy_smooth: float = 0.0

# --- Delay buffer ---
var _delay_buffer: Array[PackedFloat32Array] = []

# Smoothing factors — decay -20% for calmer quiet sections
const SMOOTH_FAST := 0.30
const SMOOTH_SLOW := 0.15
const SMOOTH_DECAY := 0.044	# 20% slower decay → values settle to zero faster in quiet parts
const BEAT_COOLDOWN := 0.135	# Dialed back: orig 0.15, prev 0.12 → 50% of diff
var _beat_cooldown_timer: float = 0.0

# FFT band ranges (Hz)
const BASS_LOW := 20.0
const BASS_HIGH := 250.0
const MID_LOW := 250.0
const MID_HIGH := 2000.0
const HIGH_LOW := 2000.0
const HIGH_HIGH := 16000.0

# Fallback mode
var _silence_timer: float = 0.0
const SILENCE_THRESHOLD := 3.0
var _synthetic_mode: bool = false
var _synthetic_phase: float = 0.0

# Visualizer band edges
var _band_edges: PackedFloat32Array


func _ready() -> void:
	_prev_magnitudes.resize(256)
	_prev_magnitudes.fill(0.0)
	_energy_history.resize(60)
	_energy_history.fill(0.0)
	spectrum_data.resize(VISUALIZER_BANDS)
	spectrum_data.fill(0.0)
	_compute_band_edges()

	# Put spectrum analyzer on the Master bus so it captures everything
	_setup_master_analyzer()

	# Try to find and play music files
	_scan_music_files()

	if _track_list.size() > 0:
		_setup_music_player()
		_play_track(0)
	else:
		# No music files found — try mic loopback as fallback
		_setup_mic_loopback()


func _compute_band_edges() -> void:
	_band_edges.resize(VISUALIZER_BANDS + 1)
	var log_min := log(20.0)
	var log_max := log(16000.0)
	for i in VISUALIZER_BANDS + 1:
		var t := float(i) / float(VISUALIZER_BANDS)
		_band_edges[i] = exp(log_min + t * (log_max - log_min))


func _setup_master_analyzer() -> void:
	## Attach a spectrum analyzer to the Master bus (index 0).
	## This captures ALL audio playing through Godot, including music files.
	var master_idx := 0

	var has_spectrum := false
	for i in AudioServer.get_bus_effect_count(master_idx):
		if AudioServer.get_bus_effect(master_idx, i) is AudioEffectSpectrumAnalyzer:
			has_spectrum = true
			_spectrum = AudioServer.get_bus_effect_instance(master_idx, i)
			break

	if not has_spectrum:
		var analyzer := AudioEffectSpectrumAnalyzer.new()
		analyzer.buffer_length = 0.1
		analyzer.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
		AudioServer.add_bus_effect(master_idx, analyzer)
		_spectrum = AudioServer.get_bus_effect_instance(master_idx, AudioServer.get_bus_effect_count(master_idx) - 1)

	print("[AudioReactor] Spectrum analyzer attached to Master bus")


func _scan_music_files() -> void:
	## Scan for music files in res://music/ and user://music/
	_track_list = PackedStringArray()

	# Check res://music/ (bundled with the game)
	_scan_directory("res://music")

	# Check user://music/ (user can drop files here)
	_scan_directory("user://music")

	if _track_list.size() > 0:
		print("[AudioReactor] Found %d music file(s):" % _track_list.size())
		for track in _track_list:
			print("  - %s" % track)
	else:
		print("[AudioReactor] No music files found in res://music/ or user://music/")
		print("[AudioReactor] To play your own music, place .mp3, .ogg, or .wav files in:")
		print("  %s" % ProjectSettings.globalize_path("user://music/"))


func _scan_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		# Try creating user://music/ if it doesn't exist
		if path == "user://music":
			DirAccess.make_dir_recursive_absolute(path)
			print("[AudioReactor] Created directory: %s" % ProjectSettings.globalize_path(path))
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var lower := file_name.to_lower()
			if lower.ends_with(".ogg") or lower.ends_with(".wav") or lower.ends_with(".mp3"):
				_track_list.append(path + "/" + file_name)
			# Also check for .import files (Godot imports audio resources)
			elif lower.ends_with(".ogg.import") or lower.ends_with(".wav.import") or lower.ends_with(".mp3.import"):
				var base := file_name.get_basename()  # strips .import
				_track_list.append(path + "/" + base)
		file_name = dir.get_next()
	dir.list_dir_end()


func _setup_music_player() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	add_child(_music_player)
	_music_player.finished.connect(_on_track_finished)
	audio_mode = "music_file"
	print("[AudioReactor] Music player ready on Master bus")


func _play_track(index: int) -> void:
	if index < 0 or index >= _track_list.size():
		return

	_current_track_index = index
	var path := _track_list[index]

	var stream: AudioStream = _load_audio_file(path)
	if stream == null:
		print("[AudioReactor] ERROR: Could not load: %s" % path)
		# Try next track
		if _track_list.size() > 1:
			_play_track((index + 1) % _track_list.size())
		return

	_music_player.stream = stream
	_music_player.play()

	current_track_name = path.get_file().get_basename()
	track_changed.emit(current_track_name)
	print("[AudioReactor] Now playing: %s" % current_track_name)


func _load_audio_file(path: String) -> AudioStream:
	## Load an audio file. For res:// paths, try the Godot resource loader first.
	## For user:// paths (or if resource loading fails), load raw bytes and
	## construct the appropriate AudioStream manually. This is required for
	## MP3/OGG/WAV files that the user drops in at runtime (not pre-imported).
	var lower := path.to_lower()

	# Try Godot's resource loader first (works for pre-imported res:// files)
	if path.begins_with("res://"):
		var res: AudioStream = load(path) as AudioStream
		if res != null:
			return res

	# Runtime loading: read raw bytes and construct the stream
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[AudioReactor] Cannot open file: %s (error %d)" % [path, FileAccess.get_open_error()])
		return null

	var bytes := file.get_buffer(file.get_length())
	file.close()

	if lower.ends_with(".mp3"):
		var mp3 := AudioStreamMP3.new()
		mp3.data = bytes
		return mp3
	elif lower.ends_with(".ogg"):
		var ogg := AudioStreamOggVorbis.load_from_buffer(bytes)
		return ogg
	elif lower.ends_with(".wav"):
		# WAV is trickier — try resource loader as fallback
		var res: AudioStream = load(path) as AudioStream
		if res != null:
			return res
		print("[AudioReactor] WAV runtime loading not supported for: %s" % path)
		print("[AudioReactor] Tip: Convert to .ogg or .mp3 for user://music/ files")
		return null

	return null


func _on_track_finished() -> void:
	# Play next track (loop playlist)
	var next := (_current_track_index + 1) % _track_list.size()
	_play_track(next)


func _setup_mic_loopback() -> void:
	## Fallback: try to capture system audio via mic input.
	## The mic audio also goes through Master bus, so the spectrum analyzer catches it.
	audio_mode = "mic_loopback"

	_mic_player = AudioStreamPlayer.new()
	_mic_player.bus = "Master"
	_mic_player.volume_db = -80.0  # Nearly silent so user doesn't hear mic feedback
	var mic_stream := AudioStreamMicrophone.new()
	_mic_player.stream = mic_stream
	add_child(_mic_player)
	_mic_player.play()

	print("[AudioReactor] Mic loopback started (fallback mode)")
	print("[AudioReactor] Tip: Enable 'Stereo Mix' in Windows Sound Settings for system audio capture")
	print("[AudioReactor] Or place .mp3/.ogg/.wav files in: %s" % ProjectSettings.globalize_path("user://music/"))


func skip_track() -> void:
	## Public method: skip to next track in playlist.
	if _music_player and _track_list.size() > 1:
		var next := (_current_track_index + 1) % _track_list.size()
		_play_track(next)


func _process(delta: float) -> void:
	if _spectrum == null:
		return

	is_beat = false
	_beat_cooldown_timer -= delta

	# Sample the spectrum analyzer for main bands
	var raw_bass := _get_band_energy(BASS_LOW, BASS_HIGH)
	var raw_mids := _get_band_energy(MID_LOW, MID_HIGH)
	var raw_highs := _get_band_energy(HIGH_LOW, HIGH_HIGH)
	var raw_energy := (raw_bass + raw_mids + raw_highs) / 3.0

	# Sample all visualizer bands
	_update_spectrum_data()

	# Check for silence
	if raw_energy < 0.001:
		_silence_timer += delta
		if _silence_timer > SILENCE_THRESHOLD and not _synthetic_mode:
			_synthetic_mode = true
			is_synthetic = true
			audio_mode = "synthetic"
			print("[AudioReactor] No audio detected, entering synthetic mode")
	else:
		_silence_timer = 0.0
		if _synthetic_mode:
			_synthetic_mode = false
			is_synthetic = false
			if _music_player and _music_player.playing:
				audio_mode = "music_file"
			else:
				audio_mode = "mic_loopback"
			print("[AudioReactor] Audio detected, leaving synthetic mode")

	# Synthetic fallback
	if _synthetic_mode:
		_process_synthetic(delta)
		_push_delay_snapshot()
		_pop_delayed_values()
		return

	# Smooth live values — balanced multipliers for real music FFT ranges
	# FFT magnitudes are small (0.0001–0.05), so we boost to get 0.0–1.0 range
	var target_bass := clampf(raw_bass * 15.0, 0.0, 1.0)   # Dialed back: orig 4, prev 25 → 50%
	var target_mids := clampf(raw_mids * 23.0, 0.0, 1.0)   # Dialed back: orig 6, prev 40 → 50%
	var target_highs := clampf(raw_highs * 34.0, 0.0, 1.0)  # Dialed back: orig 8, prev 60 → 50%
	var target_energy := clampf(raw_energy * 20.0, 0.0, 1.0) # Dialed back: orig 5, prev 35 → 50%

	# Asymmetric smoothing: snap UP fast, decay DOWN slower (music feels punchy)
	bass = lerp(bass, target_bass, SMOOTH_FAST if target_bass > bass else SMOOTH_DECAY)
	mids = lerp(mids, target_mids, SMOOTH_FAST if target_mids > mids else SMOOTH_DECAY)
	highs = lerp(highs, target_highs, SMOOTH_FAST if target_highs > highs else SMOOTH_DECAY)
	energy = lerp(energy, target_energy, SMOOTH_SLOW if target_energy > energy else SMOOTH_DECAY)

	# Spectral flux — measures rate of change in the spectrum
	var current_flux := absf(raw_bass - _energy_smooth) + absf(raw_mids - _energy_smooth) * 0.5
	spectral_flux = lerp(spectral_flux, clampf(current_flux * 30.0, 0.0, 1.0), SMOOTH_FAST)  # Dialed back: orig 10, prev 50 → 50%
	_energy_smooth = lerp(_energy_smooth, raw_energy, 0.125)  # Dialed back: orig 0.1, prev 0.15 → 50%

	# Beat detection — moderately sensitive
	_energy_history.append(raw_energy)
	if _energy_history.size() > 45:  # Dialed back: orig 60, prev 30 → 50% of diff
		_energy_history.remove_at(0)

	var avg_energy := 0.0
	for e in _energy_history:
		avg_energy += e
	avg_energy /= _energy_history.size()

	var now := Time.get_ticks_msec() / 1000.0

	# Beat threshold: moderately sensitive (orig avg*1.5+0.15, prev avg*1.2 floor 0.01)
	var beat_threshold := maxf(avg_energy * 1.35, 0.08)  # 50% between orig and prev
	if raw_energy > beat_threshold and _beat_cooldown_timer <= 0.0:
		is_beat = true
		_beat_cooldown_timer = BEAT_COOLDOWN
		beat_detected.emit()

		_onset_times.append(now)
		while _onset_times.size() > 25:  # Dialed back: orig 20, prev 30 → 50%
			_onset_times.remove_at(0)
		_estimate_bpm()

	# Onset density — how many beats per second recently
	var recent_onsets := 0
	for t in _onset_times:
		if now - t < 2.5:  # Dialed back: orig 2.0, prev 3.0 → 50%
			recent_onsets += 1
	onset_density = lerp(onset_density, float(recent_onsets) / 2.5, SMOOTH_SLOW)

	intensity_changed.emit(energy)

	_push_delay_snapshot()
	_pop_delayed_values()


func _update_spectrum_data() -> void:
	for i in VISUALIZER_BANDS:
		var low_freq := _band_edges[i]
		var high_freq := _band_edges[i + 1]
		var mag: Vector2 = _spectrum.get_magnitude_for_frequency_range(low_freq, high_freq)
		var db := (mag.x + mag.y) / 2.0
		# Balanced boost for visible but not overwhelming visualizer
		var boost := 1.0 + float(i) / float(VISUALIZER_BANDS) * 5.0  # Dialed back: orig 4, prev 6 → 50%
		var value := clampf(db * boost * 18.0, 0.0, 1.0)  # Dialed back: orig 5, prev 30 → 50%
		# Asymmetric: snap up fast, decay slower for nice trailing effect
		var rate := 0.4 if value > spectrum_data[i] else 0.2  # Slightly less snappy
		spectrum_data[i] = lerp(spectrum_data[i], value, rate)


func _push_delay_snapshot() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var snapshot := PackedFloat32Array([
		now, energy, bass, mids, highs, onset_density, spectral_flux
	])
	_delay_buffer.append(snapshot)
	while _delay_buffer.size() > 0 and _delay_buffer[0][0] < now - delay_seconds - 1.0:
		_delay_buffer.remove_at(0)


func _pop_delayed_values() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var target_time := now - delay_seconds

	if _delay_buffer.size() == 0:
		return

	if _delay_buffer[0][0] > target_time:
		var s: PackedFloat32Array = _delay_buffer[0]
		delayed_energy = s[1]
		delayed_bass = s[2]
		delayed_mids = s[3]
		delayed_highs = s[4]
		delayed_onset_density = s[5]
		delayed_spectral_flux = s[6]
		return

	for i in _delay_buffer.size():
		if _delay_buffer[i][0] >= target_time:
			var s: PackedFloat32Array = _delay_buffer[i]
			delayed_energy = s[1]
			delayed_bass = s[2]
			delayed_mids = s[3]
			delayed_highs = s[4]
			delayed_onset_density = s[5]
			delayed_spectral_flux = s[6]
			return

	var s: PackedFloat32Array = _delay_buffer[_delay_buffer.size() - 1]
	delayed_energy = s[1]
	delayed_bass = s[2]
	delayed_mids = s[3]
	delayed_highs = s[4]
	delayed_onset_density = s[5]
	delayed_spectral_flux = s[6]


func _process_synthetic(delta: float) -> void:
	_synthetic_phase += delta * 0.5
	var wave := (sin(_synthetic_phase * TAU) + 1.0) / 2.0

	energy = lerp(energy, wave * 0.3, SMOOTH_SLOW)
	bass = lerp(bass, wave * 0.2, SMOOTH_SLOW)
	mids = lerp(mids, wave * 0.15, SMOOTH_SLOW)
	highs = lerp(highs, wave * 0.1, SMOOTH_SLOW)
	spectral_flux = 0.0
	onset_density = 0.0
	bpm = 120.0

	for i in VISUALIZER_BANDS:
		var band_wave := sin(_synthetic_phase * TAU + float(i) * 0.3) * 0.15 + 0.05
		spectrum_data[i] = lerp(spectrum_data[i], clampf(band_wave, 0.0, 1.0), 0.1)


func _get_band_energy(low_freq: float, high_freq: float) -> float:
	if _spectrum == null:
		return 0.0
	var mag: Vector2 = _spectrum.get_magnitude_for_frequency_range(low_freq, high_freq)
	return (mag.x + mag.y) / 2.0


func _estimate_bpm() -> void:
	if _onset_times.size() < 4:
		return
	var intervals: Array[float] = []
	for i in range(1, _onset_times.size()):
		var interval: float = _onset_times[i] - _onset_times[i - 1]
		if interval > 0.2 and interval < 2.0:
			intervals.append(interval)
	if intervals.size() < 2:
		return
	var avg_interval := 0.0
	for iv in intervals:
		avg_interval += iv
	avg_interval /= intervals.size()
	bpm = lerp(bpm, 60.0 / avg_interval, 0.1)
	bpm = clampf(bpm, 40.0, 220.0)
