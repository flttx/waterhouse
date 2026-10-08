class_name WaterhouseWhale
extends WaterhouseCreature
## Blind carcass whale: sound fixes a remembered location; light never reveals you.
## The native imported skeleton follows its travelled spine inside the deep basin.

const WHALE_SCALE: float = 28.0
const WHALE_LENGTH: float = 27.43
const POOL := Rect2(98.0, 19.0, 78.0, 48.0)
const CENTER := Vector3(137.0, -12.0, 43.0)
var _patrol_angle: float = 0.75

func _configure_model() -> void:
	super._configure_model()
	_visual.scale = Vector3.ONE * WHALE_SCALE
	_visual.position = Vector3(0.0, -2.8, 0.489749 * WHALE_SCALE)
	_bone_rest.clear()
	_jaw_bones.clear()
	if _skeleton != null:
		for bone in _skeleton.get_bone_count():
			_bone_rest.append(global_transform.affine_inverse() * _skeleton.global_transform * _skeleton.get_bone_global_rest(bone))
	var shader := load("res://shaders/stalker_skin.gdshader") as Shader
	for skin in _skin_materials:
		skin.shader = shader
		skin.set_shader_parameter("tint", Vector3(0.47, 0.56, 0.48))
	_probe.radius = 3.2
	patrol_speed = 2.2
	pursuit_speed = 4.8

func reset_creature() -> void:
	super.reset_creature()
	_patrol_angle = 0.75
	global_position = _circle(_patrol_angle)
	_heading = Vector3(-25.0 * sin(_patrol_angle), 0.0, 12.0 * cos(_patrol_angle)).normalized()
	_history.clear()
	for sample in 180:
		_history.append(_circle(_patrol_angle - float(sample) * 0.016))
	_quiet_left = _rng.randf_range(20.0, 34.0) * quiet_multiplier
	_goal = _circle(_patrol_angle + 0.4)
	_last_seen = _goal
	if is_node_ready():
		_pose_body()

func state_name() -> String:
	return ["沉眠", "漂游", "听音", "回声搜寻", "声源猎杀", "归航"][state]

func _circle(angle: float) -> Vector3:
	return CENTER + Vector3(cos(angle) * 25.0, 0.0, sin(angle) * 12.0)

func _clamp_water_point(point: Vector3) -> Vector3:
	return Vector3(clampf(point.x, 106.0, 168.0), clampf(point.y, -15.0, -5.0), clampf(point.z, 27.0, 59.0))

func _choose_roam_point(_away: bool = false) -> Vector3:
	_patrol_angle += 0.42
	return _nearest_clear_point(_circle(_patrol_angle))

func _sense_player(delta: float) -> void:
	_refresh_player_properties()
	_last_saw_player = false
	_lost_seconds += delta
	awareness = maxf(0.0, awareness - delta * (0.05 if state == State.CHASE else 0.12))

func _player_is_in_water() -> bool:
	if not super._player_is_in_water():
		return false
	return POOL.has_point(Vector2(player.global_position.x, player.global_position.z))

func hear_noise(position: Vector3, loudness: float) -> void:
	if not enabled or not position.is_finite() or not is_finite(loudness) or loudness <= 0.0 or _noise_cooldown > 0.0 or state == State.RETREAT:
		return
	if not POOL.grow(3.0).has_point(Vector2(position.x, position.z)):
		return
	var intensity := clampf(loudness, 0.0, 1.5)
	var query := PhysicsRayQueryParameters3D.create(global_position, position, WORLD_MASK)
	query.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		intensity *= 0.25
	if global_position.distance_to(position) > (5.0 + intensity * 32.0) * detection_multiplier:
		return
	_noise_cooldown = 0.45
	_last_seen = _clamp_water_point(position)
	_goal = _last_seen
	_lost_seconds = 0.0
	awareness = minf(1.0, awareness + intensity * 0.38)
	if awareness >= 0.67 and _attack_cooldown <= 0.0 and _player_is_in_water():
		_set_state(State.CHASE)
	elif state != State.CHASE:
		_set_state(State.INVESTIGATE)

func _update_state(delta: float) -> void:
	super._update_state(delta)
	if state == State.CHASE and _state_age > 14.0:
		_set_state(State.RETREAT)

func _update_attack(delta: float) -> void:
	if state != State.CHASE or not _player_is_in_water():
		_attack_left = -1.0
		return
	var target := _player_position()
	var distance := global_position.distance_to(target)
	if _attack_left < 0.0:
		if distance < 4.5 and _attack_cooldown <= 0.0 and _has_line_of_sight(target):
			_attack_left = attack_windup * 1.45
			attack_started.emit()
		return
	_attack_left -= delta
	if _attack_left <= 0.0:
		if distance < 4.8 and _has_line_of_sight(target) and player.has_method("take_damage"):
			player.call("take_damage", attack_damage, "回声把盲鲸带到了你身边。")
		_attack_left = -1.0
		_set_state(State.RETREAT)

func _build_navigation() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_graph.clear()
	_grid_ids.clear()
	for x in 16:
		for depth in 3:
			for z in 9:
				var point := Vector3(107.0 + float(x) * 4.0, -7.0 - float(depth) * 4.0, 27.0 + float(z) * 4.0)
				if not _sphere_is_clear(point):
					continue
				var id := _graph.get_available_point_id()
				_graph.add_point(id, point)
				_grid_ids[Vector3i(x, depth, z)] = id
	var neighbors: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 0, -1), Vector3i(0, 1, 0)]
	for coordinate in _grid_ids:
		for offset in neighbors:
			if not _grid_ids.has(coordinate + offset):
				continue
			var from: int = _grid_ids[coordinate]
			var to: int = _grid_ids[coordinate + offset]
			if _clear_motion(_graph.get_point_position(from), _graph.get_point_position(to)):
				_graph.connect_points(from, to)
	_navigation_ready = _graph.get_point_count() > 0
	_path_clock = 0.0

func _pose_body() -> void:
	if _skeleton == null or _history.is_empty():
		return
	var inverse := _skeleton.global_transform.affine_inverse()
	var time := float(Time.get_ticks_msec()) * 0.001
	for bone in _bone_rest.size():
		var rest := _bone_rest[bone]
		var distance := maxf(0.0, rest.origin.z)
		var center := _spine_sample(distance)
		var tangent := (_spine_sample(maxf(0.0, distance - 0.4)) - _spine_sample(distance + 0.4)).normalized()
		if tangent.length_squared() < 0.1:
			tangent = _heading
		var frame := Basis.looking_at(tangent, Vector3.UP if absf(tangent.y) < 0.95 else Vector3.RIGHT)
		var wave := sin(time * 1.4 - distance * 0.32) * 0.16 * clampf(distance / WHALE_LENGTH, 0.0, 1.0)
		var offset := frame.x * rest.origin.x + frame.y * (rest.origin.y + wave)
		_skeleton.set_bone_global_pose_override(bone, inverse * Transform3D(frame * rest.basis, center + offset), 1.0, true)
