extends Node3D
class_name RoadGenerator
## Procedurally generates road segments ahead of the player (into -Z).
## Segments scroll toward the player (+Z direction) as the bike moves forward.
## Road properties (width, curvature, obstacles, coins) react to the AudioReactor
## with a configurable delay buffer so terrain changes arrive ahead of the player.

@export var segment_length: float = 20.0
@export var visible_segments: int = 15
@export var base_road_width: float = 14.0  # 4 lanes worth
@export var min_road_width: float = 10.0   # Raised: must fit bike + 2 lanes of clearance
@export var max_road_width: float = 21.5

var audio_reactor: AudioReactor
var bike: BikeController

# Internal state
var _segments: Array[RoadSegment] = []
var _scroll_offset: float = 0.0
var _next_segment_z: float = 0.0  # Tracks where the next segment spawns (decreasing, into -Z)
var _current_curve: float = 0.0
var _target_curve: float = 0.0
var _current_width: float = 14.0

# Obstacle/coin spawning
var _obstacle_cooldown: float = 0.0
var _coin_pattern_timer: float = 0.0

# Materials (created procedurally)
var _road_material: StandardMaterial3D
var _desert_material: StandardMaterial3D
var _void_material: StandardMaterial3D
var _edge_material: StandardMaterial3D
var _line_material: StandardMaterial3D


class RoadSegment:
	var node: Node3D
	var road_mesh: MeshInstance3D
	var left_terrain: MeshInstance3D
	var right_terrain: MeshInstance3D
	var center_line: MeshInstance3D
	var width: float
	var curve_offset: float
	var z_position: float  # The "world z" this segment was spawned at (negative = ahead)


func _ready() -> void:
	_create_materials()
	# Pre-generate initial segments ahead of the player
	for i in visible_segments:
		_spawn_segment()


func _process(delta: float) -> void:
	if bike == null:
		return

	var scroll_speed := bike.current_speed
	_scroll_offset += scroll_speed * delta

	# Update audio-reactive targets (uses delayed values from AudioReactor)
	_update_reactive_targets()

	# Move all segments toward the player (+Z scroll)
	# Each segment's apparent Z = its spawn Z + scroll offset
	for seg in _segments:
		seg.node.position.z = seg.z_position + _scroll_offset
		seg.node.position.x = seg.curve_offset

	# Recycle segments that have scrolled past behind the camera
	while _segments.size() > 0 and _segments[0].node.position.z > segment_length * 2:
		var old_seg: RoadSegment = _segments.pop_front()
		old_seg.node.queue_free()
		_spawn_segment()

	# Update bike road bounds from a segment near the bike (index ~2)
	if _segments.size() > 2:
		bike.road_half_width = _segments[2].width / 2.0
		bike.road_center_x = _segments[2].curve_offset

	# Spawn timers
	_obstacle_cooldown -= delta
	_coin_pattern_timer -= delta


func _update_reactive_targets() -> void:
	if audio_reactor == null:
		return

	# Use delayed audio values for terrain generation (gives player reaction time)
	var delayed_energy := audio_reactor.delayed_energy
	var delayed_onset := audio_reactor.delayed_onset_density
	var delayed_bass := audio_reactor.delayed_bass

	# Road width: high energy = narrower road, low energy = wide open
	var target_width := remap(delayed_energy, 0.0, 1.0, max_road_width, min_road_width)
	# Subtle bass squeeze — heavy bass sections feel a bit tighter
	target_width -= delayed_bass * 0.45  # Dialed back: orig 0, prev 3.0 → 15% of diff
	target_width = clampf(target_width, min_road_width, max_road_width)
	_current_width = lerp(_current_width, target_width, 0.085)  # Dialed back: orig 0.02, prev 0.15 → 50%

	# Curvature: onset density AND bass drive S-curves
	var curve_intensity := (delayed_onset * 3.5 + delayed_bass * 3.0 + delayed_energy * 1.5)
	# Smooth sine wave that alternates direction based on time
	var time_sec := Time.get_ticks_msec() / 1000.0
	_target_curve = curve_intensity * sin(time_sec * 0.8)
	_current_curve = lerp(_current_curve, _target_curve, 0.07)  # Dialed back: orig 0.02, prev 0.12 → 50%


