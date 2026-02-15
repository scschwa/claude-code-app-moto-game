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
	## Resonant bell/gong with FM synthesis — low, rich tone.
	## Intensity scales with combo tier: deeper body, more harmonics,
	## sub-bass octave, detuned gong voice, and shimmer at high combos.
	var tier := _combo_to_tier(combo)
	var sample_rate := 44100  # Higher rate for cleaner low frequencies

	# Parameters scaled by tier — much lower base than before
	var base_freq := 280.0 + tier * 40.0             # 280 Hz to 600 Hz (was 1200-2600)
	var sweep_ratio := 1.05 + tier * 0.03            # 1.05x to ~1.29x — subtle sweep
	var num_harmonics := 3 + int(tier * 0.85)        # 3 to 9 — richer body
	var duration := 0.25 + tier * 0.04               # 250ms to ~570ms — longer resonance
	var fm_index := maxf(0.0, (tier - 2.0) * 0.6)   # 0 for tier 0-2, gentler onset
	var has_sub_bass := tier >= 1
	var has_second_voice := tier >= 3                 # Gong beating at tier 3+
	var has_shimmer := tier >= 6

	var sample_count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)  # 16-bit = 2 bytes per sample

	for i in sample_count:
		var t := float(i) / sample_rate
		var progress := float(i) / sample_count

		# Gentle ascending frequency sweep
		var freq := base_freq + (base_freq * sweep_ratio - base_freq) * progress

		# FM synthesis: modulate carrier with modulator for metallic bell quality
		var fm_mod := sin(t * base_freq * 1.41 * TAU) * fm_index

		# Bell envelope: sharp attack, slow exponential decay for resonance
		var envelope := pow(1.0 - progress, 0.8 + tier * 0.15)
		# Quick attack ramp (first 3%)
		if progress < 0.03:
			envelope *= progress / 0.03

		# Main carrier with FM modulation
		var sample := sin(t * freq * TAU + fm_mod) * envelope

		# Rich harmonics (each at decreasing amplitude) — bell overtones
		for h in range(1, num_harmonics):
			var h_amp := 0.35 / float(h + 1)
			# Bell-like inharmonic partials: slightly detuned from integer ratios
			var partial_ratio := float(h + 1) + 0.01 * float(h)
			sample += sin(t * freq * partial_ratio * TAU + fm_mod * 0.5) * envelope * h_amp

		# Sub-bass: octave below adds warmth and body (tier 1+)
		if has_sub_bass:
			var sub_env := pow(1.0 - progress, 1.2) * 0.3
			sample += sin(t * freq * 0.5 * TAU) * sub_env

		# Second voice: slightly detuned octave for gong beating (tier 3+)
		if has_second_voice and progress > 0.05:
			var voice2_progress := (progress - 0.05) / 0.95
			var voice2_env := pow(1.0 - voice2_progress, 1.5) * 0.2
			var voice2_freq := freq * 2.003  # Slight detune creates beating
			sample += sin(t * voice2_freq * TAU) * voice2_env

		# High shimmer burst (tier 6+) — adds sparkle at extreme combos
		if has_shimmer:
			var shimmer_env := pow(maxf(1.0 - progress * 2.5, 0.0), 2.0) * 0.06
			sample += sin(t * freq * 5.03 * TAU) * shimmer_env
			sample += randf_range(-1.0, 1.0) * shimmer_env * 0.3

		# Soft clip with gentler drive for clean bell tone
		sample = clampf(sample * (0.6 + tier * 0.04), -1.0, 1.0)

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
