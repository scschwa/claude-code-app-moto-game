extends Node
class_name SfxManager
## Generates procedural sound effects for coin pickup and obstacle hit.
## Coin sound escalates in intensity with combo count — futuristic FM synthesis.
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

	_hit_player.stream = _generate_hit_sound()


func play_coin(combo: int = 0) -> void:
	_coin_player.stream = _generate_coin_sound(combo)
	_coin_player.play()


func play_hit() -> void:
	_hit_player.play()


func _combo_to_tier(combo: int) -> int:
	if combo <= 1: return 0
	if combo <= 4: return 1
	if combo <= 9: return 2
	if combo <= 14: return 3
	if combo <= 19: return 4
	if combo <= 29: return 5
	if combo <= 49: return 6
	return 7


func _generate_coin_sound(combo: int = 0) -> AudioStreamWAV:
	## Futuristic ascending ding with FM synthesis.
	## Intensity scales with combo tier: higher pitch, more harmonics,
	## FM modulation, second voice, and noise whoosh at high combos.
	var tier := _combo_to_tier(combo)
	var sample_rate := 22050

	# Parameters scaled by tier
	var base_freq := 1200.0 + tier * 200.0          # 1200 Hz to 2600 Hz
	var sweep_ratio := 1.2 + tier * 0.114            # 1.2x to ~2.0x
	var num_harmonics := 2 + int(tier * 0.7)         # 2 to 6
	var duration := 0.12 + tier * 0.018              # 120ms to ~250ms
	var fm_index := maxf(0.0, (tier - 1.5) * 0.75)  # 0 for tier 0-1, ramps up
	var has_second_voice := tier >= 4
	var has_whoosh := tier >= 6

	var sample_count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)  # 16-bit = 2 bytes per sample

	for i in sample_count:
		var t := float(i) / sample_rate
		var progress := float(i) / sample_count

		# Ascending frequency sweep
		var freq := base_freq + (base_freq * sweep_ratio - base_freq) * progress

		# FM synthesis: modulate carrier with modulator for digital quality
		var fm_mod := sin(t * base_freq * 1.5 * TAU) * fm_index

		# Envelope: sharp attack, exponential decay
		var envelope := pow(1.0 - progress, 1.5 + tier * 0.2)
		# Quick attack ramp (first 5%)
		if progress < 0.05:
			envelope *= progress / 0.05

		# Main carrier with FM modulation
		var sample := sin(t * freq * TAU + fm_mod) * envelope

		# Harmonics (each at decreasing amplitude)
		for h in range(1, num_harmonics):
			var h_amp := 0.3 / float(h + 1)
			sample += sin(t * freq * float(h + 1) * TAU + fm_mod) * envelope * h_amp

		# Second voice at musical fifth (tier 4+, delayed onset)
		if has_second_voice and progress > 0.08:
			var voice2_progress := (progress - 0.08) / 0.92
			var voice2_env := pow(1.0 - voice2_progress, 2.0)
			var voice2_freq := freq * 1.5  # Perfect fifth
			sample += sin(t * voice2_freq * TAU) * voice2_env * 0.25

		# Noise whoosh burst (tier 6+)
		if has_whoosh:
			var whoosh_env := pow(maxf(1.0 - progress * 3.0, 0.0), 2.0) * 0.08
			sample += randf_range(-1.0, 1.0) * whoosh_env

		# Soft clip with tier-scaled drive
		sample = clampf(sample * (0.8 + tier * 0.05), -1.0, 1.0)

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