func _spawn_segment() -> void:
	var seg := RoadSegment.new()
	# Segments spawn further into -Z (ahead of the player)
	seg.z_position = _next_segment_z
	seg.width = _current_width
	# Curve offset: use _current_curve directly with segment distance for smooth S-curves
	# The sin() oscillation is now in _update_reactive_targets, not here
	seg.curve_offset = _current_curve * (1.0 + sin(_next_segment_z * 0.03) * 0.5)

	var seg_node := Node3D.new()
	seg_node.position.z = seg.z_position + _scroll_offset
	seg_node.position.x = seg.curve_offset
	add_child(seg_node)
	seg.node = seg_node

	# Road surface
	seg.road_mesh = _create_road_mesh(seg.width)
	seg_node.add_child(seg.road_mesh)

	# Center line (dashed)
	seg.center_line = _create_center_line(seg.width)
	seg_node.add_child(seg.center_line)

	# Void drop-off terrain on both sides
	seg.left_terrain = _create_terrain_side(-seg.width / 2.0 - 15.0, 30.0)
	seg_node.add_child(seg.left_terrain)
	seg.right_terrain = _create_terrain_side(seg.width / 2.0 + 15.0, 30.0)
	seg_node.add_child(seg.right_terrain)

	# Glowing edge strips along road borders
	var left_edge := _create_edge_strip(-seg.width / 2.0)
	seg_node.add_child(left_edge)
	var right_edge := _create_edge_strip(seg.width / 2.0)
	seg_node.add_child(right_edge)

	# Spawn obstacles on this segment
	_maybe_spawn_obstacles(seg_node, seg.width)

	# Spawn coins on this segment
	_maybe_spawn_coins(seg_node, seg.width)

	_segments.append(seg)
	_next_segment_z -= segment_length  # Next segment further into -Z


func _create_road_mesh(width: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, segment_length)
	plane.material = _road_material
	mesh_instance.mesh = plane
	mesh_instance.position.y = -0.01  # Slightly below bike
	return mesh_instance


func _create_center_line(road_width: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.15, segment_length * 0.4)
	plane.material = _line_material
	mesh_instance.mesh = plane
	mesh_instance.position.y = 0.01
	return mesh_instance


func _create_terrain_side(x_offset: float, width: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, segment_length)
	plane.material = _void_material
	mesh_instance.mesh = plane
	mesh_instance.position.x = x_offset
	mesh_instance.position.y = -2.0  # Visible drop-off below road level
	return mesh_instance


func _create_edge_strip(x_pos: float) -> MeshInstance3D:
	## Thin glowing strip along the road border marking the drop-off edge.
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.15, 0.3, segment_length)
	box.material = _edge_material
	mesh_instance.mesh = box
	mesh_instance.position.x = x_pos
	mesh_instance.position.y = 0.0
	return mesh_instance


func _maybe_spawn_obstacles(parent: Node3D, road_width: float) -> void:
	if audio_reactor == null:
		return
	if _obstacle_cooldown > 0.0:
		return

	var delayed_energy := audio_reactor.delayed_energy
	var delayed_bass := audio_reactor.delayed_bass

	# Obstacle probability scales with energy — balanced
	# Dialed back: orig energy*0.6, prev energy*1.5+bass*0.5 → 50% of diff
	var spawn_chance := delayed_energy * 1.05 + delayed_bass * 0.25
	if randf() > spawn_chance:
		return

	# Cooldown: calm=2.15s, intense=0.275s (dialed back from both extremes)
	_obstacle_cooldown = remap(delayed_energy, 0.0, 1.0, 2.15, 0.275)

	# Spawn multiple obstacles at high energy, but less aggressively
	var obstacle_count := 1
	if delayed_energy > 0.7:   # Was 0.6
		obstacle_count = randi_range(1, 2)  # Was 1-3
	if delayed_energy > 0.9:   # Was 0.85
		obstacle_count = randi_range(2, 3)  # Was 2-4

	var half_w := road_width / 2.0 - 1.5
	for i in obstacle_count:
		var obstacle := _create_obstacle()
		obstacle.position.x = randf_range(-half_w, half_w)
		obstacle.position.y = 0.5
		obstacle.position.z = randf_range(-segment_length / 2.0, segment_length / 2.0)
		parent.add_child(obstacle)


