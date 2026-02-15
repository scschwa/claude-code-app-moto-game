extends Node
class_name SfxManager
## Generates procedural sound effects for coin pickup and obstacle hit.
## Uses AudioStreamWAV with raw PCM samples — no external files needed.

var _coin_player: AudioStreamPlayer
var _hit_player: AudioStreamPlayer


func _ready() -> void:
	_coin_player = AudioStreamPlayer.new()
	_coin_player.bus = "Master"
	_coin_player.volume_db = -6.0
	add_child(_coin_player)

	_hit_player = AudioStreamPlayer.new()
	_hit_player.bus = "Master"
	_hit_player.volume_db = -3.0
	add_child(_hit_player)

	_coin_player.stream = _generate_coin_sound()
	_hit_player.stream = _generate_hit_sound()


func play_coin() -> void:
	_coin_player.play()


func play_hit() -> void:
	_hit_player.play()


func _generate_coin_sound() -> AudioStreamWAV:
	## Bright two-tone "ding" — ascending pitches, short and snappy
	var sample_rate := 22050
	var duration := 0.15  # 150ms
	var sample_count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)  # 16-bit = 2 bytes per sample

	var freq1 := 880.0   # A5
	var freq2 := 1318.5  # E6 (musical fifth up)

	for i in sample_count:
		var t := float(i) / sample_rate
		var progress := float(i) / sample_count

		# Switch from freq1 to freq2 halfway through
		var freq := freq1 if progress < 0.4 else freq2

		# Sine wave with exponential decay envelope
		var envelope := (1.0 - progress) * (1.0 - progress)
		var sample := sin(t * freq * TAU) * envelope

		# Add a little harmonic shimmer
		sample += sin(t * freq * 2.0 * TAU) * envelope * 0.3
		sample += sin(t * freq * 3.0 * TAU) * envelope * 0.1

		# Convert to 16-bit signed integer
		var value := int(clampf(sample, -1.0, 1.0) * 32000.0)
		data[i * 2] = value & 0xFF
		data[i * 2 + 1] = (value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


func _generate_hit_sound() -> AudioStreamWAV:
	## Crunchy impact — low frequency thud with noise burst
	var sample_rate := 22050
	var duration := 0.3  # 300ms
	var sample_count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	var base_freq := 80.0  # Low thud

	for i in sample_count:
		var t := float(i) / sample_rate
		var progress := float(i) / sample_count

		# Pitch drops over time for "impact" feel
		var freq := base_freq * (1.0 - progress * 0.5)

		# Fast decay envelope
		var envelope := pow(1.0 - progress, 3.0)

		# Low sine thud
		var sample := sin(t * freq * TAU) * envelope * 0.6

		# Noise burst (louder at start, fades quickly)
		var noise_env := pow(maxf(1.0 - progress * 4.0, 0.0), 2.0)
		sample += randf_range(-1.0, 1.0) * noise_env * 0.4

		# Distortion crunch — soft clip
		sample = clampf(sample * 1.5, -1.0, 1.0)

		var value := int(clampf(sample, -1.0, 1.0) * 32000.0)
		data[i * 2] = value & 0xFF
		data[i * 2 + 1] = (value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream
