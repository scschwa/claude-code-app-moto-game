extends Node3D
class_name VisualReactor
## Drives visual effects based on audio analysis: sky color, bloom intensity,
## particle emission rates, and post-processing parameters.

var audio_reactor: AudioReactor
var environment: WorldEnvironment

# Sky gradient colors
const SKY_CALM := Color(0.15, 0.05, 0.25)       # Deep purple
const SKY_INTENSE := Color(0.4, 0.05, 0.15)      # Hot red-purple
const HORIZON_CALM := Color(0.8, 0.4, 0.2)       # Warm orange
const HORIZON_INTENSE := Color(1.0, 0.2, 0.4)    # Hot pink

# Post-processing targets
var _bloom_target: float = 0.5
var _saturation_target: float = 1.0
var _vignette_target: float = 0.3

# Particles
var _dust_particles: GPUParticles3D
var _spark_particles: GPUParticles3D

# Sun/light
var _sun: DirectionalLight3D


func _ready() -> void:
	_create_environment()
	_create_particles()
	_create_sun()


func _process(delta: float) -> void:
	if audio_reactor == null or environment == null:
		return

	var env := environment.environment
	var e := audio_reactor.energy
	var b := audio_reactor.bass
	var h := audio_reactor.highs

	# Sky color shifts with energy (balanced)
	var sky_color := SKY_CALM.lerp(SKY_INTENSE, e)
	var horizon_color := HORIZON_CALM.lerp(HORIZON_INTENSE, e)

	# Subtle bass red shift (dialed back: orig 0, prev 0.4 → 50%)
	sky_color = sky_color.lerp(Color(0.6, 0.0, 0.1), b * 0.2)

	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	if sky_mat:
		# Sky lerp (dialed back: orig 2.0, prev 8.0 → 50% of diff)
		sky_mat.sky_top_color = sky_mat.sky_top_color.lerp(sky_color, 5.0 * delta)
		sky_mat.sky_horizon_color = sky_mat.sky_horizon_color.lerp(horizon_color, 5.0 * delta)
		# Ground is calmer (15% of diff)
		sky_mat.ground_bottom_color = sky_mat.ground_bottom_color.lerp(sky_color * 0.3, 2.6 * delta)
		sky_mat.ground_horizon_color = sky_mat.ground_horizon_color.lerp(horizon_color * 0.8, 2.6 * delta)

	# Bloom intensity (dialed back: orig 0.3-1.5, prev 0.1-3.0 → 15%/50%)
	_bloom_target = remap(e, 0.0, 1.0, 0.27, 2.25)
	env.glow_intensity = lerp(env.glow_intensity, _bloom_target, 4.5 * delta)

	# Beat bloom pulse (dialed back: orig +0.5, prev +1.5*b → 50%)
	if audio_reactor.is_beat:
		env.glow_intensity += 1.0 * b

	# Glow strength (dialed back: orig static 1.0, prev 0.8-2.0 → 15%/50%)
	env.glow_strength = lerp(env.glow_strength, remap(e, 0.0, 1.0, 0.97, 1.5), 3.5 * delta)

	# Saturation (dialed back: orig 0.9-1.4, prev 0.8-1.8 → 15%/50%)
	_saturation_target = remap(e, 0.0, 1.0, 0.885, 1.6)
	env.adjustment_saturation = lerp(env.adjustment_saturation, _saturation_target, 3.5 * delta)

	# Brightness (dialed back: orig static 1.0, prev 0.95-1.15 → 15%/50%)
	var brightness_target := remap(e, 0.0, 1.0, 1.0, 1.075)
	if audio_reactor.is_beat:
		brightness_target += 0.05  # Dialed back: orig 0, prev 0.1 → 50%
	env.adjustment_brightness = lerp(env.adjustment_brightness, brightness_target, 4.0 * delta)

	# Contrast (dialed back: orig static 1.05, prev 1.0-1.2 → 15%/50%)
	env.adjustment_contrast = lerp(env.adjustment_contrast, remap(e, 0.0, 1.0, 1.04, 1.125), 3.0 * delta)

	# Vignette glow bloom (dialed back: orig *0.3, prev *0.5 → 50%)
	env.glow_bloom = lerp(env.glow_bloom, e * 0.4, 3.0 * delta)

	# Fog (dialed back: orig static 0.002, prev 0.005-0.001 → 15%/50%)
	env.fog_density = lerp(env.fog_density, remap(e, 0.0, 1.0, 0.00245, 0.0015), 2.5 * delta)
	env.fog_light_color = env.fog_light_color.lerp(horizon_color, 3.0 * delta)

	# Sun energy (dialed back: orig 0.6-1.2, prev 0.4-2.0 → 15%/50%)
	if _sun:
		var sun_energy := remap(e, 0.0, 1.0, 0.57, 1.6)
		if audio_reactor.is_beat:
			sun_energy += 0.25 * b  # Dialed back: orig 0, prev 0.5 → 50%
		_sun.light_energy = lerp(_sun.light_energy, sun_energy, 4.0 * delta)

		# Sun color (dialed back: orig 0.3/0.4, prev 0.5/0.5 → 50%)
		var target_color := Color(1.0, 0.9 - b * 0.4, 0.8 - b * 0.45)
		_sun.light_color = _sun.light_color.lerp(target_color, 3.5 * delta)

	# Particles (balanced reactivity)
	if _dust_particles:
		# Dust (dialed back: orig direct energy, prev remap 0.1-1.0)
		var dust_target := remap(e, 0.0, 1.0, 0.27, 1.0)
		_dust_particles.amount_ratio = lerp(_dust_particles.amount_ratio, dust_target, 3.5 * delta)
	if _spark_particles:
		# Sparks (dialed back: orig *1.0, prev *1.5 → 50%)
		var spark_target := h * 1.25
		_spark_particles.amount_ratio = lerp(_spark_particles.amount_ratio, clampf(spark_target, 0.0, 1.0), 4.5 * delta)
		_spark_particles.emitting = h > 0.225  # Dialed back: orig 0.3, prev 0.15 → 50%


func _create_environment() -> void:
	environment = WorldEnvironment.new()
	var env := Environment.new()

	# Sky
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SKY_CALM
	sky_mat.sky_horizon_color = HORIZON_CALM
	sky_mat.ground_bottom_color = SKY_CALM * 0.3
	sky_mat.ground_horizon_color = HORIZON_CALM * 0.8
	sky_mat.sun_angle_max = 30.0
	sky_mat.sun_curve = 0.1
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY

	# Tone mapping
	env.tonemap_mode = Environment.TONE_MAPPER_ACES

	# Glow (bloom)
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 1.0
	env.glow_bloom = 0.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(0, true)
	env.set_glow_level(1, true)
	env.set_glow_level(2, true)

	# Color adjustment
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.0

	# Fog for distance
	env.fog_enabled = true
	env.fog_light_color = HORIZON_CALM
	env.fog_density = 0.002
	env.fog_sky_affect = 0.5

	environment.environment = env
	add_child(environment)


func _create_particles() -> void:
	# Dust particles (ambient, low to ground) — balanced
	_dust_particles = GPUParticles3D.new()
	_dust_particles.amount = 200    # Dialed back: orig 100, prev 300 → 50%
	_dust_particles.lifetime = 3.5  # Dialed back: orig 4.0, prev 3.0 → 50%
	_dust_particles.amount_ratio = 0.27  # Dialed back: orig 0.3, prev 0.1 → 15%

	var dust_mat := ParticleProcessMaterial.new()
	dust_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dust_mat.emission_box_extents = Vector3(20.0, 0.5, 30.0)
	dust_mat.direction = Vector3(0, 1, 0)
	dust_mat.spread = 45.0
	dust_mat.initial_velocity_min = 0.5
	dust_mat.initial_velocity_max = 2.0
	dust_mat.gravity = Vector3(0, -0.5, 0)
	dust_mat.scale_min = 0.1
	dust_mat.scale_max = 0.4
	dust_mat.color = Color(0.8, 0.6, 0.4, 0.3)
	_dust_particles.process_material = dust_mat

	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 0.1
	dust_mesh.height = 0.1
	var dust_mesh_mat := StandardMaterial3D.new()
	dust_mesh_mat.albedo_color = Color(0.8, 0.6, 0.4, 0.5)
	dust_mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mesh.material = dust_mesh_mat
	_dust_particles.draw_pass_1 = dust_mesh

	_dust_particles.position.y = 0.5
	add_child(_dust_particles)

	# Spark / shimmer particles (high frequency reactive) — balanced
	_spark_particles = GPUParticles3D.new()
	_spark_particles.amount = 100  # Dialed back: orig 50, prev 150 → 50%
	_spark_particles.lifetime = 1.35  # Dialed back: orig 1.5, prev 1.2 → 50%
	_spark_particles.emitting = false
	_spark_particles.amount_ratio = 0.0

	var spark_mat := ParticleProcessMaterial.new()
	spark_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	spark_mat.emission_box_extents = Vector3(10.0, 2.0, 15.0)
	spark_mat.direction = Vector3(0, 1, 0)
	spark_mat.spread = 90.0
	spark_mat.initial_velocity_min = 2.0
	spark_mat.initial_velocity_max = 5.0
	spark_mat.gravity = Vector3(0, -1.0, 0)
	spark_mat.scale_min = 0.05
	spark_mat.scale_max = 0.15
	spark_mat.color = Color(0.0, 0.9, 1.0, 0.8)
	_spark_particles.process_material = spark_mat

	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.05
	spark_mesh.height = 0.05
	var spark_mesh_mat := StandardMaterial3D.new()
	spark_mesh_mat.albedo_color = Color(0.0, 0.9, 1.0)
	spark_mesh_mat.emission_enabled = true
	spark_mesh_mat.emission = Color(0.0, 0.9, 1.0)
	spark_mesh_mat.emission_energy_multiplier = 3.0
	spark_mesh.material = spark_mesh_mat
	_spark_particles.draw_pass_1 = spark_mesh

	add_child(_spark_particles)


func _create_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.85, 0.7)
	_sun.light_energy = 0.8
	_sun.rotation_degrees = Vector3(-30, -45, 0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(_sun)