func _create_obstacle() -> Node3D:
	var node := Node3D.new()

	# Visual (box for now — will be replaced with car models)
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.8, 1.2, 3.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.1, 0.1)
	mat.emission_energy_multiplier = 0.5
	box.material = mat
	mesh_instance.mesh = box
	node.add_child(mesh_instance)

	# Collision area
	var area := Area3D.new()
	area.add_to_group("obstacle")
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(1.8, 1.2, 3.5)
	shape.shape = box_shape
	area.add_child(shape)
	node.add_child(area)

	return node


func _maybe_spawn_coins(parent: Node3D, road_width: float) -> void:
	if _coin_pattern_timer > 0.0:
		return

	# Coins scale with energy — balanced
	var spawn_chance := 0.35  # Dialed back: orig 0.4, prev 0.3 → 15% toward prev
	if audio_reactor:
		spawn_chance += audio_reactor.delayed_energy * 0.25  # Dialed back: orig 0, prev 0.5 → 50%
	if audio_reactor and audio_reactor.is_beat:
		spawn_chance = 0.92
	if randf() > spawn_chance:
		return

	_coin_pattern_timer = 0.25  # Dialed back: orig 0.3, prev 0.2 → 50%

	# Slightly more coins during intense sections
	var coin_count := randi_range(3, 7)
	if audio_reactor and audio_reactor.delayed_energy > 0.7:  # Was 0.6
		coin_count = randi_range(4, 8)  # Dialed back: orig max 7, prev max 10

	var lane_x := randf_range(-road_width / 2.0 + 1.5, road_width / 2.0 - 1.5)

	for i in coin_count:
		var coin := _create_coin()
		coin.position.x = lane_x
		coin.position.y = 1.0
		coin.position.z = -segment_length / 2.0 + i * 2.0
		parent.add_child(coin)


func _create_coin() -> Node3D:
	var node := Node3D.new()

	# Visual (torus-like using a sphere for now)
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.4
	sphere.height = 0.4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.0)
	mat.emission_energy_multiplier = 2.0
	sphere.material = mat
	mesh_instance.mesh = sphere
	mesh_instance.scale = Vector3(1.0, 0.3, 1.0)  # Flatten into disc
	node.add_child(mesh_instance)

	# Collision area
	var area := Area3D.new()
	area.add_to_group("coin")
	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 0.9  # 1.5x pickup radius for forgiving collection
	shape.shape = sphere_shape
	area.add_child(shape)
	node.add_child(area)

	# Spin animation
	var spin := Node3D.new()
	spin.name = "SpinHelper"
	node.add_child(spin)

	return node


func _create_materials() -> void:
	# Road surface — dark asphalt
	_road_material = StandardMaterial3D.new()
	_road_material.albedo_color = Color(0.12, 0.12, 0.15)
	_road_material.roughness = 0.9

	# Desert terrain — warm sandy color (kept for far background)
	_desert_material = StandardMaterial3D.new()
	_desert_material.albedo_color = Color(0.76, 0.55, 0.3)
	_desert_material.roughness = 1.0

	# Void drop-off — dark semi-transparent with subtle purple emission
	_void_material = StandardMaterial3D.new()
	_void_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_void_material.albedo_color = Color(0.05, 0.02, 0.1, 0.3)
	_void_material.emission_enabled = true
	_void_material.emission = Color(0.15, 0.05, 0.25)
	_void_material.emission_energy_multiplier = 0.8
	_void_material.roughness = 0.3

	# Edge strip — glowing orange border along road edge
	_edge_material = StandardMaterial3D.new()
	_edge_material.albedo_color = Color(1.0, 0.5, 0.0, 1.0)
	_edge_material.emission_enabled = true
	_edge_material.emission = Color(1.0, 0.4, 0.0)
	_edge_material.emission_energy_multiplier = 3.0

	# Lane markings — bright white/yellow
	_line_material = StandardMaterial3D.new()
	_line_material.albedo_color = Color(1.0, 0.9, 0.3)
	_line_material.emission_enabled = true
	_line_material.emission = Color(1.0, 0.9, 0.3)
	_line_material.emission_energy_multiplier = 1.0
